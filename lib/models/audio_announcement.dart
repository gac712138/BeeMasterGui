class AudioAnnouncement {
  final String id;
  final int audioTrackId;
  final String name;
  final String fileUrl;

  AudioAnnouncement({
    required this.id,
    required this.audioTrackId,
    required this.name,
    required this.fileUrl,
  });

  factory AudioAnnouncement.fromJson(Map<String, dynamic> json) {
    return AudioAnnouncement(
      id: json['id'],
      audioTrackId: json['audioTrackId'],
      name: json['name'],
      fileUrl: json['fileUrl'],
    );
  }
}
