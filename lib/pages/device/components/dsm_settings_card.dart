import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../app_state.dart';
import '../../../config.dart';
import '../../../utils/ads_encoder.dart'; // ✅ 引入新抽離的工具類別

class DsmSettingsCard extends StatefulWidget {
  const DsmSettingsCard({super.key});

  @override
  State<DsmSettingsCard> createState() => _DsmSettingsCardState();
}

class _DsmSettingsCardState extends State<DsmSettingsCard> {
  bool _isLoadingProjects = false;
  bool _isLoadingAudios = false;
  bool _isUpdatingAudio = false;

  @override
  void initState() {
    super.initState();
    if (AppState.isDsmLoggedIn && AppState.dsmProjects.isEmpty) {
      _fetchProjects();
    }
  }

  // --- API: 抓取專案 ---
  Future<void> _fetchProjects() async {
    if (!AppState.isDsmLoggedIn) return;
    setState(() {
      _isLoadingProjects = true;
      AppState.selectedProject = null;
    });

    try {
      final uri = Uri.parse(
        "${ApiConfig.dsmApiBaseUrl}/projects?archived=false",
      );
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer ${AppState.dsmToken}",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        final List<dynamic> data = json['data'];
        setState(() {
          AppState.dsmProjects = data.map((e) => Project.fromJson(e)).toList();
          if (AppState.dsmProjects.isNotEmpty) {
            AppState.selectedProject = AppState.dsmProjects.first;
            _fetchAudios(AppState.selectedProject!.id);
          }
        });
      }
    } catch (e) {
      debugPrint("API Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingProjects = false);
    }
  }

  // --- API: 抓取專案語音列表 ---
  Future<void> _fetchAudios(String projectId) async {
    setState(() {
      _isLoadingAudios = true;
      AppState.currentProjectAudios = [];
    });
    try {
      final uri = Uri.parse(
        "${ApiConfig.dsmApiBaseUrl}/projects/$projectId/announcement-audios",
      );
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer ${AppState.dsmToken}",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        final List<dynamic> data = json['data'];
        setState(() {
          AppState.currentProjectAudios = data
              .map((e) => ProjectAudio.fromJson(e))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Audio API Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingAudios = false);
    }
  }

  // --- 🎯 步驟 1: 彈出語系選擇視窗 ---
  Future<void> _showLanguagePicker() async {
    final Map<String, String> languages = {
      'cmn-HK': '廣東話',
      'en-US': '英文',
      'cmn-TW': '中文',
      'ja-JP': '日文',
    };

    String? selectedLangCode = await showDialog<String>(
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
                "選擇燒錄語系基礎包",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
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
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
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

    if (selectedLangCode != null) {
      _processAdsPacking(selectedLangCode);
    }
  }

  // --- 🚀 步驟 2: 委派 AdsEncoder 執行打包 ---
  Future<void> _processAdsPacking(String langCode) async {
    setState(() => _isUpdatingAudio = true);
    _showMsg("正在準備合併打包流程...", Colors.blue);

    try {
      // 🎯 職責抽離：UI 層不再涉及二進位位元運算，全部交給工具類別
      final Uint8List adsFile = await AdsEncoder.convertToAds(
        langCode,
        AppState.currentProjectAudios,
      );

      // 儲存檔案
      String? path = await FilePicker.platform.saveFile(
        dialogTitle: '儲存合併語音包',
        fileName: '${AppState.selectedProject?.name}_$langCode.ads',
        allowedExtensions: ['ads'],
      );

      if (path != null) {
        await File(path).writeAsBytes(adsFile);
        _showMsg("ADS 語音包打包成功！", Colors.green);
      }
    } catch (e) {
      _showMsg("打包失敗: $e", Colors.red);
      debugPrint("Packing Error: $e");
    } finally {
      if (mounted) setState(() => _isUpdatingAudio = false);
    }
  }

  void _showMsg(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildStatusCard(
      "DSM 設定",
      AppState.isDsmLoggedIn,
      AppState.dsmEmail,
      AppState.isDsmLoggedIn ? _buildDsmContent() : _buildLoginHint(),
    );
  }

  Widget _buildDsmContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProjectDropdown(),
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
        _buildAudioList(),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _buildBtn("新增工人", () {})),
            const SizedBox(width: 10),
            Expanded(
              child: _isUpdatingAudio
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBtn("更新語音", _showLanguagePicker, isPrimary: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProjectDropdown() {
    return Container(
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
                    child: DropdownButton<Project>(
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
                          _fetchAudios(v.id);
                        }
                      },
                    ),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _fetchProjects,
          ),
        ],
      ),
    );
  }

  Widget _buildAudioList() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: _isLoadingAudios
          ? const Center(child: CircularProgressIndicator())
          : AppState.currentProjectAudios.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "尚無語音資料",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: AppState.currentProjectAudios.length,
              separatorBuilder: (c, i) =>
                  Divider(height: 1, color: Colors.grey[100]),
              itemBuilder: (context, index) {
                final audio = AppState.currentProjectAudios[index];
                String fileName = audio.fileUrl != null
                    ? Uri.parse(audio.fileUrl!).pathSegments.last
                    : "Unknown.wav";
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            audio.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF90A4AE),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        audio.content ?? "content",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildBtn(
    String text,
    VoidCallback onPressed, {
    bool isPrimary = false,
  }) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: isPrimary ? Colors.blue[50] : Colors.grey[50],
      foregroundColor: isPrimary ? Colors.blue[900] : Colors.grey[700],
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 15),
    ),
    child: Text(text),
  );

  Widget _buildLoginHint() => const Center(
    child: Padding(
      padding: EdgeInsets.all(20.0),
      child: Text("請先登入", style: TextStyle(color: Colors.grey)),
    ),
  );

  Widget _buildStatusCard(
    String title,
    bool isOk,
    String? email,
    Widget child,
  ) {
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
            if (email != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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
