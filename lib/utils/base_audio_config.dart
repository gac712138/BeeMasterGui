import 'app_state.dart';

class BaseAudioConfig {
  // 🎯 這是從 C# 代碼中提取出的專屬 S3 路徑
  static const String s3BaseUrl =
      "https://dsm-production-assets.s3.ap-southeast-1.amazonaws.com/announcements/audios";

  // 🎯 定義各語系的開頭 ID (Enum Value)
  static const Map<String, int> languageIdMap = {
    'cmn-HK': 1, // 廣東話 Cantonese
    'en-US': 2, // 英文 English
    'cmn-TW': 3, // 中文 Mandarin
    'ja-JP': 5, // 日文 Japanese
  };

  /// 🎯 核心演算法：根據 C# 邏輯生成 12 則基礎語音清單
  static List<ProjectAudio> generateBasePacks(String langCode) {
    int? langId = languageIdMap[langCode];
    if (langId == null) return [];

    List<ProjectAudio> baseList = [];

    // C# 迴圈邏輯：1-9 則與 101-103 則
    for (int j = 1; j <= 9; j++) {
      // 產生 ID 格式：{LangID}00{j} (例如 4001)
      baseList.add(_create(langId * 1000 + j, "系統音-$j"));

      if (j <= 3) {
        // 產生 ID 格式：{LangID}10{j} (例如 4101)
        baseList.add(_create(langId * 1000 + 100 + j, "系統延伸音-$j"));
      }
    }

    // 依據 ID 進行嚴格排序
    baseList.sort((a, b) => a.audioTrackId.compareTo(b.audioTrackId));
    return baseList;
  }

  static ProjectAudio _create(int id, String name) => ProjectAudio(
    id: "base-$id",
    name: name,
    audioTrackId: id,
    fileUrl: "$s3BaseUrl/$id.wav", // 基礎語音固定從 S3 下載
  );
}
