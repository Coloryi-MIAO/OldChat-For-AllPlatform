import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/ws_session_service.dart';
import '../pages/home_page.dart';
import '../utils/constants.dart';
import '../services/app_localizations.dart';
import 'geetest_captcha_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  late TabController _tabController;

  final _regUsernameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regCaptchaController = TextEditingController();
  final _regEmailCodeController = TextEditingController();
  bool _regLoading = false;
  bool _loginAgreement = false;
  bool _registrationAgreement = false;
  DateTime? _agreementOpenedAt;
  Timer? _agreementTimer;
  int _agreementSeconds = 0;

  Map<String, dynamic>? _geeTestResult;

  static final RegExp _supportedEmailPattern = RegExp(
    r'^[^\s@]+@qq\.com$',
    caseSensitive: false,
  );

  bool _isSupportedEmail(String value) =>
      _supportedEmailPattern.hasMatch(value.trim());

  bool _rememberPassword = false;
  bool _credentialsLoaded = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final savedUsername = prefs.getString(Constants.savedUsernameKey) ?? '';
    final savedPassword = prefs.getString(Constants.savedPasswordKey) ?? '';
    final remember = prefs.getBool(Constants.rememberPasswordKey) ?? savedPassword.isNotEmpty;
    if (!mounted) return;
    setState(() {
      _usernameController.text = savedUsername;
      _passwordController.text = remember ? savedPassword : '';
      _rememberPassword = remember;
      _credentialsLoaded = true;
    });
  }

  Future<void> _setRememberPassword(bool remember) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(Constants.rememberPasswordKey, remember);
    if (!remember && mounted) {
      await context.read<AuthService>().clearCredentials();
    }
  }

  Future<void> _openAgreement() async {
    final now = DateTime.now();
    if (_agreementOpenedAt == null ||
        now.difference(_agreementOpenedAt!).inSeconds >= 30) {
      _agreementOpenedAt = now;
      _agreementSeconds = 0;
      _registrationAgreement = false;
    }
    _agreementTimer?.cancel();
    void Function(VoidCallback)? refreshDialog;
    _agreementTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _agreementOpenedAt == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_agreementOpenedAt!).inSeconds;
      setState(() => _agreementSeconds = elapsed.clamp(0, 30));
      refreshDialog?.call(() {});
      if (elapsed >= 30) timer.cancel();
    });
    setState(() {});
    try {
      final text = await rootBundle.loadString(
        'assets/legal/user_service_agreement.txt',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            refreshDialog = setDialogState;
            return AlertDialog(
          title: const Text('《用户服务协议与免责声明》'),
          content: SizedBox(
            width: 620,
            height: 520,
            child: SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
            if (_agreementSeconds >= 30)
              FilledButton(
                onPressed: () {
                  setState(() => _registrationAgreement = true);
                  Navigator.pop(dialogContext);
                },
                child: const Text('我已阅读并同意'),
              )
            else
              Text('请继续阅读，还需 ${30 - _agreementSeconds} 秒'),
          ],
        );
          },
        ),
      );
      if (!mounted) return;
      refreshDialog = null;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('协议加载失败：$error')));
      }
    }
  }

  Future<void> _openGeeTest() async {
    final baseUrl = Constants.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => GeeTestCaptchaPage(pageUrl: '$baseUrl/register'),
    );
    if (!mounted || result == null) return;
    setState(() {
      _geeTestResult = result;
      _regCaptchaController.clear();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _regUsernameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regCaptchaController.dispose();
    _regEmailCodeController.dispose();
    _agreementTimer?.cancel();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_credentialsLoaded) {
      await _loadSavedCredentials();
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_loginAgreement) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.t('请先阅读并同意用户服务协议与免责声明'))),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ApiService();
      final result = await api.login(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );
      await context.read<AuthService>().saveToken(
        result['token'],
        userId: result['userId'],
        refreshToken: result['refresh_token'],
      );

      // ★ 保存账号密码到 AuthService（用于自动登录）
      if (_rememberPassword) {
        await context.read<AuthService>().saveCredentials(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await context.read<AuthService>().clearCredentials();
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr.t('登录失败:')}$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetRegistrationForm() {
    _regUsernameController.clear();
    _regEmailController.clear();
    _regPasswordController.clear();
    _regCaptchaController.clear();
    _regEmailCodeController.clear();
    _geeTestResult = null;
    FocusScope.of(context).unfocus();
  }

  Future<void> _register() async {
    final email = _regEmailController.text.trim();
    if (_regUsernameController.text.isEmpty ||
        email.isEmpty ||
        _regPasswordController.text.isEmpty ||
        _regEmailCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('请填写所有字段'))),
      );
      return;
    }
    if (!_isSupportedEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('仅支持 QQ 邮箱'))),
      );
      return;
    }
    if (!_registrationAgreement ||
        _agreementOpenedAt == null ||
        DateTime.now().difference(_agreementOpenedAt!).inSeconds < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.t('请先完整阅读用户服务协议，至少 30 秒后才能注册'))),
      );
      return;
    }
    if (_geeTestResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('请先完成人机验证'))),
      );
      return;
    }
    setState(() => _regLoading = true);
    try {
      final api = ApiService();
      await api.register(
        username: _regUsernameController.text.trim(),
        email: email,
        password: _regPasswordController.text,
        emailCode: _regEmailCodeController.text.trim(),
        captchaId: Constants.geetestCaptchaId,
        captchaCode: '',
        captchaResult: _geeTestResult,
        deviceId:
            await WsSessionService(http: true).getDeviceId() ??
            'oldchat-windows',
        deviceName: 'Flutter Client',
      );
      if (mounted) {
        _resetRegistrationForm();
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr.text(
                '注册成功！请登录',
                'Registration succeeded. Please log in.',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr.t('注册失败:')}$e')));
      }
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  Future<void> _sendEmailCode() async {
    final email = _regEmailController.text.trim();
    if (email.isEmpty || _geeTestResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('请先填写邮箱并完成人机验证'))),
      );
      return;
    }
    if (!_isSupportedEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('仅支持 QQ 邮箱'))),
      );
      return;
    }
    try {
      final api = ApiService();
      await api.sendEmailCode(email, _geeTestResult!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('验证码已发送'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('发送失败: $e'))),
      );
    }
  }

  // ★ 显示设置对话框
  void _showSettingsDialog() {
    final controller = TextEditingController(text: Constants.baseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.current.t('服务器地址设置')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '修改后会自动保存并刷新',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: AppLocalizations.current.t(
                  'http://60.205.94.101:8080',
                ),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.current.t('取消')),
          ),
          ElevatedButton(
            onPressed: () async {
              String url = controller.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.current.t('请输入服务器地址')),
                  ),
                );
                return;
              }
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.current.t('地址必须以 http:// 或 https:// 开头'),
                    ),
                  ),
                );
                return;
              }
              if (url.endsWith('/')) {
                url = url.substring(0, url.length - 1);
              }
              await Constants.saveBaseUrl(url);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.current.t('设置已保存，页面将刷新')),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.current.t('保存')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: _showSettingsDialog,
            tooltip: AppLocalizations.current.t('服务器设置'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Flexible(
                          child: Text(
                            'OldChat For AllPlatform',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFA94A6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TabBar(
                      controller: _tabController,
                      labelColor: primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: primaryColor,
                      tabs: const [
                        Tab(text: '登录'),
                        Tab(text: '注册'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 380,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildLoginForm(),
                          SingleChildScrollView(
                            padding: const EdgeInsets.only(top: 12),
                            child: _buildRegisterForm(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    final primaryColor = Theme.of(context).primaryColor;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          SizedBox(height: 8),
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: AppLocalizations.current.t('用户名 / 邮箱 / UID'),
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? '请输入用户名' : null,
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.current.t('密码'),
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? '请输入密码' : null,
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _rememberPassword,
                onChanged: (value) async {
                  final remember = value ?? false;
                  setState(() => _rememberPassword = remember);
                  await _setRememberPassword(remember);
                },
                activeColor: primaryColor,
              ),
              GestureDetector(
                onTap: () async {
                  final remember = !_rememberPassword;
                  setState(() => _rememberPassword = remember);
                  await _setRememberPassword(remember);
                },
                child: Text(AppLocalizations.current.t('记住密码')),
              ),
            ],
          ),
          CheckboxListTile(
            value: _loginAgreement,
            onChanged: (value) =>
                setState(() => _loginAgreement = value ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: GestureDetector(
              onTap: _openAgreement,
              child: const Text('我已认真阅读并完全同意《用户服务协议与免责声明》'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      context.tr.login,
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    final primaryColor = Theme.of(context).primaryColor;
    return Column(
      children: [
        SizedBox(height: 16),
        TextFormField(
          controller: _regUsernameController,
          decoration: InputDecoration(
            labelText: AppLocalizations.current.t('用户名'),
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: 12),
        TextFormField(
          controller: _regEmailController,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return '请输入邮箱';
            if (!_isSupportedEmail(email)) return '仅支持 QQ 邮箱';
            return null;
          },
          decoration: InputDecoration(
            labelText: AppLocalizations.current.t('邮箱（仅支持 QQ）'),
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: 12),
        TextFormField(
          controller: _regPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.current.t('密码（至少6位）'),
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          value: _registrationAgreement && _agreementSeconds >= 30,
          onChanged: _agreementSeconds >= 30
              ? (value) =>
                    setState(() => _registrationAgreement = value ?? false)
              : null,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: GestureDetector(
            onTap: _openAgreement,
            child: Text(
              _agreementSeconds < 30
                  ? '阅读《用户服务协议与免责声明》${_agreementSeconds == 0 ? '' : '（还需 ${30 - _agreementSeconds} 秒）'}'
                  : '我已完整阅读并同意《用户服务协议与免责声明》',
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openGeeTest,
            icon: Icon(
              _geeTestResult == null
                  ? Icons.verified_user_outlined
                  : Icons.check_circle_outline,
            ),
            label: Text(_geeTestResult == null ? '点击完成人机验证' : '人机验证已完成，点击重新验证'),
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _regEmailCodeController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.current.t('邮箱验证码'),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: ElevatedButton(
                onPressed: _sendEmailCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                  minimumSize: const Size(0, 56),
                ),
                child: Text(AppLocalizations.current.t('发送')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _regLoading ? null : _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _regLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    context.tr.register,
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
      ],
    );
  }
}
