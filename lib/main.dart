import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'services/image_cache_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'widgets/tray_manager.dart';
import 'services/auth_service.dart';
import 'services/account_storage.dart';
import 'services/notification_service.dart';
import 'services/audio_service.dart';
import 'widgets/custom_title_bar.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_profile_page.dart';
import 'pages/moments_page.dart';
import 'pages/emoji_plaza_page.dart';
import 'pages/notifications_page.dart';
import 'pages/checkin_wall_page.dart';
import 'pages/ai_chat_page.dart';
import 'pages/favorites_page.dart';
import 'pages/about_page.dart';
import 'pages/settings_page.dart';
import 'pages/chat_page.dart';
import 'pages/public_court_page.dart';
import 'pages/tools_hub_page.dart';
import 'pages/channel_page.dart';
import 'pages/scratch_card_page.dart';
import 'pages/plugin_center_page.dart';
import 'pages/cip_page.dart';
import 'pages/request_list_page.dart';
import 'utils/navigation.dart';
import 'utils/constants.dart';
import 'services/theme_service.dart';
import 'services/language_service.dart';
import 'services/app_localizations.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'widgets/update_dialog.dart';
import 'services/startup_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  await StartupService.cleanupOnStartup();
  ImageCacheService.configure();
  VideoPlayerMediaKit.ensureInitialized(
    android: true,
    iOS: true,
    macOS: true,
    windows: true,
    linux: true,
    web: false,
  );

  final auth = AuthService();
  await auth.loadFromStorage();
  await AccountStorage.instance.load(userId: auth.userId);
  await Constants.loadBaseUrl();
  final themeController = AppThemeController();
  await themeController.load();

  if (desktop) {
    // 单例检测
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      Constants.appAumid,
      onSecondWindow: (secondArgs) {
        NotificationService.handleLaunchArguments(secondArgs);
        print('第二个实例启动: $secondArgs');
      },
    );

    await windowManager.ensureInitialized();

    // 全局音频服务初始化
    await AudioService().init();

    // 窗口关闭事件监听
    await windowManager.setPreventClose(true);
    windowManager.addListener(_WindowCloseListener());

    const windowOptions = WindowOptions(
      size: Size(1100, 700),
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      fullScreen: false,
    );
    await windowManager.setTitle(Constants.appName);
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    final notificationService = NotificationService();
    try {
      await notificationService.init();
    } catch (error) {
      debugPrint('[通知] 初始化隔离：$error');
    }

    runApp(
      TrayManager(
        child: MyApp(
          auth: auth,
          notificationService: notificationService,
          themeController: themeController,
        ),
      ),
    );
  } else {
    final notificationService = NotificationService();
    try {
      await notificationService.init();
    } catch (error) {
      debugPrint('[通知] 初始化隔离：$error');
    }

    runApp(MyApp(
      auth: auth,
      notificationService: notificationService,
      themeController: themeController,
    ));
  }
}

class _WindowCloseListener extends WindowListener {
  bool _handlingClose = false;
  bool _minimizedToTray = false;

  @override
  void onWindowClose() {
    if (_handlingClose || _minimizedToTray) return;
    _handlingClose = true;
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    try {
      await AccountStorage.instance.load();
      final storage = AccountStorage.instance;
      final confirm = storage.getBool('close_confirm_enabled') ?? true;
      final savedAction = (storage.getBool('close_minimize_to_tray') ?? false)
          ? 'minimize'
          : (storage.getString('exit_close_action') ?? 'exit');
      if (!confirm) {
        await _applyCloseAction(savedAction == 'minimize');
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) {
        await _applyCloseAction(savedAction == 'minimize');
        return;
      }
      var dontShowAgain = false;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('${context.tr.t('关闭')} ${Constants.appName}'),
            content: Row(
              children: [
                Checkbox(
                  value: dontShowAgain,
                  onChanged: (value) =>
                      setDialogState(() => dontShowAgain = value ?? false),
                ),
                Expanded(child: Text(context.tr.t('不再提示'))),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'cancel'),
                child: Text(context.tr.t('取消')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'minimize'),
                child: Text(context.tr.t('最小化到托盘')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'exit'),
                child: Text(context.tr.t('直接关闭')),
              ),
            ],
          ),
        ),
      );
      if (action == null || action == 'cancel') return;
      if (dontShowAgain) {
        await storage.setBool('exit_dont_show_again', true);
        await storage.setBool('close_confirm_enabled', false);
      }
      await storage.setString('exit_close_action', action);
      await storage.setBool('close_minimize_to_tray', action == 'minimize');
      await _applyCloseAction(action == 'minimize');
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _applyCloseAction(bool minimize) async {
    if (minimize) {
      _minimizedToTray = true;
      await windowManager.setPreventClose(true);
      await windowManager.hide();
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowFocus() {
    NotificationService.setWindowVisible(true);
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') {
      _minimizedToTray = true;
      NotificationService.setWindowVisible(false);
    }
    if (eventName == 'show' || eventName == 'restore') {
      _minimizedToTray = false;
      NotificationService.setWindowVisible(true);
    }
  }

  @override
  void onWindowBlur() {
    NotificationService.setWindowVisible(true);
  }

  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowMove() {}
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _visible = true;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visible = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkAutomaticUpdate());
    });
  }

  Future<void> _checkAutomaticUpdate() async {
    if (_updateChecked || !AuthService().isLoggedIn || !mounted) return;
    _updateChecked = true;
    await AccountStorage.instance.load();
    if (!(AccountStorage.instance.getBool(Constants.autoUpdateKey) ?? true) || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    try {
      final service = UpdateService();
      final release = await service.availableForCurrentWindows(
        UpdateChannel.stable,
      );
      if (!mounted || release == null) return;
      final current = await service.currentVersion();
      if (!mounted) return;
      await UpdateDialog.show(
        context,
        release: release,
        currentVersion: current,
      );
    } catch (error) {
      debugPrint('[自动更新] 检查失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthService>().isLoggedIn;
    return Stack(
      fit: StackFit.expand,
      children: [
        isLoggedIn ? const HomePage() : const LoginPage(),
        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 360),
            child: const ColoredBox(
              color: Color(0xFFFFF5FA),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image(
                      image: AssetImage('assets/app_icon.png'),
                      width: 72,
                      height: 72,
                    ),
                    SizedBox(height: 14),
                    Text(
                      Constants.appName,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(width: 120, child: LinearProgressIndicator()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MyApp extends StatelessWidget {
  final AuthService auth;
  final NotificationService notificationService;
  final AppThemeController themeController;

  const MyApp({
    super.key,
    required this.auth,
    required this.notificationService,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider.value(value: notificationService),
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider<LanguageController>(
          create: (_) => LanguageController()..load(),
        ),
      ],
      child: Consumer<AppThemeController>(
        builder: (context, themeController, _) => MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          title: Constants.appName,
          debugShowCheckedModeBanner: false,
          locale: Locale(context.watch<LanguageController>().language),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.build(
            pink: themeController.isPink,
            fontFamily: themeController.fontFamily,
            pluginTheme: themeController.pluginTheme,
          ),
          home: const _StartupGate(),
          routes: {
            '/profile': (context) => const ProfilePage(),
            '/user_profile': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              final uid = args is String ? args : '';
              if (uid.isEmpty) return const ProfilePage();
              return UserProfilePage(uid: uid);
            },
            '/moments': (context) => const MomentsPage(),
            '/user_moments': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              final uid = args is String ? args : null;
              return MomentsPage(uid: uid);
            },
            '/emoji_plaza': (context) => const EmojiPlazaPage(),
            '/notifications': (context) => const NotificationsPage(),
            '/checkin_wall': (context) => const CheckinWallPage(),
            '/ai_chat': (context) => const AIChatPage(),
            '/favorites': (context) => const FavoritesPage(),
            '/about': (context) => const AboutPage(),
            '/settings': (context) => const SettingsPage(),
            '/chat': (context) {
              final raw = ModalRoute.of(context)?.settings.arguments;
              final args = raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : const <String, dynamic>{};
              return ChatPage(
                conversationId: args['uid']?.toString() ?? '',
                type: args['type']?.toString() ?? 'direct',
                title: args['title']?.toString() ?? context.tr.t('聊天'),
                embed: false,
              );
            },
            '/public_court': (context) => const PublicCourtPage(),
            '/tools': (context) => const ToolsHubPage(),
            '/more': (context) => const ToolsHubPage(more: true),
            '/channels': (context) => const ChannelDiscoveryPage(),
            '/scratch': (context) => const ScratchCardPage(),
            '/plugins': (context) => const PluginCenterPage(),
            '/cip': (context) => const CipPage(),
            '/friend_requests': (context) => const RequestListPage(),
            '/group_requests': (context) => const RequestListPage(groups: true),
          },
          builder: (context, child) {
            final isLogin = ModalRoute.of(context)?.settings.name == '/';
            if (isLogin) return child!;
            if (kIsWeb || !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return child!;
            return Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                const SizedBox(height: 40, child: CustomTitleBar()),
                Expanded(child: child!),
              ],
            );
          },
        ),
      ),
    );
  }
}
