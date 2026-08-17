import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../widgets/conversation_tile.dart';
import '../pages/chat_page.dart';
import '../pages/login_page.dart';
import '../utils/navigation.dart';
import '../utils/url_helper.dart';
import '../services/cache_service.dart';
import '../services/plugin_service.dart';
import '../services/account_storage.dart';
import '../services/app_localizations.dart';
import '../widgets/cached_image.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Conversation> _groups = [];
  List<Conversation> _friends = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  Map<String, int> _unreadCounts = {};
  final Map<String, bool> _pinnedMap = {};
  Conversation? _currentConversation;
  int _totalUnread = 0;
  Timer? _searchTimer;
  Timer? _unreadReloadTimer;
  Timer? _systemNotificationTimer;
  Timer? _realtimePollTimer;
  bool _unreadPollInFlight = false;
  bool _conversationPollInFlight = false;
  bool _systemNotificationBaselineReady = false;
  bool _systemNotificationPollInFlight = false;
  final Set<String> _seenSystemNotificationIds = <String>{};
  final Set<String> _seenFriendRequestIds = <String>{};
  final Set<String> _seenGroupRequestIds = <String>{};
  final Set<String> _seenGroupInvitationIds = <String>{};
  bool _requestNotificationBaselineReady = false;
  String? _avatarUrl;
  final Set<String> _realtimeMessageIds = <String>{};
  final Map<String, int> _realtimeUnreadPending = <String, int>{};
  final Map<String, Conversation> _recentConversations =
      <String, Conversation>{};
  final Map<String, int> _conversationOpenCounts = <String, int>{};
  final Map<String, int> _recentUsedAt = <String, int>{};
  final Set<String> _hiddenRecentKeys = <String>{};
  Timer? _recentSaveTimer;

  @override
  void initState() {
    super.initState();
    _restoreCachedConversations();
    _restoreRecentConversations();
    _restoreHiddenRecentKeys();
    _ensureUserCacheDirectory();
    _loadConversations();
    _loadPinnedState();
    _loadUnreadCounts();
    _startRealtimePolling();
    _startSystemNotificationPolling();
    _setupWebSocket();
    _loadUserAvatar();
  }

  Future<void> _ensureUserCacheDirectory() async {
    final uid = context.read<AuthService>().userId;
    if (uid != null) await CacheService().directory(userId: uid);
  }

  Future<void> _restoreRecentConversations() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null) return;
    final cached = await CacheService().readJson(
      CacheService().scoped(uid, 'recent_conversations'),
    );
    if (cached is! List || !mounted) return;
    final restored = <String, Conversation>{};
    final openCounts = <String, int>{};
    final usedAt = <String, int>{};
    for (final item in cached.whereType<Map>()) {
      final raw = Map<String, dynamic>.from(item);
      final value = raw['conversation'];
      final source = value is Map ? value : raw;
      final conversation = Conversation.fromJson(
        Map<String, dynamic>.from(source),
      );
      if (conversation.id.isEmpty) continue;
      final key = _conversationKey(conversation);
      if (_hiddenRecentKeys.contains(key)) continue;
      restored[key] = conversation;
      openCounts[key] = (raw['open_count'] as num?)?.toInt() ?? 0;
      usedAt[key] = (raw['used_at'] as num?)?.toInt() ?? 0;
    }
    if (!mounted) return;
    setState(() {
      _recentConversations
        ..clear()
        ..addAll(restored);
      _conversationOpenCounts
        ..clear()
        ..addAll(openCounts);
      _recentUsedAt
        ..clear()
        ..addAll(usedAt);
    });
  }

  Future<void> _restoreHiddenRecentKeys() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null || uid.isEmpty) return;
    await AccountStorage.instance.load();
    final saved = (AccountStorage.instance.getString('hidden_recent') ?? '')
        .split('\n')
        .where((value) => value.trim().isNotEmpty)
        .toList();
    if (!mounted) return;
    setState(() {
      _hiddenRecentKeys
        ..clear()
        ..addAll(saved);
      _recentConversations.removeWhere(
        (key, _) => _hiddenRecentKeys.contains(key),
      );
    });
  }

  Future<void> _persistHiddenRecentKeys() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null || uid.isEmpty) return;
    await AccountStorage.instance.setString(
      'hidden_recent',
      _hiddenRecentKeys.join('\n'),
    );
  }

  void _scheduleRecentPersist() {
    _recentSaveTimer?.cancel();
    _recentSaveTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_persistRecentConversations());
    });
  }

  Future<void> _persistRecentConversations() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null || uid.isEmpty) return;
    final entries = _recentConversations.entries
        .map(
          (entry) => {
            'conversation': entry.value.toJson(),
            'open_count': _conversationOpenCounts[entry.key] ?? 0,
            'used_at': _recentUsedAt[entry.key] ?? 0,
          },
        )
        .toList();
    await CacheService().writeJson(
      CacheService().scoped(uid, 'recent_conversations'),
      entries,
    );
  }

  void _mergeRecentDetails(Iterable<Conversation> conversations) {
    var changed = false;
    for (final conversation in conversations) {
      final key = _conversationKey(conversation);
      if (_recentConversations.containsKey(key)) {
        _recentConversations[key] = conversation;
        changed = true;
      }
    }
    if (changed) _scheduleRecentPersist();
  }

  void _rememberRecent(
    Conversation conversation, {
    bool force = false,
    bool incrementOpen = false,
  }) {
    final key = _conversationKey(conversation);
    if (_hiddenRecentKeys.contains(key) && !force) return;
    if (incrementOpen) {
      _conversationOpenCounts[key] = (_conversationOpenCounts[key] ?? 0) + 1;
    }
    if (!force &&
        !_recentConversations.containsKey(key) &&
        (_conversationOpenCounts[key] ?? 0) < 2)
      return;
    if (force) {
      _hiddenRecentKeys.remove(key);
      unawaited(_persistHiddenRecentKeys());
    }
    _recentConversations[key] = conversation;
    _recentUsedAt[key] = DateTime.now().millisecondsSinceEpoch;
    _scheduleRecentPersist();
  }

  Conversation? _conversationByKey(String key) {
    for (final conversation in [..._groups, ..._friends]) {
      if (_conversationKey(conversation) == key) return conversation;
    }
    return null;
  }

  void _rememberMessageConversation(Message message) {
    final key = message.groupId == null
        ? 'direct:${message.fromUid}'
        : 'group:${message.groupId}';
    final existing = _conversationByKey(key);
    if (existing == null) return;
    final conversation = existing.copyWith(lastMessage: message);
    final target = conversation.type == 'group' ? _groups : _friends;
    final index = target.indexWhere((item) => _conversationKey(item) == key);
    if (index >= 0) {
      target[index] = conversation;
    }
    if (!_hiddenRecentKeys.contains(key) && index >= 0) {
      _recentConversations[key] = conversation;
      _recentUsedAt[key] = DateTime.now().millisecondsSinceEpoch;
      _scheduleRecentPersist();
    }
  }

  void _mergeMessageIntoHome(Message message) {
    if (message.id.isEmpty) return;
    final key = message.groupId == null
        ? 'direct:${message.fromUid}'
        : 'group:${message.groupId}';
    final existing = _conversationByKey(key);
    if (existing == null) return;
    final currentLast = existing.lastMessage;
    if (currentLast != null &&
        currentLast.id.isNotEmpty &&
        currentLast.id == message.id) {
      return;
    }
    if (currentLast != null && currentLast.createdAt > message.createdAt) {
      return;
    }
    final updated = existing.copyWith(lastMessage: message);
    final target = updated.type == 'group' ? _groups : _friends;
    final index = target.indexWhere((item) => _conversationKey(item) == key);
    if (index >= 0) {
      target[index] = updated;
    }
  }

  void _removeRecent(Conversation conversation) {
    final key = _conversationKey(conversation);
    setState(() {
      _recentConversations.remove(key);
      _recentUsedAt.remove(key);
      _hiddenRecentKeys.add(key);
    });
    unawaited(_persistHiddenRecentKeys());
    _scheduleRecentPersist();
  }

  List<Conversation> _recentList() {
    final validKeys = {..._groups, ..._friends}.map(_conversationKey).toSet();
    final staleKeys = _recentConversations.keys
        .where((key) => !validKeys.contains(key))
        .toList();
    if (staleKeys.isNotEmpty) {
      for (final key in staleKeys) {
        _recentConversations.remove(key);
        _recentUsedAt.remove(key);
        _conversationOpenCounts.remove(key);
      }
      _scheduleRecentPersist();
    }
    final list = _recentConversations.values
        .where(
          (conversation) =>
              !_hiddenRecentKeys.contains(_conversationKey(conversation)) &&
              validKeys.contains(_conversationKey(conversation)),
        )
        .toList();
    list.sort((a, b) {
      final aPinned = _isPinned(a);
      final bPinned = _isPinned(b);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return (_recentUsedAt[_conversationKey(b)] ?? 0).compareTo(
        _recentUsedAt[_conversationKey(a)] ?? 0,
      );
    });
    return list;
  }

  Future<void> _restoreCachedConversations() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null) return;
    final cached = await CacheService().readJson(
      CacheService().scoped(uid, 'conversations'),
    );
    if (cached is! List || !mounted) return;
    final byKey = <String, Conversation>{};
    for (final item in cached.whereType<Map>()) {
      final conversation = Conversation.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (conversation.id.isNotEmpty)
        byKey[_conversationKey(conversation)] = conversation;
    }
    final conversations = byKey.values.toList();
    if (!mounted) return;
    setState(() {
      _friends = conversations.where((c) => c.type == 'direct').toList();
      _groups = conversations.where((c) => c.type == 'group').toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    WebSocketService().removeDirectListener(_onNewMessage);
    WebSocketService().removeGroupListener(_onNewMessage);
    _searchTimer?.cancel();
    _unreadReloadTimer?.cancel();
    _systemNotificationTimer?.cancel();
    _realtimePollTimer?.cancel();
    _recentSaveTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAvatar() async {
    final auth = context.read<AuthService>();
    final uid = auth.userId;
    if (uid == null) return;
    try {
      final api = ApiService();
      final profile = await api.getUserProfile(uid);
      await CacheService().writeJson(
        CacheService().scoped(uid, 'profile:$uid'),
        profile,
      );
      if (mounted) {
        setState(() {
          _avatarUrl = profile['avatar_url'];
        });
      }
    } catch (_) {
      final cached = await CacheService().readJson(
        CacheService().scoped(uid, 'profile:$uid'),
      );
      if (cached is Map && mounted) {
        setState(() => _avatarUrl = cached['avatar_url']);
      }
    }
  }

  void _setupWebSocket() {
    final ws = WebSocketService();
    ws.addDirectListener(_onNewMessage);
    ws.addGroupListener(_onNewMessage);
    ws.connect();
  }

  String _pinPreferenceKey(String userId, String conversationKey) =>
      'oldchat_pin:$userId:$conversationKey';

  Future<void> _loadPinnedState() async {
    final userId = context.read<AuthService>().userId;
    if (userId == null || userId.isEmpty) return;
    await AccountStorage.instance.load();
    final loaded = <String, bool>{};
    final prefix = 'pinned:';
    for (final key in AccountStorage.instance.keys.where(
      (key) => key.startsWith(prefix),
    )) {
      final conversationKey = key.substring(prefix.length);
      if (conversationKey.isEmpty) continue;
      final stored = AccountStorage.instance.getBool(key);
      if (stored != null) loaded[conversationKey] = stored;
    }
    if (!mounted) return;
    setState(() {
      _pinnedMap
        ..clear()
        ..addAll(loaded);
    });
  }

  void _onNewMessage(Message msg) {
    unawaited(
      PluginService().dispatchMessage(
        msg,
        conversationId: msg.groupId ?? msg.fromUid,
      ),
    );
    if (!mounted) return;
    if (!_realtimeMessageIds.add(msg.id)) return;
    if (_realtimeMessageIds.length > 5000) {
      _realtimeMessageIds.remove(_realtimeMessageIds.first);
    }
    final userId = context.read<AuthService>().userId;
    if (msg.fromUid == userId) return;

    final key = msg.groupId == null
        ? 'direct:${msg.fromUid}'
        : 'group:${msg.groupId}';
    final targetConversation = _conversationByKey(key);
    if (targetConversation == null) return;
    final isCurrentConversation =
        _currentConversation != null &&
        _currentConversation!.id == (msg.groupId ?? msg.fromUid) &&
        _currentConversation!.type ==
            (msg.groupId == null ? 'direct' : 'group');
    unawaited(
      NotificationService().showMessageNotification(
        fromName: msg.fromUid,
        message: msg.body,
        conversationId: msg.groupId ?? msg.fromUid,
        conversationType: msg.groupId == null ? 'direct' : 'group',
        withFlash: !isCurrentConversation,
      ),
    );
    setState(() {
      _mergeMessageIntoHome(msg);
      if (!isCurrentConversation) {
        _unreadCounts[key] = (_unreadCounts[key] ?? 0) + 1;
        _realtimeUnreadPending[key] = _unreadCounts[key]!;
      }
      _totalUnread = _unreadCounts.values
          .fold(0, (sum, count) => sum + count)
          .clamp(0, 1 << 30);
      final all = [..._groups, ..._friends];
      final index = all.indexWhere(
        (conversation) =>
            conversation.id == (msg.groupId ?? msg.fromUid) &&
            conversation.type == (msg.groupId == null ? 'direct' : 'group'),
      );
      if (index >= 0) {
        final conversation = all[index];
        final updated = conversation.copyWith(
          lastMessage: msg,
          unreadCount: isCurrentConversation
              ? conversation.unreadCount
              : conversation.unreadCount + 1,
        );
        if (conversation.type == 'group') {
          _groups[_groups.indexOf(conversation)] = updated;
        } else {
          _friends[_friends.indexOf(conversation)] = updated;
        }
        _rememberRecent(updated, force: true);
      } else {
        _rememberMessageConversation(msg);
      }
      _totalUnread = _unreadCounts.values
          .fold(0, (sum, count) => sum + count)
          .clamp(0, 1 << 30);
    });

    _unreadReloadTimer?.cancel();
    _unreadReloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted)
        unawaited(
          _loadUnreadCounts(excludeKey: isCurrentConversation ? key : null),
        );
    });
  }

  void _startRealtimePolling() {
    _realtimePollTimer?.cancel();
    _realtimePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _unreadPollInFlight) return;
      unawaited(_loadUnreadCounts());
      if (!_conversationPollInFlight) unawaited(_refreshConversationPreviews());
    });
  }

  void _startSystemNotificationPolling() {
    _systemNotificationTimer?.cancel();
    unawaited(_pollSystemNotifications());
    _systemNotificationTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) unawaited(_pollSystemNotifications());
    });
  }

  Future<void> _pollSystemNotifications() async {
    if (_systemNotificationPollInFlight || !mounted) return;
    _systemNotificationPollInFlight = true;
    try {
      final api = ApiService();
      Future<dynamic> safe(Future<dynamic> future, String label) async {
        try {
          return await future;
        } catch (error) {
          debugPrint('[系统通知] $label 暂不可用：$error');
          return null;
        }
      }
      final results = await Future.wait<dynamic>([
        safe(api.getNotifications(limit: 50, offset: 0), '系统通知'),
        safe(api.getFriendRequests(), '好友申请'),
        safe(api.getAllGroupRequests(), '群聊申请'),
        safe(api.getGroupInvitations(), '群聊邀请'),
      ]);
      final data = results.isNotEmpty && results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : <String, dynamic>{};
      final raw =
          data['items'] ?? data['notifications'] ?? data['data'] ?? data;
      final items = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const <Map<String, dynamic>>[];
      final incoming = <Map<String, dynamic>>[];
      for (final item in items) {
        final id = (item['id'] ?? item['notification_id'] ?? item['uuid'] ?? '')
            .toString();
        if (id.isEmpty) continue;
        if (!_systemNotificationBaselineReady) {
          _seenSystemNotificationIds.add(id);
        } else if (!_seenSystemNotificationIds.contains(id) &&
            item['is_read'] != true &&
            item['read'] != true) {
          incoming.add(item);
        }
        _seenSystemNotificationIds.add(id);
      }
      void collectRequests(
        dynamic rawValue,
        Set<String> seen,
        String title,
        String fallback,
        bool isInvitation,
      ) {
        final list = rawValue is Map
            ? (rawValue['requests'] ??
                  rawValue['invitations'] ??
                  rawValue['items'] ??
                  rawValue['data'])
            : rawValue;
        if (list is! List) return;
        for (final value in list.whereType<Map>()) {
          final item = Map<String, dynamic>.from(value);
          final status = '${item['status'] ?? 'pending'}';
          final id =
              '${item[isInvitation ? 'invitation_id' : 'id'] ?? item['request_id'] ?? item['id'] ?? ''}';
          if (id.isEmpty || (status != 'pending' && item['status'] != 0))
            continue;
          if (!_requestNotificationBaselineReady) {
            seen.add(id);
          } else if (!seen.contains(id)) {
            incoming.add({
              'id': id,
              'title': title,
              'body':
                  '${item['from_display_name'] ?? item['from_name'] ?? item['inviter_name'] ?? fallback}：${item['group_name'] ?? item['group_id'] ?? fallback}',
            });
          }
          seen.add(id);
        }
      }

      collectRequests(
        results[1],
        _seenFriendRequestIds,
        '新的好友申请',
        '有人申请添加你为好友',
        false,
      );
      collectRequests(
        results[2],
        _seenGroupRequestIds,
        '新的群聊申请',
        '有人申请加入群聊',
        false,
      );
      collectRequests(
        results[3],
        _seenGroupInvitationIds,
        '新的群聊邀请',
        '你收到群聊邀请',
        true,
      );
      _systemNotificationBaselineReady = true;
      _requestNotificationBaselineReady = true;
      for (final item in incoming.reversed) {
        unawaited(
          NotificationService().showNotification(
            title: (item['title'] ?? 'OldChat 通知').toString(),
            body:
                (item['body'] ??
                        item['content'] ??
                        item['message'] ??
                        '收到一条新通知')
                    .toString(),
          ),
        );
      }
    } catch (error) {
      debugPrint('[系统通知] 轮询失败：$error');
    } finally {
      _systemNotificationPollInFlight = false;
    }
  }

  Future<void> _refreshConversationPreviews() async {
    if (_conversationPollInFlight || !mounted) return;
    _conversationPollInFlight = true;
    try {
      final results = await Future.wait<dynamic>([
        _safeFriends(),
        _safeGroups(),
      ]);
      if (!mounted) return;
      final friends = results.isNotEmpty && results[0] is List
          ? (results[0] as List).whereType<Conversation>().toList()
          : <Conversation>[];
      final groups = results.length > 1 && results[1] is List
          ? (results[1] as List).whereType<Conversation>().toList()
          : <Conversation>[];
      final current = _currentConversation;
      setState(() {
        _friends = _mergeConversationUpdates(_friends, friends);
        _groups = _mergeConversationUpdates(_groups, groups);
        _mergeRecentDetails([..._groups, ..._friends]);
        if (current != null) {
          final replacement = [
            ..._groups,
            ..._friends,
          ].where((item) => item.id == current.id && item.type == current.type);
          if (replacement.isNotEmpty) _currentConversation = replacement.first;
        }
      });
    } catch (error) {
      debugPrint('[会话预览] 增量刷新失败：$error');
    } finally {
      _conversationPollInFlight = false;
    }
  }

  Future<List<Conversation>> _safeFriends() async {
    try {
      return await ApiService().getFriends();
    } catch (error) {
      debugPrint('[会话预览] 好友列表暂不可用：$error');
      return const <Conversation>[];
    }
  }

  Future<List<Conversation>> _safeGroups() async {
    try {
      return await ApiService().getGroups();
    } catch (error) {
      debugPrint('[会话预览] 群聊列表暂不可用：$error');
      return const <Conversation>[];
    }
  }

  List<Conversation> _mergeConversationUpdates(
    List<Conversation> current,
    List<Conversation> incoming,
  ) {
    final byKey = <String, Conversation>{
      for (final item in current) _conversationKey(item): item,
    };
    for (final item in incoming) {
      final old = byKey[_conversationKey(item)];
      final unread =
          _unreadCounts[_conversationKey(item)] ??
          old?.unreadCount ??
          item.unreadCount;
      byKey[_conversationKey(item)] = item.copyWith(unreadCount: unread);
    }
    return byKey.values.toList();
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;
    final hadVisibleData = _friends.isNotEmpty || _groups.isNotEmpty;
    if (!hadVisibleData && mounted) setState(() => _loading = true);
    try {
      final api = ApiService();
      final results = await Future.wait<dynamic>([
        api.getFriends(),
        api.getGroups(),
      ]);
      final friends = results.isNotEmpty && results[0] is List
          ? (results[0] as List).whereType<Conversation>().toList()
          : <Conversation>[];
      final groups = results.length > 1 && results[1] is List
          ? (results[1] as List).whereType<Conversation>().toList()
          : <Conversation>[];
      if (mounted) {
        setState(() {
          _friends = friends
              .where((item) => item.id.trim().isNotEmpty)
              .toList();
          _groups = groups.where((item) => item.id.trim().isNotEmpty).toList();
          _mergeRecentDetails([...groups, ...friends]);
          _error = null;
          _loading = false;
          if (_currentConversation != null) {
            final all = [...groups, ...friends];
            final active = _currentConversation!;
            final replacement = all.where(
              (c) => c.id == active.id && c.type == active.type,
            );
            if (replacement.isNotEmpty) {
              _currentConversation = replacement.first;
            }
          }
        });
        final userId = context.read<AuthService>().userId;
        if (userId != null) {
          await CacheService().writeJson(
            CacheService().scoped(userId, 'conversations'),
            [...groups, ...friends].map((c) => c.toJson()).toList(),
          );
          await _loadPinnedState();
        }
      }
    } catch (e) {
      final userId = context.read<AuthService>().userId;
      final cached = userId == null
          ? null
          : await CacheService().readJson(
              CacheService().scoped(userId, 'conversations'),
            );
      if (cached is List && mounted) {
        final conversations = cached
            .whereType<Map>()
            .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        setState(() {
          _friends = conversations.where((c) => c.type == 'direct').toList();
          _groups = conversations.where((c) => c.type == 'group').toList();
          _loading = false;
          _error = null;
        });
      } else if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _loadUnreadCounts({String? excludeKey}) async {
    if (_unreadPollInFlight) return;
    _unreadPollInFlight = true;
    try {
      final api = ApiService();
      final directUnread = await api.getDirectUnread();
      final groupUnread = await api.getGroupUnread();
      Map<String, int> counts = {};
      final seenUnreadIds = <String>{};
      final directMessages =
          directUnread['messages'] ??
          directUnread['items'] ??
          directUnread['data'];
      if (directMessages is List)
        directMessages.whereType<Map>().forEach((raw) {
          final json = Map<String, dynamic>.from(raw);
          final message = Message.fromJson(json);
          final messageKey = message.id.isNotEmpty
              ? message.id
              : '${message.fromUid}:${message.createdAt}:${message.body}';
          if (!seenUnreadIds.add(messageKey)) return;
          if (_conversationByKey('direct:${json['from_uid'] ?? message.fromUid}') != null) {
            _mergeMessageIntoHome(message);
          }
          final uid = json['from_uid'];
          final readAt = (json['read_at'] as num?)?.toInt();
          if (uid != null &&
              uid != context.read<AuthService>().userId &&
              _conversationByKey('direct:$uid') != null &&
              (readAt == null || readAt == 0)) {
            final key = 'direct:$uid';
            counts[key] = (counts[key] ?? 0) + 1;
          }
        });
      final groupMessages =
          groupUnread['messages'] ??
          groupUnread['items'] ??
          groupUnread['data'];
      if (groupMessages is List)
        groupMessages.whereType<Map>().forEach((raw) {
          final json = Map<String, dynamic>.from(raw);
          final message = Message.fromJson(json);
          final messageKey = message.id.isNotEmpty
              ? message.id
              : '${message.groupId}:${message.createdAt}:${message.body}';
          if (!seenUnreadIds.add(messageKey)) return;
          if (_conversationByKey('group:${json['group_id'] ?? message.groupId ?? ''}') != null) {
            _mergeMessageIntoHome(message);
          }
          final gid = json['group_id'];
          final readAt = (json['read_at'] as num?)?.toInt();
          if (gid != null &&
              _conversationByKey('group:$gid') != null &&
              (readAt == null || readAt == 0)) {
            final key = 'group:$gid';
            counts[key] = (counts[key] ?? 0) + 1;
          }
        });

      for (final entry in _realtimeUnreadPending.entries) {
        final serverCount = counts[entry.key] ?? 0;
        if (entry.value > serverCount) counts[entry.key] = entry.value;
      }
      final validKeys = {..._friends, ..._groups}.map(_conversationKey).toSet();
      counts.removeWhere((key, value) => !validKeys.contains(key) || value <= 0);
      final activeKey =
          excludeKey ??
          (_currentConversation == null
              ? null
              : _conversationKey(_currentConversation!));
      if (activeKey != null) counts.remove(activeKey);
      if (mounted) {
        setState(() {
          _unreadCounts = counts;
          _totalUnread = counts.values
              .where((count) => count > 0)
              .fold(0, (sum, count) => sum + count)
              .clamp(0, 1 << 30);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unreadCounts = {};
          _totalUnread = 0;
        });
      }
    } finally {
      _unreadPollInFlight = false;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      await Future.wait([
        _loadConversations(),
        _loadUnreadCounts(),
        _loadUserAvatar(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _conversationKey(Conversation conv) => '${conv.type}:${conv.id}';

  bool _isPinned(Conversation conv) =>
      _pinnedMap[_conversationKey(conv)] ?? conv.pinned;

  List<Conversation> _sortConversations(List<Conversation> conversations) {
    final list = List<Conversation>.from(conversations);
    list.sort((a, b) {
      final aPinned = _isPinned(a);
      final bPinned = _isPinned(b);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      final aLast = a.lastMessage;
      final bLast = b.lastMessage;
      if (aLast != null && bLast != null) {
        final last = bLast.createdAt.compareTo(aLast.createdAt);
        if (last != 0) return last;
        final id = bLast.id.compareTo(aLast.id);
        if (id != 0) return id;
      } else if (aLast != null || bLast != null) {
        return aLast != null ? -1 : 1;
      }
      final aUnread = _unreadCounts[_conversationKey(a)] ?? 0;
      final bUnread = _unreadCounts[_conversationKey(b)] ?? 0;
      if (aUnread != bUnread) return bUnread.compareTo(aUnread);
      final aName = (a.name ?? a.id).toLowerCase();
      final bName = (b.name ?? b.id).toLowerCase();
      return aName.compareTo(bName);
    });
    return list;
  }

  Future<void> _togglePinConversation(Conversation conv) async {
    final key = _conversationKey(conv);
    final value = !(_pinnedMap[key] ?? conv.pinned);
    setState(() {
      _pinnedMap[key] = value;
    });
    final userId = context.read<AuthService>().userId;
    if (userId != null && userId.isNotEmpty) {
      await AccountStorage.instance.setBool('pinned:$key', value);
    }
  }

  void _showConversationMenu(
    BuildContext context,
    Conversation conv,
    TapDownDetails details,
  ) {
    final key = _conversationKey(conv);
    final isPinned = _pinnedMap[key] ?? conv.pinned;
    final isRecent = _recentConversations.containsKey(key);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: isPinned ? 'unpin' : 'pin',
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(isPinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
        PopupMenuItem(
          value: isRecent ? 'remove_recent' : 'add_recent',
          child: Row(
            children: [
              Icon(
                isRecent
                    ? Icons.remove_circle_outline
                    : Icons.add_circle_outline,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(isRecent ? '移除最近会话' : '添加到最近会话'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'pin' || value == 'unpin') {
        _togglePinConversation(conv);
      } else if (value == 'remove_recent') {
        _removeRecent(conv);
      } else if (value == 'add_recent') {
        setState(() => _rememberRecent(conv, force: true));
      }
    });
  }

  Future<void> _selectConversation(Conversation conv) async {
    setState(() {
      _currentConversation = conv;
      _unreadCounts.remove(_conversationKey(conv));
      _realtimeUnreadPending.remove(_conversationKey(conv));
      _totalUnread = _unreadCounts.values
          .fold(0, (sum, count) => sum + count)
          .clamp(0, 1 << 30);
    });
    _rememberRecent(conv, incrementOpen: true);
    if (mounted) setState(() {});
    await _loadUnreadCounts();
    if (Platform.isAndroid || Platform.isIOS || kIsWeb) {
      await Navigator.pushNamed(
        context,
        '/chat',
        arguments: {
          'uid': conv.id,
          'type': conv.type,
          'title': conv.name ?? '聊天',
        },
      );
      return;
    }
  }

  void _logout() async {
    await context.read<AuthService>().clear();
    WebSocketService().disconnect();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  int get displayUnread =>
      _totalUnread < 0 ? 0 : _totalUnread.clamp(0, 1 << 30);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(AppLocalizations.current.t('加载失败: $_error')),
                  TextButton(
                    onPressed: _refresh,
                    child: Text(AppLocalizations.current.t('重试')),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 280,
                  child: Column(
                    children: [
                      _buildToolbar(),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.current.t('搜索好友或群聊...'),
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[200],
                          ),
                          onChanged: (q) {
                            _searchTimer?.cancel();
                            _searchTimer = Timer(
                              const Duration(milliseconds: 300),
                              () {
                                setState(() {});
                              },
                            );
                          },
                        ),
                      ),
                      Expanded(child: _buildList()),
                    ],
                  ),
                ),
                Expanded(
                  child: _currentConversation == null
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onSecondaryTap: _refresh,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '选择一个会话开始聊天',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '右键刷新',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ChatPage(
                          key: ValueKey(
                            '${_currentConversation!.type}:${_currentConversation!.id}',
                          ),
                          conversationId: _currentConversation!.id,
                          type: _currentConversation!.type,
                          title: _currentConversation!.name ?? '聊天',
                          embed: true,
                          onMessageSent: () {
                            unawaited(_loadConversations());
                            unawaited(_loadUnreadCounts());
                          },
                          onConversationUnavailable: () {
                            if (!mounted) return;
                            final unavailable = _currentConversation;
                            final group = unavailable?.type == 'group'
                                ? unavailable
                                : null;
                            setState(() {
                              if (group != null) {
                                _groups.removeWhere(
                                  (item) => item.id == group.id,
                                );
                                _recentConversations.remove(
                                  _conversationKey(group),
                                );
                                _recentUsedAt.remove(_conversationKey(group));
                                _hiddenRecentKeys.add(_conversationKey(group));
                                _currentConversation = null;
                              }
                            });
                            if (group != null) {
                              unawaited(_persistHiddenRecentKeys());
                              _scheduleRecentPersist();
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.current.t('群聊已不存在，已从会话列表移除'),
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

  Widget _buildToolbar() {
    final primaryColor = Theme.of(context).primaryColor;
    final avatarUrl = _avatarUrl != null ? resolveMediaUrl(_avatarUrl) : null;
    final displayTotal = displayUnread;

    return RepaintBoundary(
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: primaryColor),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/profile'),
              child: avatarUrl == null
                  ? const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 20, color: Colors.pink),
                    )
                  : SizedBox(
                      width: 32,
                      height: 32,
                      child: ClipOval(
                        child: CachedImage(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Colors.white,
                            child: Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.pink,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (displayTotal > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  displayTotal > 99 ? '99+' : '$displayTotal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
              onPressed: _logout,
              tooltip: context.tr.logout,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            ),
            IconButton(
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh, color: Colors.white, size: 20),
              onPressed: _refresh,
              tooltip: context.tr.refresh,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            ),
            IconButton(
              icon: const Icon(Icons.apps, color: Colors.white, size: 20),
              onPressed: () => Navigator.pushNamed(context, '/tools'),
              tooltip: context.tr.tools,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
              onPressed: () => Navigator.pushNamed(context, '/more'),
              tooltip: context.tr.more,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicButton() {
    return IconButton(
      icon: const Icon(Icons.music_note, color: Colors.white, size: 20),
      onPressed: () => Navigator.pushNamed(context, '/music_plaza'),
      tooltip: AppLocalizations.current.t('音乐广场'),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildEmojiButton() {
    return IconButton(
      icon: const Icon(Icons.emoji_emotions, color: Colors.white, size: 20),
      onPressed: () => Navigator.pushNamed(context, '/emoji_plaza'),
      tooltip: AppLocalizations.current.t('表情'),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildToolbarButton(IconData icon, String route, String tooltip) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: () => Navigator.pushNamed(context, route),
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildList() {
    final query = _searchController.text.trim().toLowerCase();
    final filteredFriends = _sortConversations(
      _friends
          .where(
            (c) =>
                !_recentConversations.containsKey(_conversationKey(c)) &&
                (c.name?.toLowerCase().contains(query) == true ||
                    c.id.toLowerCase().contains(query)),
          )
          .toList(),
    );
    final filteredGroups = _sortConversations(
      _groups
          .where(
            (c) =>
                !_recentConversations.containsKey(_conversationKey(c)) &&
                (c.name?.toLowerCase().contains(query) == true ||
                    c.id.toLowerCase().contains(query)),
          )
          .toList(),
    );
    final recent = _recentList().where((c) {
      return c.name?.toLowerCase().contains(query) == true ||
          c.id.toLowerCase().contains(query);
    }).toList();

    if (filteredFriends.isEmpty && filteredGroups.isEmpty && recent.isEmpty) {
      return Center(child: Text(AppLocalizations.current.t('没有匹配的会话')));
    }

    return ListView(
      children: [
        if (recent.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              AppLocalizations.current.t('最近会话'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),
          ...recent.map(
            (conv) => ConversationTile(
              conversation: conv,
              unreadCount: _unreadCounts[_conversationKey(conv)] ?? 0,
              onTap: () => _selectConversation(conv),
              onSecondaryTapDown: (details) =>
                  _showConversationMenu(context, conv, details),
              isActive:
                  _currentConversation?.id == conv.id &&
                  _currentConversation?.type == conv.type,
              isPinned: _isPinned(conv),
            ),
          ),
        ],
        if (filteredGroups.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '群聊',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),
          ...filteredGroups.map(
            (conv) => ConversationTile(
              conversation: conv,
              unreadCount: _unreadCounts['group:${conv.id}'] ?? 0,
              onTap: () => _selectConversation(conv),
              onSecondaryTapDown: (details) =>
                  _showConversationMenu(context, conv, details),
              isActive:
                  _currentConversation?.id == conv.id &&
                  _currentConversation?.type == 'group',
              isPinned: _isPinned(conv),
            ),
          ),
        ],
        if (filteredFriends.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '私聊',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),
          ...filteredFriends.map(
            (conv) => ConversationTile(
              conversation: conv,
              unreadCount: _unreadCounts['direct:${conv.id}'] ?? 0,
              onTap: () => _selectConversation(conv),
              onSecondaryTapDown: (details) =>
                  _showConversationMenu(context, conv, details),
              isActive:
                  _currentConversation?.id == conv.id &&
                  _currentConversation?.type == 'direct',
              isPinned: _isPinned(conv),
            ),
          ),
        ],
      ],
    );
  }
}
