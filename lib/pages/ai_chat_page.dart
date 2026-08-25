import 'dart:convert';
import 'package:dio/dio.dart';
import '../services/account_storage.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../services/api_service.dart';
import '../services/ai_settings_service.dart';

class AIChatPage extends StatefulWidget {
  const AIChatPage({super.key});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _sessions = [];
  String _sessionId = '';
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;
  int _quota = 0;
  String _selectedModel = '';
  List<String> _models = [];
  String _aiApiKey = '';
  String _aiBaseUrl = '';
  final TextEditingController _modelController = TextEditingController();
  bool _aiSettingsReady = false;
  bool get _hasPersonalAI =>
      _aiApiKey.trim().isNotEmpty && _aiBaseUrl.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSessions();
    _loadAISettings();
  }

  Future<void> _loadSessions() async {
    await AccountStorage.instance.load();
    final raw = AccountStorage.instance.getString('ai_sessions');
    List<dynamic> saved = <dynamic>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) saved = decoded;
      } catch (_) {
        await AccountStorage.instance.remove('ai_sessions');
      }
    }
    final sessions = saved
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (!mounted) return;
    final sessionId = sessions.isNotEmpty
        ? sessions.first['id'].toString()
        : _newSessionId();
    if (sessions.isEmpty) {
      sessions.add({'id': sessionId, 'title': '新会话', 'messages': []});
    }
    setState(() {
      _sessions.addAll(sessions);
      _sessionId = sessionId;
      _restoreSession(_sessionId);
    });
    if (saved.isEmpty) await _persistSessions();
  }

  String _newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _persistSessions() async {
    await AccountStorage.instance.setString(
      'ai_sessions',
      jsonEncode(_sessions),
    );
  }

  void _restoreSession(String id) {
    final session = _sessions.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == id,
      orElse: () => null,
    );
    _messages
      ..clear()
      ..addAll(
        (session?['messages'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)),
      );
  }

  Future<void> _selectSession(String id) async {
    if (id == _sessionId) return;
    setState(() {
      _sessionId = id;
      _restoreSession(id);
    });
    await _persistSessions();
  }

  Future<void> _newSession() async {
    final id = _newSessionId();
    setState(() {
      _sessionId = id;
      _messages.clear();
      _sessions.insert(0, {'id': id, 'title': '新会话', 'messages': []});
    });
    await _persistSessions();
  }

  Future<void> _saveCurrentSession() async {
    final title = _messages
        .where((m) => m['isUser'] == true)
        .map((m) => m['content'].toString())
        .firstWhere((t) => t.trim().isNotEmpty, orElse: () => '新会话');
    final value = {
      'id': _sessionId,
      'title': title.length > 24 ? '${title.substring(0, 24)}…' : title,
      'messages': _messages
          .map((message) => Map<String, dynamic>.from(message))
          .toList(),
    };
    if (!mounted) return;
    setState(() {
      final index = _sessions.indexWhere(
        (item) => item['id']?.toString() == _sessionId,
      );
      if (index < 0) {
        _sessions.insert(0, value);
      } else {
        _sessions[index] = value;
      }
    });
    await _persistSessions();
  }

  Future<void> _loadAISettings() async {
    final settings = await AISettingsService.load();
    if (!mounted) return;
    setState(() {
      _aiApiKey = settings.apiKey;
      _aiBaseUrl = settings.baseUrl;
      _models = _modelsForUrl(settings.baseUrl);
      _selectedModel = settings.model;
      _modelController.text = settings.model;
      _aiSettingsReady = true;
    });
    if (settings.isConfigured) {
      await _loadPersonalModels(settings);
    }
    await _loadQuota();
  }

  Future<void> _loadPersonalModels(AISettings settings) async {
    final base = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final modelsUrl = base.endsWith('/chat/completions')
        ? '${base.substring(0, base.length - '/chat/completions'.length)}/models'
        : '$base/models';
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Authorization': 'Bearer ${settings.apiKey.trim()}',
            'Accept': 'application/json',
          },
        ),
      ).get(modelsUrl);
      final raw = response.data is Map ? response.data['data'] : null;
      final discovered = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => item['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toList()
          : <String>[];
      if (!mounted || discovered.isEmpty) return;
      setState(() {
        _models = discovered;
        if (_selectedModel.isEmpty || !_models.contains(_selectedModel)) {
          _selectedModel = _models.first;
          _modelController.text = _selectedModel;
        }
      });
    } catch (_) {
      // Some compatible APIs do not expose /models; the manual model field remains available.
    }
  }

  List<String> _modelsForUrl(String url) {
    if (url.contains('deepseek')) return ['deepseek-chat', 'deepseek-reasoner'];
    if (url.contains('openrouter'))
      return ['openai/gpt-4o-mini', 'deepseek/deepseek-chat'];
    if (url.contains('openai')) return ['gpt-4o-mini', 'gpt-4.1-mini'];
    return ['自定义模型'];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _scrollController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_loading &&
        _aiSettingsReady) {
      _loadQuota();
    }
  }

  Future<void> _loadQuota() async {
    if (_hasPersonalAI) {
      if (mounted) setState(() => _quota = -1);
      return;
    }
    try {
      final api = ApiService();
      final data = await api.getAIQuota();
      if (mounted)
        setState(() {
          _quota = data['quota'] ?? 0;
        });
    } catch (_) {}
  }

  String _extractAssistantText(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] != null) {
          return message['content'].toString();
        }
      }
    }
    final content =
        response['content'] ??
        response['text'] ??
        response['answer'] ??
        response['reply'];
    if (content is List) {
      return content.map((e) => e.toString()).join('');
    }
    if (content is Map) {
      return content['content']?.toString() ??
          content['text']?.toString() ??
          'AI无响应';
    }
    if (content != null) {
      return content.toString();
    }
    return 'AI无响应';
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _loading) return;
    if (!_hasPersonalAI && _quota <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('今日配额已用完，请明天再试'))),
      );
      return;
    }
    final settings = await AISettingsService.load();
    setState(() {
      _messages.add({'role': 'user', 'content': text, 'isUser': true});
      _inputController.clear();
      _loading = true;
    });
    _scrollToBottom();

    try {
      final model = _modelController.text.trim();
      final response = await ApiService().chatWithAI(
        text,
        model: model.isEmpty ? null : model,
        settings: settings,
      );
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': _extractAssistantText(response),
          'isUser': false,
        });
        _loading = false;
      });
      await _saveCurrentSession();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '错误: $e',
          'isUser': false,
        });
        _loading = false;
      });
      await _saveCurrentSession();
      _scrollToBottom();
    }
  }

  Future<void> _showAISettings() async {
    final keyController = TextEditingController(text: _aiApiKey);
    final urlController = TextEditingController(text: _aiBaseUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.current.t('AI 接口设置')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: AppLocalizations.current.t('API URL'),
                hintText: AppLocalizations.current.t(
                  'https://api.openai.com/v1',
                ),
              ),
            ),
            TextField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: AppLocalizations.current.t('模型名称'),
                hintText: AppLocalizations.current.t('例如：deepseek-chat'),
              ),
            ),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.current.t('API Key'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.current.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.current.t('保存')),
          ),
        ],
      ),
    );
    if (saved == true) {
      await AISettingsService.save(
        apiKey: keyController.text,
        baseUrl: urlController.text,
        model: _modelController.text,
      );
      if (mounted) {
        setState(() {
          _aiApiKey = keyController.text.trim();
          _aiBaseUrl = urlController.text.trim();
          _selectedModel = _modelController.text.trim();
        });
      }
    }
    keyController.dispose();
    urlController.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('AI 助手')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_hasPersonalAI && _models.isNotEmpty)
            DropdownButton<String>(
              value: _models.contains(_selectedModel) ? _selectedModel : null,
              hint: Text(
                AppLocalizations.current.t('模型'),
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: primaryColor,
              style: const TextStyle(color: Colors.white),
              underline: const SizedBox.shrink(),
              items: _models
                  .map(
                    (model) =>
                        DropdownMenuItem(value: model, child: Text(model)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null)
                  setState(() {
                    _selectedModel = value;
                    _modelController.text = value;
                  });
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _hasPersonalAI ? null : _loadQuota,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: AppLocalizations.current.t('AI 接口设置'),
            onPressed: _showAISettings,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            alignment: Alignment.centerRight,
            child: Text(
              _hasPersonalAI ? '自备 API：不使用旧聊额度' : '今日剩余配额: $_quota',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: Material(
              color: primaryColor.withOpacity(0.08),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: primaryColor.withOpacity(0.18),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        title: Text(AppLocalizations.current.t('AI 会话')),
                        trailing: IconButton(
                          icon: Icon(Icons.add),
                          onPressed: _newSession,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final id = session['id'].toString();
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              selected: id == _sessionId,
                              title: Text(
                                session['title']?.toString() ?? '新会话',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectSession(id),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.smart_toy,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                AppLocalizations.current.t('问AI任何问题'),
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg['isUser'] == true;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: isUser
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  if (!isUser)
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: primaryColor,
                                      child: const Icon(
                                        Icons.smart_toy,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  if (!isUser) const SizedBox(width: 8),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isUser
                                            ? primaryColor
                                            : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        msg['content'] ?? '',
                                        style: TextStyle(
                                          color: isUser
                                              ? Colors.white
                                              : Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isUser) const SizedBox(width: 8),
                                  if (isUser)
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.blue,
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (_loading)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.current.t('输入问题...'),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                        color: primaryColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
