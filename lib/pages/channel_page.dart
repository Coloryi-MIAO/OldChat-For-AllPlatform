import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/app_localizations.dart';

import '../models/channel.dart';
import '../services/api_service.dart';
import '../services/image_cache_service.dart';
import '../utils/url_helper.dart';
import '../widgets/cached_image.dart';
import '../utils/file_picker_compat.dart';

class ChannelPage extends StatefulWidget {
  final ChannelInfo channel;

  const ChannelPage({super.key, required this.channel});

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  final _api = ApiService();
  late ChannelInfo _channel;
  List<ChannelPost> _posts = [];
  bool _loading = true;
  bool _busy = false;
  final _postController = TextEditingController();
  bool _sending = false;
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _postController.dispose();
    super.dispose();
  }

  static const _defaultEmojis = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _restoreCachedPosts();
    _loadPosts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadPosts();
    });
  }

  int _postSeq = 0;

  Future<void> _restoreCachedPosts() async {
    final cached = await ImageCacheService.instance.readJsonCache(
      'channel_posts:${_channel.id}',
    );
    if (!mounted || cached is! List) return;
    final posts = cached
        .whereType<Map>()
        .map((item) => ChannelPost.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    if (posts.isNotEmpty) setState(() => _posts = posts);
  }

  Future<void> _loadPosts() async {
    if (mounted && _posts.isEmpty) setState(() => _loading = true);
    try {
      final raw = await _api.getChannelPosts(_channel.id, seq: _postSeq);
      if (!mounted) return;
      final incoming = raw.map(ChannelPost.fromJson).toList();
      if (incoming.isNotEmpty) {
        final latest = incoming
            .map((post) => post.seq)
            .reduce((a, b) => a > b ? a : b);
        _postSeq = latest > _postSeq ? latest : _postSeq;
      }
      final byId = <String, ChannelPost>{
        for (final post in _posts) post.id: post,
      };
      for (final post in incoming) byId[post.id] = post;
      final posts = byId.values.toList()
        ..sort((a, b) {
          final sequence = a.seq.compareTo(b.seq);
          return sequence != 0 ? sequence : a.createdAt.compareTo(b.createdAt);
        });
      final latestSeq = posts.fold<int>(
        0,
        (value, post) => value > post.seq ? value : post.seq,
      );
      setState(() {
        _postSeq = latestSeq;
        _posts = posts;
        _loading = false;
      });
      if (latestSeq > 0) {
        unawaited(_api.markChannelRead(_channel.id, latestSeq));
      }
      await ImageCacheService.instance.writeJsonCache(
        'channel_posts:${_channel.id}',
        posts
            .map(
              (post) => {
                'id': post.id,
                'author': {
                  'name': post.authorName,
                  'avatar': post.authorAvatar,
                },
                'text': post.text,
                'media_url': post.mediaUrl,
                'created_at': post.createdAt,
                'post_seq': post.seq,
                'reactions': post.reactions,
              },
            )
            .toList(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('加载失败：$error');
    }
  }

  Future<void> _sendPost() async {
    final text = _postController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.sendChannelPost(_channel.id, text, mediaUrl: null);
      _postController.clear();
      if (mounted) _message('已发布');
      await _loadPosts();
    } catch (error) {
      if (mounted) _message('发布失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickPostMedia() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final files = filePickerFiles(result);
    if (files.isEmpty || !mounted) return;
    final bytes = await filePickerBytes(files.first);
    if (bytes == null || bytes.isEmpty) {
      _message(AppLocalizations.current.t('无法读取图片'));
      return;
    }
    try {
      setState(() => _sending = true);
      final upload = await _api.uploadFile(
        FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: files.first.name),
        }),
      );
      final url = ApiService.extractUploadUrl(upload);
      if (url == null || url.isEmpty) throw Exception('上传失败');
      await _api.sendChannelPost(
        _channel.id,
        _postController.text,
        mediaUrl: url,
      );
      _postController.clear();
      await _loadPosts();
    } catch (error) {
      if (mounted) _message('${AppLocalizations.current.t('发布失败')}：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleSubscription() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_channel.subscribed) {
        await _api.unsubscribeChannel(_channel.id);
      } else {
        await _api.subscribeChannel(_channel.id);
      }
      if (!mounted) return;
      setState(() {
        _channel = _channel.copyWith(subscribed: !_channel.subscribed);
      });
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _react(ChannelPost post, String emoji) async {
    try {
      await _api.toggleChannelReaction(_channel.id, post.id, emoji);
      await _loadPosts();
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final emojis = _channel.allowedEmojis.isEmpty
        ? _defaultEmojis
        : _channel.allowedEmojis;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('频道')),
        actions: [
          IconButton(onPressed: _loadPosts, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPosts,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Row(
                  children: [
                    ClipOval(
                      child: CachedImage(
                        resolveMediaUrl(_channel.avatarUrl),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => CircleAvatar(
                          radius: 32,
                          backgroundColor: primary.withOpacity(.15),
                          child: Icon(Icons.campaign, color: primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _channel.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_channel.handle.isNotEmpty)
                            Text(
                              AppLocalizations.current.t('@${_channel.handle}'),
                            ),
                          if (_channel.description.isNotEmpty)
                            Text(
                              _channel.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            '${_channel.subscriberCount} 人订阅',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _toggleSubscription,
                      child: Text(
                        AppLocalizations.current.t(
                          _channel.subscribed ? '已订阅' : '订阅',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _postController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.current.t('发布频道消息'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _pickPostMedia,
                      icon: const Icon(Icons.image_outlined),
                      tooltip: AppLocalizations.current.t('上传图片'),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _sendPost,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_posts.isEmpty)
              SliverFillRemaining(
                child: Center(child: Text(AppLocalizations.current.t('暂无帖子'))),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final post = _posts[index];
                  return Card(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipOval(
                                child: CachedImage(
                                  resolveMediaUrl(post.authorAvatar),
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const CircleAvatar(
                                        radius: 16,
                                        child: Icon(Icons.person, size: 18),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  post.authorName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTime(post.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          if (post.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(post.text),
                            ),
                          if (post.mediaUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: CachedImage(
                                resolveMediaUrl(post.mediaUrl!),
                                width: double.infinity,
                                height: 220,
                                fit: BoxFit.contain,
                              ),
                            ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: emojis
                                .map(
                                  (emoji) => OutlinedButton(
                                    onPressed: () => _react(post, emoji),
                                    child: Text(emoji),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                }, childCount: _posts.length),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    if (timestamp <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(
      timestamp > 20000000000 ? timestamp : timestamp * 1000,
    );
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class ChannelDiscoveryPage extends StatefulWidget {
  const ChannelDiscoveryPage({super.key});

  @override
  State<ChannelDiscoveryPage> createState() => _ChannelDiscoveryPageState();
}

class _ChannelDiscoveryPageState extends State<ChannelDiscoveryPage> {
  final _query = TextEditingController();
  List<ChannelInfo> _channels = [];
  bool _loading = true;
  bool _searchInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!mounted || _searchInFlight) return;
    _searchInFlight = true;
    final cacheKey = 'channel_discovery:${_query.text.trim()}';
    final cached = await ImageCacheService.instance.readJsonCache(cacheKey);
    if (cached is List && mounted) {
      final cachedChannels = cached
          .whereType<Map>()
          .map((item) => ChannelInfo.fromJson(Map<String, dynamic>.from(item)))
          .where((channel) => channel.id.isNotEmpty)
          .toList();
      if (cachedChannels.isNotEmpty) {
        setState(() {
          _channels = cachedChannels;
          _loading = false;
        });
      }
    }
    if (mounted) setState(() => _loading = _channels.isEmpty);
    try {
      final raw = await ApiService().discoverChannels(query: _query.text);
      await ImageCacheService.instance.writeJsonCache(cacheKey, raw);
      if (!mounted) return;
      setState(() {
        _channels = raw
            .map(ChannelInfo.fromJson)
            .where((channel) => channel.id.isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (_channels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('搜索失败：$error'))),
        );
      }
    } finally {
      _searchInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.current.t('频道发现'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: AppLocalizations.current.t('搜索频道'),
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _channels.length,
                    itemBuilder: (context, index) {
                      final channel = _channels[index];
                      return ListTile(
                        leading: ClipOval(
                          child: CachedImage(
                            resolveMediaUrl(channel.avatarUrl),
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const CircleAvatar(child: Icon(Icons.campaign)),
                          ),
                        ),
                        title: Text(channel.name),
                        subtitle: Text(
                          channel.description.isEmpty
                              ? '${channel.subscriberCount} 人订阅'
                              : channel.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChannelPage(channel: channel),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
