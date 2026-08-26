import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../utils/file_picker_compat.dart';
import '../utils/constants.dart';
import '../services/auth_service.dart';
import '../services/account_storage.dart';
import '../services/aria2_service.dart';
import '../services/cache_service.dart';
import '../services/theme_service.dart';
import '../services/language_service.dart';
import '../services/app_localizations.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../services/image_cache_service.dart';
import '../services/diagnostics_service.dart';
import '../services/startup_service.dart';
import 'about_page.dart';
import 'plugin_center_page.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _cacheSize = '计算中...';
  bool _showAria2 = false;
  final _aria2EndpointController = TextEditingController();
  final _aria2SecretController = TextEditingController();

  // 关闭窗口设置
  bool _closeConfirmEnabled = true;
  bool _closeMinimizeToTray = false;
  bool _desktopNotificationsEnabled = true;
  bool _taskbarFlashEnabled = true;
  bool _multiSessionReceptionEnabled = true;
  bool _messageOrderCorrectionEnabled = true;
  bool _autoUpdateEnabled = true;
  bool _launchAtStartup = false;
  String _apiVersion = Constants.apiVersion;
  double _splashDuration = 5.0;
  String _language = 'zh';
  final _serverController = TextEditingController();
  final _customServersController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheInfo();
  }

  @override
  void dispose() {
    _aria2EndpointController.dispose();
    _aria2SecretController.dispose();
    _serverController.dispose();
    _customServersController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await AccountStorage.instance.load();
    final storage = AccountStorage.instance;
    final launchAtStartup = await StartupService.isEnabled();
    if (!mounted) return;
    setState(() {
      _closeConfirmEnabled = storage.getBool('close_confirm_enabled') ?? true;
      _closeMinimizeToTray = storage.getBool('close_minimize_to_tray') ?? false;
      _desktopNotificationsEnabled =
          storage.getBool(Constants.desktopNotificationsKey) ?? true;
      _taskbarFlashEnabled = storage.getBool(Constants.taskbarFlashKey) ?? true;
      _multiSessionReceptionEnabled =
          storage.getBool(Constants.multiSessionReceptionKey) ?? true;
      _messageOrderCorrectionEnabled =
          storage.getBool(Constants.messageOrderCorrectionKey) ?? true;
      _autoUpdateEnabled = storage.getBool(Constants.autoUpdateKey) ?? true;
      _launchAtStartup = launchAtStartup;
      _apiVersion = 'v2';
      _showAria2 = storage.getBool('aria2_show_settings') ?? false;
      _splashDuration =
          (storage.getDouble(Constants.splashDurationKey) ??
                  storage.getInt(Constants.splashDurationKey)?.toDouble() ??
                  5.0)
              .clamp(2.0, 5.0)
              .toDouble();
      _language = storage.getString(Constants.languageKey) ?? 'zh';
      _serverController.text = Constants.baseUrl;
      _customServersController.text = Constants.visibleServers
          .skip(2)
          .join('\n');
    });
    final settings = await Aria2Service().settings();
    _aria2EndpointController.text =
        settings['endpoint'] ?? Aria2Service.defaultEndpoint;
    _aria2SecretController.text = settings['secret'] ?? '';
  }

  Future<void> _loadCacheInfo() async {
    final bytes = await CacheService().sizeBytes();
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final count = await CacheService().count;
    if (!mounted) return;
    setState(() => _cacheSize = '$count 个文件，共 $mb MB');
  }

  Future<void> _clearCache() async {
    try {
      await CacheService().clearClientCache();
      ImageCacheService.instance.clear();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _loadCacheInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.current.t('缓存已清除')),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('清除缓存失败：$error'))),
        );
      }
    }
  }

  Future<void> _chooseCacheLocation() async {
    final result = await getDirectoryPathCompat();
    if (result != null) {
      await CacheService().setLocation(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.current.t('缓存位置已设置为 $result')),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _saveAria2Settings() async {
    await Aria2Service().saveSettings(
      endpoint: _aria2EndpointController.text,
      secret: _aria2SecretController.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.current.t('Aria2 设置已保存')),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _editSplashDuration() async {
    final controller = TextEditingController(text: _splashDuration.toString());
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr.splashDuration),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: context.tr.text(
              '输入 2–5 秒的小数',
              'Enter a decimal between 2 and 5 seconds',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()),
            ),
            child: Text(context.tr.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !value.isFinite || value < 2 || value > 5) {
      if (mounted && value != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr.text(
                '请输入 2–5 之间的小数',
                'Enter a number between 2 and 5',
              ),
            ),
          ),
        );
      }
      return;
    }
    await AccountStorage.instance.setDouble(Constants.splashDurationKey, value);
    if (mounted) setState(() => _splashDuration = value);
  }

  Future<void> _checkUpdate() async {
    final service = UpdateService();
    try {
      final current = await service.currentVersion();
      final release = await service.available(UpdateChannel.stable);
      if (!mounted) return;
      if (release == null) {
        _showAlert('已是最新版本', '当前版本：$current');
        return;
      }
      await UpdateDialog.show(
        context,
        release: release,
        currentVersion: current,
      );
    } catch (error) {
      if (mounted) _showAlert('检查更新失败', error.toString());
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.current.t('确定')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final theme = Provider.of<AppThemeController>(context);
    final language = context.watch<LanguageController>();
    final tr = context.tr;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.settings),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _animatedCategory(context.tr.t('通用'), Icons.tune, [
            _buildFontSetting(theme, primary),
            _buildApiVersionSetting(primary),
            _buildServerSettings(primary),
            _buildChoiceTile(
              icon: Icons.language,
              title: tr.language,
              subtitle: _language == 'zh' ? context.tr.chinese : context.tr.english,
              options: [context.tr.chinese, context.tr.english],
              selectedIndex: _language == 'zh' ? 0 : 1,
              onSelected: (index) async {
                final value = index == 0 ? 'zh' : 'en';
                setState(() => _language = value);
                await context.read<LanguageController>().setLanguage(value);
              },
            ),
          ], 0),
          SizedBox(height: 12),
          _animatedCategory(context.tr.t('外观'), Icons.palette_outlined, [
            _buildSwitchTile(
              icon: Icons.favorite,
              title: AppLocalizations.current.t('粉色主题'),
              subtitle: AppLocalizations.current.t('启用粉色主题配色'),
              value: theme.isPink,
              onChanged: (v) => theme.setPink(v),
            ),
            _buildScaleSetting(theme, primary),
          ], 1),
          const SizedBox(height: 12),
          _animatedCategory(context.tr.t('通知'), Icons.notifications_none, [
            _buildSwitchTile(
              icon: Icons.notifications,
              title: AppLocalizations.current.t('桌面通知'),
              subtitle: context.tr.text(
                '根据系统显示通知（Windows Toast、macOS/Linux 桌面通知、Android/iOS 通知或浏览器通知）',
                'Use the system notification channel: Windows Toast, macOS/Linux desktop, Android/iOS, or browser notifications',
              ),
              value: _desktopNotificationsEnabled,
              onChanged: (v) async {
                setState(() => _desktopNotificationsEnabled = v);
                await NotificationService().setEnabled(v);
              },
            ),
            _buildSwitchTile(
              icon: Icons.task_alt,
              title: context.tr.t('任务栏闪动通知'),
              subtitle: context.tr.text(
                '窗口最小化时闪动任务栏图标',
                'Flash the taskbar icon when minimized',
              ),
              value: _taskbarFlashEnabled,
              onChanged: (value) async {
                setState(() => _taskbarFlashEnabled = value);
                await NotificationService().setTaskbarFlashEnabled(value);
              },
            ),
            _buildInfoTile(
              icon: Icons.notifications_active_outlined,
              title: context.tr.t('测试 Windows 通知'),
              subtitle: context.tr.text(
                '发送一条测试通知并写入持久日志',
                'Send a test notification and write a persistent log',
              ),
              onTap: () async {
                await NotificationService().testWindowsToast();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr.t('Windows 通知已发送'))),
                  );
                }
              },
            ),
          ], 2),
          const SizedBox(height: 12),
          _animatedCategory(context.tr.t('消息'), Icons.forum_outlined, [
            _buildSwitchTile(
              icon: Icons.all_inbox_outlined,
              title: context.tr.t('多会话消息接收'),
              subtitle: context.tr.text(
                '后台接收所有会话的消息',
                'Receive messages from all conversations in the background',
              ),
              value: _multiSessionReceptionEnabled,
              onChanged: (value) async {
                setState(() => _multiSessionReceptionEnabled = value);
                await AccountStorage.instance.setBool(
                  Constants.multiSessionReceptionKey,
                  value,
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.sort,
              title: context.tr.t('消息排序修正'),
              subtitle: context.tr.text(
                '按服务端时间、序号和消息 ID 排序',
                'Sort by server time, sequence, and message ID',
              ),
              value: _messageOrderCorrectionEnabled,
              onChanged: (value) async {
                setState(() => _messageOrderCorrectionEnabled = value);
                await AccountStorage.instance.setBool(
                  Constants.messageOrderCorrectionKey,
                  value,
                );
              },
            ),
          ], 8),
          const SizedBox(height: 12),
          _animatedCategory(context.tr.t('窗口'), Icons.window, [
            _buildSwitchTile(
              icon: Icons.close,
              title: AppLocalizations.current.t('关闭时确认'),
              subtitle: AppLocalizations.current.t('关闭窗口时弹出确认对话框'),
              value: _closeConfirmEnabled,
              onChanged: (v) {
                setState(() => _closeConfirmEnabled = v);
                AccountStorage.instance.setBool('close_confirm_enabled', v);
              },
            ),
            if (!_closeConfirmEnabled)
              _buildChoiceTile(
                icon: Icons.minimize,
                title: AppLocalizations.current.t('关闭操作'),
                subtitle: _closeMinimizeToTray ? '最小化到系统托盘' : '直接退出程序',
                options: ['直接退出', '最小化到托盘'],
                selectedIndex: _closeMinimizeToTray ? 1 : 0,
                onSelected: (index) {
                  final minimize = index == 1;
                  setState(() => _closeMinimizeToTray = minimize);
                  AccountStorage.instance.setBool(
                    'close_minimize_to_tray',
                    minimize,
                  );
                  AccountStorage.instance.setString(
                    'exit_close_action',
                    minimize ? 'minimize' : 'exit',
                  );
                },
              ),
          ], 3),
          SizedBox(height: 12),
          _animatedCategory(context.tr.t('存储'), Icons.storage, [
            _buildInfoTile(
              icon: Icons.cached,
              title: AppLocalizations.current.t('缓存大小'),
              subtitle: _cacheSize,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _clearCache,
                    child: Text(
                      AppLocalizations.current.t('清除缓存'),
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _chooseCacheLocation,
                    child: Text(
                      AppLocalizations.current.t('选择位置'),
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ], 4),
          const SizedBox(height: 12),
          _animatedCategory(context.tr.t('下载'), Icons.download, [
            _buildSwitchTile(
              icon: Icons.settings_ethernet,
              title: AppLocalizations.current.t('Aria2 设置'),
              subtitle: AppLocalizations.current.t('显示高级下载设置'),
              value: _showAria2,
              onChanged: (v) {
                setState(() => _showAria2 = v);
                AccountStorage.instance.setBool('aria2_show_settings', v);
              },
            ),
            if (_showAria2) ...[
              _buildTextInputTile(
                icon: Icons.link,
                title: AppLocalizations.current.t('端点'),
                controller: _aria2EndpointController,
                hint: Aria2Service.defaultEndpoint,
              ),
              _buildTextInputTile(
                icon: Icons.key,
                title: AppLocalizations.current.t('密钥'),
                controller: _aria2SecretController,
                hint: '留空则不使用密钥',
                obscure: true,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 8),
                child: ElevatedButton.icon(
                  onPressed: _saveAria2Settings,
                  icon: const Icon(Icons.save, size: 16),
                  label: Text(AppLocalizations.current.t('保存 Aria2 设置')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ], 5),
          SizedBox(height: 12),
          _animatedCategory(context.tr.t('插件'), Icons.extension_outlined, [
            _buildInfoTile(
              icon: Icons.extension_outlined,
              title: AppLocalizations.current.t('插件中心'),
              subtitle: AppLocalizations.current.t('管理自动回复、红包助手和审核队列'),
              onTap: _openPluginCenter,
            ),
          ], 6),
          const SizedBox(height: 12),
          _animatedCategory(context.tr.t('信息'), Icons.info_outline, [
            _buildSwitchTile(
              icon: Icons.system_update_alt,
              title: AppLocalizations.current.t('自动检查更新'),
              subtitle: AppLocalizations.current.t('启动应用后在后台检查新版本'),
              value: _autoUpdateEnabled,
              onChanged: (value) async {
                setState(() => _autoUpdateEnabled = value);
                await AccountStorage.instance.setBool(
                  Constants.autoUpdateKey,
                  value,
                );
              },
            ),
            _buildInfoTile(
              icon: Icons.update,
              title: AppLocalizations.current.t('检查更新'),
              subtitle: AppLocalizations.current.t('点击检查是否有新版本'),
              onTap: _checkUpdate,
            ),
            _buildInfoTile(
              icon: Icons.bug_report,
              title: AppLocalizations.current.t('环境诊断'),
              subtitle: AppLocalizations.current.t('查看系统环境信息'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            _buildInfoTile(
              icon: Icons.dns,
              title: AppLocalizations.current.t('DNS 缓存'),
              subtitle: AppLocalizations.current.t('清除系统 DNS 缓存'),
              onTap: () async {
                await DiagnosticsService.clearDnsCache();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.current.t('DNS 缓存已清除')),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            _buildInfoTile(
              icon: Icons.logout,
              title: AppLocalizations.current.t('退出登录'),
              subtitle: AppLocalizations.current.t('清除登录状态并返回登录页'),
              danger: true,
              onTap: () async {
                await context.read<AuthService>().clear();
                if (mounted)
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/', (route) => false);
              },
            ),
            _buildInfoTile(
              icon: Icons.key_outlined,
              title: context.tr.t('复制当前用户 Authorization'),
              subtitle: 'Bearer <token>',
              onTap: _copyAuthorizationToken,
            ),
          ], 7),
          const SizedBox(height: 12),
          _animatedCategory(context.tr.t('启动'), Icons.hourglass_bottom, [
            _buildSwitchTile(
              icon: Icons.power_settings_new,
              title: context.tr.t('开机自启动'),
              subtitle: context.tr.t('通过当前用户注册表自动检查并启动 OldChat'),
              value: _launchAtStartup,
              onChanged: (value) async {
                final previous = _launchAtStartup;
                setState(() => _launchAtStartup = value);
                try {
                  await StartupService.setEnabled(value);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr.text(
                            '开机自启动已更新',
                            'Startup setting updated',
                          ),
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    setState(() => _launchAtStartup = previous);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${context.tr.t('开机自启动设置失败')}: $error'),
                      ),
                    );
                  }
                }
              },
            ),
            _buildInfoTile(
              icon: Icons.timer_outlined,
              title: tr.splashDuration,
              subtitle: tr.splashSeconds(_splashDuration),
              onTap: _editSplashDuration,
            ),
          ], 1),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _animatedCategory(
    String title,
    IconData icon,
    List<Widget> children, [
    int index = 0,
  ]) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 55),
      curve: Curves.easeOutCubic,
      child: _buildCategory(title, icon, children),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCategory(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Theme.of(context).cardColor,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.withOpacity(0.15)),
            ),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildFontSetting(AppThemeController theme, Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.font_download_outlined, size: 22, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '字体',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                DropdownButtonFormField<String>(
                  value: theme.fontFamily,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'HarmonyOS Sans SC',
                      child: Text(context.tr.harmonyFont),
                    ),
                    DropdownMenuItem(
                      value: 'Microsoft YaHei',
                      child: Text(context.tr.yaheiFont),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) theme.setFontFamily(value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerSettings(Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr.t('首选服务器'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr.t('主要服务器与备用服务器；隐藏备用地址仅用于自动故障回退，不显示地址。'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${Constants.baseUrl}:${Constants.visibleServers.join('|')}',
            ),
            value: Constants.visibleServers.contains(Constants.baseUrl)
                ? Constants.baseUrl
                : Constants.defaultBaseUrl,
            items: Constants.visibleServers
                .map(
                  (server) => DropdownMenuItem(
                    value: server,
                    child: Text(
                      server,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              await Constants.saveBaseUrl(value);
              if (mounted) setState(() => _serverController.text = value);
            },
            decoration: InputDecoration(
              labelText: context.tr.t('选择服务器'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _serverController,
            decoration: InputDecoration(
              labelText: context.tr.t('当前服务器地址'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) async {
              await Constants.saveBaseUrl(value);
              if (mounted)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(context.tr.t('服务器已保存'))));
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customServersController,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: context.tr.t('自定义服务器（每行一个）'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) =>
                Constants.saveCustomServers(value.split(RegExp(r'[\r\n,]+'))),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Constants.resetAccountSettings();
                if (mounted) {
                  setState(() {
                    _serverController.text = Constants.defaultBaseUrl;
                    _customServersController.clear();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr.t('设置已恢复默认'))),
                  );
                }
              },
              icon: const Icon(Icons.restore),
              label: Text(context.tr.t('恢复默认设置')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiVersionSetting(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.api_outlined, size: 22, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'API 路径版本',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                DropdownButtonFormField<String>(
                  value: _apiVersion,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'v2',
                      child: Text(AppLocalizations.current.t('v2（默认）')),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _apiVersion = 'v2');
                    await Constants.saveApiVersion('v2');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildChoiceTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<String> options,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<int>(
              value: selectedIndex,
              isExpanded: true,
              menuMaxHeight: 620,
              items: List.generate(
                options.length,
                (i) => DropdownMenuItem<int>(
                  value: i,
                  child: Text(options[i], overflow: TextOverflow.ellipsis),
                ),
              ),
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final primary = Theme.of(context).primaryColor;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: danger ? Colors.red : null,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInputTile({
    required IconData icon,
    required String title,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: title,
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScaleSetting(AppThemeController theme, Color primary) {
    final percent = (theme.scaleFactor * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.zoom_in, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.tr.text('界面缩放', 'Interface scale')),
              ),
              Text('$percent%'),
            ],
          ),
          Slider(
            value: theme.scaleFactor,
            min: 0.5,
            max: 5.0,
            divisions: 90,
            label: '$percent%',
            onChanged: (value) => theme.setScaleFactor(value),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAuthorizationToken() async {
    final token = context.read<AuthService>().token?.trim() ?? '';
    if (token.isEmpty) {
      _showAlert(
        context.tr.t('复制 Token'),
        context.tr.t('当前没有可复制的登录 Token'),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: 'Bearer $token'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.t('Authorization 已复制'))),
      );
    }
  }

  void _openPluginCenter() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PluginCenterPage()));
  }
}
