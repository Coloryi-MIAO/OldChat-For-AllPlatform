import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../services/account_storage.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/notification.dart';
import '../utils/url_helper.dart';
import '../widgets/cached_image.dart';
import '../widgets/image_viewer.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationModel> _notifications = [];
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  bool _isLoadingMore = false;

  // ★ 好友申请列表
  List<Map<String, dynamic>> _friendRequests = [];
  // ★ 已处理过的申请ID集合（用于去重）
  Set<String> _processedRequestIds = {};
  List<Map<String, dynamic>> _groupRequests = [];
  Set<String> _processedGroupRequestIds = {};
  final Set<String> _localReadNotificationIds = <String>{};

  String _localReadKey(String id) => 'oldchat:notifications:read:$id';

  Future<void> _loadLocalReadIds() async {
    await AccountStorage.instance.load();
    final raw = AccountStorage.instance.getString('notification_read_ids') ?? '';
    final ids = raw.split('\n').where((id) => id.trim().isNotEmpty).toList();
    if (!mounted) return;
    setState(() => _localReadNotificationIds.addAll(ids));
  }

  @override
  void initState() {
    super.initState();
    _loadLocalReadIds();
    _loadFriendRequests();
    _loadGroupRequests();
    _loadNotifications();
  }

  // ★ 加载好友申请，过滤掉已是好友的申请
  Future<void> _loadFriendRequests() async {
    try {
      final api = ApiService();
      final friends = await api.getFriends();
      final friendUids = friends.map((f) => f.id).toSet();
      final data = await api.getFriendRequests();
      final allRequests =
          (data['requests'] ?? data['items'] ?? data['data']) is List
              ? ((data['requests'] ?? data['items'] ?? data['data']) as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : <Map<String, dynamic>>[];
      final filtered = allRequests.where((r) {
        final fromUid = '${r['from_uid'] ?? r['sender_uid'] ?? r['uid'] ?? ''}';
        if (r['status'] != 'pending' && r['status'] != 0) return false;
        if (friendUids.contains(fromUid)) return false;
        if (_processedRequestIds.contains('${r['id'] ?? r['request_id'] ?? ''}')) return false;
        return true;
      }).toList();
      if (mounted) setState(() => _friendRequests = filtered);
    } catch (e) {
      debugPrint('加载好友申请失败: $e');
    }
  }

  Future<void> _loadGroupRequests() async {
    try {
      final groups = await ApiService().getGroups();
      final incoming = <Map<String, dynamic>>[];
      for (final group in groups) {
        try {
          final data = await ApiService().getGroupRequests(group.id);
          final raw = data['requests'] ?? data['items'] ?? data['data'];
          if (raw is! List) continue;
          for (final item in raw.whereType<Map>()) {
            final request = Map<String, dynamic>.from(item);
            final status = '${request['status'] ?? 'pending'}';
            final requestId = '${request['id'] ?? request['request_id'] ?? ''}';
            if ((status == 'pending' || request['status'] == 0) &&
                requestId.isNotEmpty &&
                !_processedGroupRequestIds.contains(requestId)) {
              request['group_id'] ??= group.id;
              request['group_name'] ??= group.name ?? group.id;
              incoming.add(request);
            }
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _groupRequests = incoming);
    } catch (_) {}
  }

  Future<void> _respondGroupRequest(String requestId, bool accept) async {
    if (requestId.isEmpty) return;
    try {
      await ApiService().approveGroupRequest(requestId, accept);
      if (!mounted) return;
      setState(() {
        _processedGroupRequestIds.add(requestId);
        _groupRequests.removeWhere(
          (item) => '${item['id'] ?? item['request_id']}' == requestId,
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t(accept ? '已接受群聊申请' : '已拒绝群聊申请'))));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('处理群聊申请失败：$e'))));
    }
  }

  Future<void> _loadNotifications({bool initial = true}) async {
    if (!initial) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
      });
    }

    try {
      final api = ApiService();
      final data = await api.getNotifications(offset: _offset, limit: _limit);
      final newNotifs =
          ((data['items'] ?? data['notifications'] ?? data['data']) as List?)
              ?.whereType<Map>()
              .map((e) {
                final notification = NotificationModel.fromJson(
                  Map<String, dynamic>.from(e),
                );
                return _localReadNotificationIds.contains(notification.id)
                    ? NotificationModel(
                        id: notification.id,
                        type: notification.type,
                        fromUid: notification.fromUid,
                        fromName: notification.fromName,
                        fromAvatar: notification.fromAvatar,
                        title: notification.title,
                        body: notification.body,
                        targetId: notification.targetId,
                        isRead: true,
                        createdAt: notification.createdAt,
                        mediaUrls: notification.mediaUrls,
                      )
                    : notification;
              })
              .toList() ??
          [];
      final hasMore = data['has_more'] ?? data['next'] != null;

      setState(() {
        if (initial) {
          _notifications = newNotifs;
        } else {
          _notifications.addAll(newNotifs);
        }
        _hasMore = hasMore;
        _offset += newNotifs.length;
        _loading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('加载通知失败: $e'))));
      }
    }
  }

  Future<void> _markRead(NotificationModel notification) async {
    if (notification.isRead || _localReadNotificationIds.contains(notification.id)) return;
    _localReadNotificationIds.add(notification.id);
    await AccountStorage.instance.setString(
      'notification_read_ids',
      _localReadNotificationIds.join('\n'),
    );
    if (!mounted) return;
    setState(() {
      final index = _notifications.indexOf(notification);
      if (index != -1) {
        _notifications[index] = NotificationModel(
          id: notification.id,
          type: notification.type,
          fromUid: notification.fromUid,
          fromName: notification.fromName,
          fromAvatar: notification.fromAvatar,
          title: notification.title,
          body: notification.body,
          targetId: notification.targetId,
          isRead: true,
          createdAt: notification.createdAt,
          mediaUrls: notification.mediaUrls,
        );
      }
    });
  }

  // ★ 响应好友申请（接受/拒绝）
  Future<void> _respondFriendRequest(String requestId, bool accept) async {
    if (requestId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('请求ID无效'))));
      return;
    }
    try {
      final api = ApiService();
      await api.respondFriendRequest(requestId, accept);

      setState(() {
        _processedRequestIds.add(requestId);
        _friendRequests.removeWhere(
          (r) => '${r['id'] ?? r['request_id'] ?? ''}' == requestId,
        );
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t(accept ? '已接受好友申请' : '已拒绝'))));

      await _loadNotifications(initial: true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('操作失败: $e'))));
    }
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
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

  Widget _buildAvatar(String? rawUrl, String? name) {
    final url = resolveMediaUrl(rawUrl);
    final fallback = name?.isNotEmpty == true ? name!.substring(0, 1) : '?';
    if (url.isEmpty) return CircleAvatar(child: Text(fallback));
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewer(imageUrl: url)),
      ),
      child: ClipOval(
        child: CachedImage(
          url,
          width: 48,
          height: 48,
          cacheWidth: 144,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => CircleAvatar(child: Text(fallback)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    List<Widget> allItems = [];

    // ★ 好友申请部分（放在最顶部，相当于 Tab 效果）
    if (_friendRequests.isNotEmpty) {
      allItems.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.blue[50],
          child: Row(
            children: [
              const Icon(Icons.person_add, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Text(
                '好友申请 (${_friendRequests.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blue,
                ),
              ),
              const Spacer(),
              Text(
                '点击操作',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
      for (var req in _friendRequests) {
        final fromName =
            req['from_display_name'] ??
            req['from_username'] ??
            req['from_uid'] ??
            '未知用户';
        final fromUid =
            req['from_uid'] ?? req['sender_uid'] ?? req['uid'] ?? '';
        final requestId = '${req['id'] ?? req['request_id'] ?? ''}';
        final avatarUrl = req['avatar_url'];
        final createdAt = req['created_at'] ?? 0;

        allItems.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.blue[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: _buildAvatar(avatarUrl, fromName),
              title: Text(
                fromName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(AppLocalizations.current.t('请求添加您为好友 · ${_formatTime(createdAt)}')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _respondFriendRequest(requestId, true),
                    tooltip: AppLocalizations.current.t('接受'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _respondFriendRequest(requestId, false),
                    tooltip: AppLocalizations.current.t('拒绝'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // ★ 系统通知部分
    if (_groupRequests.isNotEmpty) {
      allItems.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.orange[50],
          child: Row(
            children: [
              const Icon(Icons.group_add, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                '群聊申请 (${_groupRequests.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      );
      for (final request in _groupRequests) {
        final requestId = '${request['id'] ?? request['request_id'] ?? ''}';
        final fromName =
            '${request['from_display_name'] ?? request['from_name'] ?? request['from_uid'] ?? '未知用户'}';
        final groupName =
            '${request['group_name'] ?? request['group_id'] ?? '群聊'}';
        allItems.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.orange[50],
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.group)),
              title: Text(AppLocalizations.current.t('$fromName 申请加入 $groupName')),
              subtitle: Text(request['message']?.toString() ?? AppLocalizations.current.t('群聊申请')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _respondGroupRequest(requestId, true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _respondGroupRequest(requestId, false),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    allItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '系统通知 (${_notifications.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ),
    );

    if (_notifications.isEmpty) {
      allItems.add(
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text(AppLocalizations.current.t('暂无通知'))),
        ),
      );
    } else {
      for (var notification in _notifications) {
        allItems.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: notification.isRead ? null : Colors.blue[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: _buildAvatar(
                notification.fromAvatar,
                notification.fromName,
              ),
              title: Text(
                notification.title,
                style: TextStyle(
                  fontWeight: notification.isRead
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.body),
                  if (notification.mediaUrls.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: notification.mediaUrls.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, mediaIndex) => InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImageViewer(
                                  imageUrl: notification.mediaUrls[mediaIndex],
                                  imageUrls: notification.mediaUrls,
                                  initialIndex: mediaIndex,
                                ),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedImage(
                                resolveMediaUrl(
                                  notification.mediaUrls[mediaIndex],
                                ),
                                width: 72,
                                height: 72,
                                cacheWidth: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 72,
                                  height: 72,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(notification.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  if (!notification.isRead)
                    const Icon(Icons.circle, color: Colors.blue, size: 8),
                ],
              ),
              onTap: () async {
                await _markRead(notification);
                if (!mounted || notification.mediaUrls.isEmpty) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImageViewer(
                      imageUrl: notification.mediaUrls.first,
                      imageUrls: notification.mediaUrls,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('通知中心')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all, color: Colors.white),
            onPressed: () async {
              for (var n in _notifications.where((n) => !n.isRead)) {
                await _markRead(n);
              }
            },
            tooltip: AppLocalizations.current.t('全部已读'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadNotifications(initial: true);
              _loadFriendRequests();
              _loadGroupRequests();
            },
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: allItems.length,
              itemBuilder: (context, index) => allItems[index],
            ),
    );
  }
}
