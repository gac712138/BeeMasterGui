import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// ✅ 補上這個 import，解決 AdsFileMeta 找不到的問題
import 'package:beemaster_ui/utils/protocol/ads_parser.dart';
import 'dongle_transport.dart'; // 確保同目錄下有 dongle_transport.dart

class BurnWorker {
  final String portName;
  final String taskId;
  final String targetMac;
  final AdsFileMeta meta; // 現在這裡不會報錯了
  final Function(String log) onLog;
  final Function(double progress) onProgress;

  BurnWorker({
    required this.portName,
    required this.taskId,
    required this.targetMac,
    required this.meta,
    required this.onLog,
    required this.onProgress,
  });

  Future<bool> start() async {
    final t = DongleTransport(portName);

    if (!t.open()) {
      onLog("❌ 無法開啟 COM Port");
      return false;
    }

    try {
      // 1. 解析 MAC
      List<int> macBytes = _parseMac(targetMac);

      // 2. 連線
      onLog("⏳ 連線至 $targetMac...");
      if (!await t.connectToHelmet(macBytes)) {
        onLog("❌ 連線失敗 (Handshake Fail)");
        return false;
      }

      onLog("🔓 解鎖裝置...");

      // 4. 初始化 Flash Checksum
      onLog("🧹 初始化 Flash...");
      if (!await t.sendAudioChunk(604, Uint8List.fromList([0xFF, 0xFF]))) {
        onLog("❌ 初始化指令失敗");
        return false;
      }
      if (!await t.waitForAck(const Duration(seconds: 2))) {
        onLog("⚠️ 初始化無回應");
        return false;
      }

      // 5. 燒錄迴圈
      int totalSize = meta.encodedData.length;
      int currentOffset = 0;
      const int chunkSize = 192;

      onLog("🔥 開始燒錄 (Size: ${meta.sizeKB} KB)...");

      while (currentOffset < totalSize) {
        int end = currentOffset + chunkSize;
        if (end > totalSize) end = totalSize;

        Uint8List chunk = meta.encodedData.sublist(currentOffset, end);
        bool packetSuccess = false;

        for (int retry = 0; retry < 5; retry++) {
          t.resetBuffer();
          await t.sendAudioChunk(currentOffset, chunk);

          if (await t.waitForAck(const Duration(milliseconds: 1500))) {
            packetSuccess = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (!packetSuccess) {
          onLog("❌ 燒錄失敗 (Offset: $currentOffset)");
          return false;
        }

        currentOffset = end;
        onProgress(currentOffset / totalSize);
      }

      // 6. Checksum 驗證
      onLog("🔐 驗證 Checksum...");
      Uint8List realChecksum = meta.rawData.sublist(604, 606);
      await t.sendAudioChunk(604, realChecksum);

      if (!await t.waitForAck(const Duration(seconds: 3))) {
        onLog("❌ 驗證失敗");
        return false;
      }

      onLog("🎉 燒錄成功！");
      return true;
    } catch (e) {
      onLog("❌ 異常: $e");
      return false;
    } finally {
      t.close();
    }
  }

  List<int> _parseMac(String mac) {
    String clean = mac.replaceAll(":", "");
    List<int> bytes = [];
    for (int i = 0; i < clean.length; i += 2) {
      if (i + 2 <= clean.length) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
    }
    return bytes;
  }
}
