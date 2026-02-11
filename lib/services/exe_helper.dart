import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ExeHelper {
  /// 將 assets 裡的 exe 複製到應用程式支援目錄，並返回絕對路徑
  static Future<String> extractWorkerExe() async {
    try {
      // 1. 取得應用程式專屬目錄 (例如 C:\Users\xxx\AppData\Roaming\YourApp)
      final directory = await getApplicationSupportDirectory();
      final exePath = p.join(directory.path, 'worker.exe');
      final file = File(exePath);

      // 2. 為了確保版本最新，建議每次都覆蓋 (或檢查 hash)
      // 讀取 assets 裡的 binary
      final data = await rootBundle.load('worker.exe');
      final bytes = data.buffer.asUint8List();

      // 寫入硬碟
      await file.writeAsBytes(bytes, flush: true);

      print("✅ Worker EXE 已提取至: $exePath");
      return exePath;
    } catch (e) {
      print("❌ 提取 EXE 失敗: $e");
      rethrow;
    }
  }
}
