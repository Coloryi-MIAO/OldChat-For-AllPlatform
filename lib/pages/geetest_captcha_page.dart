import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../utils/user_error.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;

class GeeTestCaptchaPage extends StatefulWidget {
  final String pageUrl;

  const GeeTestCaptchaPage({super.key, required this.pageUrl});

  @override
  State<GeeTestCaptchaPage> createState() => _GeeTestCaptchaPageState();
}

class _GeeTestCaptchaPageState extends State<GeeTestCaptchaPage> {
  final _controller = WebviewController();
  flutter_webview.WebViewController? _flutterController;
  StreamSubscription? _messageSubscription;
  Timer? _pollTimer;
  bool _ready = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (kIsWeb) {
        final uri = Uri.tryParse(widget.pageUrl);
        if (uri != null) await launchUrl(uri, webOnlyWindowName: '_blank');
        if (mounted) setState(() => _error = AppLocalizations.current.t('验证页面已在新窗口打开，完成后返回注册页'));
        return;
      }
      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.macOS &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android) {
        if (mounted) setState(() => _error = AppLocalizations.current.t('当前系统没有可用的内置浏览器，请使用系统浏览器完成验证'));
        return;
      }
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
        final controller = flutter_webview.WebViewController()
          ..setJavaScriptMode(flutter_webview.JavaScriptMode.unrestricted)
          ..addJavaScriptChannel('OldChat', onMessageReceived: (message) => _onMessage(message.message))
          ..loadRequest(Uri.parse(widget.pageUrl));
        _flutterController = controller;
        if (mounted) setState(() => _ready = true);
        return;
      }
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.allow);
      _messageSubscription = _controller.webMessage.listen(_onMessage);
      await _controller.loadUrl(widget.pageUrl);
      if (mounted) setState(() => _ready = true);
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => _pollValidationResult(),
      );
      Future<void>.delayed(const Duration(milliseconds: 900), _hidePageChrome);
    } catch (error) {
      if (mounted) setState(() => _error = '${AppLocalizations.current.t('人机验证加载失败')}：${safeErrorMessage(error)}');
    }
  }

  Future<void> _hidePageChrome() async {
    try {
      const script = '''(() => {
        const style = document.createElement('style');
        style.textContent = `
          html, body { background: transparent !important; overflow: hidden !important; }
          .auth-brand, #registerForm > *:not(.turnstile-field), .auth-footer, #registerError { display: none !important; }
          .auth-page, .auth-card, #registerForm, .turnstile-field { background: transparent !important; box-shadow: none !important; border: 0 !important; margin: 0 !important; padding: 0 !important; }
          .turnstile-field { display: block !important; }
        `;
        document.head.appendChild(style);
      })();''';
      if (_flutterController != null) {
        await _flutterController!.runJavaScript(script);
      } else {
        await _controller.executeScript(script);
      }
    } catch (_) {}
  }

  Future<void> _pollValidationResult() async {
    if (_submitted || !mounted) return;
    try {
      final raw = _flutterController != null
          ? await _flutterController!.runJavaScriptReturningResult('JSON.stringify(window.__geetest || null)')
          : await _controller.executeScript('JSON.stringify(window.__geetest || null)');
      dynamic decoded = raw;
      for (var i = 0; i < 2 && decoded is String; i++) {
        final text = decoded.trim();
        if (text.isEmpty || text == 'null') return;
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          return;
        }
      }
      if (decoded is Map) {
        _onMessage({'type': 'geetest-success', 'result': decoded});
      }
    } catch (_) {}
  }

  void _onMessage(dynamic value) {
    if (_submitted) return;
    dynamic decoded = value;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return;
      }
    }
    if (decoded is! Map || decoded['type'] != 'geetest-success') return;
    final result = decoded['result'];
    if (result is! Map ||
        result['lot_number'] == null ||
        result['captcha_output'] == null ||
        result['pass_token'] == null ||
        result['gen_time'] == null) {
      return;
    }
    _submitted = true;
    _pollTimer?.cancel();
    Navigator.of(context).pop(Map<String, dynamic>.from(result));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.current.t('人机验证')),
      content: SizedBox(
        width: 430,
        height: 280,
        child: _error != null
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : !_ready && _flutterController == null && !_controller.value.isInitialized
                ? Center(child: CircularProgressIndicator())
                : _flutterController != null
                    ? flutter_webview.WebViewWidget(controller: _flutterController!)
                    : Webview(_controller),
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
