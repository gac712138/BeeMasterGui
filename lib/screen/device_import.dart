import 'package:flutter/material.dart';
import 'package:beemaster_ui/widgets/helmet_view.dart';
import 'package:beemaster_ui/widgets/beacon_view.dart';

class DeviceImportPage extends StatefulWidget {
  const DeviceImportPage({super.key});

  @override
  State<DeviceImportPage> createState() => _DeviceImportPageState();
}

class _DeviceImportPageState extends State<DeviceImportPage> {
  int _currentSubTab = 0; // 0: Helmet, 1: Beacon

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 頂部導覽
        _buildSubTabs(),
        const SizedBox(height: 20),

        // 2. 下方內容區
        // 這裡不需要 Row，因為 HelmetView 內部已經處理好左右分欄了
        Expanded(
          child: _currentSubTab == 0 ? const HelmetView() : const BeaconView(),
        ),
      ],
    );
  }

  // --- UI 元件：Sub-Tabs ---
  Widget _buildSubTabs() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          _buildTabItem(0, Icons.construction), // 安全帽
          const SizedBox(width: 40),
          _buildTabItem(1, Icons.sensors), // Beacon
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon) {
    bool isActive = _currentSubTab == index;
    return InkWell(
      onTap: () => setState(() => _currentSubTab = index),
      child: Container(
        padding: const EdgeInsets.only(bottom: 10, left: 5, right: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFFFFA000) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Icon(
          icon,
          size: 28,
          color: isActive ? const Color(0xFFFFA000) : Colors.grey[300]!,
        ),
      ),
    );
  }
}
