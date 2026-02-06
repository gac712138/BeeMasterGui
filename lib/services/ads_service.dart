import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import '../app_state.dart';
import '../config.dart';
import '../utils/ads_encoder.dart';

class AdsService {
  // 1. 抓取專案列表
  static Future<List<Project>> fetchProjects() async {
    if (!AppState.isDsmLoggedIn) throw Exception("尚未登入");

    final uri = Uri.parse("${ApiConfig.dsmApiBaseUrl}/projects?archived=false");
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
      return data.map((e) => Project.fromJson(e)).toList();
    } else {
      throw Exception("無法取得專案列表: ${response.statusCode}");
    }
  }

  // 2. 抓取專案下的音訊檔
  static Future<List<ProjectAudio>> fetchAudios(String projectId) async {
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
      return data.map((e) => ProjectAudio.fromJson(e)).toList();
    } else {
      throw Exception("無法取得音訊列表");
    }
  }

  // 3. 生成 .ads 檔案並存檔
  static Future<String> generateAdsFile(
    String langCode,
    List<ProjectAudio> audios,
    String projectName,
  ) async {
    // 編碼
    final Uint8List adsFileBytes = await AdsEncoder.convertToAds(
      langCode,
      audios,
    );

    // 存檔 (Windows 存到文件資料夾/ads)
    final directory = await getApplicationDocumentsDirectory();
    final adsFolderPath = p.join(directory.path, 'ads');
    final adsFolder = Directory(adsFolderPath);

    if (!await adsFolder.exists()) {
      await adsFolder.create(recursive: true);
    }

    final fileName = '${projectName}_$langCode.ads';
    final filePath = p.join(adsFolderPath, fileName);

    await File(filePath).writeAsBytes(adsFileBytes);
    return filePath;
  }

  // 4. 選擇本地檔案
  static Future<String?> pickLocalAdsFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ads'],
    );

    if (result != null && result.files.single.path != null) {
      return result.files.single.path!;
    }
    return null;
  }
}
