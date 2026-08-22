import 'dart:convert';
import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'web_notification_service.dart';
import 'app_localizations.dart';
import 'account_storage.dart';
import 'auth_service.dart';
import 'profile_name_resolver.dart';
import '../pages/chat_page.dart';
import '../utils/constants.dart';
import '../utils/navigation.dart';
import 'native_window_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _enabled = true;
  static bool _windowIsVisible = true;
  static bool _taskbarFlashEnabled = true;
  static final List<String> _pendingActivationPayloads = <String>[];
  static File? _toastLogFile;
  static final Set<String> _shownMessageNotificationIds = <String>{};
  static Future<void> _toastQueue = Future<void>.value();
  static final WebNotificationService _webNotifier = WebNotificationService();

  static void setWindowVisible(bool visible) {
    _windowIsVisible = visible;
  }

  bool get enabled => _enabled;
  String? get toastLogPath => _toastLogFile?.path;

  static void handleLaunchArguments(List<String> args) {
    final index = args.indexWhere(
      (arg) => arg.toLowerCase() == '-toastactivated',
    );
    if (index < 0) return;
    final payload = args
        .skip(index + 1)
        .firstWhere(
          (arg) => arg.trim().isNotEmpty && !arg.startsWith('-'),
          orElse: () => '',
        );
    if (payload.isNotEmpty) _pendingActivationPayloads.add(payload);
  }

  static List<String> takePendingActivationPayloads() {
    final values = List<String>.from(_pendingActivationPayloads);
    _pendingActivationPayloads.clear();
    return values;
  }

  Future<void> _initToastLog() async {
    try {
      final appData = Platform.environment['APPDATA'];
      final root = appData == null || appData.isEmpty
          ? await getApplicationSupportDirectory()
          : Directory(
              '$appData${Platform.pathSeparator}OldChatForAllPlatform',
            );
      final accountRoot = Directory(
        '${root.path}${Platform.pathSeparator}accounts${Platform.pathSeparator}${AccountStorage.instance.userId}',
      );
      final logDirectory = Directory(
        '${accountRoot.path}${Platform.pathSeparator}logs',
      );
      await logDirectory.create(recursive: true);
      _toastLogFile = File(
        '${logDirectory.path}${Platform.pathSeparator}win_toast.log',
      );
      await _writeToastLog('初始化开始');
    } catch (error) {
      debugPrint('[Windows 通知] 创建日志失败：$error');
    }
  }

  Future<void> _writeToastLog(String message) async {
    final file = _toastLogFile;
    if (file == null) return;
    try {
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (error) {
      debugPrint('[Windows 通知] 写入日志失败：$error');
    }
  }


  Future<void> init() async {
    await AccountStorage.instance.load();
    final storage = AccountStorage.instance;
    if (!kIsWeb) await _initToastLog();
    _enabled = storage.getBool(Constants.desktopNotificationsKey) ?? true;
    _taskbarFlashEnabled = storage.getBool(Constants.taskbarFlashKey) ?? true;

    if (Platform.isWindows) {
      await _writeToastLog('Windows 7 使用 flutter_local_notifications；不依赖 WebView2 或 WinToast');
    }

    // Mobile and web notifications use the Flutter local notification backend.
    if (kIsWeb) {
      await _webNotifier.init();
      return;
    }
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'open',
    );
    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    final macPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macPlugin?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await AccountStorage.instance.setBool(
      Constants.desktopNotificationsKey,
      value,
    );
  }

  Future<void> setTaskbarFlashEnabled(bool value) async {
    _taskbarFlashEnabled = value;
    await AccountStorage.instance.setBool(Constants.taskbarFlashKey, value);
  }

  String _conversationMuteKey(String type, String conversationId) =>
      'mute:$type:$conversationId';

  bool isConversationMuted(String type, String conversationId) {
    final normalizedType = type.trim().isEmpty ? 'direct' : type.trim();
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return false;
    return AccountStorage.instance.getBool(
          _conversationMuteKey(normalizedType, normalizedId),
        ) ??
        false;
  }

  Future<void> setConversationMuted({
    required String type,
    required String conversationId,
    required bool muted,
  }) async {
    final normalizedType = type.trim().isEmpty ? 'direct' : type.trim();
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return;
    await AccountStorage.instance.setBool(
      _conversationMuteKey(normalizedType, normalizedId),
      muted,
    );
  }

  void _onNotificationTap(NotificationResponse response) =>
      openConversationFromNotification(response.payload);

  void openConversationFromNotification(String? payload) {
    if (!kIsWeb) {
      windowManager.show();
      windowManager.focus();
    }
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length != 2) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          conversationId: parts[1],
          type: parts[0],
          title: AppLocalizations.current.t('聊天'),
          embed: false,
        ),
      ),
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool withFlash = false,
  }) async {
    if (!_enabled) return;
    final operation = _toastQueue.then<void>(
      (_) => _showNotificationNow(
        title: title,
        body: body,
        payload: payload,
        withFlash: withFlash,
      ),
    );
    _toastQueue = operation.catchError((_) {});
    await operation;
  }

  Future<void> _showNotificationNow({
    required String title,
    required String body,
    String? payload,
    bool withFlash = false,
  }) async {
    if (kIsWeb) {
      final shown = await _webNotifier.show(
        title: title,
        body: body,
        payload: payload,
      );
      if (!shown) {
        debugPrint('[Web notification] Browser permission denied or unavailable');
      }
      return;
    }
    if (!kIsWeb && Platform.isWindows) {
      await _writeToastLog('Windows 7 通知已跳过原生 Toast，使用跨平台通知后端：$title');
      if (withFlash && _taskbarFlashEnabled && !_windowIsVisible) {
        await NativeWindowService.flashTaskbar();
      }
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      '聊天消息',
      channelDescription: '收到新消息时通知',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
      transient: true,
    );
    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
        ),
        payload: payload,
      );
    } catch (error) {
      debugPrint('[系统通知] 平台通知插件不可用：$error');
    }

    // 任务栏闪烁（窗口不可见时）
    if (withFlash && _taskbarFlashEnabled && !_windowIsVisible) {
      await NativeWindowService.flashTaskbar();
    }
  }

  /// 测试 Windows Toast 通知
  Future<void> testWindowsToast() async {
    await showNotification(
      title: AppLocalizations.current.t('Windows 通知测试'),
      body: AppLocalizations.current.t('Windows 通知测试成功'),
      withFlash: true,
    );
    await _writeToastLog(AppLocalizations.current.t('Windows 通知测试已完成'));
  }

  Future<void> showMessageNotification({
    required String fromName,
    required String message,
    String? conversationId,
    String? conversationType,
    String? fromUid,
    String? messageId,
    bool withFlash = false,
  }) async {
    final type = conversationType?.trim() ?? '';
    final id = conversationId?.trim() ?? '';
    final normalizedMessageId = messageId?.trim() ?? '';
    if (fromUid != null && fromUid.trim() == AuthService().userId) return;
    if (normalizedMessageId.isNotEmpty &&
        !_shownMessageNotificationIds.add(normalizedMessageId)) {
      return;
    }
    if (_shownMessageNotificationIds.length > 5000) {
      _shownMessageNotificationIds.remove(_shownMessageNotificationIds.first);
    }
    if (id.isNotEmpty && isConversationMuted(type, id)) {
      await _writeToastLog('会话免打扰，跳过通知：$type|$id');
      return;
    }
    final payload = id.isNotEmpty && type.isNotEmpty ? '$type|$id' : null;
    var display = message;
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map) {
        display =
            (decoded['text'] ??
                    decoded['content'] ??
                    decoded['file_name'] ??
                    message)
                .toString();
      }
    } on FormatException {
      display = message;
    }
    final location = type == 'group'
        ? AppLocalizations.current.text('群聊', 'Group')
        : AppLocalizations.current.text('私聊', 'Direct');
    final conversationLine = id.isEmpty ? '' : '$location - $id\n';
    final resolvedSender = fromUid == null || fromUid.trim().isEmpty
        ? fromName
        : await ProfileNameResolver.resolve(fromUid, fallback: fromName);
    final resolvedSenderLine = fromUid == null || fromUid.trim().isEmpty
        ? resolvedSender
        : '$resolvedSender - ${fromUid.trim()}';
    final toastBody =
        '$conversationLine$resolvedSenderLine\n${display.length > 240 ? '${display.substring(0, 240)}…' : display}';
    await showNotification(
      title: AppLocalizations.current.text('新消息', 'New message'),
      body: toastBody,
      payload: payload,
      withFlash: withFlash,
    );
  }

}
