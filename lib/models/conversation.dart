import 'message.dart';

class Conversation {
  final String id;
  final String type;
  final String? name;
  final String? avatar;
  final Message? lastMessage;
  final int unreadCount;
  final bool pinned;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatar,
    this.lastMessage,
    this.unreadCount = 0,
    this.pinned = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final rawGroupId = json['group_id'] ?? json['groupId'];
    final rawType = (json['type'] ?? json['conversation_type'] ?? json['kind'])?.toString().toLowerCase();
    final type = rawType == 'group' || rawGroupId != null ? 'group' : 'direct';
    final rawId = json['id'] ?? json['uid'] ?? rawGroupId ?? json['conversation_id'] ?? json['conversationId'];
    final rawLastMessage = json['last_message'] ?? json['lastMessage'] ?? json['latest_message'] ?? json['latestMessage'];
    return Conversation(
      id: rawId?.toString() ?? '',
      type: type,
      name: (json['name'] ?? json['display_name'] ?? json['displayName'] ?? json['username'] ?? json['nickname'])?.toString(),
      avatar: (json['avatar'] ?? json['avatar_url'] ?? json['avatarUrl'])?.toString(),
      lastMessage: rawLastMessage is Map
          ? Message.fromJson(Map<String, dynamic>.from(rawLastMessage))
          : null,
      unreadCount: _intValue(json['unread_count'] ?? json['unreadCount']),
      pinned: json['pinned'] == true || json['is_pinned'] == true || json['isPinned'] == true,
    );
  }

  static int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'avatar': avatar,
        'last_message': lastMessage?.toJson(),
        'unread_count': unreadCount,
        'pinned': pinned,
      };

  Conversation copyWith({
    String? name,
    String? avatar,
    Message? lastMessage,
    int? unreadCount,
    bool? pinned,
  }) {
    return Conversation(
      id: id,
      type: type,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      pinned: pinned ?? this.pinned,
    );
  }
}
