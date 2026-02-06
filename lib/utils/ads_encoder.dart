// lib/utils/ads_encoder.dart
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../app_state.dart';
import '../config/base_audio_config.dart';

class AdsEncoder {
  static Future<Uint8List> convertToAds(
    String langCode,
    List<ProjectAudio> currentProjectAudios,
  ) async {
    final List<ProjectAudio> baseAudios = BaseAudioConfig.generateBasePacks(
      langCode,
    );
    List<ProjectAudio> totalAudios = [...baseAudios, ...currentProjectAudios];

    // 1. 數字排序 (Numeric Sort)
    totalAudios.sort((a, b) => a.audioTrackId.compareTo(b.audioTrackId));

    final Uint8List header = Uint8List(606);
    final ByteData headerView = ByteData.view(header.buffer);

    // 寫入 Magic Code
    header[0] = 0x27;
    header[1] = 0x9D;
    headerView.setUint16(2, totalAudios.length, Endian.little);

    List<Uint8List> payloads = [];
    int currentOffset = 606;

    for (int i = 0; i < totalAudios.length; i++) {
      final audio = totalAudios[i];
      int entryBase = 4 + (i * 12);

      try {
        final response = await http.get(Uri.parse(audio.fileUrl!));
        if (response.statusCode == 200) {
          // 🎯 修正處：直接提取 Signed PCM 數據，不進行 +32768 轉換
          Uint8List pcmData = _processPcmData(response.bodyBytes);

          payloads.add(pcmData);

          headerView.setUint32(entryBase, audio.audioTrackId, Endian.little);
          headerView.setUint32(entryBase + 4, currentOffset, Endian.little);
          headerView.setUint32(entryBase + 8, pcmData.length, Endian.little);

          currentOffset += pcmData.length;
        } else {
          _writeEmptyEntry(headerView, entryBase, audio.audioTrackId);
        }
      } catch (e) {
        _writeEmptyEntry(headerView, entryBase, audio.audioTrackId);
      }
    }

    // 2. Checksum 計算 (維持你目前可以被解析的邏輯)
    headerView.setUint16(604, 0xFFFF, Endian.little);
    int checksum = _calculateChecksum(header.sublist(0, 604));
    headerView.setUint16(604, checksum, Endian.little);

    final BytesBuilder builder = BytesBuilder();
    builder.add(header);
    for (var data in payloads) builder.add(data);

    return builder.toBytes();
  }

  /// 🎯 核心修正：維持 16-bit Signed PCM
  static Uint8List _processPcmData(Uint8List rawWav) {
    if (rawWav.length <= 44) return rawWav;

    // 直接跳過 44 bytes WAV 檔頭，獲取原始採樣
    // 因為 16-bit WAV 本身就是 Signed Little Endian，這與 dasLoop 的 test.ads 標竿一致
    final Uint8List pcm = Uint8List.sublistView(rawWav, 44);

    // 額外確保：長度必須是 2 的倍數 (16-bit 特性)
    if (pcm.length % 2 != 0) {
      return pcm.sublist(0, pcm.length - 1);
    }
    return pcm;
  }

  static int _calculateChecksum(Uint8List data) {
    int sum = 0;
    for (int b in data) {
      sum = (sum + b) & 0xFFFF;
    }
    return sum;
  }

  static void _writeEmptyEntry(ByteData headerView, int base, int id) {
    headerView.setUint32(base, id, Endian.little);
    headerView.setUint32(base + 4, 606, Endian.little);
    headerView.setUint32(base + 8, 0, Endian.little);
  }
}
