import 'dart:convert';

class Moment {
  final String id;
  final String uid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String body;
  final String? imageUrl;
  final List<String> imageUrls;
  final int likes;
  final int comments;
  final bool isLiked;
  final int createdAt;
  final List<MomentComment>? commentList;

  Moment({
    required this.id,
    required this.uid,
    this.username,
    this.displayName,
    this.avatarUrl,
    required this.body,
    this.imageUrl,
    this.imageUrls = const [],
    this.likes = 0,
    this.comments = 0,
    this.isLiked = false,
    required this.createdAt,
    this.commentList,
  });

  factory Moment.fromJson(Map<String, dynamic> json) {
    final commentsList = json['comments_list'] ?? json['comment_list'];
    final urls = <String>[];
    void addImage(dynamic item) {
      if (item == null) return;
      if (item is List) {
        for (final nested in item) addImage(nested);
        return;
      }
      if (item is Map) {
        addImage(item['url'] ?? item['image_url'] ?? item['media_url'] ?? item['src'] ?? item['download_url'] ?? item['file_url']);
        return;
      }
      if (item is String) {
        final value = item.trim();
        if (value.isEmpty) return;
        try {
          final decoded = jsonDecode(value);
          if (decoded is List || decoded is Map) {
            addImage(decoded);
            return;
          }
        } catch (_) {}
        if (!urls.contains(value)) urls.add(value);
      }
    }
    addImage(json['image_urls']);
    addImage(json['images']);
    addImage(json['media_urls']);
    addImage(json['media']);
    addImage(json['image_url']);
    addImage(json['media_url'] ?? json['mediaUrl'] ??
        json['download_url'] ?? json['file_url'] ?? json['cover_url']);
    addImage(json['attachments']);
    addImage(json['media_list']);
    return Moment(
      id: json['id'] ?? '',
      uid: json['uid'] ?? json['from_uid'] ?? '',
      username: json['username'],
      displayName: json['display_name'] ?? json['nickname'],
      avatarUrl: json['avatar_url'] ?? json['from_avatar'],
      body: json['body'] ?? json['text'] ?? '',
      imageUrl: urls.isNotEmpty ? urls.first : null,
      imageUrls: urls,
      likes: json['likes'] ?? 0,
      comments: json['comments'] ?? 0,
      isLiked: json['liked'] ?? json['is_liked'] ?? false,
      createdAt: json['created_at'] ?? 0,
      commentList: (commentsList != null && commentsList is List)
          ? commentsList.map((e) => MomentComment.fromJson(e)).toList()
          : null,
    );
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'body': body,
        'image_urls': imageUrls,
        'likes': likes,
        'comments': comments,
        'liked': isLiked,
        'created_at': createdAt,
        if (commentList != null)
          'comments_list': commentList!.map((item) => item.toJson()).toList(),
      };
}

class MomentComment {
  final String id;
  final String uid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String text;
  final int createdAt;

  MomentComment({
    required this.id,
    required this.uid,
    this.username,
    this.displayName,
    this.avatarUrl,
    required this.text,
    required this.createdAt,
  });

  factory MomentComment.fromJson(Map<String, dynamic> json) {
    return MomentComment(
      id: json['id']?.toString() ?? '',
      uid: (json['uid'] ?? json['from_uid'] ?? '').toString(),
      username: json['username']?.toString(),
      displayName: (json['display_name'] ?? json['nickname'])?.toString(),
      avatarUrl: (json['avatar_url'] ?? json['from_avatar'])?.toString(),
      text: (json['text'] ?? json['body'] ?? '').toString(),
      createdAt: Moment._toInt(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'text': text,
        'created_at': createdAt,
      };
}
