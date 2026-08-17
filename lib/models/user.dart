class User {
  final String id; // 内部 id
  final String uid; // 对外 UID
  final String? ncuid;
  final String nickname;
  final String? avatar;

  User({
    required this.id,
    required this.uid,
    this.ncuid,
    required this.nickname,
    this.avatar,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      uid: json['uid'] ?? json['ncuid'] ?? '',
      ncuid: json['ncuid'],
      nickname: json['nickname'] ?? '',
      avatar: json['avatar'],
    );
  }
}
