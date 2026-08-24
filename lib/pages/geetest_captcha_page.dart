import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../utils/user_error.dart';
import 'package:url_launcher/url_launcher.dart';

class GeeTestCaptchaPage extends StatefulWidget {
  final String pageUrl;

  const GeeTestCaptchaPage({super.key, required this.pageUrl});

  @override
  State<GeeTestCaptchaPage> createState() => _GeeTestCaptchaPageState();
}

class _GeeTestCaptchaPageState extends State<GeeTestCaptchaPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final uri = Uri.tryParse(widget.pageUrl);
      if (uri == null) throw const FormatException('invalid captcha URL');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('unable to open system browser');
      if (mounted) {
        setState(() => _error = AppLocalizations.current.t('验证页面已在系统浏览器打开，完成后返回注册页'));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '${AppLocalizations.current.t('人机验证加载失败')}：${safeErrorMessage(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.current.t('人机验证')),
      content: SizedBox(
        width: 430,
        height: 180,
        child: Center(
          child: Text(
            _error ?? AppLocalizations.current.t('正在打开人机验证页面，请在系统浏览器中完成验证后返回'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.current.t('取消')),
        ),
      ],
    );
  }
}
