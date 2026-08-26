import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../services/clipboard_media_service.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/file_picker_compat.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cache_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/plugin_service.dart';
import '../services/notification_service.dart';
import '../services/image_cache_service.dart';
import '../services/local_emoji_service.dart';
import '../widgets/cached_image.dart';

import '../models/message.dart';
import '../models/conversation.dart';
import '../utils/message_parser.dart';
import '../widgets/message_tile.dart';
import '../pages/user_profile_page.dart';
import '../utils/url_helper.dart';
import '../utils/navigation.dart';
import '../services/app_localizations.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String type;
  final String title;
  final bool embed;
  final VoidCallback? onMessageSent;
  final VoidCallback? onConversationUnavailable;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.type,
    required this.title,
    this.embed = false,
    this.onMessageSent,
    this.onConversationUnavailable,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with RouteAware, WidgetsBindingObserver {
  final List<Message> _messages = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  String? _nextBeforeCreatedAt;
  String? _nextBeforeId;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _composerScrollController = ScrollController();
  Timer? _pollTimer;
  int? _pollGeneration;
  Message? _quotedMessage;
  final Map<String, GlobalKey> _messageKeys = {};
  bool _isFriend = false;
  bool _isCheckingFriend = true;
  Set<String> _claimedPackets = {};
  int? _firstUnreadIndex;
  bool _showUnreadButton = false;
  bool _isUserAtBottom = true;
  bool _cacheHydrated = false;
  bool _isVisible = true;
  bool _routeSubscribed = false;
  PageRoute<dynamic>? _observedRoute;
  int? _lastMessageCreatedAt;
  String? _lastMessageId;
  int _lastGroupSeq = 0;
  final Map<String, Message> _messageMap = {};
  final List<Map<String, String>> _pendingMentions = [];
  final Set<String> _selectedMessageIds = <String>{};
  bool _selectionMode = false;

  void _toggleMessageSelection(Message message) {
    setState(() {
      _selectionMode = true;
      if (!_selectedMessageIds.add(message.id)) {
        _selectedMessageIds.remove(message.id);
      }
      if (_selectedMessageIds.isEmpty) _selectionMode = false;
    });
  }

  void _clearMessageSelection() {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  Widget _buildSelectionBar() {
    if (!_selectionMode) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: _clearMessageSelection,
              icon: const Icon(Icons.close),
              tooltip: context.tr.text('取消选择', 'Cancel selection'),
            ),
            Expanded(
              child: Text(
                context.tr.text(
                  '已选择 ${_selectedMessageIds.length} 条消息',
                  '${_selectedMessageIds.length} messages selected',
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _forwardSelectedMessages,
              icon: const Icon(Icons.forward, size: 18),
              label: Text(context.tr.text('转发', 'Forward')),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _forwardSelectedMessages() async {
    final ids = _selectedMessageIds.toList(growable: false);
    if (ids.isEmpty) return;
    List<Conversation> targets;
    try {
      final result = await Future.wait<dynamic>([
        ApiService().getFriends(),
        ApiService().getGroups(),
      ]);
      targets = [
        ...(result[0] as List<Conversation>),
        ...(result[1] as List<Conversation>),
      ];
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.text('加载转发对象失败：$error', 'Failed to load forwarding targets: $error'))),
        );
      }
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Conversation>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: targets
              .map(
                (item) => ListTile(
                  leading: Icon(item.type == 'group' ? Icons.groups : Icons.person),
                  title: Text(item.name ?? item.id),
                  subtitle: Text(item.id),
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (target == null || !mounted) return;
    try {
      await ApiService().forwardMessages(
        conversationType: target.type,
        conversationId: target.id,
        messageIds: ids,
        items: ids
            .map((id) => _messageMap[id])
            .whereType<Message>()
            .map((message) {
              final profileName = message.fromUid == context.read<AuthService>().userId
                  ? 'Me'
                  : message.fromUid;
              final parsed = MessageParser.parseMessageBody(message.body, message.msgType);
              return <String, dynamic>{
                'source_message_id': message.id,
                'from_uid': message.fromUid,
                'from_name': profileName,
                'from_avatar': '',
                'type': message.msgType,
                'media_kind': parsed['media_kind'] ?? message.msgType,
                'text': parsed['text'] ?? message.displayText,
                'thumb_url': message.thumbUrl,
              };
            })
            .toList(growable: false),
      );
      _clearMessageSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.text('转发成功', 'Forwarded successfully'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.text('转发失败：$error', 'Forward failed: $error'))),
        );
      }
    }
  }

  final List<Map<String, String>> _mentionMembers = [];
  final Map<String, String> _groupRoleByUid = <String, String>{};
  Timer? _mentionFilterTimer;
  int? _mentionStart;
  int _mentionActiveIndex = 0;
  bool _mentionPopupVisible = false;
  bool _mentionLoading = false;
  int _bottomScrollRequest = 0;
  bool _realtimeSyncInFlight = false;
  bool _initialLoadFinished = false;
  bool _markReadInFlight = false;
  bool _markReadPending = false;
  int _pendingBurnAfterSeconds = 0;
  bool _conversationMuted = false;
  Timer? _cacheSaveTimer;
  bool _cacheSaveInFlight = false;
  bool _cacheSavePending = false;
  Timer? _readReceiptTimer;
  bool _readReceiptInFlight = false;
  bool _readReceiptPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFriendStatus();
    final ws = WebSocketService();
    ws.addDirectListener(_onNewMessage);
    ws.addGroupListener(_onNewMessage);
    ws.addRecallListener(_onMessageRecalled);
    ws.connect();
    _scrollController.addListener(_onScroll);
    if (widget.type == 'group') unawaited(_loadMentionMembers());
    _conversationMuted = NotificationService().isConversationMuted(
      widget.type,
      widget.conversationId,
    );
    unawaited(_loadMessages(initial: true));
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      _observedRoute = route;
      routeObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  void _setVisible(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (visible) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  void didPushNext() => _setVisible(false);

  @override
  void didPopNext() => _setVisible(true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setVisible(state == AppLifecycleState.resumed);
  }

  void _refreshUnreadButtonState() {
    if (!_scrollController.hasClients) return;
    final isAtBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50;
    final shouldShowUnread =
        !isAtBottom &&
        _firstUnreadIndex != null &&
        _firstUnreadIndex! >= 0 &&
        _firstUnreadIndex! < _messages.length;
    if (_isUserAtBottom != isAtBottom ||
        _showUnreadButton != shouldShowUnread) {
      setState(() {
        _isUserAtBottom = isAtBottom;
        _showUnreadButton = shouldShowUnread;
      });
    }
  }

  void _onScroll() {
    _refreshUnreadButtonState();
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels > 160 ||
        _loading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    _isLoadingMore = true;
    unawaited(
      _loadMessages(initial: false).whenComplete(() {
        if (mounted) _isLoadingMore = false;
      }),
    );
  }

  @override
  void dispose() {
    _mentionFilterTimer?.cancel();
    _cacheSaveTimer?.cancel();
    _readReceiptTimer?.cancel();
    unawaited(_flushCachedMessages());
    if (_routeSubscribed && _observedRoute != null) {
      routeObserver.unsubscribe(this);
    }
    WebSocketService().removeDirectListener(_onNewMessage);
    WebSocketService().removeGroupListener(_onNewMessage);
    WebSocketService().removeRecallListener(_onMessageRecalled);
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    _composerScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFriendStatus() async {
    if (widget.type != 'direct') {
      setState(() => _isCheckingFriend = false);
      return;
    }
    try {
      final api = ApiService();
      final friends = await api.getFriends();
      setState(() {
        _isFriend = friends.any((f) => f.id == widget.conversationId);
        _isCheckingFriend = false;
      });
    } catch (_) {
      setState(() => _isCheckingFriend = false);
    }
  }

  int _compareMessages(Message a, Message b) {
    if (widget.type == 'group' &&
        a.groupSeq != null &&
        b.groupSeq != null &&
        a.groupSeq != b.groupSeq) {
      return a.groupSeq!.compareTo(b.groupSeq!);
    }
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  }

  void _updatePollCursor(Message msg, {bool fromWebSocket = false}) {
    if (widget.type == 'group') {
      if (msg.groupSeq != null) {
        _lastGroupSeq = _lastGroupSeq < msg.groupSeq!
            ? msg.groupSeq!
            : _lastGroupSeq;
      }
      return;
    }
    if (_lastMessageCreatedAt == null ||
        msg.createdAt > _lastMessageCreatedAt! ||
        (msg.createdAt == _lastMessageCreatedAt! &&
            (msg.id.compareTo(_lastMessageId ?? '') > 0))) {
      _lastMessageCreatedAt = msg.createdAt;
      _lastMessageId = msg.id;
    }
  }

  void _rebuildMessageMap() {
    _messageMap
      ..clear()
      ..addEntries(_messages.map((message) => MapEntry(message.id, message)));
  }

  void _addLocalMessage(Message message) {
    if (message.id.isEmpty || _messageMap.containsKey(message.id)) return;
    _messageMap[message.id] = message;
    _updatePollCursor(message);
    final insertAt = _messages.indexWhere(
      (existing) => _compareMessages(existing, message) > 0,
    );
    if (insertAt < 0) {
      _messages.add(message);
    } else {
      _messages.insert(insertAt, message);
    }
    _messageKeys[message.id] = GlobalKey();
  }

  void _onNewMessage(Message msg) {
    if (!mounted || !_isVisible) return;
    if (widget.type == 'direct' &&
        msg.fromUid != widget.conversationId &&
        msg.threadId != widget.conversationId &&
        msg.toUid != widget.conversationId)
      return;
    if (widget.type == 'group' && msg.groupId != widget.conversationId) return;
    if (_messageMap.containsKey(msg.id)) return;
    if (msg.fromUid != context.read<AuthService>().userId) {
      unawaited(
        PluginService().dispatchMessage(
          msg,
          conversationId: msg.groupId ?? msg.fromUid,
        ),
      );
    }
    if (widget.type == 'direct' &&
        msg.fromUid == context.read<AuthService>().userId &&
        msg.threadId != widget.conversationId)
      return;
    final wasAtBottom =
        !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <=
            80;
    _isUserAtBottom = wasAtBottom;
    _messageMap[msg.id] = msg;
    _updatePollCursor(msg, fromWebSocket: true);
    final insertAt = _messages.indexWhere(
      (existing) => _compareMessages(existing, msg) > 0,
    );
    setState(() {
      if (insertAt < 0) {
        _messages.add(msg);
      } else {
        _messages.insert(insertAt, msg);
      }
      _messageKeys[msg.id] = GlobalKey();
    });
    unawaited(_saveCachedMessages());
    unawaited(_markConversationRead());
    if (wasAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isVisible) unawaited(_scheduleScrollToBottom());
      });
    }
  }

  void _onMessageRecalled(String messageId, String displayName) {
    if (!mounted) return;
    final old = _messageMap[messageId];
    if (old == null) return;
    final recalled = Message(
      id: old.id,
      fromUid: old.fromUid,
      fromNcuid: old.fromNcuid,
      body: jsonEncode({'v': 2, 'text': '$displayName撤回了一条消息', 'recall': true}),
      msgType: 'text',
      createdAt: old.createdAt,
      groupId: old.groupId,
      groupSeq: old.groupSeq,
      threadId: old.threadId,
    );
    setState(() {
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index >= 0) _messages[index] = recalled;
      _messageMap[messageId] = recalled;
    });
    unawaited(_saveCachedMessages());
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_isVisible) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted ||
          !_isVisible ||
          _isLoadingMore ||
          _loading ||
          _realtimeSyncInFlight)
        return;
      if (!WebSocketService().isConnected) {
        unawaited(WebSocketService().connect());
        return;
      }
      unawaited(_syncIncrementalMessages());
    });
  }

  Future<void> _syncIncrementalMessages() async {
    if (_realtimeSyncInFlight || !_isVisible || !mounted) return;
    if (!_initialLoadFinished && _messages.isEmpty) return;
    _realtimeSyncInFlight = true;
    try {
      final api = ApiService();
      final result = widget.type == 'group'
          ? await api.getGroupMessagesAfter(
              widget.conversationId,
              _lastGroupSeq,
            )
          : await api.getDirectMessages(
              withUid: widget.conversationId,
              limit: 100,
              afterCreatedAt: _lastMessageCreatedAt,
              afterId: _lastMessageId,
            );
      if (!mounted || !_isVisible) return;
      final newMessages =
          (result['messages'] as List?)?.whereType<Message>().toList() ??
          const <Message>[];
      final relevantMessages = newMessages.where((message) {
        if (widget.type == 'group')
          return message.groupId == widget.conversationId;
        return message.fromUid == widget.conversationId ||
            message.threadId == widget.conversationId ||
            message.fromUid == context.read<AuthService>().userId;
      }).toList();
      if (widget.type == 'group') {
        final serverSeq =
            int.tryParse('${result['server_group_seq'] ?? _lastGroupSeq}') ??
            _lastGroupSeq;
        if (serverSeq < _lastGroupSeq) {
          _lastGroupSeq = 0;
        } else {
          final nextSeq =
              int.tryParse('${result['next_group_seq'] ?? _lastGroupSeq}') ??
              _lastGroupSeq;
          if (nextSeq > _lastGroupSeq) _lastGroupSeq = nextSeq;
        }
      }
      final wasAtBottom = _isUserAtBottom;
      _insertRealtimeMessages(relevantMessages);
      if (relevantMessages.isNotEmpty) {
        unawaited(_markConversationRead());
      }
      if (relevantMessages.isNotEmpty && wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isVisible)
            unawaited(_scheduleScrollToBottom(animate: false));
        });
      }
    } catch (error) {
      debugPrint('[实时同步慢] $error');
    } finally {
      _realtimeSyncInFlight = false;
    }
  }

  void _insertRealtimeMessages(List<Message> messages) {
    final newOnes = <Message>[];
    for (final message in messages) {
      if (_messageMap.containsKey(message.id)) continue;
      if (message.fromUid != context.read<AuthService>().userId) {
        unawaited(
          PluginService().dispatchMessage(
            message,
            conversationId: message.groupId ?? message.fromUid,
          ),
        );
      }
      _messageMap[message.id] = message;
      _updatePollCursor(message);
      newOnes.add(message);
    }
    if (newOnes.isEmpty) return;
    setState(() {
      for (final message in newOnes) {
        final insertAt = _messages.indexWhere(
          (existing) => _compareMessages(existing, message) > 0,
        );
        if (insertAt < 0) {
          _messages.add(message);
        } else {
          _messages.insert(insertAt, message);
        }
        _messageKeys[message.id] = GlobalKey();
      }
    });
    unawaited(_saveCachedMessages());
    unawaited(_markConversationRead());
  }

  Future<void> _loadMessages({bool initial = false}) async {
    if (!_isVisible || _loading || (!_hasMore && !initial)) return;
    if (initial && !_cacheHydrated) await _restoreCachedMessages();
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final api = ApiService();
      final result = widget.type == 'direct'
          ? await api.getDirectMessages(
              withUid: widget.conversationId,
              limit: initial ? 15 : 30,
              offset: _offset,
              beforeCreatedAt:
                  !initial &&
                      _nextBeforeCreatedAt != null &&
                      _nextBeforeCreatedAt!.isNotEmpty
                  ? _nextBeforeCreatedAt
                  : null,
              beforeId:
                  !initial && _nextBeforeId != null && _nextBeforeId!.isNotEmpty
                  ? _nextBeforeId
                  : null,
            )
          : await api.getGroupMessages(
              groupId: widget.conversationId,
              limit: initial ? 15 : 30,
              offset: _offset,
              beforeCreatedAt:
                  !initial &&
                      _nextBeforeCreatedAt != null &&
                      _nextBeforeCreatedAt!.isNotEmpty
                  ? _nextBeforeCreatedAt
                  : null,
              beforeId:
                  !initial && _nextBeforeId != null && _nextBeforeId!.isNotEmpty
                  ? _nextBeforeId
                  : null,
            );
      final rawMessages = result['messages'];
      final newMessages = rawMessages is List
          ? rawMessages.whereType<Message>().toList()
          : <Message>[];

      if (initial) {
        setState(() {
          final byId = <String, Message>{
            for (final message in newMessages) message.id: message,
          };
          final sorted = byId.values.toList()..sort(_compareMessages);
          _messages
            ..clear()
            ..addAll(sorted);
          _messageMap.clear();
          _messageKeys.clear();
          for (var m in sorted) {
            _messageMap[m.id] = m;
            _updatePollCursor(m);
            _messageKeys[m.id] = GlobalKey();
          }
          _firstUnreadIndex = _messages.indexWhere(
            (m) =>
                m.fromUid != context.read<AuthService>().userId &&
                (m.readAt == null || m.readAt == 0),
          );
          if (_firstUnreadIndex == -1) {
            _firstUnreadIndex = null;
          }
          _hasMore = result['has_more'] == true;
          _nextBeforeCreatedAt = result['next_before_created_at']?.toString();
          _nextBeforeId = result['next_before_id']?.toString();
          _offset = result['effective_offset'] ?? _offset + newMessages.length;
          _loading = false;
          _initialLoadFinished = true;
        });
        await _saveCachedMessages();
        if (_messages.any(
          (m) =>
              m.fromUid != context.read<AuthService>().userId &&
              (m.readAt == null || m.readAt == 0),
        )) {
          unawaited(_markConversationRead());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleScrollToBottom();
        });
      } else {
        final oldFirstId = _messages.isEmpty ? null : _messages.first.id;
        final oldFirstKey = oldFirstId == null
            ? null
            : _messageKeys[oldFirstId];
        final oldFirstDy = oldFirstKey?.currentContext == null
            ? null
            : (oldFirstKey!.currentContext!.findRenderObject() as RenderBox)
                  .localToGlobal(Offset.zero)
                  .dy;

        final olderMessages = newMessages.toList()..sort(_compareMessages);
        final toAdd = olderMessages
            .where((m) => !_messageMap.containsKey(m.id))
            .toList();
        final combined = [...toAdd, ..._messages]..sort(_compareMessages);

        setState(() {
          _messages.clear();
          _messageMap.clear();
          _messages.addAll(combined);
          for (var m in combined) {
            _messageMap[m.id] = m;
            _updatePollCursor(m);
          }
          for (var m in toAdd) {
            if (!_messageKeys.containsKey(m.id)) {
              _messageKeys[m.id] = GlobalKey();
            }
          }
          _hasMore = result['has_more'] == true;
          _nextBeforeCreatedAt = result['next_before_created_at']?.toString();
          _nextBeforeId = result['next_before_id']?.toString();
          _offset = result['effective_offset'] ?? _offset + newMessages.length;
          _loading = false;
          _isLoadingMore = false;
        });
        await _saveCachedMessages();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newFirstKey = oldFirstId == null
                ? null
                : _messageKeys[oldFirstId];
            final newFirstDy = newFirstKey?.currentContext == null
                ? null
                : (newFirstKey!.currentContext!.findRenderObject() as RenderBox)
                      .localToGlobal(Offset.zero)
                      .dy;
            if (oldFirstDy != null && newFirstDy != null) {
              final target =
                  (_scrollController.offset + oldFirstDy - newFirstDy).clamp(
                    0.0,
                    _scrollController.position.maxScrollExtent,
                  );
              _scrollController.jumpTo(target);
            }
          }
        });
      }
    } catch (e) {
      if (widget.type == 'group' && e.toString().contains('(404)')) {
        if (mounted) {
          setState(() {
            _loading = false;
            _isLoadingMore = false;
          });
        }
        widget.onConversationUnavailable?.call();
        return;
      }
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('加载消息失败: $e'))),
      );
    }
  }

  Future<void> _scheduleScrollToBottom({bool animate = false}) async {
    if (!mounted) return;
    final request = ++_bottomScrollRequest;
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 30),
      Duration(milliseconds: 100),
      Duration(milliseconds: 220),
      Duration(milliseconds: 450),
    ];
    for (final delay in delays) {
      if (delay > Duration.zero) await Future.delayed(delay);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || request != _bottomScrollRequest) return;
      if (!_scrollController.hasClients ||
          !_scrollController.position.hasContentDimensions)
        continue;
      final target = _scrollController.position.maxScrollExtent;
      if (animate && (target - _scrollController.position.pixels).abs() > 1) {
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      } else if ((target - _scrollController.position.pixels).abs() > 1) {
        _scrollController.jumpTo(target);
      }
    }
    if (mounted && request == _bottomScrollRequest) {
      _isUserAtBottom = true;
      _refreshUnreadButtonState();
    }
  }

  String get _cacheKey => CacheService().scoped(
    context.read<AuthService>().userId ?? 'guest',
    'messages:${widget.type}:${widget.conversationId}',
  );

  Future<void> _restoreCachedMessages() async {
    _cacheHydrated = true;
    final cached = await CacheService().readJson(_cacheKey);
    if (cached is! List || cached.isEmpty || !mounted) return;
    final restored =
        cached
            .whereType<Map>()
            .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final visible = restored.length > 15
        ? restored.sublist(restored.length - 15)
        : restored;
    setState(() {
      _messages
        ..clear()
        ..addAll(visible);
      _rebuildMessageMap();
      for (final message in visible) {
        _updatePollCursor(message);
      }
      _messageKeys
        ..clear()
        ..addEntries(visible.map((m) => MapEntry(m.id, GlobalKey())));
    });
  }

  Future<void> _saveCachedMessages() async {
    _cacheSavePending = true;
    _cacheSaveTimer?.cancel();
    _cacheSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_flushCachedMessages());
    });
  }

  Future<void> _flushCachedMessages() async {
    if (_cacheSaveInFlight || !_cacheSavePending || !mounted) return;
    _cacheSaveInFlight = true;
    _cacheSavePending = false;
    try {
      await CacheService().writeJson(
        _cacheKey,
        _messages.map((m) => m.toJson()).toList(),
      );
    } finally {
      _cacheSaveInFlight = false;
      if (_cacheSavePending && mounted) unawaited(_flushCachedMessages());
    }
  }

  Future<void> _markConversationRead() async {
    if (_markReadInFlight) {
      _markReadPending = true;
      return;
    }
    _markReadInFlight = true;
    try {
      if (!mounted) return;
      var changed = false;
      setState(() {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];
          if (message.fromUid == context.read<AuthService>().userId ||
              (message.readAt ?? 0) > 0)
            continue;
          changed = true;
          _messages[i] = Message(
            id: message.id,
            fromUid: message.fromUid,
            fromNcuid: message.fromNcuid,
            toUid: message.toUid,
            threadId: message.threadId,
            groupId: message.groupId,
            groupSeq: message.groupSeq,
            body: message.body,
            msgType: message.msgType,
            mediaUrl: message.mediaUrl,
            thumbUrl: message.thumbUrl,
            durationMs: message.durationMs,
            createdAt: message.createdAt,
            deliveredAt: message.deliveredAt,
            readAt: now,
            readCount: message.readCount,
            burnAfterSeconds: message.burnAfterSeconds,
          );
        }
        _firstUnreadIndex = null;
        _showUnreadButton = false;
        _rebuildMessageMap();
      });
      if (changed) await _saveCachedMessages();
      _queueReadReceipt();
    } finally {
      _markReadInFlight = false;
      if (_markReadPending && mounted && _isVisible) {
        _markReadPending = false;
        unawaited(_markConversationRead());
      }
    }
  }

  void _queueReadReceipt() {
    if (!mounted || !_isVisible) return;
    _readReceiptPending = true;
    _readReceiptTimer?.cancel();
    _readReceiptTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(_flushReadReceipt());
    });
  }

  Future<void> _flushReadReceipt() async {
    if (_readReceiptInFlight || !_readReceiptPending || !mounted) return;
    _readReceiptInFlight = true;
    _readReceiptPending = false;
    try {
      if (widget.type == 'direct') {
        await ApiService().markDirectRead(widget.conversationId);
      } else if (widget.type == 'group') {
        await ApiService().markGroupRead(widget.conversationId);
      }
    } catch (error) {
      debugPrint('[read receipt] $error');
      _readReceiptPending = true;
    } finally {
      _readReceiptInFlight = false;
      if (_readReceiptPending && mounted && _isVisible) {
        _readReceiptTimer?.cancel();
        _readReceiptTimer = Timer(const Duration(seconds: 2), () {
          unawaited(_flushReadReceipt());
        });
      }
    }
  }

  Future<void> _refreshConversation() async {
    _offset = 0;
    _nextBeforeCreatedAt = null;
    _nextBeforeId = null;
    _hasMore = true;
    _messages.clear();
    _messageMap.clear();
    _messageKeys.clear();
    await _loadMessages(initial: true);
    await _scheduleScrollToBottom();
  }

  void _scrollToBottom() {
    unawaited(_forceScrollToBottom());
  }

  Future<void> _forceScrollToBottom() async {
    for (var i = 0; i < 100 && mounted && _loading; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;
    await _scheduleScrollToBottom(animate: false);
  }

  Future<void> _scrollToMessage(
    String messageId, {
    int retry = 0,
    bool searchOlder = true,
  }) async {
    final normalizedId = messageId.trim();
    if (normalizedId.isEmpty) return;
    final index = _messages.indexWhere((m) => _sameMessageId(m.id, messageId));
    if (index != -1) {
      final targetMessage = _messages[index];
      final key = _messageKeys[targetMessage.id];
      if (key?.currentContext != null) {
        await Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.25,
        );
        return;
      }
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        final ratio = _messages.length <= 1
            ? 0.0
            : index / (_messages.length - 1);
        final targetOffset = position.maxScrollExtent * ratio;
        await position.animateTo(
          targetOffset.clamp(0.0, position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
        if (retry < 8) {
          await WidgetsBinding.instance.endOfFrame;
          return _scrollToMessage(
            normalizedId,
            retry: retry + 1,
            searchOlder: false,
          );
        }
      }
      return;
    }

    if (searchOlder && _hasMore && !_loading) {
      final previousCount = _messages.length;
      await _loadMessages(initial: false);
      if (!mounted) return;
      if (_messages.length > previousCount) {
        await Future.delayed(const Duration(milliseconds: 100));
        await _scrollToMessage(messageId, retry: retry, searchOlder: _hasMore);
      }
    }
  }

  bool _sameMessageId(String left, String right) {
    return left.trim() == right.trim() ||
        left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  Future<void> _showSearchMessages() async {
    final searchController = TextEditingController();
    List<Message> results = [];
    String? errorMessage;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(AppLocalizations.current.t('搜索聊天记录')),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.current.t('关键词'),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) async {
                        if (loading) return;
                        final query = searchController.text.trim();
                        if (query.isEmpty) return;
                        setState(() {
                          loading = true;
                          errorMessage = null;
                        });
                        try {
                          final api = ApiService();
                          final response = widget.type == 'direct'
                              ? await api.searchDirectMessages(
                                  widget.conversationId,
                                  query,
                                )
                              : await api.searchGroupMessages(
                                  widget.conversationId,
                                  query,
                                );
                          results = _parseSearchMessages(response);
                        } catch (e) {
                          errorMessage = '搜索失败: $e';
                        } finally {
                          if (mounted) setState(() => loading = false);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (loading) const CircularProgressIndicator(),
                    if (errorMessage != null)
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    if (!loading && results.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(AppLocalizations.current.t('输入关键词后搜索聊天记录')),
                      ),
                    if (results.isNotEmpty)
                      SizedBox(
                        height: 280,
                        child: ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final result = results[index];
                            return ListTile(
                              title: Text(
                                _getMessageDisplayText(result),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_formatDateTime(result.createdAt)),
                              onTap: () {
                                Navigator.of(context).pop();
                                if (!_messages.any(
                                  (message) => message.id == result.id,
                                )) {
                                  setState(() {
                                    _addLocalMessage(result);
                                    _messages.sort(_compareMessages);
                                  });
                                }
                                _scrollToMessage(result.id);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.current.t('关闭')),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final query = searchController.text.trim();
                          if (query.isEmpty) return;
                          setState(() {
                            loading = true;
                            errorMessage = null;
                          });
                          try {
                            final api = ApiService();
                            final response = widget.type == 'direct'
                                ? await api.searchDirectMessages(
                                    widget.conversationId,
                                    query,
                                  )
                                : await api.searchGroupMessages(
                                    widget.conversationId,
                                    query,
                                  );
                            final raw =
                                response['messages'] ??
                                response['results'] ??
                                response['items'] ??
                                response['records'] ??
                                response['data'];
                            final list = raw is List ? raw : const <dynamic>[];
                            results = list
                                .whereType<Map>()
                                .map(
                                  (item) => Message.fromJson(
                                    Map<String, dynamic>.from(item),
                                  ),
                                )
                                .toList();
                          } catch (e) {
                            errorMessage = '搜索失败: $e';
                          } finally {
                            if (mounted) setState(() => loading = false);
                          }
                        },
                  child: Text(AppLocalizations.current.t('搜索')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAnnouncement() async {
    try {
      final data = await ApiService().getGroupAnnouncement(widget.conversationId);
      final value = (data['announcement'] ?? data['content'] ?? data['text'] ?? data['data'] ?? '').toString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr.text('群公告', 'Group announcement')),
          content: Text(value.isEmpty ? context.tr.text('暂无群公告', 'No group announcement') : value),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.tr.text('关闭', 'Close')))],
        ),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr.text('加载群公告失败：$error', 'Failed to load announcement: $error'))));
    }
  }

  Future<void> _showGroupTools() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.groups_2), title: Text(context.tr.t('群成员')), onTap: () => Navigator.pop(sheetContext, 'members')),
            ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(context.tr.t('群公告')), onTap: () => Navigator.pop(sheetContext, 'announcement')),
            ListTile(leading: const Icon(Icons.manage_search), title: Text(context.tr.t('搜索历史消息')), onTap: () => Navigator.pop(sheetContext, 'search')),
            ListTile(leading: const Icon(Icons.exit_to_app, color: Colors.red), title: Text(context.tr.text('退出群聊', 'Leave group')), onTap: () => Navigator.pop(sheetContext, 'leave')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'members') await _showGroupMembers();
    if (action == 'announcement') await _showAnnouncement();
    if (action == 'search') await _showSearchMessages();
    if (action == 'leave') {
      try {
        await ApiService().leaveGroup(widget.conversationId);
        widget.onConversationUnavailable?.call();
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr.text('退出群聊失败：$error', 'Failed to leave group: $error'))));
      }
    }
  }

  String _groupRoleLabel(dynamic rawRole) {
    final role = rawRole?.toString().trim().toLowerCase() ?? '';
    if (role == 'owner' || role == 'group_owner' || role == '群主') {
      return context.tr.text('群主', 'Owner');
    }
    if (role == 'admin' || role == 'administrator' || role == 'group_admin' || role == '管理员') {
      return context.tr.text('群管理员', 'Administrator');
    }
    return context.tr.text('群成员', 'Member');
  }

  Future<void> _showGroupMembers() async {
    try {
      final api = ApiService();
      final response = await api.getGroupMembers(widget.conversationId);
      final list = (response['members'] as List?) ?? [];
      await showDialog<void>(
        context: context,
        builder: (context) {
          final ownerUid = response['owner_uid']?.toString() ?? '';
          final memberCount = response['member_count']?.toString() ?? '${list.length}';
          return AlertDialog(
            title: Text('${AppLocalizations.current.t('群成员')} ($memberCount)'),
            content: SizedBox(
              width: 420,
              height: 360,
              child: list.isEmpty
                  ? Center(child: Text(AppLocalizations.current.t('暂无成员')))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final member = Map<String, dynamic>.from(list[index]);
                        final uid =
                            (member['uid'] ??
                                    member['user_uid'] ??
                                    member['id'] ??
                                    '')
                                .toString();
                        final name =
                            (member['display_name'] ??
                                    member['nickname'] ??
                                    member['name'] ??
                                    uid)
                                .toString();
                        final isOwner = member['is_owner'] == true ||
                            (ownerUid.isNotEmpty && ownerUid == uid);
                        final isAdmin = member['is_admin'] == true ||
                            member['isAdmin'] == true ||
                            (member['role']?.toString().toLowerCase() == 'admin') ||
                            (member['role']?.toString().toLowerCase() == 'administrator');
                        final rawAvatar =
                            member['avatar_url'] ??
                            member['avatar'] ??
                            member['photo_url'];
                        final avatarUrl = resolveMediaUrl(
                          rawAvatar?.toString(),
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatarUrl.isNotEmpty
                                ? ImageCacheService.instance.provider(
                                    avatarUrl,
                                    cacheWidth: 96,
                                  )
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    name.isEmpty ? '?' : name.substring(0, 1),
                                  )
                                : null,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            isOwner
                                ? context.tr.text('群主', 'Owner')
                                : isAdmin
                                ? context.tr.text('群管理员', 'Administrator')
                                : _groupRoleLabel(member['role'] ?? member['group_role'] ?? member['member_role']),
                          ),
                          onTap: uid.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  Navigator.of(this.context).push(
                                    MaterialPageRoute(
                                      builder: (_) => UserProfilePage(uid: uid),
                                    ),
                                  );
                                },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.current.t('关闭')),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('加载群成员失败: $e'))),
      );
    }
  }

  Future<void> _loadMentionMembers() async {
    if (widget.type != 'group' || !mounted) return;
    if (_mentionMembers.isEmpty && mounted) {
      setState(() => _mentionLoading = true);
    }
    try {
      final response = await ApiService().getGroupMembers(
        widget.conversationId,
      );
      final raw = response['members'];
      final members = <Map<String, String>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final uid = (map['uid'] ?? map['user_uid'] ?? map['id'] ?? '')
              .toString()
              .trim();
          final ncuid = (map['ncuid'] ?? map['user_ncuid'] ?? '')
              .toString()
              .trim();
          final name =
              (map['display_name'] ??
                      map['nickname'] ??
                      map['username'] ??
                      map['name'] ??
                      uid)
                  .toString()
                  .trim();
          final role = (map['role'] ?? map['member_role'] ?? map['group_role'] ?? map['title'])?.toString().trim() ?? '';
          if ((uid.isEmpty && ncuid.isEmpty) || name.isEmpty) continue;
          final key = uid.isNotEmpty ? uid : ncuid;
          if (members.any((member) => member['uid'] == key)) continue;
          members.add({'uid': key, 'ncuid': ncuid, 'name': name, if (role.isNotEmpty) 'role': role});
          if (role.isNotEmpty) _groupRoleByUid[key] = role;
        }
      }
      if (!mounted) return;
      setState(() {
        _mentionMembers
          ..clear()
          ..addAll(members);
        _mentionLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _mentionLoading = false);
    }
  }

  List<Map<String, String>> _filteredMentionMembers(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, String>>.from(_mentionMembers);
    return _mentionMembers.where((member) {
      final name = (member['name'] ?? '').toLowerCase();
      final uid = (member['uid'] ?? '').toLowerCase();
      final ncuid = (member['ncuid'] ?? '').toLowerCase();
      return name.contains(q) || uid.contains(q) || ncuid.contains(q);
    }).toList();
  }

  void _updateMentionPopup() {
    if (widget.type != 'group') return;
    final value = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    final safeCursor = cursor < 0 || cursor > value.length
        ? value.length
        : cursor;
    final before = value.substring(0, safeCursor);
    final match = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(before);
    if (match == null) {
      if (_mentionPopupVisible && mounted)
        setState(() => _mentionPopupVisible = false);
      _mentionStart = null;
      _mentionFilterTimer?.cancel();
      return;
    }
    _mentionStart = match.start + match.group(1)!.length;
    _mentionPopupVisible = true;
    _mentionActiveIndex = 0;
    _mentionFilterTimer?.cancel();
    _mentionFilterTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _selectMention(Map<String, String> member) {
    final start = _mentionStart;
    if (start == null) return;
    final value = _inputController.text;
    final cursor = _inputController.selection.baseOffset.clamp(0, value.length);
    final mentionName = member['name'] ?? member['uid'] ?? '';
    final replacement = '@$mentionName\u200B ';
    final next =
        '${value.substring(0, start)}$replacement${value.substring(cursor)}';
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    final uid = (member['uid'] ?? '').trim();
    final ncuid = (member['ncuid'] ?? '').trim();
    if (uid.isNotEmpty || ncuid.isNotEmpty) {
      _pendingMentions.removeWhere((item) => item['uid'] == uid);
      _pendingMentions.add({
        'uid': uid,
        'ncuid': (member['ncuid'] ?? '').trim(),
        'name': mentionName,
      });
    }
    _mentionFilterTimer?.cancel();
    _inputFocus.requestFocus();
    setState(() {
      _mentionPopupVisible = false;
      _mentionStart = null;
    });
  }

  String _formatDateTime(int timestamp) {
    final milliseconds = timestamp > 1000000000000
        ? timestamp
        : timestamp > 1000000000
        ? timestamp * 1000
        : timestamp;
    final dt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return DateFormat('yyyy/MM/dd HH:mm').format(dt);
  }

  List<Message> _parseSearchMessages(dynamic response) {
    dynamic value = response;
    for (var i = 0; i < 3 && value is Map; i++) {
      final map = Map<String, dynamic>.from(value as Map);
      final candidate = map['messages'] ?? map['results'] ?? map['items'];
      if (candidate is List) {
        value = candidate;
        break;
      }
      if (map['data'] is List) {
        value = map['data'];
        break;
      }
      if (map['data'] is Map) {
        value = map['data'];
        continue;
      }
      value = const <dynamic>[];
    }
    if (value is! List) return const <Message>[];
    return value
        .whereType<Map>()
        .map((item) {
          final json = Map<String, dynamic>.from(item);
          json['id'] ??= json['message_id'] ?? json['msg_id'];
          json['from_uid'] ??= json['sender_uid'] ?? json['uid'] ?? '';
          json['body'] ??= json['text'] ?? '';
          json['msg_type'] ??= json['type'] ?? 'text';
          json['created_at'] ??= json['timestamp'] ?? 0;
          return Message.fromJson(json);
        })
        .where((message) => message.id.isNotEmpty)
        .toList();
  }

  String _getMessageDisplayText(Message msg) {
    if (msg.msgType == 'text') {
      final parsed = MessageParser.parseV2(msg.body);
      final text = parsed['text']?.toString() ?? '';
      return text.isEmpty ? MessageParser.extractPlainText(msg.body) : text;
    }
    if (msg.msgType == 'image') return '[图片]';
    if (msg.msgType == 'voice') return '[语音]';
    if (msg.msgType == 'video') return '[视频]';
    if (msg.msgType == 'file' || msg.msgType == 'resource') return '[文件]';
    if (msg.msgType == 'red_packet') return '[红包]';
    return msg.body.isEmpty ? '[原消息内容不可用]' : msg.body;
  }

  // ★ 日期格式化
  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy/MM/dd').format(dt);
  }

  bool _isSameDay(int timestamp1, int timestamp2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(timestamp1 * 1000);
    final d2 = DateTime.fromMillisecondsSinceEpoch(timestamp2 * 1000);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  Future<bool> _showFriendRequestDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.current.t('不是好友')),
            content: Text(
              AppLocalizations.current.t('您还不是对方的好友，需要先发送好友申请才能聊天。'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppLocalizations.current.t('取消')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppLocalizations.current.t('发送申请')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendFriendRequest(String toUid) async {
    try {
      final friends = await ApiService().getFriends();
      if (friends.any((f) => f.id == toUid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('你们已经是好友了'))),
        );
        return;
      }
      final requests = await ApiService().getFriendRequests();
      final sent =
          (requests['sent'] as List?)?.any((r) => r['to_uid'] == toUid) ??
          false;
      final received =
          (requests['requests'] as List?)?.any((r) => r['from_uid'] == toUid) ??
          false;
      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.current.t('您已发送过好友申请，请等待对方通过')),
          ),
        );
        return;
      }
      if (received) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.current.t('对方已向您发送好友申请，请检查通知')),
          ),
        );
        return;
      }
      await ApiService().sendFriendRequest(toUid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('好友申请已发送，等待对方通过'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('发送申请失败: $e'))),
      );
    }
  }

  Future<void> _handleMessageAction(
    Message message,
    String action,
    String data,
  ) async {
    if (action == 'open_url' || action == 'url') {
      final uri = Uri.tryParse(data);
      if (uri != null)
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (action == 'claim_red_packet') {
      await _claimRedPacket(data);
      return;
    }
    if (action != 'send_text' && action != 'reply_msg') {
      try {
        var buttonIndex = 0;
        var formData = data;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map) {
            buttonIndex =
                int.tryParse(
                  '${decoded['button_index'] ?? decoded['index'] ?? 0}',
                ) ??
                0;
            formData = (decoded['form_data'] ?? decoded['data'] ?? '')
                .toString();
          }
        } catch (_) {}
        await ApiService().callbackButton(
          messageId: message.id,
          conversationType: widget.type,
          conversationId: widget.conversationId,
          buttonIndex: buttonIndex,
          action: action,
          formData: formData,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.current.t('操作已提交'))),
          );
        }
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.current.t('操作失败：$error'))),
          );
      }
      return;
    }
    await _sendTextMessage(data);
  }

  Future<void> _sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) {
        await _sendFriendRequest(widget.conversationId);
      }
      return;
    }

    Map<String, dynamic> payload = {'v': 2, 'text': text};
    if (_pendingMentions.isNotEmpty) {
      payload['mentions'] = _pendingMentions
          .map(
            (mention) => {
              'uid': mention['uid'],
              if ((mention['ncuid'] ?? '').isNotEmpty)
                'ncuid': mention['ncuid'],
              'name': mention['name'],
            },
          )
          .toList();
    }
    _pendingMentions.clear();
    if (_quotedMessage != null) {
      payload['quote'] = {
        'id': _quotedMessage!.id,
        'from_uid': _quotedMessage!.fromUid,
        'from_name': _quotedMessage!.fromUid,
        'type': _quotedMessage!.msgType,
        'text': _getMessageDisplayText(_quotedMessage!),
        if (_quotedMessage!.mediaUrl != null)
          'media_url': _quotedMessage!.mediaUrl,
        if (_quotedMessage!.thumbUrl != null)
          'thumb_url': _quotedMessage!.thumbUrl,
      };
      setState(() => _quotedMessage = null);
    }
    final bodyJson = jsonEncode(payload);

    try {
      final api = ApiService();
      final sent = widget.type == 'direct'
          ? await api.sendDirectMessage(
              toUid: widget.conversationId,
              body: bodyJson,
              burnAfterSeconds: _pendingBurnAfterSeconds,
            )
          : await api.sendGroupMessage(
              groupId: widget.conversationId,
              body: bodyJson,
              burnAfterSeconds: _pendingBurnAfterSeconds,
            );
      if (sent.id.isEmpty) {
        throw Exception(AppLocalizations.current.t('服务器返回的消息无效'));
      }
      setState(() {
        _addLocalMessage(sent);
        _pendingBurnAfterSeconds = 0;
      });
      unawaited(
        PluginService().dispatchMessage(
          sent,
          conversationId: widget.conversationId,
        ),
      );
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToBottom();
      });
      if (widget.onMessageSent != null) widget.onMessageSent!();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('发送失败: $e'))),
      );
    }
  }

  Future<void> _sendPickedFile(PlatformFile picked, String type) async {
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) await _sendFriendRequest(widget.conversationId);
      return;
    }
    try {
      final bytes = await filePickerBytes(picked);
      if (bytes == null || bytes.isEmpty) throw Exception('无法读取文件');
      final api = ApiService();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      final uploadResult = await api.uploadFile(formData);
      final mediaUrl = ApiService.extractUploadUrl(uploadResult);
      if (mediaUrl == null || mediaUrl.isEmpty) throw Exception('上传失败');
      final isImage = type == 'image';
      final isVideo = type == 'video';
      final msgType = isImage
          ? 'image'
          : isVideo
          ? 'video'
          : 'resource';
      final body = jsonEncode({
        'v': 2,
        'text': '',
        'media_kind': isImage
            ? 'image'
            : isVideo
            ? 'video'
            : 'file',
        'file_name': picked.name,
        'url': mediaUrl,
        'media_url': mediaUrl,
        'size': bytes.length,
      });
      final sent = widget.type == 'direct'
          ? await api.sendDirectMessage(
              toUid: widget.conversationId,
              body: body,
              msgType: msgType,
              mediaUrl: mediaUrl,
            )
          : await api.sendGroupMessage(
              groupId: widget.conversationId,
              body: body,
              msgType: msgType,
              mediaUrl: mediaUrl,
            );
      if (!mounted) return;
      setState(() => _addLocalMessage(sent));
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToBottom();
        if (mounted) _inputFocus.requestFocus();
      });
      widget.onMessageSent?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('发送失败: $e'))),
        );
      }
    }
  }

  Future<void> _sendPickedFileBytes(XFile picked, String type) async {
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    await _sendPickedBytes(bytes, picked.name, type);
  }

  Future<void> _sendPickedBytes(
    Uint8List bytes,
    String fileName,
    String type,
  ) async {
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) await _sendFriendRequest(widget.conversationId);
      return;
    }
    try {
      final api = ApiService();
      final uploadResult = await api.uploadFile(
        FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        }),
      );
      final mediaUrl = ApiService.extractUploadUrl(uploadResult);
      if (mediaUrl == null || mediaUrl.isEmpty) throw Exception('上传失败');
      final isImage = type == 'image';
      final isVideo = type == 'video';
      final msgType = isImage ? 'image' : isVideo ? 'video' : 'resource';
      final body = jsonEncode({
        'v': 2,
        'text': '',
        'media_kind': isImage ? 'image' : isVideo ? 'video' : 'file',
        'file_name': fileName,
        'url': mediaUrl,
        'media_url': mediaUrl,
        'size': bytes.length,
      });
      final sent = widget.type == 'direct'
          ? await api.sendDirectMessage(
              toUid: widget.conversationId,
              body: body,
              msgType: msgType,
              mediaUrl: mediaUrl,
            )
          : await api.sendGroupMessage(
              groupId: widget.conversationId,
              body: body,
              msgType: msgType,
              mediaUrl: mediaUrl,
            );
      if (!mounted) return;
      setState(() => _addLocalMessage(sent));
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleScrollToBottom());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('发送失败: $error'))),
        );
      }
    }
  }

  // ★ 发红包
  Future<void> _sendRedPacket() async {
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) {
        await _sendFriendRequest(widget.conversationId);
      }
      return;
    }

    final amountC = TextEditingController();
    final countC = TextEditingController();
    final titleC = TextEditingController(text: '恭喜发财');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.current.t('发红包')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: AppLocalizations.current.t('金额 (旧币)'),
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.type == 'group') const SizedBox(height: 8),
              if (widget.type == 'group')
                TextField(
                  controller: countC,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.current.t('个数'),
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: titleC,
                decoration: InputDecoration(
                  hintText: AppLocalizations.current.t('红包标题'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.current.t('取消')),
          ),
          TextButton(
            onPressed: () {
              final amount = int.tryParse(amountC.text);
              final count = int.tryParse(countC.text) ?? 1;
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.current.t('请输入有效金额')),
                  ),
                );
                return;
              }
              if (widget.type == 'group' && count <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.current.t('请输入有效个数')),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'amount': amount.toString(),
                'count': count,
                'title': titleC.text.trim(),
              });
            },
            child: Text(AppLocalizations.current.t('发送')),
          ),
        ],
      ),
    );
    if (result == null) return;

    try {
      final api = ApiService();
      final amount = int.tryParse(result['amount']) ?? 0;

      final data = await api.createRedPacket(
        targetId: widget.conversationId,
        amount: amount.toString(),
        type: widget.type,
        count: result['count'],
        title: result['title']?.toString() ?? '恭喜发财',
      );

      final rawPacketId =
          data['packet_id'] ??
          data['packetId'] ??
          data['id'] ??
          (data['data'] is Map
              ? data['data']['packet_id'] ?? data['data']['packetId']
              : null);
      final packetId = rawPacketId?.toString() ?? '';
      if (packetId.isEmpty) throw Exception('服务器未返回红包 ID');

      final bodyJson = jsonEncode({
        'packet_id': packetId,
        'total_amount': amount,
        'total_count': result['count'],
        'text': result['title']?.toString().trim().isNotEmpty == true
            ? result['title']
            : '恭喜发财',
        'v': 1,
      });

      final msg = Message(
        id: packetId,
        fromUid: context.read<AuthService>().userId ?? '',
        body: bodyJson,
        msgType: 'red_packet',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        groupId: widget.type == 'group' ? widget.conversationId : null,
        threadId: widget.type == 'direct' ? widget.conversationId : null,
      );

      setState(() {
        _addLocalMessage(msg);
      });
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToBottom();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('红包已发送'))),
      );
      if (widget.onMessageSent != null) widget.onMessageSent!();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('红包发送失败: $e'))),
      );
    }
  }

  Future<void> _claimRedPacket(String packetId) async {
    try {
      final api = ApiService();
      final data = await api.claimRedPacket(packetId);
      final amount = data['amount'] ?? data['claimed_amount'] ?? 0;
      if (!mounted) return;
      setState(() => _claimedPackets = {..._claimedPackets, packetId});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('领取成功：$amount 旧币'))),
      );
      await _saveCachedMessages();
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('already claimed') || msg.contains('已领取')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('该红包已被领取'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('领取失败: $e'))),
        );
      }
    }
  }

  Future<void> _toggleConversationMute() async {
    final next = !_conversationMuted;
    await NotificationService().setConversationMuted(
      type: widget.type,
      conversationId: widget.conversationId,
      muted: next,
    );
    if (mounted) setState(() => _conversationMuted = next);
  }

  void _showChatBackgroundMenu(Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final local = overlay.globalToLocal(globalPosition);
    final right = overlay.size.width - local.dx;
    final bottom = overlay.size.height - local.dy;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(local.dx, local.dy, right, bottom),
      items: [
        PopupMenuItem<String>(
          value: 'bottom',
          child: ListTile(
            leading: Icon(Icons.vertical_align_bottom),
            title: Text(AppLocalizations.current.t('回到底部')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'refresh',
          child: ListTile(
            leading: Icon(Icons.refresh),
            title: Text(AppLocalizations.current.t('刷新消息')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ).then((value) {
      if (value == 'bottom') {
        unawaited(_scheduleScrollToBottom());
      } else if (value == 'refresh') {
        unawaited(_refreshConversation());
      }
    });
  }

  Future<void> _showBurnDurationDialog() async {
    final controller = TextEditingController(text: '30');
    final seconds = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr.t('阅后即焚')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: AppLocalizations.current.t('打开后多少秒销毁（5-86400）'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.current.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()),
            ),
            child: Text(AppLocalizations.current.t('发送')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (seconds == null || seconds < 5 || seconds > 86400 || !mounted) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('先输入要发送的内容'))),
      );
      return;
    }
    _pendingBurnAfterSeconds = seconds;
    await _sendTextMessage(text);
  }

  void _showMessageMenu(Message msg) {
    if (_selectionMode) {
      _toggleMessageSelection(msg);
      return;
    }
    final displayText = _getMessageDisplayText(msg);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: Text(AppLocalizations.current.t('引用')),
              onTap: () {
                Navigator.pop(context);
                setState(() => _quotedMessage = msg);
                _inputFocus.requestFocus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: Text(AppLocalizations.current.t('选择消息')),
              onTap: () {
                Navigator.pop(context);
                _toggleMessageSelection(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(AppLocalizations.current.t('复制')),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: displayText));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.current.t('已复制'))),
                );
              },
            ),

            if (msg.burnAfterSeconds > 0)
              ListTile(
                leading: const Icon(
                  Icons.visibility_outlined,
                  color: Colors.deepPurple,
                ),
                title: Text(context.tr.t('阅后即焚')),
                onTap: () {
                  Navigator.pop(context);
                  _openBurnMessage(msg);
                },
              ),
            if (msg.fromUid == context.read<AuthService>().userId &&
                DateTime.now().millisecondsSinceEpoch - msg.createdAt * 1000 <
                    120000)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  AppLocalizations.current.t('撤回'),
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _recallMessage(msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBurnMessage(Message msg) async {
    try {
      if (widget.type == 'group') {
        await ApiService().openGroupBurnMessage(msg.id);
      } else {
        await ApiService().openBurnMessage(msg.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr.t('阅后即焚'))));
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.current.t('打开阅后即焚消息失败：$error')),
          ),
        );
    }
  }

  Future<void> _recallMessage(Message msg) async {
    try {
      final api = ApiService();
      if (widget.type == 'direct') {
        await api.recallDirectMessage(msg.id);
      } else {
        await api.recallGroupMessage(msg.id);
      }
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _messageMap.remove(msg.id);
        _messageKeys.remove(msg.id);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('撤回失败: $e'))),
      );
    }
  }

  Widget _buildQuotePreview() {
    if (_quotedMessage == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '引用: ${_quotedMessage!.fromUid}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _getMessageDisplayText(_quotedMessage!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _quotedMessage = null),
          ),
        ],
      ),
    );
  }

  void _showSendOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: Text(AppLocalizations.current.t('图片')),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final result = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (result != null) _sendPickedFileBytes(result, 'image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_collection, color: Colors.green),
              title: Text(AppLocalizations.current.t('视频')),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final result = await picker.pickVideo(
                  source: ImageSource.gallery,
                );
                if (result != null) _sendPickedFileBytes(result, 'video');
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.timer_outlined,
                color: Colors.deepPurple,
              ),
              title: Text(context.tr.t('阅后即焚')),
              onTap: () {
                Navigator.pop(context);
                _showBurnDurationDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.red),
              title: Text(AppLocalizations.current.t('红包')),
              onTap: () {
                Navigator.pop(context);
                _sendRedPacket();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocalEmojiPicker() async {
    final items = await LocalEmojiService.instance.list();
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('暂无本地收藏表情'))),
      );
      return;
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              onTap: () => Navigator.pop(sheetContext, item),
              child: CachedImage(
                resolveMediaUrl(item['media_url']?.toString() ?? ''),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            );
          },
        ),
      ),
    );
    if (selected == null) return;
    final mediaUrl = selected['media_url']?.toString() ?? '';
    if (mediaUrl.isEmpty) return;
    try {
      final sent = widget.type == 'direct'
          ? await ApiService().sendDirectMessage(
              toUid: widget.conversationId,
              body: jsonEncode({
                'v': 2,
                'text': '',
                'media_kind': 'image',
                'media_url': mediaUrl,
                'url': mediaUrl,
              }),
              msgType: 'image',
              mediaUrl: mediaUrl,
            )
          : await ApiService().sendGroupMessage(
              groupId: widget.conversationId,
              body: jsonEncode({
                'v': 2,
                'text': '',
                'media_kind': 'image',
                'media_url': mediaUrl,
                'url': mediaUrl,
              }),
              msgType: 'image',
              mediaUrl: mediaUrl,
            );
      if (mounted) setState(() => _addLocalMessage(sent));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('发送表情失败：$error'))),
        );
    }
  }

  // ★ 头像右键菜单（仅群聊有效）
  void _insertMention(String name, {String? uid}) {
    final text = _inputController.text;
    final rawPosition = _inputController.selection.baseOffset;
    final position = rawPosition < 0 || rawPosition > text.length
        ? text.length
        : rawPosition;
    final before = text.substring(0, position);
    final after = text.substring(position);
    final mention = '@$name\u200B ';
    final next = '$before$mention$after';
    if (uid != null && uid.trim().isNotEmpty) {
      _pendingMentions.removeWhere((item) => item['uid'] == uid.trim());
      _pendingMentions.add({'uid': uid.trim(), 'name': name});
    }
    if (next.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('消息最多 2000 字'))),
      );
      return;
    }
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: before.length + mention.length,
      ),
    );
    _inputFocus.requestFocus();
  }

  void _showAvatarMenu(String uid, String name, Offset position) {
    if (widget.type != 'group') return;

    final items = <PopupMenuEntry<String>>[];

    items.add(
      PopupMenuItem(
        value: 'mention',
        child: Row(
          children: [
            Icon(Icons.alternate_email, size: 18),
            SizedBox(width: 8),
            Text(AppLocalizations.current.t('@提及')),
          ],
        ),
      ),
    );

    items.add(
      PopupMenuItem(
        value: 'profile',
        child: Row(
          children: [
            Icon(Icons.person, size: 18),
            SizedBox(width: 8),
            Text(AppLocalizations.current.t('查看资料')),
          ],
        ),
      ),
    );

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'mention':
          _insertMention(name, uid: uid);
          break;
        case 'friend':
          _sendFriendRequest(uid);
          break;
        case 'chat':
          Navigator.pushNamed(
            context,
            '/chat',
            arguments: {'uid': uid, 'title': name},
          );
          break;
        case 'profile':
          Navigator.pushNamed(context, '/user_profile', arguments: uid);
          break;
      }
    });
  }

  String _mediaTypeForFile(String path) {
    final lower = path.toLowerCase();
    if (RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic|avif)$').hasMatch(lower))
      return 'image';
    if (RegExp(r'\.(mp4|mkv|mov|avi|webm|wmv|flv|m4v)$').hasMatch(lower))
      return 'video';
    return 'file';
  }

  Future<bool> _confirmClipboardSend(List<String> names) async {
    final visibleNames = names.where((name) => name.isNotEmpty).toList();
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppLocalizations.current.t('发送剪贴板内容？')),
            content: Text(
              visibleNames.length == 1
                  ? context.tr.text('Clipboard detected ${visibleNames.first}', 'Clipboard detected ${visibleNames.first}')
                  : context.tr.text(
                      'Clipboard detected ${visibleNames.length} files:\n${visibleNames.take(8).join('\n')}${visibleNames.length > 8 ? '\n...' : ''}',
                      'Clipboard detected ${visibleNames.length} files:\n${visibleNames.take(8).join('\n')}${visibleNames.length > 8 ? '\n...' : ''}',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.current.t('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppLocalizations.current.t('发送')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleClipboardPaste() async {
    final textData = await Clipboard.getData(Clipboard.kTextPlain);
    if (textData?.text != null && textData!.text!.isNotEmpty) {
      final text = textData.text!;
      final selection = _inputController.selection;
      final start = selection.start >= 0
          ? selection.start
          : _inputController.text.length;
      final end = selection.end >= 0 ? selection.end : start;
      final value = _inputController.text;
      final safeStart = start.clamp(0, value.length);
      final safeEnd = end.clamp(safeStart, value.length);
      _inputController.value = TextEditingValue(
        text: value.replaceRange(safeStart, safeEnd, text),
        selection: TextSelection.collapsed(offset: safeStart + text.length),
      );
      _updateMentionPopup();
      return;
    }
    final media = await clipboardFileMedia();
    if (media.isNotEmpty) {
      if (!await _confirmClipboardSend(media.map((item) => item.name).toList())) {
        return;
      }
      for (final item in media) {
        await _sendPickedBytes(item.bytes, item.name, _mediaTypeForFile(item.name));
      }
      return;
    }
    final image = await clipboardImageMedia();
    if (image != null) {
      if (await _confirmClipboardSend([image.name])) {
        await _sendPickedBytes(image.bytes, image.name, 'image');
      }
    }
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(_handleClipboardPaste());
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _mentionPopupVisible) {
      final members = _filteredMentionMembers(_currentMentionQuery());
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (members.isNotEmpty)
          setState(
            () => _mentionActiveIndex = (_mentionActiveIndex + 1).clamp(
              0,
              members.length - 1,
            ),
          );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (members.isNotEmpty)
          setState(
            () => _mentionActiveIndex = (_mentionActiveIndex - 1).clamp(
              0,
              members.length - 1,
            ),
          );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        if (members.isNotEmpty)
          _selectMention(
            members[_mentionActiveIndex.clamp(0, members.length - 1)],
          );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _mentionPopupVisible = false);
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _sendTextMessage(_inputController.text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _currentMentionQuery() {
    final value = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    final safeCursor = cursor < 0 || cursor > value.length
        ? value.length
        : cursor;
    final before = value.substring(0, safeCursor);
    final match = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(before);
    return match?.group(2) ?? '';
  }

  Widget _buildMentionPopup() {
    final members = _filteredMentionMembers(_currentMentionQuery());
    final visible = members.take(8).toList();
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: _mentionLoading
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              )
            : visible.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppLocalizations.current.t('暂无匹配成员')),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final member = visible[index];
                  final active = index == _mentionActiveIndex;
                  return InkWell(
                    onTap: () => _selectMention(member),
                    child: Container(
                      color: active
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(.12)
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            child: Text(
                              (member['name'] ?? '?').characters.first,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              member['name'] ?? member['uid'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if ((member['uid'] ?? '').isNotEmpty)
                            Text(
                              member['uid']!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthService>().userId;
    if (_isCheckingFriend && widget.type == 'direct') {
      return Center(child: CircularProgressIndicator());
    }

    final body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _loading && _messages.isEmpty
                      ? Center(child: CircularProgressIndicator())
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollEndNotification &&
                                notification.metrics.pixels <= 160 &&
                                _hasMore &&
                                !_isLoadingMore &&
                                !_loading) {
                              _isLoadingMore = true;
                              unawaited(
                                _loadMessages(initial: false).whenComplete(() {
                                  if (mounted) _isLoadingMore = false;
                                }),
                              );
                            }
                              return false;
                            },
                            child: ListView.builder(
                            controller: _scrollController,
                            reverse: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) {
                              final msg = _messages[i];
                              final parsed = MessageParser.parseMessageBody(
                                msg.body,
                                msg.msgType,
                              );
                              final isRedPacket =
                                  msg.msgType == 'red_packet' ||
                                  (msg.msgType == 'text' &&
                                      parsed['redPacket'] != null);
                              final isClaimed = _claimedPackets.contains(
                                parsed['redPacket']?['packet_id'] ??
                                    parsed['redPacket']?['packetId'],
                              );

                              final bool showDateDivider =
                                  i == 0 ||
                                  !_isSameDay(
                                    _messages[i - 1].createdAt,
                                    msg.createdAt,
                                  );

                              return RepaintBoundary(
                                key: ValueKey('message-row:${msg.id}'),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showDateDivider)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Center(
                                          child: Text(
                                            _formatDate(msg.createdAt),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    MessageTile(
                                      key: _messageKeys[msg.id],
                                      message: msg,
                                      isMe: msg.fromUid == userId,
                                      selected: _selectedMessageIds.contains(msg.id),
                                      groupRole: _groupRoleByUid[msg.fromUid],
                                      onTap: () => _selectionMode ? _toggleMessageSelection(msg) : null,
                                      onLongPress: _selectionMode ? null : () => _showMessageMenu(msg),
                                      showAvatar:
                                          i == 0 ||
                                          _messages[i - 1].fromUid !=
                                              msg.fromUid ||
                                          msg.createdAt -
                                                  _messages[i - 1].createdAt >=
                                              5 * 60,
                                      onSecondaryTap: () => _showMessageMenu(msg),
                                      onQuoteTap: (quotedId) =>
                                          _scrollToMessage(quotedId),
                                      onMessageAction: _handleMessageAction,
                                      onAvatarLongPress: widget.type == 'group'
                                          ? (uid, name) =>
                                                _insertMention(name, uid: uid)
                                          : null,
                                      onAvatarSecondaryTap:
                                          widget.type == 'group'
                                          ? _showAvatarMenu
                                          : null,
                                      isRedPacket: isRedPacket,
                                      isClaimed: isClaimed,
                                      onClaimRedPacket: isRedPacket
                                          ? () => _claimRedPacket(
                                              parsed['redPacket']?['packet_id'] ??
                                                  parsed['redPacket']?['packetId'] ??
                                                  '',
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                            },
                              ),
                            ),
                        ),
                ),
                _buildQuotePreview(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(.12),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: Theme.of(context).primaryColor,
                              ),
                              onPressed: _showSendOptions,
                              tooltip: AppLocalizations.current.t('发送图片/视频/红包'),
                            ),
                            Expanded(
                              child: Focus(
                                onKeyEvent: _handleComposerKeyEvent,
                                child: TextField(
                                  controller: _inputController,
                                  focusNode: _inputFocus,
                                  scrollController: _composerScrollController,
                                  minLines: 1,
                                  maxLines: 6,
                                  maxLength: 2000,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  onChanged: (_) => _updateMentionPopup(),
                                  onTapOutside: (_) => _inputFocus.unfocus(),
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(2000),
                                  ],
                                  buildCounter:
                                      (
                                        context, {
                                        required currentLength,
                                        required isFocused,
                                        maxLength,
                                      }) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                          bottom: 2,
                                        ),
                                        child: Text(
                                          '$currentLength/2000',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Theme.of(context).hintColor,
                                          ),
                                        ),
                                      ),
                                  decoration: InputDecoration(
                                    hintText:
                                        widget.type == 'direct' && !_isFriend
                                        ? '发送好友申请后才能聊天'
                                        : '输入消息…（Enter 发送，Shift+Enter 换行）',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                Icons.emoji_emotions_outlined,
                                color: Theme.of(context).primaryColor,
                              ),
                              onPressed: _showLocalEmojiPicker,
                              tooltip: AppLocalizations.current.t('发送收藏表情'),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.send,
                                color: Theme.of(context).primaryColor,
                              ),
                              onPressed: () =>
                                  _sendTextMessage(_inputController.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 84,
              child: _mentionPopupVisible && widget.type == 'group'
                  ? _buildMentionPopup()
                  : const SizedBox.shrink(),
            ),
          ],
        ),
    );

    if (widget.embed) {
      return Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'refresh':
                        _refreshConversation();
                        break;
                      case 'bottom':
                        _scrollToBottom();
                        break;
                      case 'clear':
                        _inputController.clear();
                        _inputFocus.unfocus();
                        break;
                      case 'copy_id':
                        Clipboard.setData(
                          ClipboardData(
                            text: '${widget.type}:${widget.conversationId}',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.current.t('已复制会话ID'),
                            ),
                          ),
                        );
                        break;
                      case 'group_tools':
                        _showGroupTools();
                        break;
                      case 'search_history':
                        _showSearchMessages();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text(AppLocalizations.current.t('刷新消息')),
                    ),
                    PopupMenuItem(
                      value: 'bottom',
                      child: Text(AppLocalizations.current.t('回到底部')),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      child: Text(AppLocalizations.current.t('清空输入框')),
                    ),
                    PopupMenuItem(
                      value: 'copy_id',
                      child: Text(AppLocalizations.current.t('复制会话ID')),
                    ),
                    if (widget.type == 'group')
                      PopupMenuItem(
                        value: 'group_tools',
                        child: Text(AppLocalizations.current.t('群成员与群工具')),
                      ),
                    PopupMenuItem(
                      value: 'search_history',
                      child: Text(AppLocalizations.current.t('搜索历史消息')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: Column(children: [_buildSelectionBar(), Expanded(child: body)])),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.type == 'group')
            IconButton(
              icon: const Icon(Icons.group, color: Colors.white),
              tooltip: AppLocalizations.current.t('查看群成员'),
              onPressed: _showGroupTools,
            ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: AppLocalizations.current.t('搜索历史消息'),
            onPressed: _showSearchMessages,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.white,
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _refreshConversation();
                  break;
                case 'bottom':
                  _scrollToBottom();
                  break;
                case 'clear':
                  _inputController.clear();
                  _inputFocus.unfocus();
                  break;
                case 'copy_id':
                  Clipboard.setData(
                    ClipboardData(
                      text: '${widget.type}:${widget.conversationId}',
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.current.t('已复制会话ID')),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Text(AppLocalizations.current.t('刷新消息')),
              ),
              PopupMenuItem(
                value: 'bottom',
                child: Text(AppLocalizations.current.t('回到底部')),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(AppLocalizations.current.t('清空输入框')),
              ),
              PopupMenuItem(
                value: 'copy_id',
                child: Text(AppLocalizations.current.t('复制会话ID')),
              ),
              if (widget.type == 'group')
                PopupMenuItem(
                  value: 'group_tools',
                  child: Text(AppLocalizations.current.t('群成员与群工具')),
                ),
              PopupMenuItem(
                value: 'search_history',
                child: Text(AppLocalizations.current.t('搜索历史消息')),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: [_buildSelectionBar(), Expanded(child: body)]),
    );
  }
}
