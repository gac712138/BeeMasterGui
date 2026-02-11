// lib/app_state.dart

class ProjectAudio {
  final String id;
  final String name;
  final String? content;
  final String? fileUrl; // ✅ 修正：image_4c0057.png 的報錯
  final int audioTrackId; // ✅ 修正：image_4c61b2.png 的報錯

  ProjectAudio({
    required this.id,
    required this.name,
    this.content,
    this.fileUrl,
    required this.audioTrackId,
  });

  factory ProjectAudio.fromJson(Map<String, dynamic> json) {
    return ProjectAudio(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      content: json['content'],
      fileUrl: json['fileUrl'],
      // 確保 JSON 裡面的欄位名稱與 API 對應（可能是 audioTrackId）
      audioTrackId: json['audioTrackId'] ?? 0,
    );
  }
}

class Project {
  final String id;
  final String name;

  Project({required this.id, required this.name});

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Project',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AppState {
  static String? opsToken;
  static String? opsEmail;
  static bool get isOpsLoggedIn => opsToken != null;

  static String? dsmToken;
  static String? dsmEmail;
  static bool get isDsmLoggedIn => dsmToken != null;

  static List<Project> dsmProjects = [];
  static Project? selectedProject;

  // ✨ 新增：儲存目前選中專案的語音列表
  static List<ProjectAudio> currentProjectAudios = [];

  static void logoutOps() {
    opsToken = null;
    opsEmail = null;
  }

  static void logoutDsm() {
    dsmToken = null;
    dsmEmail = null;
    dsmProjects = [];
    selectedProject = null;
    currentProjectAudios = [];
  }
}
