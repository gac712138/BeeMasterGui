import 'package:flutter/material.dart';
import 'device/helmet_view.dart';
import 'device/beacon_view.dart';
import 'device/components/dsm_settings_card.dart';
import '../app_state.dart';
// 引入 Model 以便識別 WorkerImportData
import '../models/worker_import_data.dart';

class DeviceImportPage extends StatefulWidget {
  // ✅ 移除 onRefresh，配合 MainLayout 的修改
  const DeviceImportPage({super.key});

  @override
  State<DeviceImportPage> createState() => _DeviceImportPageState();
}

class _DeviceImportPageState extends State<DeviceImportPage> {
  int _currentSubTab = 0;

  // ✅ 狀態提升：用來儲存從工作臺 (HelmetView) 解析出來的 ID
  List<String> _currentDasIds = [];

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    // 右側面板寬度設定
    final double rightPanelWidth = (screenWidth * 0.25).clamp(280.0, 450.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 頂部導覽 (分隔線在這之下)
        _buildSubTabs(),
        const SizedBox(height: 20),

        // 2. 下方內容區：左右並排
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 👈 左側：工作臺 (安全帽或 Beacon)
              Expanded(
                child: _currentSubTab == 0
                    ? HelmetView(
                        // ✅ 監聽：當 Excel 解析完成，更新父層狀態
                        onDataParsed: (List<WorkerImportData> workers) {
                          setState(() {
                            // 取出 DasID 並過濾空值，轉為 List<String>
                            _currentDasIds = workers
                                .map((w) => w.dasId)
                                .where((id) => id.isNotEmpty)
                                .toList()
                                .cast<
                                  String
                                >(); // ⚠️ 這裡加了 cast<String>() 確保型別正確，解決報錯
                          });
                        },
                      )
                    : const BeaconView(),
              ),

              const SizedBox(width: 20),

              // 👉 右側：OPS/DSM 設定
              SizedBox(
                width: rightPanelWidth,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildOpsStatusCard(),
                      const SizedBox(height: 20),
                      // ✅ 傳遞：將 ID 傳給右側卡片，讓按鈕變亮
                      DsmSettingsCard(validDasIds: _currentDasIds),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          _buildTabItem(0, Icons.construction),
          const SizedBox(width: 40),
          _buildTabItem(1, Icons.sensors),
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

  // --- UI 元件：右側 OPS 卡片 ---
  Widget _buildOpsStatusCard() {
    return _simpleStatusCard(
      "OPS 設定",
      AppState.isOpsLoggedIn,
      AppState.isOpsLoggedIn ? _buildOpsControls() : _buildLoginHint(),
    );
  }

  Widget _buildOpsControls() => ElevatedButton(
    onPressed: () {},
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue[50],
      foregroundColor: Colors.blue[900],
      elevation: 0,
      minimumSize: const Size(double.infinity, 45),
    ),
    child: const Text("建立 ENDPOINT"),
  );

  Widget _buildLoginHint() => const Center(
    child: Padding(
      padding: EdgeInsets.all(20.0),
      child: Text("請先登入", style: TextStyle(color: Colors.grey)),
    ),
  );

  Widget _simpleStatusCard(String title, bool isOk, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isOk ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isOk ? "已連線" : "未連線",
                style: TextStyle(
                  fontSize: 10,
                  color: isOk ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}
