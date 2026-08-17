import 'dart:convert' as convert;

class ChannelInfo {
  final String id;
  final String name;
  final String handle;
  final String avatarUrl;
  final String description;
  final int subscriberCount;
  final bool subscribed;
  final List<String> allowedEmojis;

  const ChannelInfo({
    required this.id,
    required this.name,
    this.handle = '',
    this.avatarUrl = '',
    this.description = '',
    this.subscriberCount = 0,
    this.subscribed = false,
    this.allowedEmojis = const [],
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['allowed_emojis'];
    final count = json['subscriber_count'] ?? json['channel_subscribers'] ?? 0;
    return ChannelInfo(
      id: '${json['id'] ?? json['channel_id'] ?? ''}',
      name: '${json['name'] ?? json['channel_name'] ?? '未命名频道'}',
      handle: '${json['handle'] ?? json['channel_handle'] ?? ''}',
      avatarUrl: '${json['avatar_url'] ?? json['avatar'] ?? ''}',
      description: '${json['description'] ?? ''}',
      subscriberCount: count is num
          ? count.toInt()
          : int.tryParse('$count') ?? 0,
      subscribed:
          json['subscribed'] == true || json['channel_subscribed'] == true,
      allowedEmojis: raw is List
          ? raw.map((e) => e.toString()).toList()
          : const [],
    );
  }

  ChannelInfo copyWith({bool? subscribed}) => ChannelInfo(
    id: id,
    name: name,
    handle: handle,
    avatarUrl: avatarUrl,
    description: description,
    subscriberCount: subscriberCount,
    subscribed: subscribed ?? this.subscribed,
    allowedEmojis: allowedEmojis,
  );
}

class ChannelPost {
  final String id;
  final String authorName;
  final String authorAvatar;
  final String text;
  final String? mediaUrl;
  final int createdAt;
  final int seq;
  final Map<String, dynamic> reactions;

  const ChannelPost({
    required this.id,
    required this.authorName,
    required this.authorAvatar,
    required this.text,
    required this.createdAt,
    this.mediaUrl,
    this.seq = 0,
    this.reactions = const {},
  });

  factory ChannelPost.fromJson(Map<String, dynamic> json) {
    final body = json['body'];
    Map<String, dynamic>? map;
    if (body is Map) {
      map = Map<String, dynamic>.from(body);
    } else if (body is String && body.trim().startsWith('{')) {
      try {
        final decoded = convert.jsonDecode(body);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final fallbackText = body is String && map == null
        ? body
        : json['content'] ?? json['text'] ?? '';
    final author = json['author'] is Map
        ? Map<String, dynamic>.from(json['author'])
        : const <String, dynamic>{};
    final rawCreatedAt = json['created_at'] ?? json['created_at_ts'] ?? 0;
    final rawSeq = json['post_seq'] ?? json['seq'] ?? json['sequence'] ?? 0;
    return ChannelPost(
      id: '${json['id'] ?? json['post_id'] ?? ''}',
      authorName:
          '${json['from_name'] ?? author['name'] ?? json['name'] ?? '频道'}',
      authorAvatar: '${json['from_avatar'] ?? author['avatar'] ?? ''}',
      text: '${map?['text'] ?? map?['content'] ?? fallbackText}',
      mediaUrl: (map?['media_url'] ?? map?['media'] ?? json['media_url'])
          ?.toString(),
      createdAt: rawCreatedAt is num
          ? rawCreatedAt.toInt()
          : int.tryParse('$rawCreatedAt') ?? 0,
      seq: rawSeq is num ? rawSeq.toInt() : int.tryParse('$rawSeq') ?? 0,
      reactions: (map?['reactions'] ?? json['reactions']) is Map
          ? Map<String, dynamic>.from(
              (map?['reactions'] ?? json['reactions']) as Map,
            )
          : const {},
    );
  }
}
