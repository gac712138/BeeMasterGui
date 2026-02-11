import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:beemaster_ui/utils/com_scanner.dart';
import 'package:beemaster_ui/utils/ads_parser.dart';
import 'package:intl/intl.dart';
import 'package:beemaster_ui/services/exe_helper.dart';

enum JobStatus { pending, burning, verifying, success, failed }

class TaskTrackInfo {
  final int index;
  final int id;
  final int size;
  TaskTrackInfo(this.index, this.id, this.size);
}

class TaskItem {
  final String dasId;
  String? assignedPort;
  String? mac;
  JobStatus status;
  double progress;
  List<TaskTrackInfo> tracks = [];

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
  Process? _factoryProcess;

  final Map<String, String> _portToMacMap = {};

  // 🔥 新增：全域音軌快取 (因為所有任務的音軌結構都一樣，抓到一次就能共用)
  final List<TaskTrackInfo> _globalTrackCache = [];

  int get completedTasksCount =>
      tasks.values.where((t) => t.status == JobStatus.success).length;
  int get totalTasksCount => tasks.length;
  String get progressRatio => "($completedTasksCount/$totalTasksCount)";
  bool get isAllTasksCompleted =>
      tasks.values.every((t) => t.status == JobStatus.success);

  BurnTaskController({
    required List<String> targetIds,
    required this.onStateChanged,
    required this.onMessage,
  }) {
    tasks = {for (var id in targetIds) id: TaskItem(id)};
  }

  String getPortStatusText(String port) {
    if (!isSystemRunning) return "停止";
    if (busyDonglePorts.contains(port)) return "工作中";
    return "待命";
  }

  bool isPortBusy(String port) => busyDonglePorts.contains(port);

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

  Future<void> startSystem() async {
    if (fileMeta == null || _cachedExePath == null || allDonglePorts.isEmpty) {
      onMessage("系統未就緒", true);
      return;
    }
    isSystemRunning = true;
    _globalTrackCache.clear(); // 清空快取
    onStateChanged();
    _addGlobalLog("啟動燒錄程式", "SYSTEM");

    if (_factoryProcess == null) {
      await _spawnFactoryProcess();
    }

    var order = {
      "command": "START",
      "file": _currentAdsFilePath,
      "target_ids": tasks.values.map((t) => t.dasId).toList(),
      "ports": allDonglePorts,
    };

    if (_factoryProcess != null) {
      _factoryProcess!.stdin.writeln(jsonEncode(order));
      _addGlobalLog("訂單已發送，自動化產線運作中...", "SYSTEM");
    }
  }

  void stopSystem() {
    isSystemRunning = false;
    if (_factoryProcess != null) {
      var order = {"command": "STOP"};
      _factoryProcess!.stdin.writeln(jsonEncode(order));
    }
    busyDonglePorts.clear();
    _portToMacMap.clear();
    _addGlobalLog("系統已停止", "SYSTEM");
    onStateChanged();
  }

  Future<void> _spawnFactoryProcess() async {
    _factoryProcess = await Process.start(_cachedExePath!, []);
    _factoryProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _handleWorkerMessage(line);
        });
    _factoryProcess!.stderr
        .transform(utf8.decoder)
        .listen((data) => print("Go Error: $data"));
  }

  void _handleWorkerMessage(String line) {
    try {
      if (!line.trim().startsWith('{')) return;

      final resp = jsonDecode(line);
      String type = resp['type'];
      String port = resp['port'] ?? 'SYSTEM';

      if (type == 'LOG' || type == 'ERROR') {
        String msg = resp['message'] ?? '';
        _addGlobalLog(msg, port);

        // 🔥 1. 抓取音軌詳情 (存入全域快取)
        if (msg.contains("TRACK_DETAIL:")) {
          _parseTrackDetail(msg);
        }

        // 策略 A：透過 DasID 綁定
        for (var task in tasks.values) {
          if (msg.contains(task.dasId)) {
            if (task.assignedPort != port) {
              task.assignedPort = port;
              if (_portToMacMap.containsKey(port)) {
                task.mac = _portToMacMap[port];
              }
            }
            if (!busyDonglePorts.contains(port)) {
              busyDonglePorts.add(port);
              onStateChanged();
            }
            _checkLogForStatus(task, msg, port);
          }
        }

        // 策略 B：透過 Port 綁定
        if (port != 'SYSTEM') {
          for (var task in tasks.values) {
            if (task.assignedPort == port) {
              _checkLogForStatus(task, msg, port);
            }
          }
        }
      } else if (type == 'PROGRESS') {
        String mac = resp['mac'];
        int pct = resp['pct'] ?? 0;
        _updateTaskState(mac, port, pct);
      }
    } catch (e) {
      print("JSON Parse Error: $line");
    }
  }

  void _updateTaskState(String mac, String port, int pct) {
    final normalizedMac = mac.toUpperCase();
    if (port != 'SYSTEM') {
      if (pct < 100) {
        busyDonglePorts.add(port);
        _portToMacMap[port] = normalizedMac;
      } else {
        busyDonglePorts.remove(port);
      }
    }

    for (var task in tasks.values) {
      bool isMatch = false;
      if (port != 'SYSTEM' && task.assignedPort == port) {
        task.mac = normalizedMac;
        isMatch = true;
      } else if (task.mac == normalizedMac) {
        isMatch = true;
      }

      if (isMatch) {
        if (task.status != JobStatus.burning && pct < 100) {
          task.status = JobStatus.burning;
        }
        task.progress = pct / 100.0;
        onStateChanged();
        break;
      }
    }
  }

  // 🔥 修正：解析音軌並存入全域快取
  void _parseTrackDetail(String msg) {
    try {
      final parts = msg.split("TRACK_DETAIL:")[1].trim().split(":");
      if (parts.length >= 3) {
        final index = int.parse(parts[0]);
        final id = int.parse(parts[1]);
        final size = int.parse(parts[2]);

        // 避免重複加入
        if (!_globalTrackCache.any((t) => t.index == index)) {
          _globalTrackCache.add(TaskTrackInfo(index, id, size));
          // 可選：可以嘗試把這個資訊也推給所有正在 verifying 的任務，但下方 checkLogForStatus 會處理
        }
      }
    } catch (e) {}
  }

  void _checkLogForStatus(TaskItem task, String msg, String port) {
    bool changed = false;

    // 1. 偵測驗證階段
    if (msg.contains("設備重啟") ||
        msg.contains("正在啟動語音") ||
        msg.contains("正在讀取資料")) {
      if (task.status != JobStatus.verifying) {
        task.status = JobStatus.verifying;
        task.progress = 1.0;
        changed = true;
      }
    }

    // 2. 偵測成功
    if (msg.contains("任務圓滿完成") || msg.contains("比對成功")) {
      if (task.status != JobStatus.success) {
        task.status = JobStatus.success;
        task.progress = 1.0;
        busyDonglePorts.remove(port);

        // 🔥 關鍵修正：任務完成時，把全域收集到的音軌資料塞給它
        if (task.tracks.isEmpty && _globalTrackCache.isNotEmpty) {
          task.tracks.addAll(_globalTrackCache);
          // 排序一下比較好看
          task.tracks.sort((a, b) => a.index.compareTo(b.index));
        }

        changed = true;
      }
    }

    // 3. 偵測失敗
    if (msg.contains("燒錄失敗") ||
        msg.contains("Write Fail") ||
        msg.contains("解鎖失敗")) {
      if (task.status != JobStatus.failed) {
        task.status = JobStatus.failed;
        changed = true;
      }
    }

    if (changed) {
      onStateChanged();
    }
  }

  void _addGlobalLog(String msg, String source) {
    final time = DateFormat('HH:mm:ss').format(DateTime.now());
    String cleanMsg = msg.replaceAll('🤖', '').replaceAll('⌛', '').trim();
    if (!cleanMsg.startsWith('[')) {
      cleanMsg = "[${source.padRight(8)}] $cleanMsg";
    }
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
    allDonglePorts = devices.map((d) => d.portName).toList();
    _addGlobalLog("Dongle 重整: 共發現 ${allDonglePorts.length} 支可用", "SYSTEM");
    onStateChanged();
  }
}
