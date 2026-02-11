import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class AdsFileMeta {
  final Uint8List rawData;
  final Uint8List encodedData;
  final int sizeKB;

  AdsFileMeta({
    required this.rawData,
    required this.encodedData,
    required this.sizeKB,
  });
}

class AdsParser {
  // 解析並編碼 ADS 檔案
  static Future<AdsFileMeta?> parse(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint("❌ 檔案不存在: $path");
        return null;
      }

      final rawData = await file.readAsBytes();

      // 簡單檢查 Magic Code [0x27, 0x9D] (Go code: ads_reader.go)
      // 這裡直接進行編碼
      final encoded = _encodeAudioData(rawData);

      return AdsFileMeta(
        rawData: rawData,
        encodedData: encoded,
        sizeKB: rawData.length ~/ 1024,
      );
    } catch (e) {
      debugPrint("❌ 解析失敗: $e");
      return null;
    }
  }

  // 對應 Go: utils.go -> encodeAudioData
  static Uint8List _encodeAudioData(Uint8List rawData) {
    final buffer = BytesBuilder();

    for (int i = 0; i < rawData.length; i++) {
      if (i == 604 || i == 605) {
        // Offset 604, 605 必須填入 0xFF
        buffer.addByte(0xFF);
      } else if (i < 606) {
        // Header 區域直接複製
        buffer.addByte(rawData[i]);
      } else if (i % 2 == 0) {
        // 偶數位置直接複製
        buffer.addByte(rawData[i]);
      } else {
        // 🔥 奇數位置 + 0x80
        int val = rawData[i] + 0x80;
        buffer.addByte(val & 0xFF);
      }
    }
    return buffer.toBytes();
  }
}
