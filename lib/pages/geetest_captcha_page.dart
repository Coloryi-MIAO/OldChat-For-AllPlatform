import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:webview_windows/webview_windows.dart';

class GeeTestCaptchaPage extends StatefulWidget {
  final String pageUrl;

  const GeeTestCaptchaPage({super.key, required this.pageUrl});

  @override
  State<GeeTestCaptchaPage> createState() => _GeeTestCaptchaPageState();
}

class _GeeTestCaptchaPageState extends State<GeeTestCaptchaPage> {
  final _controller = WebviewController();
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
      if (mounted) setState(() => _error = '人机验证加载失败：$error');
    }
  }

  Future<void> _hidePageChrome() async {
    try {
      await _controller.executeScript('''(() => {
        const style = document.createElement('style');
        style.textContent = `
          html, body { background: transparent !important; overflow: hidden !important; }
          .auth-brand, #registerForm > *:not(.turnstile-field), .auth-footer, #registerError { display: none !important; }
          .auth-page, .auth-card, #registerForm, .turnstile-field { background: transparent !important; box-shadow: none !important; border: 0 !important; margin: 0 !important; padding: 0 !important; }
          .turnstile-field { display: block !important; }
        `;
        document.head.appendChild(style);
      })();''');
    } catch (_) {}
  }

  Future<void> _pollValidationResult() async {
    if (_submitted || !mounted) return;
    try {
      final raw = await _controller.executeScript(
        'JSON.stringify(window.__geetest || null)',
      );
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
            : !_ready && !_controller.value.isInitialized
                ? Center(child: CircularProgressIndicator())
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
