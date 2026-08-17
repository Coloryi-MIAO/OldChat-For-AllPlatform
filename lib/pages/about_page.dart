import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/cache_service.dart';
import '../services/environment_service.dart';
import '../services/update_service.dart';
import '../services/auth_service.dart';
import '../widgets/update_dialog.dart';
import '../utils/constants.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '1.4.0+5';
  EnvironmentSnapshot? _environment;
  bool _checking = false;
  String _updateMessage = '尚未检查更新';

  @override
  void initState() {
    super.initState();
    _loadEnvironment();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        final build = info.buildNumber.trim();
        final version = build.isEmpty
            ? info.version
            : '${info.version}+${build.replaceFirst(RegExp(r'^\+'), '')}';
        setState(() => _version = version);
      }
    } catch (_) {}
  }

  Future<void> _loadEnvironment() async {
    try {
      final auth = AuthService();
      final uid = auth.userId ?? 'guest';
      final path = await CacheService().cacheDirectory(userId: uid);
      final snapshot = await EnvironmentService().inspect(cachePath: path);
      if (mounted) setState(() => _environment = snapshot);
    } catch (_) {}
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateMessage = '正在检查 GitHub 最新版本…';
    });
    try {
      final release = await UpdateService().availableForCurrentWindows(
        UpdateChannel.stable,
      );
      if (!mounted) return;
      if (release == null) {
        setState(() => _updateMessage = '当前已是最新版本');
      } else {
        setState(() => _updateMessage = '发现新版本 ${release.tagName}');
        await UpdateDialog.show(
          context,
          release: release,
          currentVersion: _version,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _updateMessage = '检查失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final tr = context.tr;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr.text(
            '关于 ${Constants.appName}（OCFW）',
            'About ${Constants.appName} (OCFW)',
          ),
        ),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '${Constants.appName} · OCFW',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(tr.text('版本 $_version', 'Version $_version')),
                const SizedBox(height: 24),
                Text(
                  tr.text(
                    '由 Coloryi-MIAO 开发的 Windows Flutter 聊天客户端，基于 OldChat 服务端.',
                    'A Windows Flutter chat client by Coloryi-MIAO, powered by the OldChat server.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr.text('客户端环境监测', 'Client environment'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_environment == null)
                          const LinearProgressIndicator()
                        else ...[
                          Text(AppLocalizations.current.t('系统：${_environment!.operatingSystem}')),
                          Text(
                            '模式：${_environment!.buildMode} · ${_environment!.architecture}',
                          ),
                          Text(AppLocalizations.current.t('缓存：${_environment!.cacheBytes} bytes')),
                          Text(
                            '缓存目录：${_environment!.cachePath}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'WebView2：${_environment!.webView2Installed ? '可用' : '未确认'} · Media Kit：${_environment!.mediaKitConfigured ? '已配置' : '不可用'}',
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _loadEnvironment,
                            icon: const Icon(Icons.refresh),
                            label: Text(tr.text('重新检测', 'Recheck')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.system_update),
                    title: Text(tr.update),
                    subtitle: Text(_updateMessage),
                    trailing: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _checking ? null : _checkForUpdate,
                  ),
                ),
                const SizedBox(height: 18),
                _row('默认服务器', '60.205.94.101:8080'),
                _row('开发者', 'Coloryi-MIAO'),
                _row('开源协议', 'MIT License'),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://github.com/Coloryi-MIAO/OldChat-For-AllPlatform',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(tr.text('打开 GitHub 项目', 'Open GitHub project')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
