import 'dart:async';
import 'package:flutter/material.dart';

import 'package:beemaster_ui/utils/com_scanner.dart';
import 'package:beemaster_ui/utils/protocol/ads_parser.dart';
import 'package:beemaster_ui/services/burn_worker.dart';
import 'package:beemaster_ui/utils/ble_scanner.dart';

// 定義任務狀態
enum JobStatus {
  scanning, // 正在尋找藍牙訊號
  queued, // 已找到 MAC，等待 Dongle
  burning, // 正在燒錄中
  success, // 成功
  failed, // 失敗 (等待重試)
}

class TaskItem {
  final String dasId;
  String? macAddress;
  JobStatus status;
  double progress;
  List<String> logs;
  String? assignedPort; // 目前被誰認領

  TaskItem(this.dasId)
    : status = JobStatus.scanning,
      progress = 0.0,
      logs = [],
      macAddress = null;
}

class BurnTaskOverlay extends StatefulWidget {
  final String adsFilePath;
  final List<String> targetIds;
  final VoidCallback onClose;

  const BurnTaskOverlay({
    super.key,
    required this.adsFilePath,
    required this.targetIds,
    required this.onClose,
  });

  @override
  State<BurnTaskOverlay> createState() => _BurnTaskOverlayState();
}

class _BurnTaskOverlayState extends State<BurnTaskOverlay> {
  // UI 狀態
  bool _isExpanded = true;
  bool _isSystemRunning = false; // 總開關

  // 資源池
  List<String> _allDonglePorts = []; // 所有偵測到的 COM
  final Set<String> _busyDonglePorts = {}; // 正在忙碌的 COM

  // 任務清單 (DasID -> Task)
  late Map<String, TaskItem> _tasks;

  // 檔案快取
  AdsFileMeta? _fileMeta;

  // 定時調度器
  Timer? _schedulerTimer;

  @override
  void initState() {
    super.initState();
    // 1. 初始化任務
    _tasks = {for (var id in widget.targetIds) id: TaskItem(id)};

    // 2. 預載入檔案 (只讀一次)
    _loadFile();

    // 3. 掃描 COM Port
    _refreshDongles();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    BleScanner.stop();
    super.dispose();
  }

  Future<void> _loadFile() async {
    final meta = await AdsParser.parse(widget.adsFilePath);
    if (meta != null) {
      _fileMeta = meta;
      _logSystem("檔案載入成功 (${meta.sizeKB} KB)");
    } else {
      _logSystem("❌ 檔案載入失敗！無法啟動任務");
    }
  }

  void _logSystem(String msg) {
    print("[SYSTEM] $msg");
  }

  void _refreshDongles() {
    final devices = ComScanner.findDonglePorts();
    setState(() {
      _allDonglePorts = devices.map((d) => d.portName).toList();
    });
  }

  // ==========================================
  // 核心邏輯：啟動系統
  // ==========================================
  void _startSystem() {
    if (_fileMeta == null) {
      _showMsg("檔案尚未準備好，無法啟動", Colors.red);
      return;
    }
    if (_allDonglePorts.isEmpty) {
      _showMsg("沒有可用的 Dongle，無法啟動", Colors.red);
      return;
    }

    setState(() => _isSystemRunning = true);

    // 1. 啟動藍牙掃描 (生產者)
    BleScanner.startListening(
      onDeviceFound: (name, mac, rssi) {
        // 🔥 除錯用：印出所有掃到的東西到 VSCode Console
        // 這樣如果 UI 沒反應，看 Console 就知道是不是名字有空白鍵之類的差異
        print("[BLE RAW] Name: '$name' | MAC: $mac | RSSI: $rssi");

        // 遍歷所有任務，看有沒有匹配的
        _tasks.forEach((dasId, task) {
          // 比對邏輯：忽略大小寫，並修剪前後空白
          // 您的 CLI 邏輯是 strings.Contains(name, targetID)
          if (name.isNotEmpty &&
              name.toLowerCase().contains(dasId.toLowerCase().trim())) {
            if (task.macAddress == null) {
              setState(() {
                task.macAddress = mac;
                task.status = JobStatus.queued;
                // UI 上顯示捕獲
                task.logs.add("✅ 捕獲目標: $name ($mac)");
                task.logs.add("📡 訊號強度: $rssi dBm");
              });
            }
          }
        });
      },
      onError: (err) {
        _logSystem("BLE Error: $err");
        _showMsg("藍牙掃描錯誤: $err", Colors.red);
      },
    );

    // 2. 啟動調度器 (消費者分配邏輯) - 每 1 秒檢查一次
    _schedulerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _runScheduler();
    });
  }

  // 調度器：負責將「閒置 Dongle」分配給「已就緒任務」
  void _runScheduler() {
    // 找出閒置的 Dongle
    List<String> idleDongles = _allDonglePorts
        .where((p) => !_busyDonglePorts.contains(p))
        .toList();

    if (idleDongles.isEmpty) return; // 沒人有空

    // 找出需要執行的任務 (Queued 或 Failed 需要重試的)
    List<TaskItem> pendingTasks = _tasks.values
        .where(
          (t) => t.status == JobStatus.queued || t.status == JobStatus.failed,
        )
        .toList();

    if (pendingTasks.isEmpty) return; // 沒事可做

    // --- 開始配對 ---
    for (var task in pendingTasks) {
      if (idleDongles.isEmpty) break; // Dongle 用光了

      String port = idleDongles.removeAt(0); // 取出一個 Dongle
      _assignWorker(port, task);
    }
  }

  // 指派並執行
  Future<void> _assignWorker(String port, TaskItem task) async {
    setState(() {
      _busyDonglePorts.add(port); // 標記 Dongle 忙碌
      task.status = JobStatus.burning;
      task.assignedPort = port;
      task.logs.add("🚀 分配給 Dongle $port 開始燒錄...");
    });

    try {
      final worker = BurnWorker(
        portName: port,
        taskId: task.dasId,
        targetMac: task.macAddress!, // 一定有值，因為只有 Queued 才會進來
        meta: _fileMeta!,
        onLog: (msg) {
          if (mounted) setState(() => task.logs.add(msg));
        },
        onProgress: (pct) {
          if (mounted) setState(() => task.progress = pct);
        },
      );

      bool success = await worker.start();

      if (mounted) {
        setState(() {
          if (success) {
            task.status = JobStatus.success;
            task.logs.add("🎉 燒錄成功！任務結束。");
          } else {
            task.status = JobStatus.failed; // 標記失敗，讓調度器下次重新抓取
            task.logs.add("❌ 燒錄失敗，釋放 Dongle，等待接手...");
            task.assignedPort = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = JobStatus.failed;
          task.logs.add("💥 發生異常: $e");
          task.assignedPort = null;
        });
      }
    } finally {
      // 無論成功失敗，都釋放 Dongle
      if (mounted) {
        setState(() {
          _busyDonglePorts.remove(port);
        });
      }
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ==========================================
  // UI 構建
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final targetWidth = (screenWidth - 40).clamp(300.0, 1200.0);

    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isExpanded ? targetWidth : 70,
          height: _isExpanded ? 650 : 70,
          child: _isExpanded ? _buildDashboard() : _buildFloatingBall(),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(flex: 4, child: _buildTaskList()),
          const Divider(height: 1),
          Expanded(flex: 2, child: _buildDongleList()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.targetIds.length,
        itemBuilder: (context, index) {
          final id = widget.targetIds[index];
          final task = _tasks[id]!;
          return _buildTaskCard(task);
        },
      ),
    );
  }

  Widget _buildTaskCard(TaskItem task) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (task.status) {
      case JobStatus.scanning:
        statusColor = Colors.grey;
        statusIcon = Icons.radar;
        statusText = "正在搜尋裝置...";
        break;
      case JobStatus.queued:
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_top;
        statusText = "已找到 (${task.macAddress})，等待 Dongle...";
        break;
      case JobStatus.burning:
        statusColor = Colors.orange;
        statusIcon = Icons.local_fire_department;
        statusText = "燒錄中 (由 ${task.assignedPort} 執行)";
        break;
      case JobStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = "完成";
        break;
      case JobStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = "失敗 - 等待重試";
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          task.dasId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusText,
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
            if (task.status == JobStatus.burning)
              LinearProgressIndicator(value: task.progress),
          ],
        ),
        children: [
          Container(
            height: 100,
            color: Colors.black87,
            padding: const EdgeInsets.all(8),
            child: ListView.builder(
              itemCount: task.logs.length,
              itemBuilder: (c, i) => Text(
                task.logs[i],
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDongleList() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Dongle 資源池 (${_allDonglePorts.length})",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _isSystemRunning ? null : _refreshDongles,
                icon: const Icon(Icons.refresh),
                label: const Text("重整"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _allDonglePorts.length,
              itemBuilder: (context, index) {
                final port = _allDonglePorts[index];
                final isBusy = _busyDonglePorts.contains(port);
                return Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isBusy ? Colors.orange[50] : Colors.green[50],
                    border: Border.all(
                      color: isBusy ? Colors.orange : Colors.green,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.usb,
                        color: isBusy ? Colors.orange : Colors.green,
                      ),
                      Text(
                        port,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isBusy ? "工作中" : "閒置",
                        style: TextStyle(
                          fontSize: 10,
                          color: isBusy ? Colors.orange : Colors.green,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      color: Colors.grey[100],
      child: Row(
        children: [
          const Icon(Icons.settings_input_component, color: Colors.blue),
          const SizedBox(width: 10),
          const Text(
            "自動化產線控制中心",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => widget.onClose(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSystemRunning ? null : _startSystem,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            backgroundColor: Colors.blue[800],
            foregroundColor: Colors.white,
          ),
          child: _isSystemRunning
              ? const Text("系統運行中 (自動調度)...")
              : const Text("啟動自動化燒錄作業"),
        ),
      ),
    );
  }

  Widget _buildFloatingBall() {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.engineering, color: Colors.white),
      ),
    );
  }
}
