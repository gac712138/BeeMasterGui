import 'dart:async';
import 'dart:io';
import 'package:beemaster_ui/utils/com_scanner.dart';
import 'package:beemaster_ui/utils/protocol/ads_parser.dart';
import 'package:intl/intl.dart';

import 'package:beemaster_ui/services/exe_helper.dart';
import 'package:beemaster_ui/services/burn_task_service.dart';

enum JobStatus { pending, burning, verifying, success, failed }

// 存放單個音軌的詳細資訊 (ID, Size)
class TaskTrackInfo {
  final int index;
  final int id;
  final int size;
  TaskTrackInfo(this.index, this.id, this.size);
}

class TaskItem {
  final String dasId;
  String? assignedPort;
  JobStatus status;
  double progress;
  List<TaskTrackInfo> tracks = [];

  // 🔥 新增：下次允許指派的時間 (冷卻機制)
  DateTime? nextAvailableTime;

  TaskItem(this.dasId) : status = JobStatus.pending, progress = 0.0;
}

class BurnTaskController {
  final Function() onStateChanged;
  final Function(String msg, bool isError) onMessage;

  bool isSystemRunning = false;
  List<String> allDonglePorts = [];
  final Set<String> busyDonglePorts = {};
  late Map<String, TaskItem> tasks;
  List<String> globalLogs = [];
  AdsFileMeta? fileMeta;
  String? _cachedExePath;
  String? _currentAdsFilePath;
  Timer? _schedulerTimer;
  final Map<String, BurnTaskService> _activeServices = {};

  bool get isAllTasksCompleted =>
      tasks.values.every((t) => t.status == JobStatus.success);

  BurnTaskController({
    required List<String> targetIds,
    required this.onStateChanged,
    required this.onMessage,
  }) {
    tasks = {for (var id in targetIds) id: TaskItem(id)};
  }

  Future<void> init(String adsFilePath) async {
    _addGlobalLog("系統初始化...", "SYSTEM");
    await _killExistingWorkers();
    try {
      _cachedExePath = await ExeHelper.extractWorkerExe();
      _addGlobalLog("核心引擎準備就緒", "SYSTEM");
    } catch (e) {
      _addGlobalLog("❌ 核心引擎提取失敗: $e", "SYSTEM");
      onMessage("核心引擎錯誤，請重啟電腦", true);
      return;
    }
    _currentAdsFilePath = adsFilePath;
    await _loadFile(adsFilePath);
    refreshDongles();
  }

  Future<void> _killExistingWorkers() async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'worker.exe']);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {}
  }

  void dispose() {
    stopSystem();
  }

  void _addGlobalLog(String msg, String source) {
    // 1. 取得時間戳記 [HH:mm:ss]
    final time = DateFormat('HH:mm:ss').format(DateTime.now());

    // 2. 清理訊息內容：移除機器人 (🤖)、沙漏 (⌛) 以及多餘的冒號空格
    // 同時確保「進度」與數字之間沒有多餘空格以統一寬度
    String cleanMsg = msg
        .replaceAll('🤖', '')
        .replaceAll('⌛', '')
        .replaceAll('進度: ', '進度')
        .trim();

    // 3. 重新組裝：拿掉原本的 [$source]，因為 Go 傳過來的訊息開頭已經包含 [COMx][DasLoop-ID]
    // 最終格式：[10:39:11][COM33][Dasloop-LLBMTPE006517] 進度5% (52032/1038854)
    globalLogs.add("[$time]$cleanMsg");

    if (globalLogs.length > 1000) globalLogs.removeAt(0);
    onStateChanged();
  }

  Future<void> _loadFile(String path) async {
    final meta = await AdsParser.parse(path);
    if (meta != null) {
      fileMeta = meta;
      _addGlobalLog("檔案載入成功 (${meta.sizeKB} KB)", "SYSTEM");
    } else {
      _addGlobalLog("❌ 檔案載入失敗", "SYSTEM");
      onMessage("檔案載入失敗", true);
    }
  }

  void refreshDongles() {
    final devices = ComScanner.findDonglePorts();
    List<String> foundPorts = devices.map((d) => d.portName).toList();
    allDonglePorts = foundPorts;
    _addGlobalLog(
      "Dongle 重整: 共發現 ${allDonglePorts.length} 支可用 Dongle",
      "SYSTEM",
    );
    onStateChanged();
  }

  Future<void> startSystem() async {
    if (fileMeta == null || _cachedExePath == null || allDonglePorts.isEmpty) {
      onMessage("系統尚未準備就緒或未偵測到 Dongle", true);
      return;
    }
    isSystemRunning = true;
    onStateChanged();
    _addGlobalLog("啟動全自動燒錄排程...", "SYSTEM");
    _startScheduler();
  }

  void _startScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _runScheduler();
    });
    _runScheduler();
  }

  void stopSystem() {
    isSystemRunning = false;
    _schedulerTimer?.cancel();
    _activeServices.forEach((port, service) => service.kill());
    _activeServices.clear();
    busyDonglePorts.clear();
    _addGlobalLog("系統已停止", "SYSTEM");
    onStateChanged();
  }

  // 🔥 優化：排程加入冷卻判斷
  void _runScheduler() {
    if (isAllTasksCompleted || !isSystemRunning) return;

    final now = DateTime.now();
    List<String> idleWorkers = allDonglePorts
        .where((p) => !busyDonglePorts.contains(p))
        .toList();
    if (idleWorkers.isEmpty) return;
    idleWorkers.shuffle();

    List<TaskItem> pendingTasks = tasks.values.where((t) {
      bool isWaiting =
          t.status == JobStatus.pending || t.status == JobStatus.failed;
      // 💡 只有當前時間大於 nextAvailableTime 時才指派
      bool isReady =
          t.nextAvailableTime == null || now.isAfter(t.nextAvailableTime!);
      return isWaiting && isReady;
    }).toList();

    for (var task in pendingTasks) {
      if (idleWorkers.isEmpty) break;
      _assignWorker(idleWorkers.removeAt(0), task);
    }
  }

  Future<void> _assignWorker(String port, TaskItem task) async {
    if (_cachedExePath == null || _currentAdsFilePath == null) return;

    busyDonglePorts.add(port);
    task.status = JobStatus.burning;
    task.assignedPort = port;
    task.tracks.clear();
    onStateChanged();

    List<String> extraArgs = ["-target", task.dasId];
    if (task.progress >= 1.0) {
      extraArgs.add("-skip-burn");
      _addGlobalLog("⏩ [${task.dasId}] 偵測到已燒錄完成，由 ($port) 接力檢查握手...", "SYSTEM");
    } else {
      _addGlobalLog("派遣 Dongle ($port) 搜尋目標: ${task.dasId}", "SYSTEM");
    }

    final service = BurnTaskService();
    _activeServices[port] = service;

    await service.startBurning(
      exePath: _cachedExePath!,
      portName: port,
      targetMac: "",
      filePath: _currentAdsFilePath!,
      extraArgs: extraArgs,
      onLog: (msg) {
        if (msg.contains("TRACK_DETAIL:")) {
          try {
            final parts = msg.split("TRACK_DETAIL:")[1].trim().split(":");
            if (parts.length >= 3) {
              task.tracks.add(
                TaskTrackInfo(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                ),
              );
            }
          } catch (e) {}
          return;
        }

        if (msg.contains("任務圓滿完成") || msg.contains("比對成功！內容一致")) {
          task.status = JobStatus.success;
          task.progress = 1.0;
          _addGlobalLog("✅ [${task.dasId}] 燒錄與驗證成功", port);
          service.kill();
          return;
        }

        // 🔥 修改：釋放時設定 10 秒冷卻
        if (msg.contains("釋放") || (msg.contains("失敗") && msg.contains("釋放"))) {
          _addGlobalLog("⚠️ [${task.dasId}] 握手異常，進入 10s 冷卻等待接力", port);
          task.status = JobStatus.failed;
          task.nextAvailableTime = DateTime.now().add(
            const Duration(seconds: 10),
          );
          service.kill();
          return;
        }

        if (msg.contains("原地重燒") || msg.contains("比對不符")) {
          _addGlobalLog("🔄 [${task.dasId}] 比對不符，執行原地重燒...", port);
          task.status = JobStatus.burning;
          task.progress = 0.0;
          task.tracks.clear();
          onStateChanged();
        }

        if (msg.contains("設備重啟中") || msg.contains("啟動語音一致性比對")) {
          task.status = JobStatus.verifying;
          task.progress = 1.0;
          onStateChanged();
        }

        if (msg.contains("ERROR") ||
            msg.contains("成功") ||
            msg.contains("失敗") ||
            msg.contains("捕獲") ||
            msg.contains("進度") ||
            msg.contains("比對") ||
            msg.contains("重啟")) {
          _addGlobalLog(msg, task.dasId);
        }
      },
      onProgress: (pct) {
        if (task.status == JobStatus.burning) {
          task.progress = pct;
          onStateChanged();
        }
      },
      onDone: (success) {
        _activeServices.remove(port);
        busyDonglePorts.remove(port);
        if (task.status == JobStatus.success) {
          // OK
        } else if (task.status == JobStatus.failed) {
          task.assignedPort = null;
        } else {
          // 意外退出：設定較長的冷卻時間
          task.status = JobStatus.failed;
          task.assignedPort = null;
          task.nextAvailableTime = DateTime.now().add(
            const Duration(seconds: 10),
          );
          _addGlobalLog("❌ [${task.dasId}] Worker 異常退出，冷卻 10s", port);
        }
        onStateChanged();
      },
    );
  }
}
