import 'package:flutter/material.dart';
import "device_import.dart";
import 'login_page.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 1;
  bool _isCollapsed = false; // 控制側邊欄收合狀態

  void _refreshUI() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // --- 左側導航欄 (Sidebar) ---
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isCollapsed ? 70 : 250, // 收合寬度 70, 展開 250
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(5, 0),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 選單內容
                Column(
                  children: [
                    const SizedBox(height: 10),
                    _buildMenuItem(0, Icons.upload_file, "裝置匯入"),
                    _buildMenuItem(1, Icons.login, "登入設定"),
                    const Spacer(),
                    if (!_isCollapsed)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          "Ver 1.0.0",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),

                // 收合按鈕 (懸浮)
                Positioned(
                  right: -12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isCollapsed = !_isCollapsed;
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 24,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isCollapsed
                              ? Icons.chevron_right
                              : Icons.chevron_left,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- 右側內容區 ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: _selectedIndex == 0
                  // ✅ 修正：移除 onRefresh 參數
                  ? const DeviceImportPage()
                  : LoginPage(onLoginSuccess: _refreshUI),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        height: 50,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: isSelected
              ? const Border(left: BorderSide(color: Colors.amber, width: 4))
              : null,
          color: isSelected
              ? Colors.amber.withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: _isCollapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.amber[800] : Colors.grey,
              size: 24,
            ),
            if (!_isCollapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.amber[800] : Colors.grey[700],
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
