import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win_toast/win_toast.dart';
import 'package:flutter_desktop_notifications/flutter_desktop_notifications.dart';

import 'app_localizations.dart';
import 'account_storage.dart';
import 'auth_service.dart';
import '../pages/chat_page.dart';
import '../utils/constants.dart';
import '../utils/navigation.dart';
import 'native_window_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _enabled = true;
  static bool _winToastInitialized = false;
  static bool _windowIsVisible = true;
  static bool _taskbarFlashEnabled = true;
  static final List<String> _pendingActivationPayloads = <String>[];
  static String? _toastInitError;
  static File? _toastLogFile;
  static final Set<String> _shownMessageNotificationIds = <String>{};
  static Future<void> _toastQueue = Future<void>.value();
  static final DesktopNotifier _desktopNotifier = DesktopNotifier(
    appName: Constants.appName,
    appId: Constants.appAumid,
  );

  static void setWindowVisible(bool visible) {
    _windowIsVisible = visible;
  }

  bool get enabled => _enabled;
  bool get winToastInitialized => _winToastInitialized;
  String? get toastInitError => _toastInitError;
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
              '$appData${Platform.pathSeparator}OldChat_For_AllPlatform',
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

  String _notificationIconPath() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '${executableDir}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.ico',
      '${executableDir}${Platform.pathSeparator}app_icon.ico',
      '${Directory.current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.ico',
      '${executableDir}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.png',
      '${Directory.current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.png',
    ];
    return candidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );
  }

  Future<void> init() async {
    await AccountStorage.instance.load();
    final storage = AccountStorage.instance;
    await _initToastLog();
    _enabled = storage.getBool(Constants.desktopNotificationsKey) ?? true;
    _taskbarFlashEnabled = storage.getBool(Constants.taskbarFlashKey) ?? true;

    if (Platform.isWindows) {
      NotificationService.setWindowVisible(await windowManager.isVisible());
      // ========== 步骤 1：注册 AUMID 和 COM 服务器（非 MSIX 必需） ==========
      const String aumid = Constants.appAumid;
      const String clsid = Constants.appClsid;

      try {
        await WindowsNotification.registerAumid(
          aumid: aumid,
          displayName: Constants.appName,
        );
        await _writeToastLog('AUMID/COM 注册成功');
      } catch (e) {
        await _writeToastLog('AUMID/COM 注册异常：$e');
      }

      // ========== 步骤 2：初始化 win_toast（必须传入 clsid） ==========
      try {
        final iconPath = _notificationIconPath();
        _toastInitError = iconPath.isEmpty ? '未找到通知图标，尝试无图标注册' : null;
        final toast = WinToast.instance();

        _winToastInitialized = await toast.initialize(
          aumId: aumid,
          displayName: Constants.appName,
          iconPath: iconPath,
          clsid: clsid,
        );
        await _writeToastLog(
          _winToastInitialized
              ? 'WinToast 注册成功：AUMID=$aumid, CLSID=$clsid'
              : 'WinToast 注册返回 false',
        );

        if (!_winToastInitialized && iconPath.isNotEmpty) {
          await _writeToastLog('带图标注册失败，重试无图标注册');
          _winToastInitialized = await toast.initialize(
            aumId: aumid,
            displayName: Constants.appName,
            iconPath: '',
            clsid: clsid,
          );
          await _writeToastLog(
            _winToastInitialized ? 'WinToast 无图标回退注册成功' : 'WinToast 无图标回退注册失败',
          );
        }
      } catch (error) {
        _winToastInitialized = false;
        _toastInitError = error.toString();
        await _writeToastLog('初始化失败：$error');
        debugPrint('[Windows 通知] 初始化失败：$error');
      }

      // ========== 步骤 3：设置激活回调（点击通知时触发） ==========
      if (_winToastInitialized) {
        WinToast.instance().setActivatedCallback((event) {
          unawaited(_writeToastLog('通知被点击：${event.argument}'));
          openConversationFromNotification(event.argument);
        });
      }
      if (!_winToastInitialized) {
        await _writeToastLog('WinToast 未初始化，继续使用 WindowsNotification/备用通知');
      }
      await _desktopNotifier.requestPermission();
      await WindowsNotification(applicationId: Constants.appAumid).init();
      await _desktopNotifier.setCallback((event) {
        if (event.event == NotificationEvent.activated) {
          openConversationFromNotification(event.arguments);
        }
      });

      await _writeToastLog(
        _winToastInitialized
            ? '初始化成功'
            : '初始化返回 false${_toastInitError == null ? '' : '：$_toastInitError'}',
      );
    }

    // 非 Windows 平台（Android）的初始化
    if (!Platform.isWindows) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      await _notifications.initialize(
        const InitializationSettings(android: androidSettings),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();
    }
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
    windowManager.show();
    windowManager.focus();
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
    if (Platform.isWindows) {
      final notificationId = 'oldchat-${DateTime.now().microsecondsSinceEpoch}';
      var shown = false;
      if (_winToastInitialized) {
        try {
          final toastPayload = _escapeXml(payload ?? '');
          final toast = Toast(
            launch: toastPayload,
            duration: ToastDuration.short,
            children: [
              ToastChildAudio(source: ToastAudioSource.defaultSound),
              ToastChildVisual(
                binding: ToastVisualBinding(
                  children: [
                    ToastVisualBindingChildText(text: title, id: 1),
                    ToastVisualBindingChildText(text: body, id: 2),
                  ],
                ),
              ),
            ],
          );
          await WinToast.instance().showToast(
            toast: toast,
            tag: notificationId,
            group: 'oldchat',
          );
          shown = true;
          await _writeToastLog('显示通知：$title（WinToast）');
        } catch (winToastError) {
          await _writeToastLog('WinToast 发送失败：$winToastError');
        }
      }
      if (!shown) {
        try {
          await WindowsNotification(
            applicationId: Constants.appAumid,
          ).showNotificationPluginTemplate(
            NotificationMessage.fromPluginTemplate(
              notificationId,
              title,
              body,
              launch: payload,
              group: 'oldchat',
              audio: const NotificationAudio(sound: NotificationSound.Default),
            ),
          );
          shown = true;
          await _writeToastLog('WindowsNotification 已显示：$title');
        } catch (windowsNotificationError) {
          await _writeToastLog(
            'WindowsNotification 发送失败：$windowsNotificationError',
          );
        }
      }
      if (!shown) {
        shown = await _showDesktopFallback(title, body, payload);
      }
      if (!shown) {
        await _writeToastLog('Windows 通知最终发送失败：$title');
      }
      if (withFlash && _taskbarFlashEnabled && !_windowIsVisible) {
        await NativeWindowService.flashTaskbar();
      }
      return;
    }

    // 非 Windows 平台（Android）通知
    if (!Platform.isWindows) {
      const androidDetails = AndroidNotificationDetails(
        'chat_channel',
        '聊天消息',
        channelDescription: '收到新消息时通知',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    }

    // 任务栏闪烁（窗口不可见时）
    if (withFlash && _taskbarFlashEnabled && !_windowIsVisible) {
      await NativeWindowService.flashTaskbar();
    }
  }

  Future<bool> _showDesktopFallback(
    String title,
    String body,
    String? payload,
  ) async {
    try {
      await _desktopNotifier.show(
        NotificationMessage.fromPluginTemplate(
          'oldchat-${DateTime.now().microsecondsSinceEpoch}',
          title,
          body,
          launch: payload,
          group: 'oldchat',
          audio: const NotificationAudio(sound: NotificationSound.Default),
        ),
      );
      await _writeToastLog('备用通知已显示：$title');
      return true;
    } catch (error) {
      await _writeToastLog('备用通知失败：$error');
      return false;
    }
  }

  /// 测试 Windows Toast 通知
  Future<void> testWindowsToast() async {
    await showNotification(
      title: AppLocalizations.current.t(Constants.appName),
      body: AppLocalizations.current.t('Windows 通知测试成功'),
      withFlash: true,
    );
    if (!_winToastInitialized) {
      await _writeToastLog(AppLocalizations.current.t('测试通知未发送：WinToast 未初始化'));
    }
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
    await showNotification(
      title: AppLocalizations.current.t('来自 $fromName 的消息'),
      body: display.length > 100 ? '${display.substring(0, 100)}...' : display,
      payload: payload,
      withFlash: withFlash,
    );
  }

  String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
