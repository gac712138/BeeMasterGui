import 'package:flutter/material.dart';
import 'package:beemaster_ui/utils/burn_task_controller.dart';

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
  bool _isExpanded = true;
  bool _showExitConfirm = false;

  late BurnTaskController _controller;
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = BurnTaskController(
      targetIds: widget.targetIds,
      onStateChanged: () {
        if (mounted) {
          setState(() {});
          if (_logScrollController.hasClients) {
            _logScrollController.jumpTo(
              _logScrollController.position.maxScrollExtent,
            );
          }
        }
      },
      onMessage: (msg, isError) {
        if (mounted) _showMsg(msg, isError ? Colors.red : Colors.green);
      },
    );
    _controller.init(widget.adsFilePath);
  }

  @override
  void dispose() {
    _controller.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _handleClose() {
    // 🔥 優化：如果全部完成了，直接關閉，不用跳確認窗
    if (_controller.isAllTasksCompleted) {
      _confirmClose();
      return;
    }

    // 檢查是否有正在進行的任務 (包含 burning, pending, verifying)
    bool isBusy =
        _controller.isSystemRunning ||
        _controller.tasks.values.any(
          (t) =>
              t.status == JobStatus.burning ||
              t.status == JobStatus.pending ||
              t.status == JobStatus.verifying,
        );

    if (isBusy) {
      setState(() {
        _showExitConfirm = true;
      });
    } else {
      _confirmClose();
    }
  }

  void _confirmClose() {
    _controller.stopSystem();
    widget.onClose();
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double width = _isExpanded ? screenSize.width : 70;
    final double height = _isExpanded ? screenSize.height : 70;
    final margin = _isExpanded
        ? const EdgeInsets.all(24)
        : const EdgeInsets.only(right: 20, bottom: 20);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: _isExpanded ? Alignment.center : Alignment.bottomRight,
            child: Padding(
              padding: margin,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isExpanded ? (width - 48) : width,
                height: _isExpanded ? (height - 48) : height,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_isExpanded ? 16 : 35),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 20),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_isExpanded ? 16 : 35),
                  child: _isExpanded ? _buildDashboard() : _buildFloatingBall(),
                ),
              ),
            ),
          ),
          if (_showExitConfirm) _buildExitDialog(),
        ],
      ),
    );
  }

  Widget _buildExitDialog() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "確認結束任務？",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text("作業正在進行中，確定要離開嗎？", style: TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _showExitConfirm = false),
                    child: const Text("取消"),
                  ),
                  ElevatedButton(
                    onPressed: _confirmClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("強制結束"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildSectionTitle("任務進度 (${widget.targetIds.length})"),
                    Expanded(child: _buildTaskList()),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _buildSectionTitle("系統日誌 Console"),
                    Expanded(child: _buildConsole()),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildSectionTitle("Dongle 資源池"),
                    Expanded(child: _buildDongleGrid()),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Colors.grey[100],
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: widget.targetIds.length,
        itemBuilder: (context, index) {
          final id = widget.targetIds[index];
          if (!_controller.tasks.containsKey(id)) return const SizedBox();
          final task = _controller.tasks[id]!;
          // 🔥 改用可展開的卡片
          return _buildExpandableTaskCard(task);
        },
      ),
    );
  }

  // 🔥 核心修改：可展開的任務卡片 (顯示音軌詳情)
  Widget _buildExpandableTaskCard(TaskItem task) {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.help;
    String statusText = "未知";

    switch (task.status) {
      case JobStatus.pending:
        statusColor = Colors.blueGrey;
        statusIcon = Icons.radar;
        statusText = "搜尋/等待中...";
        break;
      case JobStatus.burning:
        statusColor = Colors.orange;
        statusIcon = Icons.local_fire_department;
        statusText = "燒錄中 (${(task.progress * 100).toInt()}%)";
        break;
      case JobStatus.verifying:
        statusColor = Colors.purple;
        statusIcon = Icons.compare_arrows;
        statusText = "重啟比對中...";
        break;
      case JobStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = "完成 (點擊展開)";
        break;
      case JobStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = "失敗 (重試中)";
        break;
    }

    // 卡片標題內容
    Widget contentRow = Row(
      children: [
        Icon(statusIcon, color: statusColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            task.dasId,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );

    // 1. 若非成功狀態，顯示普通卡片 + 進度條
    if (task.status != JobStatus.success) {
      return Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Column(
            children: [
              contentRow,
              if (task.status == JobStatus.burning)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    backgroundColor: Colors.orange[50],
                    color: Colors.orange,
                    minHeight: 4,
                  ),
                ),
              if (task.status == JobStatus.verifying)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.purple[50],
                    color: Colors.purple,
                    minHeight: 4,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 2. 若為成功狀態，顯示可展開卡片 (ExpansionTile)
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.green, width: 1), // 綠框強調
        borderRadius: BorderRadius.circular(4),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          title: contentRow,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.green[50]),
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "✅ 安全帽內音訊詳細清單",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Divider(height: 10),
                  if (task.tracks.isEmpty)
                    const Text("無詳細資訊", style: TextStyle(color: Colors.grey)),

                  // 列出所有音軌
                  ...task.tracks.map(
                    (t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check,
                            color: Colors.green,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "#${t.index}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "ID: ${t.id}",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            "Size: ${t.size}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        controller: _logScrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _controller.globalLogs.length,
        itemBuilder: (context, index) {
          final log = _controller.globalLogs[index];
          Color textColor = Colors.greenAccent;
          if (log.contains("❌") || log.contains("💥")) {
            textColor = Colors.redAccent;
          } else if (log.contains("⚠️")) {
            textColor = Colors.orangeAccent;
          } else if (log.contains("[SYSTEM]")) {
            textColor = Colors.cyanAccent;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              log,
              style: TextStyle(
                color: textColor,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDongleGrid() {
    final ports = _controller.allDonglePorts;

    if (ports.isEmpty) {
      return const Center(
        child: Text("無可用 Dongle", style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.6, // 稍微調整比例，讓文字更清楚
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: ports.length,
        itemBuilder: (context, index) {
          final port = ports[index];

          // 🔥 改進 1：透過 Controller 獲取更精確的狀態文字
          final statusText = _controller.getPortStatusText(port);
          final isBusy = _controller.isPortBusy(port);

          // 🔥 改進 2：如果忙碌，嘗試找出它正在處理哪個任務，顯示進度
          String detailText = statusText;
          if (isBusy) {
            // 嘗試找對應任務
            try {
              final task = _controller.tasks.values.firstWhere(
                (t) => t.assignedPort == port,
              );
              if (task.status == JobStatus.burning) {
                detailText = "燒錄 ${(task.progress * 100).toInt()}%";
              } else if (task.status == JobStatus.verifying) {
                detailText = "驗證中";
              } else {
                detailText = "作業中";
              }
            } catch (e) {
              // 找不到對應任務，維持原樣
            }
          }

          return Container(
            decoration: BoxDecoration(
              color: isBusy ? Colors.orange[50] : Colors.green[50],
              border: Border.all(color: isBusy ? Colors.orange : Colors.green),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.usb, color: isBusy ? Colors.orange : Colors.green),
                const SizedBox(height: 4),
                Text(
                  port,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detailText, // 使用動態狀態文字
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isBusy ? Colors.orange[800] : Colors.green[800],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.settings_input_component, color: Colors.blue),
          const SizedBox(width: 10),
          const Text(
            "燒錄任務中心",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            tooltip: "最小化",
            icon: const Icon(Icons.remove),
            onPressed: () => setState(() => _isExpanded = false),
          ),
          IconButton(
            tooltip: "結束任務",
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: _handleClose,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    // 檢查是否所有任務都已成功
    bool allCompleted = _controller.isAllTasksCompleted;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          // 如果全部完成，按鈕功能變成「關閉視窗」
          // 否則，如果系統正在跑則 disable (防止重複按)
          onPressed: allCompleted
              ? _confirmClose
              : (_controller.isSystemRunning ? null : _controller.startSystem),

          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            // 全部完成變綠色，否則為藍色
            backgroundColor: allCompleted
                ? Colors.green[700]
                : Colors.blue[800],
            foregroundColor: Colors.white,
          ),
          child: allCompleted
              ? const Text("✅ 所有任務已完成 (點擊關閉)")
              : (_controller.isSystemRunning
                    ? const Text("系統運行中 (自動燒錄模式)...")
                    : const Text("啟動全自動燒錄")),
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
        child: const Icon(Icons.engineering, color: Colors.white, size: 30),
      ),
    );
  }
}
