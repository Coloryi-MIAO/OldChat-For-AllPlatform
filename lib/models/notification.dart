import 'dart:convert';

class NotificationModel {
  final String id;
  final String type;
  final String? fromUid;
  final String? fromName;
  final String? fromAvatar;
  final String title;
  final String body;
  final String? targetId;
  final bool isRead;
  final int createdAt;
  final List<String> mediaUrls;

  NotificationModel({
    required this.id,
    required this.type,
    this.fromUid,
    this.fromName,
    this.fromAvatar,
    required this.title,
    required this.body,
    this.targetId,
    this.isRead = false,
    required this.createdAt,
    this.mediaUrls = const [],
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final urls = <String>[];
    void add(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) add(item);
        return;
      }
      if (value is Map) {
        add(value['url'] ?? value['image_url'] ?? value['media_url'] ?? value['src'] ?? value['download_url']);
        return;
      }
      final text = value.toString().trim();
      if (text.isEmpty) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is List || decoded is Map) {
          add(decoded);
          return;
        }
      } catch (_) {}
      if (!urls.contains(text)) urls.add(text);
    }
    add(json['image_urls']);
    add(json['image_url']);
    add(json['images']);
    add(json['media_urls']);
    add(json['media_url']);
    add(json['media']);
    add(json['attachments']);
    add(json['file_url']);

    int toInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return NotificationModel(
      id: '${json['id'] ?? json['notification_id'] ?? ''}',
      type: '${json['type'] ?? ''}',
      fromUid: json['from_uid']?.toString(),
      fromName: (json['from_name'] ?? json['from_display_name'] ?? json['username'])?.toString(),
      fromAvatar: (json['from_avatar'] ?? json['avatar_url'])?.toString(),
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? json['text'] ?? json['content'] ?? ''}',
      targetId: (json['target_id'] ?? json['target'])?.toString(),
      isRead: json['is_read'] == true || json['read'] == true,
      createdAt: toInt(json['created_at']),
      mediaUrls: urls,
    );
  }
}
