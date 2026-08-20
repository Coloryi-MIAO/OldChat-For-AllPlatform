import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/file_picker_compat.dart';
import '../services/app_localizations.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../utils/url_helper.dart';
import '../widgets/cached_image.dart';

class CheckinWallPage extends StatefulWidget {
  const CheckinWallPage({super.key});

  @override
  State<CheckinWallPage> createState() => _CheckinWallPageState();
}

class _CheckinWallPageState extends State<CheckinWallPage> {
  final _textController = TextEditingController();
  List<Map<String, dynamic>> _posts = [];
  final List<String> _mediaUrls = [];
  bool _uploadingMedia = false;
  bool _loading = true;
  bool _checkingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const [];

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService().getCheckinWall();
      final raw =
          data['posts'] ??
          (data['response'] is Map
              ? data['response']['posts']
              : data['response']) ??
          data['items'] ??
          (data['data'] is Map ? data['data']['items'] : data['data']) ??
          data['data'] ??
          data;
      final payload = raw is Map && raw['featured_messages'] is List
          ? raw['featured_messages']
          : raw;
      if (mounted)
        setState(() {
          _posts = _items(payload);
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = error.toString();
        });
    }
  }

  Future<void> _checkIn() async {
    if (_checkingIn) return;
    setState(() => _checkingIn = true);
    try {
      final result = await ApiService().dailyCheckin();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['already_checked'] == true ? '今天已经签到过了' : '签到成功',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('签到失败：$error'))),
        );
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  Future<void> _pickMedia() async {
    if (_uploadingMedia) return;
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    final selectedFiles = filePickerFiles(result);
    if (selectedFiles.isEmpty) return;
    setState(() => _uploadingMedia = true);
    try {
      for (final selected in selectedFiles) {
        final bytes = await filePickerBytes(selected);
        if (bytes == null || bytes.isEmpty) continue;
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: selected.name),
        });
        final uploaded = await ApiService().uploadFile(form);
        final raw = ApiService.extractUploadUrl(uploaded);
        if (raw != null && raw.isNotEmpty) _mediaUrls.add(raw);
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('图片上传失败：$error'))),
        );
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _publish() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _mediaUrls.isEmpty) return;
    try {
      await ApiService().postCheckinWall(text, mediaUrls: _mediaUrls);
      _textController.clear();
      _mediaUrls.clear();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('已发布到签到墙'))),
        );
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('发布失败：$error'))),
        );
    }
  }

  Future<void> _toggleLike(String postId, bool liked) async {
    final index = _posts.indexWhere(
      (post) => _value(post, const ['id', 'post_id']) == postId,
    );
    if (index >= 0 && mounted) {
      setState(() {
        final updated = Map<String, dynamic>.from(_posts[index]);
        updated['liked_by_me'] = !liked;
        final current =
            int.tryParse('${updated['like_count'] ?? updated['likes'] ?? 0}') ??
            0;
        updated['like_count'] = liked
            ? (current - 1).clamp(0, 1 << 30)
            : current + 1;
        _posts[index] = updated;
      });
    }
    try {
      if (liked) {
        await ApiService().unlikeCheckinWall(postId);
      } else {
        await ApiService().likeCheckinWall(postId);
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('操作失败：$error'))),
        );
    }
  }

  String _value(
    Map<String, dynamic> item,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty)
        return value.toString();
    }
    return fallback;
  }

  List<String> _postMedia(Map<String, dynamic> post) {
    final values = <dynamic>[
      post['image_urls'],
      post['images'],
      post['media_urls'],
      post['image_url'],
    ];
    final result = <String>[];
    for (final value in values) {
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            final url =
                item['url'] ??
                item['image_url'] ??
                item['media_url'] ??
                item['src'] ??
                item['download_url'] ??
                item['file_url'];
            if (url != null) result.add(url.toString());
          } else {
            result.add(item.toString());
          }
        }
      } else if (value is Map) {
        final url =
            value['url'] ??
            value['image_url'] ??
            value['media_url'] ??
            value['src'] ??
            value['download_url'] ??
            value['file_url'];
        if (url != null) result.add(url.toString());
      } else if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final url =
                    item['url'] ??
                    item['image_url'] ??
                    item['media_url'] ??
                    item['src'] ??
                    item['download_url'] ??
                    item['file_url'];
                if (url != null) result.add(url.toString());
              } else {
                result.add(item.toString());
              }
            }
            continue;
          }
        } catch (_) {}
        result.add(value);
      }
    }
    return result
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('签到墙')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null && _posts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.current.t('加载失败：$_error')),
                  TextButton(
                    onPressed: _load,
                    child: Text(AppLocalizations.current.t('重试')),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日签到',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        TextField(
                          controller: _textController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.current.t('写下今天的状态…'),
                          ),
                        ),
                        SizedBox(height: 10),
                        if (_mediaUrls.isNotEmpty)
                          Text(
                            AppLocalizations.current.t(
                              '已选择 ${_mediaUrls.length} 张图片',
                            ),
                          ),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _checkingIn ? null : _checkIn,
                              icon: const Icon(Icons.today),
                              label: Text(AppLocalizations.current.t('签到')),
                            ),
                            SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _uploadingMedia ? null : _pickMedia,
                              icon: const Icon(Icons.image_outlined),
                              label: Text(AppLocalizations.current.t(_uploadingMedia ? '上传中…' : '图片')),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _publish,
                              icon: const Icon(Icons.send),
                              label: Text(AppLocalizations.current.t('发布')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_posts.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(AppLocalizations.current.t('暂无签到动态')),
                    ),
                  ),
                ..._posts.map((post) {
                  final user = post['user'] is Map
                      ? Map<String, dynamic>.from(post['user'] as Map)
                      : const <String, dynamic>{};
                  final name =
                      _value(user, const [
                        'display_name',
                        'username',
                        'name',
                        'uid',
                      ]).isNotEmpty
                      ? _value(user, const [
                          'display_name',
                          'username',
                          'name',
                          'uid',
                        ])
                      : _value(post, const [
                          'display_name',
                          'username',
                          'uid',
                        ], '用户');
                  final text = _value(post, const [
                    'content_text',
                    'text',
                    'body',
                    'content',
                  ], '');
                  final mediaValues = <String>[];
                  final rawMedia =
                      post['image_urls'] ??
                      post['images'] ??
                      post['media_urls'] ??
                      post['media'];
                  if (rawMedia is List) {
                    mediaValues.addAll(
                      rawMedia
                          .map(
                            (value) => value is Map
                                ? (value['url'] ??
                                              value['media_url'] ??
                                              value['src'])
                                          ?.toString() ??
                                      ''
                                : value.toString(),
                          )
                          .where((value) => value.trim().isNotEmpty),
                    );
                  } else if (rawMedia is String && rawMedia.trim().isNotEmpty) {
                    try {
                      final decoded = jsonDecode(rawMedia);
                      if (decoded is List)
                        mediaValues.addAll(
                          decoded.map((value) => value.toString()),
                        );
                    } catch (_) {
                      mediaValues.add(rawMedia);
                    }
                  }
                  final singleMedia = _value(post, const [
                    'image_url',
                    'media_url',
                    'cover_url',
                  ]);
                  if (mediaValues.isEmpty && singleMedia.isNotEmpty)
                    mediaValues.add(singleMedia);
                  final avatar = resolveMediaUrl(
                    _value(user, const ['avatar_url', 'avatar']).isNotEmpty
                        ? _value(user, const ['avatar_url', 'avatar'])
                        : _value(post, const ['avatar_url', 'avatar']),
                  );
                  final likes = post['like_count'] ?? post['likes'] ?? 0;
                  final liked =
                      post['liked_by_me'] == true || post['liked'] == true;
                  final postId = _value(post, const ['id', 'post_id']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: avatar.isEmpty
                          ? CircleAvatar(
                              child: Text(
                                name.isEmpty ? '?' : name.substring(0, 1),
                              ),
                            )
                          : CachedImage(
                              avatar,
                              width: 40,
                              height: 40,
                              cacheWidth: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                child: Text(
                                  name.isEmpty ? '?' : name.substring(0, 1),
                                ),
                              ),
                            ),
                      title: Text(name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (text.isNotEmpty) Text(text),
                            ..._postMedia(post).map(
                              (url) => Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: CachedImage(
                                  resolveMediaUrl(url),
                                  width: 220,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  cacheWidth: 440,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          color: liked ? Colors.red : null,
                        ),
                        onPressed: postId.isEmpty
                            ? null
                            : () => _toggleLike(postId, liked),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
