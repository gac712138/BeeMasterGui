import 'dart:async';
import 'dart:io';
import 'package:beemaster_ui/utils/com_scanner.dart';
import 'package:beemaster_ui/utils/protocol/ads_parser.dart';
import 'package:intl/intl.dart';

import 'package:beemaster_ui/services/exe_helper.dart';
import 'package:beemaster_ui/services/burn_task_service.dart';

enum JobStatus { pending, burning, verifying, success, failed }

class TaskItem {
  final String dasId;
  String? assignedPort;
  JobStatus status;
  double progress;

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
    await _killExistingWorkers(); // 清理殘留

    try {
      _cachedExePath = await ExeHelper.extractWorkerExe();
      _addGlobalLog("核心引擎準備就緒", "SYSTEM");
    } catch (e) {
      _addGlobalLog("❌ 核心引擎提取失敗: $e", "SYSTEM");
      if (await File('path/to/worker.exe').exists()) {
        _addGlobalLog("⚠️ 提取失敗，嘗試使用現有核心...", "SYSTEM");
      } else {
        onMessage("核心引擎錯誤，請重啟電腦", true);
        return;
      }
    }

    _currentAdsFilePath = adsFilePath;
    await _loadFile(adsFilePath);
    refreshDongles();
  }

  Future<void> _killExistingWorkers() async {
    _addGlobalLog("正在清理殘留程序...", "SYSTEM");
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'worker.exe']);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      // 忽略錯誤
    }
  }

  void dispose() {
    stopSystem();
  }

  void _addGlobalLog(String msg, String source) {
    final time = DateFormat('HH:mm:ss').format(DateTime.now());
    globalLogs.add("[$time][$source] $msg");
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

    if (foundPorts.isNotEmpty) {
      allDonglePorts = foundPorts;
      _addGlobalLog(
        "Dongle 重整: 共發現 ${allDonglePorts.length} 支可用 Dongle",
        "SYSTEM",
      );
    } else {
      allDonglePorts = [];
      _addGlobalLog("⚠️ 未偵測到 Dongle", "SYSTEM");
    }
    onStateChanged();
  }

  Future<void> startSystem() async {
    if (fileMeta == null || _cachedExePath == null) {
      onMessage("系統尚未準備就緒", true);
      return;
    }
    if (allDonglePorts.isEmpty) {
      onMessage("未偵測到 Dongle", true);
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
    _activeServices.forEach((port, service) {
      service.kill();
    });
    _activeServices.clear();
    busyDonglePorts.clear();
    _addGlobalLog("系統已停止", "SYSTEM");
    onStateChanged();
  }

  void _runScheduler() {
    if (isAllTasksCompleted) {
      onStateChanged();
      return;
    }

    // 找出閒置的 Dongle
    List<String> idleWorkers = allDonglePorts
        .where((p) => !busyDonglePorts.contains(p))
        .toList();

    if (idleWorkers.isEmpty) return;
    idleWorkers.shuffle(); // 隨機排序，確保負載均衡

    // 找出待處理任務 (包含 Pending 和 Failed)
    List<TaskItem> pendingTasks = tasks.values
        .where(
          (t) => t.status == JobStatus.pending || t.status == JobStatus.failed,
        )
        .toList();

    if (pendingTasks.isEmpty) return;

    for (var task in pendingTasks) {
      if (idleWorkers.isEmpty) break;
      String workerPort = idleWorkers.removeAt(0);
      _assignWorker(workerPort, task);
    }
  }

  Future<void> _assignWorker(String port, TaskItem task) async {
    if (_cachedExePath == null || _currentAdsFilePath == null) return;

    busyDonglePorts.add(port);
    task.status = JobStatus.burning; // 初始設為燒錄中
    task.assignedPort = port;
    task.progress = 0.0;
    onStateChanged();

    _addGlobalLog("派遣 Dongle ($port) 搜尋目標: ${task.dasId}", "SYSTEM");

    final service = BurnTaskService();
    _activeServices[port] = service;

    await service.startBurning(
      exePath: _cachedExePath!,
      portName: port,
      targetMac: "",
      filePath: _currentAdsFilePath!,
      extraArgs: ["-target", task.dasId],

      onLog: (msg) {
        // --------------------------------------------------------
        // 🔥 1. 成功判斷 (比對一致)
        // --------------------------------------------------------
        if (msg.contains("任務圓滿完成") || msg.contains("比對成功！內容一致")) {
          task.status = JobStatus.success;
          task.progress = 1.0;
          _addGlobalLog("✅ [${task.dasId}] 燒錄與驗證成功", port);

          // 任務完成後，強制結束這個 Worker，釋放 Dongle 資源
          service.kill();
          return;
        }

        // --------------------------------------------------------
        // 🔥 2. 失敗/釋放判斷 (需要換 Dongle 接手)
        // --------------------------------------------------------
        if (msg.contains("釋放") || (msg.contains("失敗") && msg.contains("釋放"))) {
          _addGlobalLog(
            "⚠️ [${task.dasId}] 此 Dongle 釋放任務，等待其他 Dongle 接手",
            port,
          );

          // 標記為 Failed，這樣 Scheduler 下一次就會把這個任務分派給別的 Dongle
          task.status = JobStatus.failed;
          task.progress = 0.0;

          // 強制結束，釋放這個 Port
          service.kill();
          return;
        }

        // --------------------------------------------------------
        // 🔥 3. 內容不符判斷 (原地重燒)
        // --------------------------------------------------------
        if (msg.contains("原地重燒") || msg.contains("比對不符")) {
          _addGlobalLog("🔄 [${task.dasId}] 比對不符，執行原地重燒...", port);

          // 切回燒錄狀態
          task.status = JobStatus.burning;
          task.progress = 0.0;
          onStateChanged();
        }

        // --------------------------------------------------------
        // 🔥 4. 狀態更新 (驗證中)
        // --------------------------------------------------------
        if (msg.contains("設備重啟中") || msg.contains("啟動語音一致性比對")) {
          task.status = JobStatus.verifying;
          task.progress = 1.0;
          onStateChanged();
        }

        // 一般 Log 記錄
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
        // 驗證階段不更新進度條 (保持 100% 或無限轉圈)
        if (task.status == JobStatus.burning) {
          task.progress = pct;
          onStateChanged();
        }
      },

      onDone: (success) {
        // 資源清理
        _activeServices.remove(port);
        busyDonglePorts.remove(port);

        // 如果在 onLog 已經被標記為 Success 或 Failed，就保留該狀態
        // 這樣 Scheduler 才能正確處理
        if (task.status == JobStatus.success) {
          // 任務已完成，不做事
        } else if (task.status == JobStatus.failed) {
          // 任務已失敗，清空分配的 Port，等待 Scheduler 重新分配
          task.assignedPort = null;
        } else {
          // 意外退出 (Crashed)，視為失敗
          task.status = JobStatus.failed;
          task.assignedPort = null;
          task.progress = 0.0;
          _addGlobalLog("❌ [${task.dasId}] Worker 異常退出", port);
        }

        onStateChanged();
      },
    );
  }
}
