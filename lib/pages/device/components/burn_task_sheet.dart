// lib/pages/device/components/burn_task_sheet.dart
import 'package:flutter/material.dart';
import '../../../utils/com_scanner.dart';

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
  List<DongleDeviceInfo> _availableDongles = [];
  late Map<String, Map<String, dynamic>> _taskStates;

  @override
  void initState() {
    super.initState();
    _taskStates = {
      for (var id in widget.targetIds)
        id: {
          "status": "等待分派",
          "progress": 0.0,
          "log": ["[${_now()}] 任務初始化..."],
        },
    };
    _refreshDongles();
  }

  String _now() => DateTime.now().toString().substring(11, 19);

  void _refreshDongles() {
    setState(() {
      _availableDongles = ComScanner.findDonglePorts();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 取得螢幕寬度
    final screenWidth = MediaQuery.of(context).size.width;
    // 設定最大寬度限制 (例如不超過 900)，避免在大螢幕上太寬
    final targetWidth = (screenWidth - 40).clamp(300.0, 900.0);

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        // 🎯 關鍵修改：展開時使用計算後的動態寬度
        width: _isExpanded ? targetWidth : 70,
        height: _isExpanded ? 650 : 70, // 高度稍微拉高一點
        child: _isExpanded ? _buildMainDashboard() : _buildFloatingBall(),
      ),
    );
  }

  Widget _buildMainDashboard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          _buildHeader(),
          // 上半部：任務清單 (Flex 佔比調大)
          Expanded(flex: 4, child: _buildTaskSection()),
          const Divider(height: 1, thickness: 1),
          // 下半部：Dongle 資源池
          Expanded(flex: 2, child: _buildDongleSection()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.settings_input_component,
            color: Colors.blue,
            size: 24,
          ),
          const SizedBox(width: 12),
          const Text(
            "產線燒錄控制器",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove, size: 24),
            onPressed: () => setState(() => _isExpanded = false),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 24),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSection() {
    return Container(
      color: const Color(0xFFFAFAFA), // 稍微灰一點的背景區分區塊
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.targetIds.length,
        itemBuilder: (context, index) {
          final id = widget.targetIds[index];
          final state = _taskStates[id]!;
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ExpansionTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.engineering, color: Colors.orange),
              ),
              title: Text(
                id,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: state['progress'],
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state['status'],
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
              trailing: Text(
                "${(state['progress'] * 100).toInt()}%",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFF1E1E1E), // 終端機風格黑底
                  child: ListView(
                    children: (state['log'] as List<String>)
                        .map(
                          (l) => Text(
                            l,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDongleSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "可用 DONGLE 資源 (COM)",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              InkWell(
                onTap: _refreshDongles,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.refresh, size: 14, color: Colors.blue),
                      SizedBox(width: 4),
                      Text(
                        "重新掃描",
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _availableDongles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.usb_off, size: 30, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        const Text(
                          "未偵測到 Silicon Labs 裝置",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableDongles.length,
                    itemBuilder: (context, index) {
                      final d = _availableDongles[index];
                      return Container(
                        width: 160, // 固定寬度卡片
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[100]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.usb,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  d.portName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              d.productName ?? "Unknown Device",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
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

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => print("開始讀取: ${widget.adsFilePath}"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            "啟動同步燒錄任務",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBall() {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.orange, width: 3),
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                value: 0.35,
                color: Colors.orange,
                strokeWidth: 4,
              ),
            ),
            Icon(Icons.engineering, color: Colors.orange, size: 32),
          ],
        ),
      ),
    );
  }
}
