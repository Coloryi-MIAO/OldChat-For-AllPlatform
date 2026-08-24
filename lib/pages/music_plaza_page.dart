import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../utils/constants.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../models/music.dart';
import '../models/conversation.dart';
import '../utils/url_helper.dart';
import '../widgets/cached_image.dart';
import '../widgets/image_viewer.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/image_cache_service.dart';

enum MusicTab { plaza, ranking, mine }

class MusicPlazaPage extends StatefulWidget {
  const MusicPlazaPage({super.key});

  @override
  State<MusicPlazaPage> createState() => _MusicPlazaPageState();
}

class _MusicPlazaPageState extends State<MusicPlazaPage> {
  List<Music> _musics = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 20;
  String? _errorMessage;
  MusicTab _currentTab = MusicTab.plaza;
  final ScrollController _listScrollController = ScrollController();
  final AudioService _audioService = AudioService();
  final TextEditingController _searchController = TextEditingController();
  Music? _currentMusic;
  String _searchKeyword = '';
  String? _lyrics;
  bool _lyricsLoading = false;
  int _lyricsIndex = 0;
  String? _lyricsMusicId;

  @override
  void initState() {
    super.initState();
    _restoreMusicCache();
    _loadMusic();
    _audioService.addListener(_onAudioStateChanged);
  }

  @override
  void dispose() {
    _audioService.removeListener(_onAudioStateChanged);
    _listScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onAudioStateChanged() {
    if (!mounted) return;
    final lines = _lyricLines(_lyrics);
    var nextIndex = 0;
    if (lines.isNotEmpty && _audioService.duration.inMilliseconds > 0) {
      nextIndex = ((_audioService.position.inMilliseconds /
                  _audioService.duration.inMilliseconds) *
              lines.length)
          .floor()
          .clamp(0, lines.length - 1);
    }
    if (_lyricsIndex != nextIndex || _audioService.isPlaying) {
      setState(() => _lyricsIndex = nextIndex);
    }
  }

  String _getEndpoint() {
    switch (_currentTab) {
      case MusicTab.ranking:
        return '/v2/music/plaza/ranking';
      case MusicTab.mine:
        return '/v2/music/plaza/mine';
      default:
        return '/v2/music/plaza';
    }
  }
  String _cacheKey() {
    final userId = AuthService().userId ?? 'guest';
    final tab = _currentTab.name;
    final query = _searchKeyword.trim().isEmpty ? 'all' : _searchKeyword.trim();
    return CacheService().scoped(userId, 'music-plaza:$tab:$query');
  }

  Future<void> _restoreMusicCache() async {
    final cached = await CacheService().readJson(_cacheKey());
    if (!mounted || cached is! Map) return;
    final rawItems = cached['items'];
    if (rawItems is! List || rawItems.isEmpty) return;
    final items = rawItems.whereType<Map>().map((item) => Music.fromJson(Map<String, dynamic>.from(item))).toList();
    if (items.isEmpty) return;
    setState(() {
      _musics = items;
      _currentMusic ??= items.first;
      _loading = false;
    });
    for (final music in items) {
      final cover = resolveMediaUrl(music.coverUrl ?? music.avatarUrl);
      if (cover.isNotEmpty) ImageCacheService.instance.cacheInBackground(cover);
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _loadMusic({bool initial = true}) async {
    if (!initial) {
      if (_isLoadingMore || !_hasMore) return;
      if (mounted) setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
        _errorMessage = null;
      });
    }

    try {
      final api = ApiService();
      final data = await api.getMusicPlaza(
        offset: _offset,
        limit: _limit,
        endpoint: _getEndpoint(),
        query: _searchKeyword,
      );
      final items =
          data['items'] ??
          (data['response'] is Map
              ? data['response']['items']
              : data['response']) ??
          (data['data'] is Map ? data['data']['items'] : data['data']) ??
          data['list'];
      if (items == null) throw Exception('返回数据格式错误');
      if (data['error'] != null) throw Exception(data['error']);
      if (items is! List) throw Exception('返回数据格式错误');
      final newMusic = items.whereType<Map>().map((e) => Music.fromJson(Map<String, dynamic>.from(e))).toList();
      final hasMore = data['has_more'] ?? false;

      setState(() {
        if (initial)
          _musics = newMusic;
        else
          _musics.addAll(newMusic);
        _hasMore = hasMore;
        _offset += newMusic.length;
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = null;
        if (initial && _musics.isNotEmpty) {
          _currentMusic = _musics[0];
        }
      });
      await CacheService().writeJson(
        _cacheKey(),
        <String, dynamic>{
          'items': _musics.map((music) => music.toJson()).toList(),
          'has_more': _hasMore,
        },
      );
      for (final music in newMusic) {
        final cover = resolveMediaUrl(music.coverUrl ?? music.avatarUrl);
        if (cover.isNotEmpty) ImageCacheService.instance.cacheInBackground(cover);
      }
    } catch (e) {
      final cached = await CacheService().readJson(_cacheKey());
      if (initial && cached is Map && cached['items'] is List && mounted) {
        final items = (cached['items'] as List)
            .whereType<Map>()
            .map((item) => Music.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        if (items.isNotEmpty) {
          setState(() {
            _musics = items;
            _currentMusic = items.first;
            _loading = false;
            _errorMessage = null;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('加载音乐失败: $e'))));
      }
    }
  }

  Future<void> _loadLyrics(Music music) async {
    if (music.lyrics?.trim().isNotEmpty == true) {
      if (mounted) {
        setState(() {
          _lyrics = music.lyrics;
          _lyricsMusicId = music.id;
          _lyricsIndex = 0;
        });
      }
      return;
    }
    if (music.lyricsUrl?.trim().isNotEmpty == true) {
      try {
        final text = await ApiService().getMusicLyricsText(resolveMediaUrl(music.lyricsUrl!));
        if (mounted) {
          setState(() {
            _lyrics = text;
            _lyricsMusicId = music.id;
            _lyricsIndex = 0;
          });
        }
        return;
      } catch (_) {}
    }
    if (_lyricsLoading || music.id.isEmpty || _lyricsMusicId == music.id) return;
    setState(() => _lyricsLoading = true);
    try {
      final data = await ApiService().getMusicLyrics(music.id);
      final nested = data['data'];
      final value = (data['lyrics'] ?? data['lyric'] ?? data['text'] ??
              (nested is Map
                  ? (nested['lyrics'] ?? nested['lyric'] ?? nested['text'])
                  : nested))
          ?.toString();
      final lyricsUrl = (data['lyrics_url'] ?? data['lyric_url'] ?? data['url'])?.toString();
      if (value != null && value.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _lyrics = value;
            _lyricsMusicId = music.id;
            _lyricsIndex = 0;
          });
        }
      } else if (lyricsUrl != null && lyricsUrl.trim().isNotEmpty) {
        final lyricResponse = await ApiService().getExternalText(resolveMediaUrl(lyricsUrl));
        if (mounted) {
          setState(() {
            _lyrics = lyricResponse;
            _lyricsMusicId = music.id;
            _lyricsIndex = 0;
          });
        }
      } else if (mounted) {
        setState(() {
          _lyrics = null;
          _lyricsMusicId = music.id;
          _lyricsIndex = 0;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _lyrics = null; _lyricsMusicId = music.id; });
    } finally {
      if (mounted) setState(() => _lyricsLoading = false);
    }
  }

  List<String> _lyricLines(String? value) => (value ?? '')
      .split(RegExp(r'\r?\n'))
      .map((line) => line.replaceFirst(RegExp(r'^\[[^\]]+\]'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();

  Future<void> _showLyricsDialog(Music music) async {
    if (_lyrics == null || _lyrics!.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.current.t('${music.title} · 歌词')),
        content: SizedBox(
          width: 520,
          height: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              _lyrics!,
              style: const TextStyle(fontSize: 14, height: 1.7),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.current.t('关闭')),
          ),
        ],
      ),
    );
  }

  void _playMusic(Music music) {
    final url = resolveMediaUrl(music.audioUrl);
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('音频链接无效'))));
      return;
    }
    setState(() {
      _currentMusic = music;
      _lyrics = music.lyrics;
      _lyricsMusicId = music.id;
      _lyricsLoading = false;
    });
    _loadLyrics(music);
    _audioService.play(url);
  }

  void _togglePlay() {
    if (_currentMusic == null) return;
    final url = resolveMediaUrl(_currentMusic!.audioUrl);
    if (url.isEmpty) return;
    if (_audioService.isPlaying && _audioService.currentUrl == url) {
      _audioService.pause();
    } else if (!_audioService.isPlaying && _audioService.currentUrl == url) {
      _audioService.resume();
    } else {
      _playMusic(_currentMusic!);
    }
  }

  Future<Conversation?> _chooseConversation() async {
    final api = ApiService();
    final results = await Future.wait<dynamic>([api.getFriends(), api.getGroups()]);
    if (!mounted) return null;
    final friends = results.isNotEmpty && results[0] is List
        ? (results[0] as List).whereType<Conversation>().toList()
        : <Conversation>[];
    final groups = results.length > 1 && results[1] is List
        ? (results[1] as List).whereType<Conversation>().toList()
        : <Conversation>[];
    final all = [...friends, ...groups];
    if (all.isEmpty) {
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
              ...friends.map((conversation) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(conversation.name ?? conversation.id),
                    subtitle: Text(AppLocalizations.current.t('私聊')),
                    onTap: () => Navigator.pop(dialogContext, conversation),
                  )),
              if (groups.isNotEmpty)
                ListTile(title: Text(AppLocalizations.current.t('群聊')), enabled: false),
              ...groups.map((conversation) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.groups)),
                    title: Text(conversation.name ?? conversation.id),
                    subtitle: Text(AppLocalizations.current.t('群聊')),
                    onTap: () => Navigator.pop(dialogContext, conversation),
                  )),
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
  }

  Future<void> _shareMusic(Music music) async {
    final target = await _chooseConversation();
    if (target == null) return;
    final body = jsonEncode({
      'v': 2,
      'text':
          '歌曲: ${music.title}\n歌手: ${music.artist ?? '未知'}\n时长: ${_formatDuration(music.duration)}\n点击播放',
      'media_kind': 'music',
    });
    try {
      final api = ApiService();
      if (target.type == 'direct') {
        await api.sendDirectMessage(
          toUid: target.id,
          body: body,
          msgType: 'resource',
          mediaUrl: music.audioUrl ?? '',
          thumbUrl: music.coverUrl ?? '',
        );
      } else {
        await api.sendGroupMessage(
          groupId: target.id,
          body: body,
          msgType: 'resource',
          mediaUrl: music.audioUrl ?? '',
          thumbUrl: music.coverUrl ?? '',
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

  Widget _buildMusicListItem(Music music, Color primaryColor) {
    final isPlaying = _currentMusic?.id == music.id && _audioService.isPlaying;
    final coverUrl = resolveMediaUrl(music.coverUrl ?? music.avatarUrl);
    final artist =
        music.artist ?? music.displayName ?? music.username ?? '未知歌手';

    return ListTile(
      leading: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: coverUrl.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImageViewer(
                      imageUrl: coverUrl,
                      imageUrls: music.coverUrls,
                    ),
                  ),
                ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedImage(
          coverUrl.isNotEmpty ? coverUrl : '',
          width: 48,
          height: 48,
          cacheWidth: 160,
            errorBuilder: (_, __, ___) => Container(
              width: 48,
              height: 48,
              color: Colors.grey[300],
              child: const Icon(Icons.music_note, size: 24),
            ),
          ),
        ),
      ),
      title: Text(
        music.title,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
          color: isPlaying ? primaryColor : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$artist · ${music.plays}次播放',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPlaying)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.play_arrow, size: 20, color: Colors.grey),
          IconButton(
            icon: const Icon(Icons.share, size: 18),
            onPressed: () => _shareMusic(music),
            tooltip: AppLocalizations.current.t('分享'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      onTap: () => _playMusic(music),
      selected: _currentMusic?.id == music.id,
      selectedTileColor: primaryColor.withOpacity(0.08),
    );
  }

  Widget _buildPlayer() {
    if (_currentMusic == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 80, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(AppLocalizations.current.t('选择一首歌曲播放'), style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final music = _currentMusic!;
    final coverUrl = resolveMediaUrl(music.coverUrl ?? music.avatarUrl);
    final artist = music.artist ?? music.displayName ?? music.username ?? '未知歌手';
    final isPlaying = _audioService.currentUrl == resolveMediaUrl(music.audioUrl) && _audioService.isPlaying;
    final progress = _audioService.duration.inMilliseconds > 0
        ? (_audioService.position.inMilliseconds / _audioService.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final currentTime = _audioService.position;
    final totalTime = _audioService.duration;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final coverSize = compact ? 128.0 : 200.0;
        final lyricLines = _lyricLines(_lyrics);
        return Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: coverUrl.isEmpty
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImageViewer(
                                  imageUrl: coverUrl,
                                  imageUrls: music.coverUrls,
                                ),
                              ),
                            ),
                    child: CachedImage(
                      coverUrl,
                      width: coverSize,
                      height: coverSize,
                      cacheWidth: 640,
                      errorBuilder: (_, __, ___) => Container(
                        width: coverSize,
                        height: coverSize,
                        color: Colors.grey[300],
                        child: Icon(Icons.music_note, size: 60),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  music.title,
                  style: TextStyle(fontSize: compact ? 17 : 20, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  artist,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_formatDuration(currentTime.inSeconds), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Expanded(
                      child: Slider(
                        value: progress,
                        onChanged: (value) => _audioService.seek(totalTime * value),
                        activeColor: Theme.of(context).primaryColor,
                        inactiveColor: Colors.grey[300],
                        min: 0,
                        max: 1,
                      ),
                    ),
                    Text(_formatDuration(totalTime.inSeconds), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 32),
                      onPressed: () {
                        final index = _musics.indexOf(music);
                        if (index > 0) _playMusic(_musics[index - 1]);
                      },
                    ),
                    const SizedBox(width: 16),
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: IconButton(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
                        onPressed: _togglePlay,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 32),
                      onPressed: () {
                        final index = _musics.indexOf(music);
                        if (index < _musics.length - 1) _playMusic(_musics[index + 1]);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lyricsLoading)
                  const LinearProgressIndicator()
                else if (lyricLines.isNotEmpty)
                  Column(
                    children: [
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 96),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Builder(
                          builder: (context) {
                            final active = _lyricsIndex.clamp(0, lyricLines.length - 1);
                            return SingleChildScrollView(
                              child: Column(
                                children: lyricLines.asMap().entries.map((entry) {
                                  final selected = entry.key == active;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Text(
                                      entry.value,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: selected ? 14 : 13,
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                        color: selected ? Theme.of(context).primaryColor : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _showLyricsDialog(music),
                          icon: const Icon(Icons.open_in_full, size: 16),
                          label: Text(AppLocalizations.current.t('展开歌词')),
                        ),
                      ),
                    ],
                  )
                else
                  Text(AppLocalizations.current.t('暂无歌词'), style: TextStyle(color: Colors.grey)),
                SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _shareMusic(music),
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(AppLocalizations.current.t('分享到聊天')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('音乐广场')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadMusic(initial: true),
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧列表
          SizedBox(
            width: 320,
            child: Column(
              children: [
                // Tab切换
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      _buildTabButton('广场', MusicTab.plaza),
                      _buildTabButton('排行榜', MusicTab.ranking),
                      _buildTabButton('我的', MusicTab.mine),
                    ],
                  ),
                ),
                if (_currentTab == MusicTab.plaza)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.current.t('搜索音乐'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                const Divider(height: 1),
                // 列表
                Expanded(
                  child: _loading
                      ? Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => _loadMusic(initial: true),
                                child: Text(AppLocalizations.current.t('重试')),
                              ),
                            ],
                          ),
                        )
                      : _musics.isEmpty
                      ? Center(
                          child: Text(
                            _currentTab == MusicTab.mine ? '暂无上传的音乐' : '暂无音乐',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      : ListView.builder(
                          controller: _listScrollController,
                          itemCount: _musics.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _musics.length) {
                              if (_isLoadingMore) {
                                return Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.all(8),
                                child: Center(
                                  child: TextButton(
                                    onPressed: () => _loadMusic(initial: false),
                                    child: Text(AppLocalizations.current.t('加载更多')),
                                  ),
                                ),
                              );
                            }
                            return _buildMusicListItem(
                              _musics[index],
                              primaryColor,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          // 右侧播放器
          Expanded(
            child: Container(color: Colors.grey[50], child: _buildPlayer()),
          ),
        ],
      ),
    );
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query == _searchKeyword) {
      _loadMusic(initial: true);
      return;
    }
    setState(() {
      _searchKeyword = query;
    });
    _loadMusic(initial: true);
  }

  Widget _buildTabButton(String label, MusicTab tab) {
    final isSelected = _currentTab == tab;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          onPressed: () {
            if (_currentTab != tab) {
              setState(() {
                _currentTab = tab;
                _musics.clear();
                _offset = 0;
                _hasMore = true;
                _searchKeyword = '';
                _searchController.clear();
                _loadMusic(initial: true);
              });
            }
          },
          style: TextButton.styleFrom(
            backgroundColor: isSelected
                ? Theme.of(context).primaryColor
                : Colors.transparent,
            foregroundColor: isSelected ? Colors.white : Colors.grey[700],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}