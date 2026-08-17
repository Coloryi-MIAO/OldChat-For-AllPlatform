import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/emoji.dart';
import '../models/conversation.dart';
import '../utils/url_helper.dart';
import '../services/auth_service.dart';
import '../services/image_cache_service.dart';
import '../services/cache_service.dart';
import '../services/local_emoji_service.dart';
import '../widgets/cached_image.dart';

class EmojiPlazaPage extends StatefulWidget {
  const EmojiPlazaPage({super.key});

  @override
  State<EmojiPlazaPage> createState() => _EmojiPlazaPageState();
}

class _EmojiPlazaPageState extends State<EmojiPlazaPage> {
  List<Emoji> _emojis = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 20;
  String? _errorMessage;
  final Set<String> _localEmojiIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadLocalEmojiIds();
    _loadEmojis();
  }

  Future<void> _loadLocalEmojiIds() async {
    final items = await LocalEmojiService.instance.list();
    if (!mounted) return;
    setState(() {
      _localEmojiIds
        ..clear()
        ..addAll(items.map((item) => item['id']?.toString()).whereType<String>());
    });
  }

  Future<void> _loadEmojis({bool initial = true}) async {
    final userId = context.read<AuthService>().userId ?? 'guest';
    final cacheKey = CacheService().scoped(userId, 'emoji-plaza');
    if (initial) {
      final cached = await CacheService().readJson(cacheKey);
      if (cached is List && mounted && _emojis.isEmpty) {
        final savedIds = (await LocalEmojiService.instance.list())
            .map((item) => item['id']?.toString())
            .whereType<String>()
            .toSet();
        setState(() {
          _emojis = cached
              .whereType<Map>()
              .map((item) => Emoji.fromJson(Map<String, dynamic>.from(item)))
              .map((emoji) => emoji.copyWith(isLiked: savedIds.contains(emoji.id)))
              .toList();
          _loading = false;
        });
      }
    }
    if (!initial) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await ApiService().getEmojiPlaza(offset: _offset, limit: _limit);
      final rawItems = data['items'] ?? data['data'] ?? data['list'];
      if (data['error'] != null) throw Exception(data['error']);
      if (rawItems is! List) throw Exception('返回数据格式错误');
      final savedIds = (await LocalEmojiService.instance.list())
          .map((item) => item['id']?.toString())
          .whereType<String>()
          .toSet();
      final newEmojis = rawItems
          .whereType<Map>()
          .map((item) => Emoji.fromJson(Map<String, dynamic>.from(item)))
          .map((emoji) => emoji.copyWith(isLiked: savedIds.contains(emoji.id)))
          .toList();
      final hasMore = data['has_more'] == true ||
          (data['next_offset'] != null && newEmojis.isNotEmpty);

      if (!mounted) return;
      setState(() {
        if (initial) {
          _emojis = newEmojis;
        } else {
          _emojis = [..._emojis, ...newEmojis];
        }
        _hasMore = hasMore;
        _offset += newEmojis.length;
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = null;
      });
      await CacheService().writeJson(cacheKey, _emojis.map((emoji) => emoji.toJson()).toList());
      for (final emoji in newEmojis) {
        final imageUrl = resolveMediaUrl(emoji.thumbUrl ?? emoji.mediaUrl);
        if (imageUrl.isNotEmpty) ImageCacheService.instance.cacheInBackground(imageUrl);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _toggleSaveEmoji(Emoji emoji) async {
    try {
      final alreadySaved = _localEmojiIds.contains(emoji.id);
      if (alreadySaved) {
        await LocalEmojiService.instance.remove(emoji.id);
        _localEmojiIds.remove(emoji.id);
      } else {
        await LocalEmojiService.instance.save({
          'id': emoji.id,
          'media_url': emoji.mediaUrl,
          'thumb_url': emoji.thumbUrl,
          'name': emoji.displayName ?? emoji.username ?? emoji.id,
        });
        _localEmojiIds.add(emoji.id);
      }
      if (!mounted) return;
      setState(() {
        final index = _emojis.indexWhere((item) => item.id == emoji.id);
        if (index >= 0) _emojis[index] = emoji.copyWith(isLiked: !alreadySaved);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(alreadySaved ? '已取消本地收藏' : '已保存到本地')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('收藏操作失败：$error'))));
    }
  }

  Future<Conversation?> _chooseConversation() async {
    try {
      final results = await Future.wait<dynamic>([
        ApiService().getFriends(),
        ApiService().getGroups(),
      ]);
      if (!mounted) return null;
      final friends = results.isNotEmpty && results[0] is List
          ? (results[0] as List).whereType<Conversation>().toList()
          : <Conversation>[];
      final groups = results.length > 1 && results[1] is List
          ? (results[1] as List).whereType<Conversation>().toList()
          : <Conversation>[];
      if (friends.isEmpty && groups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('暂无可分享的聊天'))),
        );
        return null;
      }
      return showDialog<Conversation>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocalizations.current.t('选择分享对象')),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView(
              children: [
                if (friends.isNotEmpty)
                  ListTile(title: Text(AppLocalizations.current.t('好友')), enabled: false),
                ...friends.map(
                  (conversation) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(conversation.name ?? conversation.id),
                    subtitle: Text(AppLocalizations.current.t('私聊')),
                    onTap: () => Navigator.pop(dialogContext, conversation),
                  ),
                ),
                if (groups.isNotEmpty)
                  ListTile(title: Text(AppLocalizations.current.t('群聊')), enabled: false),
                ...groups.map(
                  (conversation) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.groups)),
                    title: Text(conversation.name ?? conversation.id),
                    subtitle: Text(AppLocalizations.current.t('群聊')),
                    onTap: () => Navigator.pop(dialogContext, conversation),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.current.t('取消')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('获取会话失败: $error'))),
        );
      }
      return null;
    }
  }

  Future<void> _shareEmoji(Emoji emoji) async {
    final target = await _chooseConversation();
    if (target == null) return;
    try {
      if (target.type == 'direct') {
        await ApiService().sendDirectMessage(
          toUid: target.id,
          body: '',
          msgType: 'image',
          mediaUrl: emoji.mediaUrl,
          thumbUrl: emoji.thumbUrl,
        );
      } else {
        await ApiService().sendGroupMessage(
          groupId: target.id,
          body: '',
          msgType: 'image',
          mediaUrl: emoji.mediaUrl,
          thumbUrl: emoji.thumbUrl,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('已分享给 ${target.name ?? target.id}'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('分享失败: $error'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('表情广场')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadEmojis(initial: true),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(AppLocalizations.current.t('加载失败: $_errorMessage')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _loadEmojis(initial: true),
                        child: Text(AppLocalizations.current.t('重试')),
                      ),
                    ],
                  ),
                )
              : _emojis.isEmpty
                  ? Center(child: Text(AppLocalizations.current.t('暂无表情')))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _emojis.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _emojis.length) {
                          if (_isLoadingMore) {
                            return Center(child: CircularProgressIndicator());
                          }
                          return InkWell(
                            onTap: () => _loadEmojis(initial: false),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(child: Text(AppLocalizations.current.t('加载更多'))),
                            ),
                          );
                        }
                        final emoji = _emojis[index];
                        final imageUrl = resolveMediaUrl(emoji.thumbUrl ?? emoji.mediaUrl);
                        return InkWell(
                          onTap: () => _shareEmoji(emoji),
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[200]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedImage(
                                      imageUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      cacheWidth: 480,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: _localEmojiIds.contains(emoji.id) ? '取消收藏' : '收藏表情',
                                  onPressed: () => _toggleSaveEmoji(emoji),
                                  icon: Icon(
                                    _localEmojiIds.contains(emoji.id) ? Icons.star : Icons.star_border,
                                    color: _localEmojiIds.contains(emoji.id) ? Colors.amber : Colors.white,
                                  ),
                                ),
                              ),

                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '喜欢 ${emoji.likes}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('上传功能请使用网页端或 App 内文件选择'))),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
