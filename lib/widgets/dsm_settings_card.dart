import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:beemaster_ui/utils/burn_task_sheet.dart';
// 引入必要的 Service 與其他檔案
import 'package:beemaster_ui/services/ads_service.dart';
import 'package:beemaster_ui/utils/app_state.dart';

class DsmSettingsCard extends StatefulWidget {
  // ✅ 新增：接收來自父層 (DeviceImportPage) 的有效 ID 列表
  final List<String> validDasIds;

  const DsmSettingsCard({
    super.key,
    required this.validDasIds, // 必須由父層傳入
  });

  @override
  State<DsmSettingsCard> createState() => _DsmSettingsCardState();
}

class _DsmSettingsCardState extends State<DsmSettingsCard> {
  // UI 讀取狀態
  bool _isLoadingProjects = false;
  bool _isLoadingAudios = false;
  bool _isProcessingAds = false;

  // 檔案生成狀態
  bool _isAdsReady = false;
  String? _adsFilePath;

  // Overlay 控制
  OverlayEntry? _taskOverlayEntry;

  @override
  void initState() {
    super.initState();
    // 初始化時，若已登入但無資料，自動抓取
    if (AppState.isDsmLoggedIn && AppState.dsmProjects.isEmpty) {
      _loadProjects();
    }
  }

  @override
  void dispose() {
    _closeTaskOverlay();
    super.dispose();
  }

  // ==========================================
  //  邏輯區：調用 AdsService
  // ==========================================

  // 1. 載入專案
  Future<void> _loadProjects() async {
    setState(() => _isLoadingProjects = true);
    try {
      final projects = await AdsService.fetchProjects();
      setState(() {
        AppState.dsmProjects = projects;
        if (AppState.dsmProjects.isNotEmpty) {
          AppState.selectedProject = AppState.dsmProjects.first;
          _loadAudios(AppState.selectedProject!.id);
        }
      });
    } catch (e) {
      _showMsg("載入專案失敗: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoadingProjects = false);
    }
  }

  // 2. 載入音訊
  Future<void> _loadAudios(String projectId) async {
    setState(() {
      _isLoadingAudios = true;
      AppState.currentProjectAudios = [];
      _isAdsReady = false; // 切換專案需重置
      _adsFilePath = null;
    });

    try {
      final audios = await AdsService.fetchAudios(projectId);
      setState(() {
        AppState.currentProjectAudios = audios;
      });
    } catch (e) {
      _showMsg("載入音訊失敗: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoadingAudios = false);
    }
  }

  // 3. 雲端生成流程 (包含選擇語系)
  Future<void> _handleCloudGeneration() async {
    // 3.1 選擇語系
    final Map<String, String> languages = {
      'cmn-HK': '廣東話',
      'en-US': '英文',
      'cmn-TW': '中文',
      'ja-JP': '日文',
    };

    String? selectedLang = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "選擇語系",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ...languages.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => Navigator.pop(context, e.key),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Center(
                            child: Text(
                              e.value,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("取消", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedLang == null) return;

    // 3.2 開始生成
    setState(() => _isProcessingAds = true);
    try {
      String path = await AdsService.generateAdsFile(
        selectedLang,
        AppState.currentProjectAudios,
        AppState.selectedProject?.name ?? "Project",
      );

      setState(() {
        _isAdsReady = true;
        _adsFilePath = path;
      });
      _showMsg("檔案已生成：${p.basename(path)}", Colors.green);
    } catch (e) {
      _showMsg("生成失敗: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessingAds = false);
    }
  }

  // 4. 本地載入流程
  Future<void> _handleLocalFile() async {
    String? path = await AdsService.pickLocalAdsFile();
    if (path != null) {
      setState(() {
        _adsFilePath = path;
        _isAdsReady = true;
      });
      _showMsg("已載入：${p.basename(path)}", Colors.green);
    }
  }

  // ==========================================
  //  UI 區：視窗控制與畫面
  // ==========================================

  void _showSourceSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "選擇來源",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.cloud_download, color: Colors.blue),
              title: const Text("雲端下載生成"),
              subtitle: const Text("透過 API 下載音訊並重新打包"),
              onTap: () {
                Navigator.pop(context);
                _handleCloudGeneration();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.orange),
              title: const Text("載入本地檔案"),
              subtitle: const Text("使用既有的 .ads 檔案"),
              onTap: () {
                Navigator.pop(context);
                _handleLocalFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openOverlay() {
    if (_taskOverlayEntry != null) return;
    if (_adsFilePath == null) return;

    // ✅ 修改：使用父層傳入的 validDasIds
    if (widget.validDasIds.isEmpty) {
      _showMsg("沒有可燒錄的目標，請先匯入 Excel", Colors.orange);
      return;
    }

    _taskOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        right: 20,
        bottom: 20,
        child: BurnTaskOverlay(
          adsFilePath: _adsFilePath!,
          targetIds: widget.validDasIds, // 使用真實資料
          onClose: _closeTaskOverlay,
        ),
      ),
    );
    Overlay.of(context).insert(_taskOverlayEntry!);
  }

  void _closeTaskOverlay() {
    _taskOverlayEntry?.remove();
    _taskOverlayEntry = null;
  }

  void _showMsg(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    bool isOk = AppState.isDsmLoggedIn;
    bool canUpdateVoice = _isAdsReady && widget.validDasIds.isNotEmpty;

    // 🔥 結構：Column -> [標題, Spacer/Expanded(白卡片)]
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. DSM 標題 (固定高度)
        Row(
          children: [
            const Text("DSM 設定", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            // ... (狀態燈號保持不變)
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
            if (AppState.dsmEmail != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    AppState.dsmEmail!,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. 白色卡片本體 (填滿剩餘高度)
        // 🔥 關鍵修改 3：這裡也要 Expanded，承接父層給的高度
        Expanded(
          child: Container(
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
            // 如果沒登入，顯示置中文字；如果登入，顯示內容
            child: isOk
                ? _buildLoggedInContent(canUpdateVoice)
                : const Center(
                    child: Text("請先登入", style: TextStyle(color: Colors.grey)),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedInContent(bool canUpdateVoice) {
    // 🔥 結構：Column -> [下拉選單, 標題, Expanded(列表), 按鈕]
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A. 下拉選單 (固定高度)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _isLoadingProjects
                    ? const LinearProgressIndicator()
                    : DropdownButtonHideUnderline(
                        child: DropdownButton(
                          value: AppState.selectedProject,
                          isExpanded: true,
                          items: AppState.dsmProjects
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => AppState.selectedProject = v);
                              _loadAudios(v.id);
                            }
                          },
                        ),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadProjects,
              ),
            ],
          ),
        ),

        const SizedBox(height: 15),
        const Text(
          "專案語音列表：",
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        // B. 音訊列表 (彈性高度)
        // 🔥 關鍵修改 4：列表容器使用 Expanded
        // 這解決了「小畫面爆版」的問題，因為它會自動縮小並產生卷軸
        Expanded(
          child: Container(
            width: double.infinity,
            // 注意：這裡移除了 constraints: BoxConstraints(maxHeight: 250)
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: _isLoadingAudios
                ? const Center(child: CircularProgressIndicator())
                : AppState.currentProjectAudios.isEmpty
                ? const Center(
                    child: Text("無資料", style: TextStyle(color: Colors.grey)),
                  )
                : ListView.separated(
                    // 讓 ListView 在有限空間內滾動
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: AppState.currentProjectAudios.length,
                    separatorBuilder: (c, i) =>
                        Divider(height: 1, color: Colors.grey[100]),
                    itemBuilder: (context, index) {
                      final audio = AppState.currentProjectAudios[index];
                      // ... (Item 內容保持不變) ...
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    audio.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  Text(
                                    audio.content ?? "",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (audio.fileUrl != null)
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                ),
                                child: Text(
                                  p.basename(Uri.parse(audio.fileUrl!).path),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),

        const SizedBox(height: 15),

        // C. 按鈕區 (固定高度)
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[50],
                  foregroundColor: Colors.grey[700],
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text("新增工人"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _isProcessingAds
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: !_isAdsReady
                          ? _showSourceSelection
                          : (canUpdateVoice ? _openOverlay : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                        foregroundColor: Colors.blue[900],
                        disabledBackgroundColor: Colors.grey[200],
                        disabledForegroundColor: Colors.grey[400],
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(_isAdsReady ? "更新語音" : "選擇語音"),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
