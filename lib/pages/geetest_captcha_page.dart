import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_localizations.dart';

class GeeTestCaptchaPage extends StatelessWidget {
  final String pageUrl;

  const GeeTestCaptchaPage({super.key, required this.pageUrl});

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('无法打开系统浏览器'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return AlertDialog(
      title: Text(AppLocalizations.current.t('人机验证')),
      content: SizedBox(
        width: 430,
        child: Text(
          AppLocalizations.current.t(
            isWindows
                ? 'Windows 7 版本不内置 WebView2，请在系统浏览器完成验证后返回应用。'
                : '请在系统浏览器完成验证后返回应用。',
          ),
          textAlign: TextAlign.center,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => _openInBrowser(context),
          child: Text(AppLocalizations.current.t('在浏览器中打开')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.current.t('取消')),
        ),
      ],
    );
  }
}
