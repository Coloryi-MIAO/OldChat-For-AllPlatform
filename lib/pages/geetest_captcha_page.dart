import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_localizations.dart';
import '../utils/user_error.dart';

class GeeTestCaptchaPage extends StatefulWidget {
  final String pageUrl;

  const GeeTestCaptchaPage({super.key, required this.pageUrl});

  @override
  State<GeeTestCaptchaPage> createState() => _GeeTestCaptchaPageState();
}

class _GeeTestCaptchaPageState extends State<GeeTestCaptchaPage> {
  late final WebViewController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (mounted) setState(() => _error = '${AppLocalizations.current.t('人机验证加载失败')}：${error.description}');
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(widget.pageUrl));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.current.t('人机验证')),
      content: SizedBox(
        width: 520,
        height: 620,
        child: _error == null
            ? WebViewWidget(controller: _controller)
            : Center(child: Text(_error!, textAlign: TextAlign.center)),
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
