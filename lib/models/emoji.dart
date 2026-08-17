class Emoji {
  final String id;
  final String uid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String mediaUrl;
  final String? thumbUrl;
  final int likes;
  final bool isLiked;
  final int createdAt;

  Emoji({
    required this.id,
    required this.uid,
    this.username,
    this.displayName,
    this.avatarUrl,
    required this.mediaUrl,
    this.thumbUrl,
    this.likes = 0,
    this.isLiked = false,
    required this.createdAt,
  });

  factory Emoji.fromJson(Map<String, dynamic> json) {
    return Emoji(
      id: json['id']?.toString() ?? '',
      uid: json['uid']?.toString() ?? '',
      username: json['username']?.toString(),
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      mediaUrl: json['media_url']?.toString() ?? '',
      thumbUrl: json['thumb_url']?.toString(),
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      isLiked: json['is_liked'] == true,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  Emoji copyWith({bool? isLiked}) => Emoji(
        id: id,
        uid: uid,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        mediaUrl: mediaUrl,
        thumbUrl: thumbUrl,
        likes: likes,
        isLiked: isLiked ?? this.isLiked,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'media_url': mediaUrl,
        'thumb_url': thumbUrl,
        'likes': likes,
        'is_liked': isLiked,
        'created_at': createdAt,
      };
}
