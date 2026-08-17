import 'dart:convert';

class Music {
  final String id;
  final String uid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String title;
  final String? artist;
  final String? coverUrl;
  final List<String> coverUrls;
  final String? audioUrl;
  final String? lyrics;
  final String? lyricsUrl;
  final int duration;
  final int plays;
  final int likes;
  final bool isLiked;
  final int createdAt;

  Music({
    required this.id,
    required this.uid,
    this.username,
    this.displayName,
    this.avatarUrl,
    required this.title,
    this.artist,
    this.coverUrl,
    this.coverUrls = const [],
    this.audioUrl,
    this.lyrics,
    this.lyricsUrl,
    this.duration = 0,
    this.plays = 0,
    this.likes = 0,
    this.isLiked = false,
    required this.createdAt,
  });

  static String? _textValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static int _durationValue(dynamic value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (number == null || number <= 0) return 0;
    return number > 1000 ? (number / 1000).round() : number.round();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'title': title,
        'artist': artist,
        'cover_url': coverUrl,
        'cover_urls': coverUrls,
        'audio_url': audioUrl,
        'lyrics': lyrics,
        'lyrics_url': lyricsUrl,
        'duration': duration,
        'plays': plays,
        'likes': likes,
        'is_liked': isLiked,
        'created_at': createdAt,
      };

  factory Music.fromJson(Map<String, dynamic> json) {
    final audioUrl = json['song_url'] ?? json['media_url'] ?? json['audio_url'] ?? json['url'];
    final coverUrl = json['cover_url'] ?? json['image_url'] ?? json['avatar_url'];
    final coverUrls = <String>[];
    void addCover(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) addCover(item);
        return;
      }
      if (value is Map) {
        addCover(value['url'] ?? value['image_url'] ?? value['cover_url']);
        return;
      }
      final text = value.toString().trim();
      if (text.isEmpty) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is List || decoded is Map) {
          addCover(decoded);
          return;
        }
      } catch (_) {}
      if (!coverUrls.contains(text)) coverUrls.add(text);
    }
    addCover(json['cover_urls']);
    addCover(json['covers']);
    addCover(coverUrl);
    final displayName = json['display_name'] ?? json['owner_display_name'];
    final avatarUrl = json['avatar_url'] ?? json['owner_avatar'];
    final username = json['username'] ?? json['owner_name'];

    return Music(
      id: json['id'] ?? json['music_id'] ?? '',
      uid: json['uid'] ?? json['owner_uid'] ?? '',
      username: _textValue(username),
      displayName: _textValue(displayName),
      avatarUrl: _textValue(avatarUrl),
      title: json['name'] ?? json['title'] ?? '未知歌曲',
      artist: json['artist'] ?? json['singer'] ?? json['owner_name'] ?? '未知歌手',
      coverUrl: _textValue(coverUrl),
      coverUrls: coverUrls,
      audioUrl: _textValue(audioUrl),
      lyrics: _textValue(json['lyrics']) ?? _textValue(json['lyric']) ??
          _textValue(json['lyric_text']) ?? _textValue(json['lyrics_text']) ??
          _textValue(json['lrc']),
      lyricsUrl: _textValue(json['lyrics_url']) ?? _textValue(json['lyric_url']) ??
          _textValue(json['lrc_url']),
      duration: _durationValue(json['duration_ms'] ?? json['duration']),
      plays: json['play_count'] ?? json['plays'] ?? 0,
      likes: json['likes'] ?? 0,
      isLiked: json['liked'] ?? json['is_liked'] ?? false,
      createdAt: json['created_at'] ?? 0,
    );
  }
}
