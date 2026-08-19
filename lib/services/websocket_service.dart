import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/constants.dart';
import '../models/message.dart';
import 'auth_service.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'ws_session_service.dart';
import 'plugin_service.dart';

typedef OnMessageCallback = void Function(Message message);
typedef OnEventCallback = void Function(String type, Map<String, dynamic> data);
typedef OnRecallCallback = void Function(String messageId, String displayName);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  bool _connecting = false;
  bool _shouldReconnect = true;
  int _connectionGeneration = 0;
  bool _connected = false;
  final AuthService _auth = AuthService();
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const Duration _reconnectDelay = Duration(seconds: 5);
  bool _isReconnecting = false;

  OnEventCallback? onEvent;
  final Set<OnMessageCallback> _directListeners = <OnMessageCallback>{};
  final Set<OnMessageCallback> _groupListeners = <OnMessageCallback>{};
  final Set<OnRecallCallback> _recallListeners = <OnRecallCallback>{};

  void addRecallListener(OnRecallCallback listener) =>
      _recallListeners.add(listener);
  void removeRecallListener(OnRecallCallback listener) =>
      _recallListeners.remove(listener);

  void addDirectListener(OnMessageCallback listener) =>
      _directListeners.add(listener);
  void removeDirectListener(OnMessageCallback listener) =>
      _directListeners.remove(listener);
  void addGroupListener(OnMessageCallback listener) =>
      _groupListeners.add(listener);
  void removeGroupListener(OnMessageCallback listener) =>
      _groupListeners.remove(listener);

  void _emit(Set<OnMessageCallback> listeners, Message message) {
    for (final listener in List<OnMessageCallback>.from(listeners)) {
      try {
        listener(message);
      } catch (error) {
        print('WebSocket: listener error - $error');
      }
    }
  }

  Future<void> connect() async {
    if (_connected || _connecting || _channel != null) return;
    final token = _auth.token;
    if (token == null || token.isEmpty) {
      print('WebSocket: No token, skip');
      return;
    }
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    _connecting = true;
    final generation = ++_connectionGeneration;

    try {
      final session = WsSessionService();
      await session.ensureReady();
      if (session.sessionId == null || session.sessionId!.isEmpty) {
        throw Exception('Session ID is null after handshake');
      }
      print('WebSocket: sessionId = ${session.sessionId}');

      final baseUri = Uri.parse(Constants.baseUrl);
      final wsUri = baseUri.replace(
        scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
        path: Constants.wsPath,
        queryParameters: {'token': token, 'sid': session.sessionId!},
      );
      print('WebSocket: Connecting to $wsUri');

      final channel = WebSocketChannel.connect(wsUri);
      await channel.ready.timeout(const Duration(seconds: 12));
      print('WebSocket: Socket connected');
      _channel = channel;

      channel.stream.listen(
        (data) => _handleMessage(data),
        onDone: () => _handleDisconnected(channel, generation),
        onError: (error) {
          final errorStr = error.toString().toLowerCase();
          final authError =
              errorStr.contains('401') ||
              errorStr.contains('unauthorized') ||
              errorStr.contains('400');
          _handleDisconnected(channel, generation, error, false);
          if (authError) {
            WsSessionService().reset();
            unawaited(_refreshTokenAndReconnect());
          } else if (_shouldReconnect) {
            _scheduleReconnect();
          }
        },
      );

      _connected = true;
      _reconnectAttempts = 0;
      _isReconnecting = false;
      print('WebSocket: Connected');
    } catch (e) {
      _connecting = false;
      _channel = null;
      print('WebSocket: Connection failed - $e');
      WsSessionService().reset();
      _scheduleReconnect();
    }
  }

  void _handleDisconnected(
    WebSocketChannel channel,
    int generation, [
    Object? error,
    bool schedule = true,
  ]) {
    if (generation != _connectionGeneration || !identical(_channel, channel))
      return;
    _channel = null;
    _connected = false;
    _connecting = false;
    final errorStr = error?.toString() ?? '';
    if (errorStr.contains('400') ||
        errorStr.contains('401') ||
        errorStr.contains('Unauthorized')) {
      WsSessionService().reset();
      print('WebSocket: 认证错误，已重置会话');
    }
    if (error != null) print('WebSocket: Error - $error');
    print('WebSocket: Disconnected');
    if (_shouldReconnect && schedule) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectTimer?.isActive == true || _connecting)
      return;
    _reconnectAttempts++;
    final exponent = _reconnectAttempts > 4 ? 4 : _reconnectAttempts - 1;
    final delay = Duration(
      milliseconds: (_reconnectDelay.inMilliseconds * (1 << exponent)).clamp(
        1000,
        30000,
      ),
    );
    print('WebSocket: ${delay.inSeconds}秒后重连 (尝试 $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_shouldReconnect && !_connected && !_connecting) connect();
    });
  }

  Future<void> _refreshTokenAndReconnect() async {
    if (_isReconnecting) return;
    _isReconnecting = true;
    try {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      final recovered = await ApiService().recoverAuthentication();
      if (recovered) {
        print('WebSocket: 认证恢复成功，重新连接...');
        _reconnectAttempts = 0;
        disconnect();
        await connect();
        return;
      }
      print('WebSocket: 认证恢复未完成，等待下一次连接');
    } catch (error) {
      print('WebSocket: 认证恢复失败: $error');
    } finally {
      _isReconnecting = false;
    }
    _scheduleReconnect();
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionGeneration++;
    final channel = _channel;
    _channel = null;
    _connected = false;
    _connecting = false;
    _reconnectAttempts = 0;
    if (channel != null) {
      unawaited(channel.sink.close(status.normalClosure));
    }
    print('WebSocket: 主动断开');
  }

  bool get isConnected => _connected;

  Future<void> _handleMessage(dynamic data) async {
    try {
      dynamic decoded = data;
      if (decoded is String) {
        final decrypted = await WsSessionService().decrypt(decoded);
        final text = decrypted ?? decoded;
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          return;
        }
      }
      if (decoded is! Map) return;

      final envelope = Map<String, dynamic>.from(decoded as Map);
      var type = envelope['type']?.toString().toLowerCase();
      if (type == null || type.isEmpty) {
        type = envelope['event']?.toString().toLowerCase();
      }
      dynamic rawPayload =
          envelope['data'] ??
          envelope['message'] ??
          envelope['payload'] ??
          envelope['data_payload'] ??
          envelope;
      if (rawPayload is String) {
        try {
          rawPayload = jsonDecode(rawPayload);
        } on FormatException {
          return;
        }
      }
      if (rawPayload is! Map) return;
      var payload = Map<String, dynamic>.from(rawPayload as Map);
      final nestedType = payload['type']?.toString().toLowerCase();
      if ((type == null || type == 'message' || type == 'event') &&
          nestedType != null) {
        type = nestedType;
      }
      if (payload['message'] is Map) {
        payload = Map<String, dynamic>.from(payload['message'] as Map);
      }

      final normalizedType = (type ?? '')
          .replaceAll('-', '_')
          .replaceAll('.', '_')
          .toLowerCase();
      if (normalizedType.contains('recall') ||
          normalizedType.contains('recalled') ||
          normalizedType == 'message_deleted') {
        final messageId = (payload['message_id'] ?? payload['id'] ?? '')
            .toString();
        if (messageId.isNotEmpty) {
          final displayName =
              (payload['from_name'] ??
                      payload['display_name'] ??
                      payload['recall_by_name'] ??
                      payload['from_uid'] ??
                      '对方')
                  .toString();
          onEvent?.call(normalizedType, payload);
          for (final listener in List<OnRecallCallback>.from(
            _recallListeners,
          )) {
            try {
              listener(messageId, displayName);
            } catch (error) {
              print('WebSocket: recall listener error - $error');
            }
          }
        }
        return;
      }
      final isGroup =
          normalizedType == 'group_message' ||
          normalizedType == 'new_group_message' ||
          normalizedType == 'group_message_new' ||
          (normalizedType.contains('group_message') &&
              normalizedType.endsWith('_new')) ||
          (normalizedType == 'new_message' && payload['group_id'] != null);
      final isDirect =
          normalizedType == 'direct_message' ||
          normalizedType == 'new_direct_message' ||
          normalizedType == 'direct_message_new' ||
          (normalizedType.contains('direct_message') &&
              normalizedType.endsWith('_new')) ||
          (normalizedType == 'new_message' && payload['group_id'] == null);
      if ((!isDirect && !isGroup) || payload['id'] == null) return;

      onEvent?.call(normalizedType, payload);
      final message = Message.fromJson(payload);
      if (isDirect) {
        _emitDirect(message);
      } else {
        _emitGroup(message);
      }
    } catch (e) {
      print('WebSocket: 解析消息错误 - $e');
    }
  }

  void _emitDirect(Message message) {
    final conversationId = message.fromUid;
    final isSelf = _auth.userId == message.fromUid;
    if (!isSelf) {
      unawaited(
        NotificationService().showMessageNotification(
          fromName: message.fromUid,
          message: message.body,
          conversationId: conversationId,
          conversationType: 'direct',
          fromUid: message.fromUid,
          messageId: message.id,
          withFlash: true,
        ),
      );
      unawaited(
        PluginService().dispatchMessage(
          message,
          conversationId: conversationId,
        ),
      );
    }
    _emit(_directListeners, message);
  }

  void _emitGroup(Message message) {
    final conversationId = message.groupId ?? '';
    final isSelf = _auth.userId == message.fromUid;
    if (!isSelf) {
      unawaited(
        NotificationService().showMessageNotification(
          fromName: message.fromUid,
          message: message.body,
          conversationId: conversationId,
          conversationType: 'group',
          fromUid: message.fromUid,
          messageId: message.id,
          withFlash: true,
        ),
      );
      unawaited(
        PluginService().dispatchMessage(
          message,
          conversationId: conversationId,
        ),
      );
    }
    _emit(_groupListeners, message);
  }
}
