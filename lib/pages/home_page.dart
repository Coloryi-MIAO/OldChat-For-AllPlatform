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
  Timer? _messageBatchTimer;
  final List<Message> _pendingRealtimeMessages = <Message>[];
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
    unawaited(_initializeHomeState());
  }

  Future<void> _initializeHomeState() async {
    final uid = context.read<AuthService>().userId;
    if (uid != null && uid.isNotEmpty) {
      await AccountStorage.instance.load(userId: uid);
      await CacheService().directory(userId: uid);
    }
    await _restoreHiddenRecentKeys();
    await _restoreCachedConversations();
    await _restoreRecentConversations();
    await _loadPinnedState();
    if (!mounted) return;
    unawaited(_loadConversations());
    unawaited(_loadUnreadCounts());
    _startRealtimePolling();
    _startSystemNotificationPolling();
    _setupWebSocket();
    unawaited(_loadUserAvatar());
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

  bool _isIdentifierLabel(Conversation conversation, String? value) {
    final label = value?.trim();
    return label == null ||
        label.isEmpty ||
        label == conversation.id ||
        label == '${conversation.type}:${conversation.id}';
  }

  bool _hasUsefulLastMessage(Message? message) {
    if (message == null) return false;
    return message.id.trim().isNotEmpty ||
        message.body.trim().isNotEmpty ||
        message.createdAt > 0 ||
        message.msgType != 'text';
  }

  Message? _mergeLastMessage(Message? incoming, Message? previous) {
    if (!_hasUsefulLastMessage(incoming)) return previous;
    if (!_hasUsefulLastMessage(previous)) return incoming;
    final incomingTime = incoming!.createdAt;
    final previousTime = previous!.createdAt;
    if (incomingTime != previousTime) {
      return incomingTime > previousTime ? incoming : previous;
    }
    return incoming.id.compareTo(previous.id) >= 0 ? incoming : previous;
  }

  Conversation _mergeConversationValue(
    Conversation incoming,
    Conversation? previous,
  ) {
    final key = _conversationKey(incoming);
    final keepName =
        _isIdentifierLabel(incoming, incoming.name) &&
        previous != null &&
        !_isIdentifierLabel(previous, previous.name);
    return incoming.copyWith(
      name: keepName ? previous!.name : incoming.name ?? previous?.name,
      avatar: incoming.avatar ?? previous?.avatar,
      lastMessage: _mergeLastMessage(
        incoming.lastMessage,
        previous?.lastMessage,
      ),
      pinned: _pinnedMap[key] ?? previous?.pinned ?? incoming.pinned,
      unreadCount:
          _unreadCounts[key] ?? previous?.unreadCount ?? incoming.unreadCount,
    );
  }

  void _mergeRecentDetails(Iterable<Conversation> conversations) {
    var changed = false;
    for (final conversation in conversations) {
      final key = _conversationKey(conversation);
      final previous = _recentConversations[key];
      if (previous == null) continue;
      final merged = _mergeConversationValue(conversation, previous);
      if (merged.toJson().toString() != previous.toJson().toString()) {
        _recentConversations[key] = merged;
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
    if (force) {
      _hiddenRecentKeys.remove(key);
      unawaited(_persistHiddenRecentKeys());
    }
    final previous = _recentConversations[key];
    _recentConversations[key] = _mergeConversationValue(conversation, previous);
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
    _messageBatchTimer?.cancel();
    _pendingRealtimeMessages.clear();
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
    if (!mounted) return;
    if (!_realtimeMessageIds.add(msg.id)) return;
    if (_realtimeMessageIds.length > 5000) {
      _realtimeMessageIds.remove(_realtimeMessageIds.first);
    }
    final userId = context.read<AuthService>().userId;
    if (msg.fromUid == userId) return;

    final conversationType = msg.groupId == null ? 'direct' : 'group';
    final conversationId = msg.groupId ?? msg.fromUid;
    final isMuted = NotificationService().isConversationMuted(
      conversationType,
      conversationId,
    );
    final isCurrentConversation =
        _currentConversation != null &&
        _currentConversation!.id == conversationId &&
        _currentConversation!.type == conversationType;
    unawaited(
      NotificationService().showMessageNotification(
        fromName: msg.fromUid,
        message: msg.body,
        conversationId: conversationId,
        conversationType: conversationType,
        fromUid: msg.fromUid,
        messageId: msg.id,
        withFlash: !isCurrentConversation && !isMuted,
      ),
    );

    final key = '$conversationType:$conversationId';
    _pendingRealtimeMessages.add(msg);
    _messageBatchTimer ??= Timer(const Duration(milliseconds: 40), () {
      _messageBatchTimer = null;
      if (!mounted || _pendingRealtimeMessages.isEmpty) return;
      final pending = List<Message>.from(_pendingRealtimeMessages);
      _pendingRealtimeMessages.clear();
      setState(() {
        for (final queued in pending) {
          final queuedType = queued.groupId == null ? 'direct' : 'group';
          final queuedId = queued.groupId ?? queued.fromUid;
          final queuedKey = '$queuedType:$queuedId';
          final queuedConversation = _conversationByKey(queuedKey);
          final queuedCurrent =
              _currentConversation != null &&
              _currentConversation!.id == queuedId &&
              _currentConversation!.type == queuedType;
          if (queuedConversation != null) _mergeMessageIntoHome(queued);
          if (queuedConversation != null && !queuedCurrent) {
            _unreadCounts[queuedKey] = (_unreadCounts[queuedKey] ?? 0) + 1;
            _realtimeUnreadPending[queuedKey] = _unreadCounts[queuedKey]!;
          }
          final all = [..._groups, ..._friends];
          final index = all.indexWhere(
            (conversation) =>
                conversation.id == queuedId && conversation.type == queuedType,
          );
          if (index >= 0) {
            final conversation = all[index];
            final updated = conversation.copyWith(
              lastMessage: queued,
              unreadCount: queuedCurrent
                  ? conversation.unreadCount
                  : conversation.unreadCount + 1,
            );
            if (queuedType == 'group') {
              _groups[_groups.indexOf(conversation)] = updated;
            } else {
              _friends[_friends.indexOf(conversation)] = updated;
            }
            _rememberRecent(updated, force: true);
          } else {
            _rememberMessageConversation(queued);
          }
        }
        _totalUnread = _unreadCounts.values
            .fold(0, (sum, count) => sum + count)
            .clamp(0, 1 << 30);
      });
    });

    _unreadReloadTimer?.cancel();
    _unreadReloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        unawaited(
          _loadUnreadCounts(excludeKey: isCurrentConversation ? key : null),
        );
      }
    });
  }

  void _startRealtimePolling() {
    _realtimePollTimer?.cancel();
    _realtimePollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _unreadPollInFlight || WebSocketService().isConnected)
        return;
      unawaited(_loadUnreadCounts());
      if (!_conversationPollInFlight) unawaited(_refreshConversationPreviews());
    });
  }

  void _startSystemNotificationPolling() {
    _systemNotificationTimer?.cancel();
    unawaited(_pollSystemNotifications());
    _systemNotificationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !WebSocketService().isConnected) {
        unawaited(_pollSystemNotifications());
      }
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
          : null;
      final groups = results.length > 1 && results[1] is List
          ? (results[1] as List).whereType<Conversation>().toList()
          : null;
      final current = _currentConversation;
      var changed = false;
      if (friends != null) {
        final next = friends.isEmpty && _friends.isNotEmpty
            ? _friends
            : _mergeConversationUpdates(_friends, friends)
                  .where(
                    (item) => friends.any(
                      (incoming) =>
                          _conversationKey(incoming) == _conversationKey(item),
                    ),
                  )
                  .toList();
        changed = !_sameConversationSnapshot(_friends, next);
        if (changed) _friends = next;
      }
      if (groups != null) {
        final next = groups.isEmpty && _groups.isNotEmpty
            ? _groups
            : _mergeConversationUpdates(_groups, groups)
                  .where(
                    (item) => groups.any(
                      (incoming) =>
                          _conversationKey(incoming) == _conversationKey(item),
                    ),
                  )
                  .toList();
        final groupChanged = !_sameConversationSnapshot(_groups, next);
        changed = changed || groupChanged;
        if (groupChanged) _groups = next;
      }
      _mergeRecentDetails([..._groups, ..._friends]);
      if (current != null) {
        final replacement = [
          ..._groups,
          ..._friends,
        ].where((item) => item.id == current.id && item.type == current.type);
        if (replacement.isNotEmpty && replacement.first != current) {
          _currentConversation = replacement.first;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    } catch (error) {
      debugPrint('[会话预览] 增量刷新失败：$error');
    } finally {
      _conversationPollInFlight = false;
    }
  }

  bool _sameConversationSnapshot(
    List<Conversation> left,
    List<Conversation> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].toJson().toString() != right[index].toJson().toString()) {
        return false;
      }
    }
    return true;
  }

  Future<List<Conversation>?> _safeFriends() async {
    try {
      return await ApiService().getFriends();
    } catch (error) {
      debugPrint('[会话预览] 好友列表暂不可用：$error');
      return null;
    }
  }

  Future<List<Conversation>?> _safeGroups() async {
    try {
      return await ApiService().getGroups();
    } catch (error) {
      debugPrint('[会话预览] 群聊列表暂不可用：$error');
      return null;
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
      final key = _conversationKey(item);
      final old = byKey[key];
      byKey[key] = _mergeConversationValue(item, old);
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
          final mergedFriends = _mergeConversationUpdates(_friends, friends)
              .where(
                (item) => friends.any(
                  (incoming) =>
                      _conversationKey(incoming) == _conversationKey(item),
                ),
              )
              .where((item) => item.id.trim().isNotEmpty)
              .toList();
          final mergedGroups = _mergeConversationUpdates(_groups, groups)
              .where(
                (item) => groups.any(
                  (incoming) =>
                      _conversationKey(incoming) == _conversationKey(item),
                ),
              )
              .where((item) => item.id.trim().isNotEmpty)
              .toList();
          _friends = friends.isEmpty && _friends.isNotEmpty
              ? _friends
              : mergedFriends;
          _groups = groups.isEmpty && _groups.isNotEmpty
              ? _groups
              : mergedGroups;
          final validKeys = {
            ..._friends,
            ..._groups,
          }.map(_conversationKey).toSet();
          _recentConversations.removeWhere(
            (key, _) => !validKeys.contains(key),
          );
          _recentUsedAt.removeWhere((key, _) => !validKeys.contains(key));
          _mergeRecentDetails([..._groups, ..._friends]);
          _error = null;
          _loading = false;
          if (_currentConversation != null) {
            final all = [..._groups, ..._friends];
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
          unawaited(
            CacheService().writeJson(
              CacheService().scoped(userId, 'conversations'),
              [..._groups, ..._friends].map((c) => c.toJson()).toList(),
            ),
          );
          _scheduleRecentPersist();
          unawaited(_loadPinnedState());
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

  void _notifyIncomingMessage(Message message, String type, String id) {
    if (message.fromUid == context.read<AuthService>().userId ||
        id.trim().isEmpty)
      return;
    unawaited(
      NotificationService().showMessageNotification(
        fromName: message.fromUid,
        message: message.body,
        conversationId: id,
        conversationType: type,
        fromUid: message.fromUid,
        messageId: message.id,
        withFlash: true,
      ),
    );
  }

  Future<void> _loadUnreadCounts({String? excludeKey}) async {
    if (_unreadPollInFlight) return;
    _unreadPollInFlight = true;
    try {
      final api = ApiService();
      final unreadResults = await Future.wait<Map<String, dynamic>>([
        api.getDirectUnread(),
        api.getGroupUnread(),
      ]);
      final directUnread = unreadResults[0];
      final groupUnread = unreadResults[1];
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
          _notifyIncomingMessage(
            message,
            'direct',
            (json['from_uid'] ?? message.fromUid).toString(),
          );
          if (!seenUnreadIds.add(messageKey)) return;
          if (_conversationByKey(
                'direct:${json['from_uid'] ?? message.fromUid}',
              ) !=
              null) {
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
          _notifyIncomingMessage(
            message,
            'group',
            (json['group_id'] ?? message.groupId ?? '').toString(),
          );
          if (!seenUnreadIds.add(messageKey)) return;
          if (_conversationByKey(
                'group:${json['group_id'] ?? message.groupId ?? ''}',
              ) !=
              null) {
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
      counts.removeWhere(
        (key, value) => !validKeys.contains(key) || value <= 0,
      );
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
    } catch (error) {
      debugPrint('[未读] 暂时无法刷新，保留当前计数：$error');
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
      final list = conv.type == 'group' ? _groups : _friends;
      final index = list.indexWhere((item) => _conversationKey(item) == key);
      if (index >= 0) list[index] = list[index].copyWith(pinned: value);
      if (_recentConversations.containsKey(key)) {
        _recentConversations[key] = _recentConversations[key]!.copyWith(
          pinned: value,
        );
      }
    });
    await AccountStorage.instance.setBool('pinned:$key', value);
    _scheduleRecentPersist();
    final userId = context.read<AuthService>().userId;
    if (userId != null && userId.isNotEmpty) {
      await CacheService().writeJson(
        CacheService().scoped(userId, 'conversations'),
        [..._groups, ..._friends].map((item) => item.toJson()).toList(),
      );
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
        PopupMenuItem(
          value: NotificationService().isConversationMuted(conv.type, conv.id)
              ? 'unmute'
              : 'mute',
          child: Row(
            children: [
              Icon(
                NotificationService().isConversationMuted(conv.type, conv.id)
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                NotificationService().isConversationMuted(conv.type, conv.id)
                    ? '取消免打扰'
                    : '免打扰',
              ),
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
      } else if (value == 'mute' || value == 'unmute') {
        unawaited(
          NotificationService().setConversationMuted(
            type: conv.type,
            conversationId: conv.id,
            muted: value == 'mute',
          ),
        );
        if (mounted) setState(() {});
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
    if (!mounted) return;
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      if (!mounted) return;
      setState(() => _currentConversation = null);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conv.id,
            type: conv.type,
            title: conv.name ?? context.tr.chat,
            embed: false,
            onMessageSent: () {
              unawaited(_loadConversations());
              unawaited(_loadUnreadCounts());
            },
          ),
        ),
      );
      if (mounted) {
        unawaited(_loadConversations());
        unawaited(_loadUnreadCounts());
      }
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

  int get displayUnread {
    final total = _unreadCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return total < 0 ? 0 : total.clamp(0, 1 << 30);
  }

  @override
  Widget build(BuildContext context) {
    final compactNavigation = kIsWeb || Platform.isAndroid || Platform.isIOS;
    if (compactNavigation) return _buildCompactShell(context);
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

  Widget _buildCompactShell(BuildContext context) {
    final destinations = <(String, IconData, String)>[
      (context.tr.text('主页', 'Home'), Icons.home_outlined, '/'),
      (context.tr.text('功能', 'Tools'), Icons.apps_outlined, '/tools'),
      (context.tr.text('更多', 'More'), Icons.more_horiz, '/more'),
      (context.tr.text('个人', 'Profile'), Icons.person_outline, '/profile'),
    ];
    final current = _currentConversation;
    return Scaffold(
      appBar: AppBar(
        title: Text(current?.name ?? context.tr.text('主页', 'Home')),
        actions: [
          IconButton(
            tooltip: context.tr.refresh,
            onPressed: _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: context.tr.logout,
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : current == null
          ? _buildCompactHomeBody()
          : ChatPage(
              key: ValueKey('${current.type}:${current.id}'),
              conversationId: current.id,
              type: current.type,
              title: current.name ?? context.tr.chat,
              embed: false,
              onMessageSent: () {
                unawaited(_loadConversations());
                unawaited(_loadUnreadCounts());
              },
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) async {
          if (index == 0) {
            if (mounted) setState(() => _currentConversation = null);
            return;
          }
          await Navigator.pushNamed(context, destinations[index].$3);
          if (mounted) setState(() {});
        },
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.$2),
              selectedIcon: Icon(destination.$2),
              label: destination.$1,
            ),
        ],
      ),
    );
  }

  Widget _buildCompactHomeBody() {
    final query = _searchController.text.trim().toLowerCase();
    final conversations =
        <Conversation>[..._recentList(), ..._groups, ..._friends]
            .where(
              (conversation) =>
                  conversation.name?.toLowerCase().contains(query) == true ||
                  conversation.id.toLowerCase().contains(query),
            )
            .fold<Map<String, Conversation>>({}, (map, conversation) {
              map[_conversationKey(conversation)] = conversation;
              return map;
            })
            .values
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr.text(
                '搜索好友或群聊...',
                'Search friends or groups...',
              ),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: conversations.isEmpty
              ? Center(
                  child: Text(context.tr.text('暂无会话', 'No conversations yet')),
                )
              : ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    return ConversationTile(
                      conversation: conversation,
                      unreadCount:
                          _unreadCounts[_conversationKey(conversation)] ?? 0,
                      isActive: false,
                      isPinned: _isPinned(conversation),
                      onTap: () => _selectConversation(conversation),
                      onSecondaryTapDown: (details) =>
                          _showConversationMenu(context, conversation, details),
                    );
                  },
                ),
        ),
      ],
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
              key: ValueKey('conversation:${_conversationKey(conv)}'),
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
              key: ValueKey('conversation:${_conversationKey(conv)}'),
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
              key: ValueKey('conversation:${_conversationKey(conv)}'),
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
