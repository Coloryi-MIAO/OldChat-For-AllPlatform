import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../services/auth_service.dart';
import '../services/app_localizations.dart';
import '../utils/navigation.dart';
import '../pages/login_page.dart';

class TrayManager extends StatefulWidget {
  final Widget child;
  const TrayManager({super.key, required this.child});

  @override
  State<TrayManager> createState() => _TrayManagerState();
}

class _TrayManagerState extends State<TrayManager> with TrayListener {
  bool _isQuitting = false;
  bool _trayInitialized = false;
  Timer? _healthCheckTimer;
  int _reinitAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTray();
      _startHealthCheck();
    });
    trayManager.addListener(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _healthCheckTimer?.cancel();
    super.dispose();
  }

  String _getIconPath(String fileName) {
    final devPath = 'assets/$fileName';
    if (File(devPath).existsSync()) return devPath;
    final exeDir = File(Platform.resolvedExecutable).parent;
    final prodPath = '${exeDir.path}/data/flutter_assets/assets/$fileName';
    if (File(prodPath).existsSync()) return prodPath;
    final cwdPath = '${Directory.current.path}/assets/$fileName';
    if (File(cwdPath).existsSync()) return cwdPath;
    return devPath;
  }

  Future<void> _initTray() async {
    if (_trayInitialized) return;
    try {
      String iconPath = Platform.isWindows
          ? _getIconPath('app_icon.ico')
          : _getIconPath('app_icon.png');
      if (!File(iconPath).existsSync()) {
        final fallback = Platform.isWindows
            ? _getIconPath('app_icon.png')
            : _getIconPath('app_icon.ico');
        if (File(fallback).existsSync()) iconPath = fallback;
      }
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('OldChat');

      final menu = Menu(
        items: [
          MenuItem(key: 'show_window', label: AppLocalizations.current.t('显示窗口')),
          MenuItem(key: 'hide_window', label: AppLocalizations.current.t('隐藏窗口')),
          MenuItem.separator(),
          MenuItem(key: 'logout', label: AppLocalizations.current.t('退出登录')),
          MenuItem(key: 'exit_app', label: AppLocalizations.current.t('退出')),
        ],
      );
      await trayManager.setContextMenu(menu);

      _trayInitialized = true;
      _reinitAttempts = 0;
      print('Tray: 初始化成功');
    } catch (e) {
      print('Tray: 初始化失败: $e');
      _trayInitialized = false;
      Future.delayed(const Duration(seconds: 3), () {
        if (!_trayInitialized && mounted) _initTray();
      });
    }
  }

  Future<void> _checkTrayHealth() async {
    if (_isQuitting || !mounted) return;
    try {
      await trayManager.setToolTip('OldChat');
    } catch (e) {
      print('Tray: 健康检查失败: $e');
      _trayInitialized = false;
      _reinitAttempts++;
      if (_reinitAttempts < 10) await _initTray();
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isQuitting && mounted) _checkTrayHealth();
    });
  }

  @override
  void onTrayIconMouseDown() {
    if (!_trayInitialized || _isQuitting) return;
    windowManager.isVisible().then((visible) {
      if (visible)
        windowManager.hide();
      else {
        windowManager.show();
        windowManager.focus();
      }
    }).catchError((e) {
      print('Tray: 左键异常: $e');
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!_trayInitialized || _isQuitting) return;
    trayManager.popUpContextMenu().catchError((e) {
      print('Tray: 右键菜单失败: $e');
      _trayInitialized = false;
      unawaited(_initTray());
    });
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (!_trayInitialized || _isQuitting) return;
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        windowManager.focus();
        break;
      case 'hide_window':
        windowManager.hide();
        break;
      case 'logout':
        _logout();
        break;
      case 'exit_app':
        _quitApp();
        break;
    }
  }

  void _logout() {
    print('Tray: 退出登录');
    AuthService().clear().then((_) {
      windowManager.hide();
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        Navigator.of(ctx).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }).catchError((e) {
      print('Tray: 退出登录失败: $e');
    });
  }

  void _quitApp() {
    if (_isQuitting) return;
    _isQuitting = true;
    print('Tray: 执行退出程序');
    _healthCheckTimer?.cancel();
    // 销毁托盘
    try {
      trayManager.destroy();
    } catch (_) {}

    // ★★★ 真正退出进程 ★★★
    windowManager.destroy().then((_) {
      exit(0);
    }).catchError((_) {
      exit(0);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
