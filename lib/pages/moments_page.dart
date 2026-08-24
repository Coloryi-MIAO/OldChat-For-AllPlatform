import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/moment.dart';
import '../utils/url_helper.dart';
import '../widgets/cached_image.dart';
import 'user_profile_page.dart'; // ★ 添加这行
import '../widgets/image_viewer.dart';
import '../services/cache_service.dart';
import '../services/image_cache_service.dart';

class MomentsPage extends StatefulWidget {
  final String? uid;
  final bool embedded;
  const MomentsPage({super.key, this.uid, this.embedded = false});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage>
    with WidgetsBindingObserver, RouteAware {
  List<Moment> _moments = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  int _offset = 0;
  final int _limit = 20;
  String? _errorMessage;
  final TextEditingController _postController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  XFile? _selectedImageFile;
  String? _uploadedImageUrl;
  bool _posting = false;
  String? _commentingMomentId;
  final List<XFile> _selectedImageFiles = [];
  final List<String> _uploadedImageUrls = [];
  bool _isVisible = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMoments();
    _precacheMomentMedia();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _postController.dispose();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isVisible = state == AppLifecycleState.resumed;
  }

  @override
  void didPushNext() => _isVisible = false;

  @override
  void didPopNext() => _isVisible = true;

  Future<void> _precacheMomentMedia() async {
    final cached = await CacheService().readJson(
      CacheService().scoped(
        context.read<AuthService>().userId ?? 'guest',
        'moments:${widget.uid ?? 'feed'}',
      ),
    );
    if (cached is! List) return;
    for (final item in cached.whereType<Map>()) {
      final moment = Moment.fromJson(Map<String, dynamic>.from(item));
      for (final url in moment.imageUrls) {
        final resolved = resolveMediaUrl(url);
        if (resolved.isNotEmpty) {
          ImageCacheService.instance.cacheInBackground(resolved);
        }
      }
    }
  }

  Future<void> _loadMoments({bool initial = true}) async {
    if (!initial && !_hasMore) return;

    if (!initial) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _hasError = false;
        _errorMessage = null;
        _offset = 0;
        _hasMore = true;
      });
    }

    try {
      final api = ApiService();
      Map<String, dynamic> data;
      if (widget.uid != null) {
        data = await api.getUserMoments(
          widget.uid!,
          offset: _offset,
          limit: _limit,
        );
      } else {
        data = await api.getMoments(offset: _offset, limit: _limit);
      }
      if (data['error'] != null) throw Exception(data['error']);
      final rawMoments =
          data['moments'] ??
          (data['response'] is Map
              ? data['response']['moments']
              : data['response']) ??
          (data['data'] is Map ? data['data']['moments'] : data['data']) ??
          data['items'] ??
          data['list'] ??
          data;
      final newMoments = rawMoments is List
          ? rawMoments
                .whereType<Map>()
                .map((e) => Moment.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : rawMoments is Map && rawMoments['moments'] is List
          ? (rawMoments['moments'] as List)
                .whereType<Map>()
                .map((e) => Moment.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : <Moment>[];
      final hasMore =
          data['has_more'] == true ||
          data['hasMore'] == true ||
          (data['pagination'] is Map &&
              data['pagination']['has_more'] == true) ||
          newMoments.length >= _limit;
      final merged = initial
          ? newMoments
          : <Moment>[..._moments, ...newMoments];
      final byId = <String, Moment>{};
      for (final item in merged) {
        byId[item.id.isEmpty
                ? '${item.uid}:${item.createdAt}:${item.body}'
                : item.id] =
            item;
      }
      final uniqueMoments = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _moments = uniqueMoments;
        _hasMore = hasMore;
        _offset += newMoments.length;
        _loading = false;
        _isLoadingMore = false;
        _hasError = false;
      });
      final userId = context.read<AuthService>().userId ?? 'guest';
      await CacheService().writeJson(
        CacheService().scoped(userId, 'moments:${widget.uid ?? 'feed'}'),
        _moments.map((moment) => moment.toJson()).toList(),
      );
    } catch (e) {
      if (initial) {
        final userId = context.read<AuthService>().userId ?? 'guest';
        final cached = await CacheService().readJson(
          CacheService().scoped(userId, 'moments:${widget.uid ?? 'feed'}'),
        );
        if (cached is List && cached.isNotEmpty && mounted) {
          setState(() {
            _moments = cached
                .whereType<Map>()
                .map((item) => Moment.fromJson(Map<String, dynamic>.from(item)))
                .toList();
            _loading = false;
            _hasError = false;
          });
          return;
        }
      }
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('加载动态失败: $e'))),
        );
      }
    }
  }

  Future<List<MomentComment>> _loadMomentComments(String momentId) async {
    try {
      final api = ApiService();
      final data = await api.getMomentComments(momentId, limit: 100);
      final comments =
          (data['comments'] as List?)
              ?.map((e) => MomentComment.fromJson(e))
              .toList() ??
          [];
      return comments;
    } catch (e) {
      return [];
    }
  }

  Future<void> _toggleLike(Moment moment) async {
    final index = _moments.indexWhere((item) => item.id == moment.id);
    if (index == -1) return;
    final nextLiked = !moment.isLiked;
    final updated = Moment(
      id: moment.id,
      uid: moment.uid,
      username: moment.username,
      displayName: moment.displayName,
      avatarUrl: moment.avatarUrl,
      body: moment.body,
      imageUrl: moment.imageUrl,
      imageUrls: moment.imageUrls,
      likes: nextLiked
          ? moment.likes + 1
          : (moment.likes - 1).clamp(0, 1 << 30),
      comments: moment.comments,
      isLiked: nextLiked,
      createdAt: moment.createdAt,
      commentList: moment.commentList,
    );
    setState(() => _moments[index] = updated);
    try {
      final api = ApiService();
      if (nextLiked) {
        await api.likeMoment(moment.id);
      } else {
        await api.unlikeMoment(moment.id);
      }
      final userId = context.read<AuthService>().userId ?? 'guest';
      await CacheService().writeJson(
        CacheService().scoped(userId, 'moments:${widget.uid ?? 'feed'}'),
        _moments.map((item) => item.toJson()).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _moments[index] = moment);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('操作失败: $e'))),
      );
    }
  }

  Future<void> _addComment(Moment moment, String text) async {
    if (text.trim().isEmpty) return;
    try {
      final api = ApiService();
      final result = await api.commentMoment(moment.id, text);
      final comments = await _loadMomentComments(moment.id);
      setState(() {
        _commentController.clear();
        _commentingMomentId = null;
        final index = _moments.indexOf(moment);
        if (index != -1) {
          _moments[index] = Moment(
            id: moment.id,
            uid: moment.uid,
            username: moment.username,
            displayName: moment.displayName,
            avatarUrl: moment.avatarUrl,
            body: moment.body,
            imageUrl: moment.imageUrl,
            imageUrls: moment.imageUrls,
            likes: moment.likes,
            comments: moment.comments + 1,
            isLiked: moment.isLiked,
            createdAt: moment.createdAt,
            commentList: comments,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('评论成功'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('评论失败: $e'))),
      );
    }
  }

  Future<void> _deleteMoment(Moment moment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.current.t('删除动态')),
        content: Text(AppLocalizations.current.t('确定要删除这条动态吗？')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.current.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppLocalizations.current.t('删除'),
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ApiService();
      await api.deleteMoment(moment.id);
      setState(() {
        _moments.removeWhere((m) => m.id == moment.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('已删除'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('删除失败: $e'))),
      );
    }
  }

  void _showImage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImageViewer(imageUrl: url)),
    );
  }

  void _showImageGallery(List<String> urls, {required int initialIndex}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewer(
          imageUrl: urls[initialIndex],
          imageUrls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _navigateToUser(String uid) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)),
    );
  }

  void _showPostDialog() {
    _postController.clear();
    setState(() {
      _selectedImageFiles.clear();
      _uploadedImageUrls.clear();
    });
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(AppLocalizations.current.t('发布动态')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _postController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.current.t('分享你的想法...'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image),
                      onPressed: () async {
                        final picker = ImagePicker();
                        final results = await picker.pickMultiImage();
                        if (results.isEmpty) return;
                        setDialogState(() {
                          _selectedImageFiles
                            ..clear()
                            ..addAll(results);
                          _uploadedImageUrls.clear();
                        });
                      },
                      tooltip: AppLocalizations.current.t('选择图片（可多选）'),
                    ),
                    Expanded(
                      child: Text(
                        _selectedImageFiles.isEmpty
                            ? '未选择图片'
                            : '已选择 ${_selectedImageFiles.length} 张图片',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_selectedImageFiles.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setDialogState(() {
                          _selectedImageFiles.clear();
                          _uploadedImageUrls.clear();
                        }),
                      ),
                  ],
                ),
                if (_selectedImageFiles.isNotEmpty)
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImageFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, index) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FutureBuilder<Uint8List>(
                          future: _selectedImageFiles[index].readAsBytes(),
                          builder: (_, snapshot) {
                            if (!snapshot.hasData) {
                              return const SizedBox(
                                width: 92,
                                height: 92,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return Image.memory(
                              snapshot.data!,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.current.t('取消')),
              ),
              TextButton(
                onPressed: _posting
                    ? null
                    : () async {
                        try {
                          final api = ApiService();
                          _uploadedImageUrls.clear();
                          for (final file in _selectedImageFiles) {
                            final formData = FormData.fromMap({
                              'file': MultipartFile.fromBytes(
                                await file.readAsBytes(),
                                filename: file.name,
                              ),
                            });
                            final result = await api.uploadFile(formData);
                            final url = ApiService.extractUploadUrl(result);
                            if (url == null || url.isEmpty) {
                              throw Exception('图片上传失败');
                            }
                            _uploadedImageUrls.add(url);
                          }
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          await _postMoment();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.current.t('上传失败: $e'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: Text(AppLocalizations.current.t('发布')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _postMoment() async {
    final text = _postController.text.trim();
    final imageUrls = List<String>.from(_uploadedImageUrls);
    if (text.isEmpty && imageUrls.isEmpty && _selectedImageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('请输入内容或选择图片'))),
      );
      return;
    }
    setState(() => _posting = true);
    try {
      final api = ApiService();
      if (imageUrls.isEmpty && _selectedImageFiles.isNotEmpty) {
        for (final file in _selectedImageFiles) {
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(
              await file.readAsBytes(),
              filename: file.name,
            ),
          });
          final result = await api.uploadFile(formData);
          final url = ApiService.extractUploadUrl(result);
          if (url == null || url.isEmpty) throw Exception('图片上传失败');
          imageUrls.add(url);
        }
      }
      await api.createMoment(body: text, imageUrls: imageUrls);
      if (!mounted) return;
      setState(() {
        _postController.clear();
        _selectedImageFiles.clear();
        _uploadedImageUrls.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('发布成功'))),
      );
      await _loadMoments(initial: true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('发布失败: $e'))),
        );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _showCommentInput(Moment moment) {
    _commentController.clear();
    _commentingMomentId = moment.id;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.current.t('写评论'),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _commentController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: AppLocalizations.current.t('输入评论...'),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  _addComment(moment, _commentController.text);
                  Navigator.pop(context);
                },
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.current.t('取消')),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _addComment(moment, _commentController.text);
                      Navigator.pop(context);
                    },
                    child: Text(AppLocalizations.current.t('发送')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComments(Moment moment) async {
    final loadingDialog = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );
    final comments = await _loadMomentComments(moment.id);
    Navigator.pop(context);
    setState(() {
      final index = _moments.indexOf(moment);
      if (index != -1) {
        _moments[index] = Moment(
          id: moment.id,
          uid: moment.uid,
          username: moment.username,
          displayName: moment.displayName,
          avatarUrl: moment.avatarUrl,
          body: moment.body,
          imageUrl: moment.imageUrl,
          imageUrls: moment.imageUrls,
          likes: moment.likes,
          comments: moment.comments,
          isLiked: moment.isLiked,
          createdAt: moment.createdAt,
          commentList: comments,
        );
      }
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '全部评论 (${comments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Divider(),
              Expanded(
                child: comments.isEmpty
                    ? Center(child: Text(AppLocalizations.current.t('暂无评论')))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          final commentName =
                              comment.displayName ??
                              comment.username ??
                              comment.uid;
                          final avatarUrl = resolveMediaUrl(comment.avatarUrl);
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? ImageCacheService.instance.provider(
                                      avatarUrl,
                                      cacheWidth: 96,
                                    )
                                  : null,
                              child: avatarUrl.isEmpty
                                  ? Text(
                                      commentName.isNotEmpty
                                          ? commentName.substring(0, 1)
                                          : '?',
                                    )
                                  : null,
                            ),
                            title: Text(
                              commentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(comment.text),
                            trailing: Text(
                              _formatTime(comment.createdAt),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.current.t('写评论...'),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          _addComment(moment, _commentController.text);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        _addComment(moment, _commentController.text);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 7) {
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  Widget _buildMomentCard(Moment moment, Color primaryColor, String? userId) {
    final isOwner = moment.uid == userId;
    final avatarUrl = resolveMediaUrl(moment.avatarUrl);
    final displayName = moment.displayName ?? moment.username ?? moment.uid;
    final imageUrls = moment.imageUrls.isNotEmpty
        ? moment.imageUrls
        : (moment.imageUrl == null ? const <String>[] : [moment.imageUrl!]);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _navigateToUser(moment.uid),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: avatarUrl.isNotEmpty
                        ? ImageCacheService.instance.provider(
                            resolveMediaUrl(avatarUrl),
                            cacheWidth: 96,
                          )
                        : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName.substring(0, 1)
                                : '?',
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _navigateToUser(moment.uid),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _formatTime(moment.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isOwner)
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          AppLocalizations.current.t('删除'),
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                    onSelected: (_) => _deleteMoment(moment),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (moment.body.isNotEmpty)
              Text(
                moment.body,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            if (imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildMomentImageGrid(imageUrls),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    moment.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: moment.isLiked ? Colors.red : null,
                  ),
                  onPressed: () => _toggleLike(moment),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 22,
                ),
                const SizedBox(width: 4),
                Text(
                  '${moment.likes}',
                  style: TextStyle(
                    fontSize: 13,
                    color: moment.isLiked ? Colors.red : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => _showCommentInput(moment),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 22,
                ),
                const SizedBox(width: 4),
                Text(
                  '${moment.comments}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const Spacer(),
                if (moment.comments > 0)
                  TextButton(
                    onPressed: () => _showComments(moment),
                    child: Text(
                      '查看全部 ${moment.comments} 条评论',
                      style: TextStyle(fontSize: 12, color: primaryColor),
                    ),
                  ),
              ],
            ),
            if (moment.commentList != null && moment.commentList!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: moment.commentList!.take(2).map((comment) {
                    final commentName =
                        comment.displayName ?? comment.username ?? comment.uid;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _navigateToUser(comment.uid),
                            child: Text(
                              commentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              comment.text,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMomentImageGrid(List<String> urls) {
    final normalized = urls
        .map(resolveMediaUrl)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return const SizedBox.shrink();
    final count = normalized.length;
    final visibleCount = count > 9 ? 9 : count;
    final columns = count == 1 ? 1 : 3;
    final rows = count == 1 ? 1 : ((visibleCount + columns - 1) ~/ columns);
    final height = count == 1 ? 220.0 : (rows * 112.0) + ((rows - 1) * 4.0);
    return SizedBox(
      height: height,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: count == 1 ? 1.7 : 1,
        ),
        itemCount: visibleCount,
        itemBuilder: (_, index) => GestureDetector(
          onTap: () => _showImageGallery(normalized, initialIndex: index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedImage(
                  normalized[index],
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: count == 1 ? 960 : 360,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
              if (index == 8 && count > 9)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+${count - 9}',
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final userId = context.read<AuthService>().userId;
    final isMyMoments = widget.uid == null || widget.uid == userId;

    final content = _loading
        ? Center(child: CircularProgressIndicator())
        : _hasError
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.current.t('加载失败: $_errorMessage'),
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _loadMoments(initial: true),
                  child: Text(AppLocalizations.current.t('重试')),
                ),
              ],
            ),
          )
        : _moments.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_album, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  widget.uid != null ? 'TA还没有动态' : '暂无动态，发布一条吧',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                if (isMyMoments) const SizedBox(height: 16),
                if (isMyMoments)
                  ElevatedButton.icon(
                    onPressed: _showPostDialog,
                    icon: const Icon(Icons.add),
                    label: Text(AppLocalizations.current.t('发布动态')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: () => _loadMoments(initial: true),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _moments.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _moments.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: _isLoadingMore
                          ? const CircularProgressIndicator()
                          : Text(AppLocalizations.current.t('没有更多了')),
                    ),
                  );
                }
                return _buildMomentCard(_moments[index], primaryColor, userId);
              },
            ),
          );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t(widget.uid != null ? 'TA的动态' : '动态')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (isMyMoments)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _showPostDialog,
              tooltip: AppLocalizations.current.t('发布动态'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadMoments(initial: true),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _hasError
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    AppLocalizations.current.t('加载失败: $_errorMessage'),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _loadMoments(initial: true),
                    child: Text(AppLocalizations.current.t('重试')),
                  ),
                ],
              ),
            )
          : _moments.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_album, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    widget.uid != null ? 'TA还没有动态' : '暂无动态，发布一条吧',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (isMyMoments) const SizedBox(height: 16),
                  if (isMyMoments)
                    ElevatedButton.icon(
                      onPressed: _showPostDialog,
                      icon: const Icon(Icons.add),
                      label: Text(AppLocalizations.current.t('发布动态')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadMoments(initial: true),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _moments.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _moments.length) {
                    if (_isLoadingMore) {
                      return Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: TextButton(
                          onPressed: () => _loadMoments(initial: false),
                          child: Text(AppLocalizations.current.t('加载更多')),
                        ),
                      ),
                    );
                  }
                  final moment = _moments[index];
                  return _buildMomentCard(moment, primaryColor, userId);
                },
              ),
            ),
    );
  }
}

class _MomentGalleryPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _MomentGalleryPage({required this.urls, required this.initialIndex});

  @override
  State<_MomentGalleryPage> createState() => _MomentGalleryPageState();
}

class _MomentGalleryPageState extends State<_MomentGalleryPage> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          AppLocalizations.current.t(
            '${_currentIndex + 1} / ${widget.urls.length}',
          ),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (_, index) => InteractiveViewer(
          child: Center(
            child: CachedImage(
              resolveMediaUrl(widget.urls[index]),
              width: double.infinity,
              height: double.infinity,
              cacheWidth: 1400,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
