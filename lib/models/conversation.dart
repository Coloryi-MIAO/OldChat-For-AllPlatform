import 'message.dart';

class Conversation {
  final String id;
  final String type;
  final String? name;
  final String? avatar;
  final String? ownerUid;
  final String? role;
  final bool isAdmin;
  final bool isOwner;
  final int memberCount;
  final String? announcement;
  final Message? lastMessage;
  final int unreadCount;
  final bool pinned;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatar,
    this.ownerUid,
    this.role,
    this.isAdmin = false,
    this.isOwner = false,
    this.memberCount = 0,
    this.announcement,
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
      ownerUid: (json['owner_uid'] ?? json['ownerUid'] ?? json['group_owner_uid'])?.toString(),
      role: (json['role'] ?? json['group_role'] ?? json['member_role'])?.toString(),
      isAdmin: _flag(json['is_admin'] ?? json['isAdmin']) ||
          _roleIs(json['role'] ?? json['group_role'] ?? json['member_role'], 'admin'),
      isOwner: _flag(json['is_owner'] ?? json['isOwner']) ||
          _roleIs(json['role'] ?? json['group_role'] ?? json['member_role'], 'owner'),
      memberCount: _intValue(json['member_count'] ?? json['memberCount'] ?? json['members_count']),
      announcement: (json['announcement'] ?? json['group_announcement'])?.toString(),
      lastMessage: rawLastMessage is Map
          ? Message.fromJson(Map<String, dynamic>.from(rawLastMessage))
          : null,
      unreadCount: _intValue(json['unread_count'] ?? json['unreadCount']),
      pinned: json['pinned'] == true || json['is_pinned'] == true || json['isPinned'] == true,
    );
  }

  static bool _flag(dynamic value) => value == true ||
      value?.toString().trim().toLowerCase() == 'true' ||
      value?.toString().trim() == '1';

  static bool _roleIs(dynamic value, String expected) {
    final role = value?.toString().trim().toLowerCase() ?? '';
    return role == expected || role == 'group_$expected' ||
        (expected == 'admin' && role == 'administrator');
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
        'owner_uid': ownerUid,
        'role': role,
        'is_admin': isAdmin,
        'is_owner': isOwner,
        'member_count': memberCount,
        'announcement': announcement,
        'last_message': lastMessage?.toJson(),
        'unread_count': unreadCount,
        'pinned': pinned,
      };

  Conversation copyWith({
    String? name,
    String? avatar,
    String? ownerUid,
    String? role,
    bool? isAdmin,
    bool? isOwner,
    int? memberCount,
    String? announcement,
    Message? lastMessage,
    int? unreadCount,
    bool? pinned,
  }) {
    return Conversation(
      id: id,
      type: type,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      ownerUid: ownerUid ?? this.ownerUid,
      role: role ?? this.role,
      isAdmin: isAdmin ?? this.isAdmin,
      isOwner: isOwner ?? this.isOwner,
      memberCount: memberCount ?? this.memberCount,
      announcement: announcement ?? this.announcement,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      pinned: pinned ?? this.pinned,
    );
  }
}
