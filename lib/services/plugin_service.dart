import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/file_picker_compat.dart';
import 'package:flutter/foundation.dart';
import 'package:lua_dardo_plus/lua.dart';

import 'account_storage.dart';
import 'app_localizations.dart';
import '../models/message.dart';

import '../utils/message_parser.dart';
import '../services/json_guard.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'theme_service.dart';
import 'notification_service.dart';

class PluginService extends ChangeNotifier {
  static final PluginService _instance = PluginService._();
  factory PluginService() => _instance;
  PluginService._();

  static const allowedPermissions = <String>{
    'events.message',
    'messages.send',
    'messages.send_image',
    'redpacket.claim',
    'redpacket.send',
    'checkin.run',
    'checkin.post',
    'moments.post',
    'theme.apply',
    'storage.local',
    'network',
    'network_external',
    'camera',
    'files.local',
    'storage',
  };

  final Map<String, Map<String, dynamic>> _plugins = {};
  final Map<String, LuaState> _cipStates = <String, LuaState>{};
  final List<Map<String, dynamic>> _pendingActions = [];
  final Map<String, DateTime> _replyCooldowns = {};
  final List<DateTime> _redPacketClaims = [];
  final Set<String> _claimedPacketIds = {};
  final Set<String> _dispatchedMessageIds = {};
  final Set<String> _claimingPacketIds = {};
  final Map<String, DateTime> _redPacketRetryAfter = {};
  final List<void Function(Map<String, dynamic>)> _messageListeners = [];
  final Map<String, Map<String, dynamic>> _uiResults =
      <String, Map<String, dynamic>>{};
  bool _loaded = false;
  String? _loadedUserId;

  List<Map<String, dynamic>> get plugins => _plugins.values
      .map((value) {
        final copy = Map<String, dynamic>.from(value);
        if (copy['rules'] is List)
          copy['rules'] = List<Map<String, dynamic>>.from(
            (copy['rules'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        return copy;
      })
      .toList(growable: false);

  List<Map<String, dynamic>> get pendingActions => _pendingActions
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  bool get loaded => _loaded;

  Map<String, dynamic>? uiResult(String id) => _uiResults[id];

  void clearUiResult(String id) {
    _uiResults.remove(id);
    notifyListeners();
  }

  Future<void> load() async {
    final userId = AuthService().userId ?? 'guest';
    await AccountStorage.instance.load(userId: userId);
    if (_loaded && _loadedUserId == userId) return;
    _plugins.clear();
    _pendingActions.clear();
    _replyCooldowns.clear();
    _redPacketClaims.clear();
    _claimedPacketIds.clear();
    _dispatchedMessageIds.clear();
    _claimingPacketIds.clear();
    _redPacketRetryAfter.clear();
    _uiResults.clear();
    _loaded = true;
    _loadedUserId = userId;
    final storage = AccountStorage.instance;
    _readPlugins(storage.getString('plugins'));
    _readPending(storage.getString('plugin_pending'));
    final claimed = (storage.getString('plugin_claimed_packets') ?? '')
        .split('\n')
        .where((value) => value.trim().isNotEmpty)
        .toList();
    _claimedPacketIds.addAll(claimed);
    _installBuiltIns();
    await _save();
    notifyListeners();
  }

  void _readPlugins(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded.whereType<Map>()) {
        final saved = Map<String, dynamic>.from(item);
        final plugin = _sanitizeManifest(saved);
        if (plugin != null) {
          plugin['enabled'] = saved['enabled'] == true;
          if (saved['config'] is Map) {
            plugin['config'] = Map<String, dynamic>.from(
              saved['config'] as Map,
            );
          }
          if (saved['logs'] is List) {
            plugin['logs'] = saved['logs']
                .map((value) => value.toString())
                .take(100)
                .toList();
          }
          if (saved['cip_main'] is String)
            plugin['cip_main'] = saved['cip_main'];
          _plugins[plugin['id'] as String] = plugin;
        }
      }
    } catch (_) {}
  }

  void _readPending(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _pendingActions.addAll(
          decoded.whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      }
    } catch (_) {}
  }

  void _installBuiltIns() {
    _plugins.putIfAbsent(
      'oldchat.auto-reply',
      () => {
        'id': 'oldchat.auto-reply',
        'name': '系统自动回复',
        'version': '1.0.0',
        'description': '按规则自动回复私聊或群聊消息。默认关闭，可自行编辑规则。',
        'builtIn': true,
        'enabled': false,
        'permissions': ['events.message', 'messages.send', 'storage.local'],
        'rules': [
          {
            'when': {'conversation_type': 'direct', 'contains': '你好'},
            'action': {
              'type': 'send_text',
              'text': '你好，我现在不方便及时回复，稍后联系。',
              'cooldown_seconds': 60,
            },
          },
        ],
        'config': <String, dynamic>{},
        'logs': <String>[],
      },
    );
    _plugins.putIfAbsent(
      'oldchat.redpacket-helper',
      () => {
        'id': 'oldchat.redpacket-helper',
        'name': '系统红包助手',
        'version': '1.0.0',
        'description': '检测私聊和群聊红包，按限速、每日限额和重复保护自动领取。默认关闭。',
        'builtIn': true,
        'enabled': false,
        'permissions': ['events.message', 'redpacket.claim', 'storage.local'],
        'rules': const <Map<String, dynamic>>[],
        'config': {
          'auto_claim': false,
          'max_per_minute': 3,
          'daily_limit': 30,
          'conversation_types': ['direct', 'group'],
          'min_remaining_count': 1,
          'min_amount': 0,
          'max_amount': 0,
          'only_unclaimed': true,
          'skip_self': true,
          'skip_expired': true,
          'skip_claimed': true,
        },
        'logs': <String>[],
      },
    );
    _plugins.putIfAbsent(
      'oldchat.function-buttons',
      () => {
        'id': 'oldchat.function-buttons',
        'name': '功能按钮编辑',
        'version': '1.0.0',
        'description': '编辑功能中心和更多页面的入口顺序；默认显示全部入口。',
        'builtIn': true,
        'enabled': true,
        'permissions': ['storage.local'],
        'rules': const <Map<String, dynamic>>[],
        'config': <String, dynamic>{},
        'logs': <String>[],
      },
    );
    _plugins.putIfAbsent(
      'oldchat.dice-buddy',
      () => {
        'id': 'oldchat.dice-buddy',
        'name': '骰子伙伴',
        'version': '1.0.0',
        'description': '收到“骰子”或“掷骰子”时，随机回复 1–20 点。',
        'builtIn': true,
        'enabled': false,
        'permissions': ['events.message', 'messages.send', 'storage.local'],
        'rules': const <Map<String, dynamic>>[],
        'config': <String, dynamic>{},
        'logs': <String>[],
      },
    );
    _plugins.putIfAbsent(
      'oldchat.keyword-alert',
      () => {
        'id': 'oldchat.keyword-alert',
        'name': '关键词提醒',
        'version': '1.0.0',
        'description': '发现“重要”“@我”“紧急”等关键词时弹出桌面提醒，不自动发消息。',
        'builtIn': true,
        'enabled': false,
        'permissions': ['events.message', 'storage.local'],
        'rules': const <Map<String, dynamic>>[],
        'config': {'keywords': '重要,@我,紧急,截止日期'},
        'logs': <String>[],
      },
    );
    _plugins.putIfAbsent(
      'oldchat.message-counter',
      () => {
        'id': 'oldchat.message-counter',
        'name': '消息计数器',
        'version': '1.0.0',
        'description': '本地统计收到的消息数量，不联网、不自动发送内容。',
        'builtIn': true,
        'enabled': false,
        'permissions': ['events.message', 'storage.local'],
        'rules': const <Map<String, dynamic>>[],
        'config': {'received': 0},
        'logs': <String>[],
      },
    );
  }

  Map<String, dynamic>? _sanitizeManifest(Map<String, dynamic> manifest) {
    final id = manifest['id']?.toString().trim() ?? '';
    if (id.isEmpty || !RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(id))
      return null;
    final rawPermissions = manifest['permissions'];
    final permissions = rawPermissions is List
        ? rawPermissions
              .map((value) => value.toString())
              .where(allowedPermissions.contains)
              .toSet()
              .toList()
        : <String>[];
    final rules = manifest['rules'] is List
        ? (manifest['rules'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    return {
      'id': id,
      'name': (manifest['name'] ?? id).toString().trim(),
      'version': (manifest['version'] ?? '0.0.0').toString(),
      'description': (manifest['description'] ?? '').toString(),
      'builtIn': manifest['builtIn'] == true,
      'enabled': false,
      'permissions': permissions,
      'rules': rules,
      'config': manifest['config'] is Map
          ? Map<String, dynamic>.from(manifest['config'])
          : <String, dynamic>{},
      if (manifest['theme'] is Map)
        'theme': Map<String, dynamic>.from(manifest['theme']),
      if (manifest['cip_main'] is String)
        'cip_main': manifest['cip_main'].toString(),
      'logs': manifest['logs'] is List
          ? manifest['logs'].map((item) => item.toString()).take(100).toList()
          : <String>[],
    };
  }

  Future<Map<String, dynamic>> importPluginBytes(Uint8List bytes) async {
    await load();
    if (bytes.length > 4 * 1024 * 1024) {
      throw Exception('插件包不能超过 4 MiB');
    }
    Map<String, dynamic> manifest;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.length > 128) throw Exception('插件包最多包含 128 个条目');
      ArchiveFile? manifestFile;
      var total = 0;
      for (final entry in archive) {
        final path = entry.name.replaceAll('\\', '/');
        if (path.startsWith('/') || path.contains('..') || path.contains(':')) {
          throw Exception('插件包包含不安全路径');
        }
        if (entry.isSymbolicLink) throw Exception('插件包不允许符号链接');
        total += entry.size;
        if (total > 16 * 1024 * 1024) {
          throw Exception('插件包解压后不能超过 16 MiB');
        }
        if (path == 'manifest.json') manifestFile = entry;
        if (path.isNotEmpty &&
            path != 'manifest.json' &&
            !path.startsWith('assets/')) {
          throw Exception('插件包只允许 manifest.json 和 assets/');
        }
      }
      if (manifestFile == null) throw Exception('插件包缺少根目录 manifest.json');
      final decoded = jsonDecode(
        utf8.decode(manifestFile.readBytes() ?? const <int>[]),
      );
      if (decoded is! Map) throw Exception('manifest.json 必须是对象');
      manifest = Map<String, dynamic>.from(decoded);
    } on FormatException {
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw Exception('插件文件必须是 ZIP 包或 JSON manifest');
        manifest = Map<String, dynamic>.from(decoded);
      } on FormatException {
        throw Exception('插件文件不是有效的 ZIP 包或 JSON manifest');
      }
    }
    await registerManifest(manifest);
    final id = manifest['id']?.toString() ?? '';
    return _plugins[id] == null
        ? manifest
        : Map<String, dynamic>.from(_plugins[id]!);
  }

  Future<void> registerManifest(Map<String, dynamic> manifest) async {
    await load();
    final plugin = _sanitizeManifest(manifest);
    if (plugin == null) throw Exception('插件 ID 或 manifest 无效');
    final requested = manifest['permissions'] is List
        ? (manifest['permissions'] as List)
              .map((value) => value.toString())
              .toSet()
        : <String>{};
    final rejected = requested.difference(allowedPermissions);
    if (rejected.isNotEmpty)
      throw Exception('插件包含不支持的权限：${rejected.join(', ')}');
    final existing = _plugins[plugin['id'] as String];
    if (existing != null) {
      plugin['enabled'] = existing['enabled'] == true;
      plugin['config'] = existing['config'] is Map
          ? Map<String, dynamic>.from(existing['config'] as Map)
          : plugin['config'];
      plugin['logs'] = existing['logs'] is List
          ? List<String>.from(existing['logs'] as List)
          : plugin['logs'];
    }
    _plugins[plugin['id'] as String] = plugin;
    await _save();
    notifyListeners();
  }

  Future<Uint8List> exportPlugin(String id) async {
    await load();
    final plugin = _plugins[id];
    if (plugin == null) throw Exception('插件不存在');
    final manifest = Map<String, dynamic>.from(plugin)
      ..remove('logs')
      ..remove('enabled')
      ..remove('builtIn');
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final archive = Archive()
      ..add(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  Future<String?> exportPluginFile(String id) async {
    await load();
    final plugin = _plugins[id];
    if (plugin == null) throw Exception('插件不存在');
    final manifest = Map<String, dynamic>.from(plugin)
      ..remove('logs')
      ..remove('enabled')
      ..remove('builtIn');
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final archive = Archive()
      ..add(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    final bytes = ZipEncoder().encodeBytes(archive);
    final selected = filePickerPath(
      await saveFileCompat(
        dialogTitle: '导出插件',
        fileName: '${plugin['id']}.oldchat-plugin',
        type: FileType.custom,
        allowedExtensions: const ['oldchat-plugin'],
        bytes: bytes,
      ),
    );
    return selected;
  }

  Future<Uint8List> exportCip(String id) async {
    await load();
    final plugin = _plugins[id];
    final script = plugin?['cip_main']?.toString();
    if (plugin == null || script == null || script.isEmpty) {
      throw Exception('该插件没有可导出的 CIP 脚本');
    }
    final manifest = Map<String, dynamic>.from(plugin)..remove('cip_main');
    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final scriptBytes = utf8.encode(script);
    archive.add(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    archive.add(ArchiveFile('main.lua', scriptBytes.length, scriptBytes));
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await load();
    final plugin = _plugins[id];
    if (plugin == null) throw Exception('插件不存在');
    plugin['enabled'] = enabled;
    await _save();
    notifyListeners();
  }

  Future<void> updateConfig(String id, Map<String, dynamic> config) async {
    await load();
    final plugin = _plugins[id];
    if (plugin == null) throw Exception('插件不存在');
    plugin['config'] = Map<String, dynamic>.from(config);
    if (id == 'oldchat.auto-reply') {
      final contains = config['contains']?.toString().trim() ?? '';
      final reply = config['reply']?.toString().trim() ?? '';
      final conversationTypes = config['conversation_types'] is List
          ? (config['conversation_types'] as List)
                .map((value) => value.toString())
                .where((value) => value == 'direct' || value == 'group')
                .toSet()
          : <String>{config['conversation_type']?.toString() ?? 'direct'};
      if (conversationTypes.isEmpty) conversationTypes.add('direct');
      final cooldown = _intValue(
        config['cooldown_seconds'],
        60,
      ).clamp(0, 86400);
      final triggers = contains
          .split(RegExp(r'[,，\\n]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      plugin['rules'] = triggers.isEmpty || reply.isEmpty
          ? <Map<String, dynamic>>[]
          : triggers
                .map(
                  (trigger) => <String, dynamic>{
                    'when': {
                      'conversation_types': conversationTypes.toList(),
                      'contains': trigger,
                    },
                    'action': {
                      'type': 'send_text',
                      'text': reply,
                      'cooldown_seconds': cooldown,
                    },
                  },
                )
                .toList();
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await load();
    final plugin = _plugins[id];
    if (plugin?['builtIn'] == true) throw Exception('系统插件不能删除，只能停用');
    _plugins.remove(id);
    await _save();
    notifyListeners();
  }

  void addMessageListener(void Function(Map<String, dynamic>) listener) {
    if (!_messageListeners.contains(listener)) _messageListeners.add(listener);
  }

  void removeMessageListener(void Function(Map<String, dynamic>) listener) {
    _messageListeners.remove(listener);
  }

  Future<void> dispatchMessage(
    Message message, {
    String? conversationId,
  }) async {
    await load();
    if (message.id.isEmpty || !_dispatchedMessageIds.add(message.id)) return;
    if (_dispatchedMessageIds.length > 5000)
      _dispatchedMessageIds.remove(_dispatchedMessageIds.first);
    final currentUid = AuthService().userId;
    if (currentUid != null && message.fromUid == currentUid) return;
    final parsed = MessageParser.parseMessageBody(
      message.body,
      message.msgType,
    );
    final packet = _extractRedPacket(message, parsed['redPacket']);
    final event = <String, dynamic>{
      'type': 'message.received',
      'conversation_type': message.groupId == null ? 'direct' : 'group',
      'conversation_id': conversationId ?? message.groupId ?? message.fromUid,
      'message_id': message.id,
      'from_uid': message.fromUid,
      'text': (parsed['text'] ?? message.displayText).toString(),
      'msg_type': message.msgType,
      'created_at': message.createdAt,
      'media_url': message.mediaUrl,
      'red_packet': packet,
    };
    for (final listener in List<void Function(Map<String, dynamic>)>.from(
      _messageListeners,
    )) {
      try {
        listener(Map<String, dynamic>.from(event));
      } catch (_) {}
    }
    for (final plugin in _plugins.values.toList()) {
      if (plugin['enabled'] != true ||
          !_hasPermission(plugin, 'events.message'))
        continue;
      try {
        await _runPlugin(plugin, event);
      } catch (error) {
        _log(plugin, '插件执行失败：$error');
      }
    }
  }

  Map<String, dynamic>? _extractRedPacket(Message message, dynamic parsed) {
    Map<String, dynamic>? normalize(Map value) {
      final result = Map<String, dynamic>.from(value);
      final nested = result['red_packet'] ?? result['redPacket'];
      if (nested is Map) return normalize(nested);
      final id =
          result['packet_id'] ??
          result['packetId'] ??
          result['red_packet_id'] ??
          result['redPacketId'] ??
          (result['packet'] is Map
              ? (result['packet'] as Map)['id']
              : result['id']);
      if (id == null || id.toString().trim().isEmpty) return null;
      result['packet_id'] = id.toString().trim();
      return result;
    }

    if (parsed is Map) {
      final value = normalize(parsed);
      if (value != null) return value;
    }
    final decoded = _decodeMap(message.body);
    if (decoded != null) {
      final value = normalize(decoded);
      if (value != null) return value;
      for (final key in const ['data', 'result', 'payload']) {
        final nested = decoded[key];
        if (nested is Map) {
          final value = normalize(nested);
          if (value != null) return value;
        }
      }
    }
    final type = message.msgType.toLowerCase();
    if (type.contains('redpacket') ||
        type.contains('red_packet') ||
        type.contains('red-pack')) {
      final match = RegExp(
        r"""(?:packet[_-]?id|red[_-]?packet[_-]?id)\s*[=:]\s*["']?([A-Za-z0-9._-]+)""",
        caseSensitive: false,
      ).firstMatch(message.body);
      if (match != null) return {'packet_id': match.group(1)!};
    }
    return null;
  }

  Map<String, dynamic>? _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runPlugin(
    Map<String, dynamic> plugin,
    Map<String, dynamic> event,
  ) async {
    if (plugin['id'] == 'oldchat.redpacket-helper') {
      await _autoClaim(plugin, event);
      return;
    }
    if (plugin['id'] == 'oldchat.auto-reply') {
      await _runRules(plugin, event);
      return;
    }
    if (plugin['id'] == 'oldchat.dice-buddy') {
      await _runDiceBuddy(plugin, event);
      return;
    }
    if (plugin['id'] == 'oldchat.keyword-alert') {
      await _runKeywordAlert(plugin, event);
      return;
    }
    if (plugin['id'] == 'oldchat.message-counter') {
      await _countMessage(plugin);
      return;
    }
    final cipScript = plugin['cip_main']?.toString();
    if (cipScript != null && cipScript.trim().isNotEmpty) {
      await executeCip(plugin['id'].toString(), cipScript, event: event);
    }
    final rules = plugin['rules'];
    if (rules is! List) return;
    for (final raw in rules.whereType<Map>()) {
      final rule = Map<String, dynamic>.from(raw);
      if (!_matches(rule['when'], event)) continue;
      final action = rule['action'] is Map
          ? Map<String, dynamic>.from(rule['action'] as Map)
          : <String, dynamic>{'type': 'send_text', 'text': rule['reply']};
      await _runAction(plugin, action, event);
    }
  }

  Future<void> _runRules(
    Map<String, dynamic> plugin,
    Map<String, dynamic> event,
  ) async {
    final rules = plugin['rules'];
    if (rules is! List) return;
    for (final raw in rules.whereType<Map>()) {
      final rule = Map<String, dynamic>.from(raw);
      if (_matches(rule['when'], event)) {
        final action = rule['action'] is Map
            ? Map<String, dynamic>.from(rule['action'] as Map)
            : <String, dynamic>{'type': 'send_text', 'text': rule['reply']};
        await _runAction(plugin, action, event);
      }
    }
  }

  Future<void> _runDiceBuddy(
    Map<String, dynamic> plugin,
    Map<String, dynamic> event,
  ) async {
    final text = event['text']?.toString().trim() ?? '';
    if (!text.contains('骰子') &&
        !text.contains('掷骰') &&
        !text.toLowerCase().contains('dice'))
      return;
    final value = 1 + DateTime.now().microsecondsSinceEpoch % 20;
    await _sendText(event, '🎲 骰子结果：$value / 20');
    _log(plugin, '已回复骰子结果 $value');
  }

  Future<void> _runKeywordAlert(
    Map<String, dynamic> plugin,
    Map<String, dynamic> event,
  ) async {
    final config = plugin['config'] is Map
        ? Map<String, dynamic>.from(plugin['config'])
        : <String, dynamic>{};
    final keywords = (config['keywords']?.toString() ?? '重要,@我,紧急,截止日期')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final text = event['text']?.toString() ?? '';
    String? keyword;
    for (final value in keywords) {
      if (text.contains(value)) {
        keyword = value;
        break;
      }
    }
    if (keyword == null) return;
    await NotificationService().showNotification(
      title: '${AppLocalizations.current.t('关键词提醒：')}$keyword',
      body: text.length > 120 ? '${text.substring(0, 120)}…' : text,
      payload: '${event['conversation_type']}|${event['conversation_id']}',
      withFlash: true,
    );
    _log(plugin, '${AppLocalizations.current.t('关键词提醒：')}$keyword');
  }

  // ★ 修改点：每 10 条消息才保存一次，降低写入频率
  Future<void> _countMessage(Map<String, dynamic> plugin) async {
    final config = plugin['config'] is Map
        ? Map<String, dynamic>.from(plugin['config'])
        : <String, dynamic>{};
    final count = _intValue(config['received'], 0) + 1;
    plugin['config'] = {...config, 'received': count};
    // 只在计数为 10 的倍数时写入存储
    if (count % 10 == 0) {
      _log(plugin, '本地收到消息 $count 条');
      await _save();
    }
  }

  bool _matches(dynamic when, Map<String, dynamic> event) {
    if (when is! Map) return true;
    final types = when['conversation_types'] is List
        ? (when['conversation_types'] as List)
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toSet()
        : <String>{};
    final legacyType = when['conversation_type']?.toString();
    if (types.isNotEmpty && !types.contains(event['conversation_type'])) {
      return false;
    }
    if (types.isEmpty &&
        legacyType != null &&
        legacyType.isNotEmpty &&
        legacyType != event['conversation_type']) {
      return false;
    }
    final msgType = when['msg_type']?.toString();
    if (msgType != null && msgType.isNotEmpty && msgType != event['msg_type']) {
      return false;
    }
    final contains = when['contains']?.toString() ?? '';
    if (contains.isNotEmpty && !event['text'].toString().contains(contains)) {
      return false;
    }
    return true;
  }

  Future<void> _runAction(
    Map<String, dynamic> plugin,
    Map<String, dynamic> action,
    Map<String, dynamic> event,
  ) async {
    final type = (action['type'] ?? 'send_text').toString();
    final pluginId = plugin['id'].toString();
    final targetId = event['conversation_id'].toString();
    if (type == 'send_text') {
      if (!_hasPermission(plugin, 'messages.send')) return;
      final rawText = action['text']?.toString().trim() ?? '';
      if (rawText.isEmpty) return;
      final text = rawText
          .replaceAll('{text}', event['text']?.toString() ?? '')
          .replaceAll('{uid}', event['from_uid']?.toString() ?? '')
          .replaceAll('{conversation_id}', targetId);
      final cooldown = _intValue(
        action['cooldown_seconds'],
        60,
      ).clamp(0, 86400);
      final key = '$pluginId:$targetId';
      final last = _replyCooldowns[key];
      if (last != null && DateTime.now().difference(last).inSeconds < cooldown)
        return;
      _replyCooldowns[key] = DateTime.now();
      await _sendText(event, text);
      _log(plugin, '自动回复已发送');
      return;
    }
    if (type == 'send_image') {
      if (!_hasPermission(plugin, 'messages.send_image')) return;
      final url = action['media_url']?.toString().trim() ?? '';
      if (!_isSafeMediaUrl(url)) throw Exception('图片地址必须是 http(s) URL');
      await _queueReviewedAction(plugin, 'send_image', {
        'conversation_type': event['conversation_type'],
        'conversation_id': targetId,
        'media_url': url,
        'text': action['caption']?.toString() ?? '',
      });
      return;
    }
    if (type == 'send_redpacket') {
      if (!_hasPermission(plugin, 'redpacket.send')) return;
      await _queueReviewedAction(plugin, 'send_redpacket', {
        'target_id': targetId,
        'type': event['conversation_type'],
        'amount': _intValue(action['amount'], 0),
        'count': _intValue(action['count'], 1).clamp(1, 1000),
        'title': action['title']?.toString() ?? '恭喜发财',
      });
      return;
    }
    if (type == 'checkin') {
      if (_hasPermission(plugin, 'checkin.run')) {
        await ApiService().dailyCheckin();
        _log(plugin, '已完成每日签到');
      }
      return;
    }
    if (type == 'checkin_post' || type == 'moment') {
      final permission = type == 'moment' ? 'moments.post' : 'checkin.post';
      if (!_hasPermission(plugin, permission)) return;
      final mediaUrl = action['media_url']?.toString().trim();
      if (mediaUrl != null &&
          mediaUrl.isNotEmpty &&
          !_isSafeMediaUrl(mediaUrl)) {
        throw Exception('动态图片地址必须是 http(s) URL');
      }
      await _queueReviewedAction(plugin, type, {
        'text': action['text']?.toString() ?? '',
        if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
      });
      return;
    }
    if (type == 'apply_theme' && _hasPermission(plugin, 'theme.apply')) {
      throw Exception('主题需要在插件页面手动应用');
    }
  }

  Future<void> _sendText(Map<String, dynamic> event, String text) async {
    final body = jsonEncode({'v': 2, 'text': text});
    if (event['conversation_type'] == 'group') {
      await ApiService().sendGroupMessage(
        groupId: event['conversation_id'].toString(),
        body: body,
      );
    } else {
      await ApiService().sendDirectMessage(
        toUid: event['conversation_id'].toString(),
        body: body,
      );
    }
  }

  Future<void> _autoClaim(
    Map<String, dynamic> plugin,
    Map<String, dynamic> event,
  ) async {
    final packet = event['red_packet'];
    if (packet is! Map || !_hasPermission(plugin, 'redpacket.claim')) return;
    final config = plugin['config'] is Map
        ? Map<String, dynamic>.from(plugin['config'])
        : <String, dynamic>{};
    if (config['auto_claim'] != true) return;
    final packetId =
        (packet['packet_id'] ??
                packet['packetId'] ??
                packet['red_packet_id'] ??
                packet['redPacketId'] ??
                packet['id'])
            ?.toString()
            .trim() ??
        '';
    if (packetId.isEmpty) return;
    if (_claimedPacketIds.contains(packetId) ||
        _redPacketRetryAfter[packetId]?.isAfter(DateTime.now()) == true ||
        !_claimingPacketIds.add(packetId))
      return;
    try {
      final allowedTypes = config['conversation_types'] is List
          ? (config['conversation_types'] as List)
                .map((value) => value.toString())
                .toSet()
          : {'direct', 'group'};
      if (!allowedTypes.contains(event['conversation_type']?.toString()))
        return;
      final remainingCount = _intValue(
        packet['remaining_count'] ?? packet['remainingCount'],
        1,
      );
      final minRemainingCount = _intValue(
        config['min_remaining_count'],
        1,
      ).clamp(0, 100000);
      if (remainingCount < minRemainingCount) return;
      final currentUid = AuthService().userId;
      final senderUid = _packetFromUid(packet);
      if (config['skip_self'] == true &&
          currentUid != null &&
          currentUid.isNotEmpty &&
          senderUid.isNotEmpty &&
          senderUid == currentUid)
        return;
      final amount = _packetAmount(packet);
      final minAmount = _doubleValue(config['min_amount'], 0);
      final maxAmount = _doubleValue(config['max_amount'], 0);
      if (amount != null && amount < minAmount) return;
      if (amount != null && maxAmount > 0 && amount > maxAmount) return;
      if (config['only_unclaimed'] == true && _packetAlreadyClaimed(packet))
        return;
      final status = (packet['status'] ?? '').toString().toLowerCase();
      if (config['skip_expired'] == true &&
          {'expired', 'closed', 'finished'}.contains(status))
        return;
      if (config['skip_claimed'] == true &&
          (_packetAlreadyClaimed(packet) ||
              {'claimed', 'already_claimed'}.contains(status)))
        return;
      final maxPerMinute = _intValue(config['max_per_minute'], 3).clamp(1, 30);
      final dailyLimit = _intValue(config['daily_limit'], 30).clamp(1, 500);
      final now = DateTime.now();
      _redPacketClaims.removeWhere(
        (time) => now.difference(time) > const Duration(minutes: 1),
      );
      if (_redPacketClaims.length >= maxPerMinute) return;
      final today = _redPacketClaims
          .where(
            (time) =>
                time.year == now.year &&
                time.month == now.month &&
                time.day == now.day,
          )
          .length;
      if (today >= dailyLimit) return;
      await claimRedPacket(plugin['id'].toString(), packetId);
    } finally {
      _claimingPacketIds.remove(packetId);
    }
  }

  Future<void> claimRedPacket(String pluginId, String packetId) async {
    await load();
    final plugin = _plugins[pluginId];
    if (plugin == null ||
        plugin['enabled'] != true ||
        !_hasPermission(plugin, 'redpacket.claim')) {
      throw Exception('插件未启用或没有领取红包权限');
    }
    if (_claimedPacketIds.contains(packetId)) return;
    try {
      await ApiService().claimRedPacket(packetId);
    } on Exception catch (error) {
      final message = error.toString().toLowerCase();
      final terminal =
          message.contains('400') ||
          message.contains('404') ||
          message.contains('expired') ||
          message.contains('claimed');
      final transient = message.contains('401') || message.contains('429');
      if (terminal) {
        _claimedPacketIds.add(packetId);
        await _save();
      } else if (transient) {
        _redPacketRetryAfter[packetId] = DateTime.now().add(
          const Duration(seconds: 20),
        );
      }
      rethrow;
    }
    _claimedPacketIds.add(packetId);
    _redPacketClaims.add(DateTime.now());
    await _save();
    _log(plugin, '已领取红包 $packetId');
  }

  Future<void> _queueReviewedAction(
    Map<String, dynamic> plugin,
    String type,
    Map<String, dynamic> data,
  ) async {
    final text = data['text']?.toString() ?? data['title']?.toString() ?? '';
    final moderation = _moderate(text);
    if (!moderation.$1) throw Exception('内容未通过预检：${moderation.$2}');
    _pendingActions.add({
      'id': '${plugin['id']}-${DateTime.now().microsecondsSinceEpoch}',
      'plugin_id': plugin['id'],
      'plugin_name': plugin['name'],
      'type': type,
      'data': data,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'review': 'pending',
    });
    if (_pendingActions.length > 100)
      _pendingActions.removeRange(0, _pendingActions.length - 100);
    await _save();
    notifyListeners();
    _log(plugin, '已提交人工审核：$type');
  }

  (bool, String) _moderate(String text) {
    if (text.length > 2000) return (false, '文本超过 2000 字');
    if (text.contains('\u0000')) return (false, '文本包含控制字符');
    final blocked = RegExp(
      r'(token|password|passwd|api[_ -]?key|Bearer\s+[A-Za-z0-9._-]+)',
      caseSensitive: false,
    );
    if (blocked.hasMatch(text)) return (false, '疑似包含凭据');
    return (true, '');
  }

  Future<void> approvePending(String id) async {
    await load();
    final index = _pendingActions.indexWhere((item) => item['id'] == id);
    if (index < 0) throw Exception('审核项不存在');
    final item = Map<String, dynamic>.from(_pendingActions[index]);
    try {
      await _executeReviewed(
        item['type'].toString(),
        Map<String, dynamic>.from(item['data'] as Map),
      );
      _pendingActions.removeAt(index);
      await _save();
      notifyListeners();
    } catch (error) {
      item['error'] = error.toString();
      _pendingActions[index] = item;
      await _save();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rejectPending(String id) async {
    await load();
    _pendingActions.removeWhere((item) => item['id'] == id);
    await _save();
    notifyListeners();
  }

  Future<void> _executeReviewed(String type, Map<String, dynamic> data) async {
    switch (type) {
      case 'send_image':
        final url = data['media_url']?.toString() ?? '';
        if (!_isSafeMediaUrl(url)) throw Exception('图片地址无效');
        final body = jsonEncode({
          'v': 2,
          'text': data['text'] ?? '',
          'media_kind': 'image',
          'url': url,
          'media_url': url,
        });
        if (data['conversation_type'] == 'group') {
          await ApiService().sendGroupMessage(
            groupId: data['conversation_id'].toString(),
            body: body,
            msgType: 'image',
            mediaUrl: url,
          );
        } else {
          await ApiService().sendDirectMessage(
            toUid: data['conversation_id'].toString(),
            body: body,
            msgType: 'image',
            mediaUrl: url,
          );
        }
        break;
      case 'send_redpacket':
        final target = data['target_id'].toString();
        await ApiService().createRedPacket(
          targetId: target,
          amount: data['amount'].toString(),
          type: data['type'].toString(),
          count: _intValue(data['count'], 1),
          title: data['title']?.toString() ?? '恭喜发财',
        );
        break;
      case 'checkin_post':
        await ApiService().postCheckinWall(
          data['text']?.toString() ?? '',
          mediaUrls: [
            if (data['media_url'] != null) data['media_url'].toString(),
          ],
        );
        break;
      case 'moment':
        await ApiService().createMoment(
          body: data['text']?.toString() ?? '',
          imageUrl: data['media_url']?.toString(),
        );
        break;
      default:
        throw Exception('不支持的审核动作：$type');
    }
  }

  Future<void> applyTheme(
    String pluginId,
    AppThemeController controller,
  ) async {
    await load();
    final plugin = _plugins[pluginId];
    if (plugin == null ||
        plugin['enabled'] != true ||
        !_hasPermission(plugin, 'theme.apply'))
      throw Exception('插件未启用或没有主题权限');
    final theme = plugin['theme'];
    if (theme is! Map) throw Exception('插件没有主题定义');
    final primary = theme['primary']?.toString() ?? '';
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(primary))
      throw Exception('主题颜色无效');
    await controller.setPluginTheme(Map<String, dynamic>.from(theme));
    _log(plugin, '主题已应用');
  }

  bool _hasPermission(Map<String, dynamic> plugin, String permission) {
    final permissions = plugin['permissions'];
    return permissions is List &&
        permissions.map((value) => value.toString()).contains(permission);
  }

  bool _isSafeMediaUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  int _intValue(dynamic value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  void _log(Map<String, dynamic> plugin, String text) {
    final logs = plugin['logs'] is List ? plugin['logs'] as List : <dynamic>[];
    logs.add('${DateTime.now().toIso8601String()} $text');
    if (logs.length > 100) logs.removeRange(0, logs.length - 100);
    plugin['logs'] = logs;
    _save();
  }

  List<String> logs(String id) =>
      ((_plugins[id]?['logs'] as List?)
          ?.map((value) => value.toString())
          .toList() ??
      const <String>[]);

  Future<void> _save() async {
    final storage = AccountStorage.instance;
    await storage.setString('plugins', jsonEncode(_plugins.values.toList()));
    await storage.setString('plugin_pending', jsonEncode(_pendingActions));
    await storage.setString(
      'plugin_claimed_packets',
      _claimedPacketIds.join('\n'),
    );
  }

  Future<Map<String, dynamic>> importCipBytes(Uint8List bytes) async {
    await load();
    if (bytes.length > 2 * 1024 * 1024) throw Exception('CIP 文件不能超过 2 MiB');
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.length > 128) throw Exception('CIP 文件最多包含 128 个条目');
    ArchiveFile? manifestFile;
    ArchiveFile? mainFile;
    var total = 0;
    for (final entry in archive) {
      final path = entry.name.replaceAll('\\', '/');
      if (path.startsWith('/') || path.contains('..') || path.contains(':')) {
        throw Exception('CIP 包含不安全路径');
      }
      if (entry.isSymbolicLink) throw Exception('CIP 不允许符号链接');
      total += entry.size;
      if (total > 8 * 1024 * 1024) throw Exception('CIP 解压后不能超过 8 MiB');
      if (path == 'manifest.json') manifestFile = entry;
      if (path == 'main.lua') mainFile = entry;
      if (path.isNotEmpty &&
          !path.startsWith('assets/') &&
          path != 'manifest.json' &&
          path != 'main.lua') {
        throw Exception('CIP 根目录只允许 manifest.json、main.lua 和 assets/');
      }
      if (path.startsWith('assets/') && path.length > 8) {
        final assetName = path.substring(7);
        if (assetName.isEmpty ||
            assetName.startsWith('/') ||
            assetName.contains('..')) {
          throw Exception('CIP 资源路径无效');
        }
      }
    }
    if (manifestFile == null || mainFile == null)
      throw Exception('CIP 缺少 manifest.json 或 main.lua');
    final manifestBytes = manifestFile.readBytes();
    if (manifestBytes == null) throw Exception('CIP manifest 读取失败');
    final manifestValue = tryDecodeJson<dynamic>(
      utf8.decode(manifestBytes, allowMalformed: false),
    );
    if (manifestValue is! Map) throw Exception('manifest.json 必须是有效 JSON 对象');
    final manifest = Map<String, dynamic>.from(manifestValue);
    final plugin = _sanitizeManifest(manifest);
    if (plugin == null) throw Exception('CIP manifest 无效');
    final requested = manifest['permissions'] is List
        ? (manifest['permissions'] as List)
              .map((value) => value.toString())
              .toSet()
        : <String>{};
    final rejected = requested.difference(allowedPermissions);
    if (rejected.isNotEmpty)
      throw Exception('CIP 包含不支持的权限：${rejected.join(', ')}');
    final scriptBytes = mainFile.readBytes();
    if (scriptBytes == null) throw Exception('CIP main.lua 读取失败');
    final script = utf8.decode(scriptBytes, allowMalformed: false);
    if (script.length > 512 * 1024) throw Exception('CIP 脚本超过 512 KiB');
    plugin['cip_main'] = script;
    await registerManifest(plugin);
    _plugins[plugin['id'] as String]?['cip_main'] = script;
    await _save();
    notifyListeners();
    return plugin;
  }

  dynamic _luaValue(LuaState ls, int index, [int depth = 0]) {
    if (depth > 8) return null;
    final absoluteIndex = ls.absIndex(index);
    if (ls.isNil(absoluteIndex)) return null;
    if (ls.isFunction(absoluteIndex)) {
      ls.pushValue(absoluteIndex);
      final reference = ls.ref(luaRegistryIndex);
      return {'__lua_callback_ref': reference};
    }
    if (ls.isString(absoluteIndex)) return ls.toStr(absoluteIndex);
    if (ls.isBoolean(absoluteIndex)) return ls.toBoolean(absoluteIndex);
    if (ls.isNumber(absoluteIndex)) return ls.toNumberX(absoluteIndex);
    if (!ls.isTable(absoluteIndex)) return null;
    final entries = <dynamic, dynamic>{};
    ls.pushValue(absoluteIndex);
    final tableIndex = ls.absIndex(-1);
    ls.pushNil();
    while (ls.next(tableIndex)) {
      final key = ls.isNumber(-2) ? ls.toInteger(-2) : (ls.toStr(-2) ?? '');
      final value = _luaValue(ls, -1, depth + 1);
      entries[key] = value;
      ls.pop(1);
    }
    ls.pop(1);
    final numericKeys = entries.keys.whereType<int>().toList()..sort();
    if (numericKeys.isNotEmpty &&
        numericKeys.length == entries.length &&
        numericKeys.first == 1 &&
        numericKeys.last == numericKeys.length) {
      return numericKeys.map((key) => entries[key]).toList();
    }
    return entries.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, dynamic>? _normalizeUiTree(Map<String, dynamic> raw, [String path = '0']) {
    final rawType = raw['type'] ?? raw['kind'] ?? raw['view'] ?? raw['widget'];
    final type = rawType?.toString().toLowerCase() ?? 'text';
    const aliases = {
      'screen': 'page',
      'container': 'column',
      'vertical': 'column',
      'horizontal': 'row',
      'label': 'text',
      'edittext': 'input',
      'checkboxlisttile': 'checkbox',
    };
    final normalizedType = aliases[type] ?? type;
    const allowed = {
      'page', 'text', 'button', 'image', 'input', 'checkbox', 'list',
      'spacer', 'column', 'row',
    };
    if (!allowed.contains(normalizedType)) return null;
    final children = <Map<String, dynamic>>[];
    final rawChildren = raw['children'] ?? raw['items'] ?? raw['child'] ?? raw['content'];
    final childValues = rawChildren is List
        ? rawChildren
        : rawChildren is Map
            ? rawChildren.values.toList()
            : rawChildren == null
                ? const <dynamic>[]
                : <dynamic>[rawChildren];
    for (final child in childValues.whereType<Map>()) {
      final normalized = _normalizeUiTree(
        Map<String, dynamic>.from(child),
        '$path.${children.length}',
      );
      if (normalized != null) children.add(normalized);
    }
    final result = <String, dynamic>{'type': normalizedType};
    if ((normalizedType == 'button' || normalizedType == 'input' || normalizedType == 'checkbox') &&
        (raw['id'] == null || raw['id'].toString().isEmpty)) {
      final label = (raw['label'] ?? raw['text'] ?? normalizedType).toString();
      result['id'] = '$path:$normalizedType:$label';
    }
    for (final key in const [
      'title', 'text', 'label', 'value', 'placeholder', 'hint', 'src', 'url',
      'action', 'id', 'plugin_id', 'size', 'color', 'height', 'margin',
      'visible', 'enabled', 'single_line', 'input_type', 'max_length',
    ]) {
      final value = raw[key];
      if (value != null) result[key] = value;
    }
    if (raw['checked'] is bool) result['checked'] = raw['checked'];
    for (final entry in const [
      MapEntry('on_click', 'callback_ref'),
      MapEntry('on_change', 'change_callback_ref'),
      MapEntry('on_submit', 'submit_callback_ref'),
      MapEntry('on_focus_lost', 'focus_lost_callback_ref'),
    ]) {
      final callback = raw[entry.key];
      if (callback is Map && callback['__lua_callback_ref'] is num) {
        result[entry.value] = (callback['__lua_callback_ref'] as num).toInt();
      }
    }
    if (raw['callback_ref'] is num) result['callback_ref'] = (raw['callback_ref'] as num).toInt();
    if (children.isNotEmpty) result['children'] = children;
    return result;
  }

  Future<void> executeCip(
    String id,
    String mainLua, {
    Map<String, dynamic>? event,
  }) async {
    await load();
    final plugin = _plugins[id];
    if (plugin == null || plugin['enabled'] != true) {
      throw Exception('CIP 未启用');
    }
    if (mainLua.length > 512 * 1024) throw Exception('CIP 脚本超过 512 KiB');
    final permissions =
        (plugin['permissions'] as List?)
            ?.map((value) => value.toString())
            .toSet() ??
        <String>{};
    await AccountStorage.instance.load();
    final storage = AccountStorage.instance;
    final storagePrefix = 'cip:${plugin['id']}:';
    final state = LuaState.newState();
    state.openLibs();
    if (event != null) {
      state.pushString(event['type']?.toString() ?? 'message.received');
      state.setGlobal('event_type');
      state.pushString(event['text']?.toString() ?? '');
      state.setGlobal('event_text');
      state.pushString(event['conversation_id']?.toString() ?? '');
      state.setGlobal('conversation_id');
      state.pushString(event['from_uid']?.toString() ?? '');
      state.setGlobal('from_uid');
      state.newTable();
      final eventValues = <String, dynamic>{
        'type': event['type'],
        'conversation_type': event['conversation_type'],
        'conversation_id': event['conversation_id'],
        'message_id': event['message_id'],
        'from_uid': event['from_uid'],
        'text': event['text'],
        'msg_type': event['msg_type'],
        'created_at': event['created_at'],
        'media_url': event['media_url'],
        'action': event['action'],
        'node_id': event['node_id'],
        'value': event['value'],
      };
      for (final entry in eventValues.entries) {
        if (entry.value == null) continue;
        if (entry.value is num) {
          state.pushNumber((entry.value as num).toDouble());
        } else if (entry.value is bool) {
          state.pushBoolean(entry.value as bool);
        } else {
          state.pushString(entry.value.toString());
        }
        state.setField(-2, entry.key);
      }
      state.setGlobal('event');
    }
    for (final name in const [
      'io',
      'os',
      'debug',
      'package',
      'require',
      'dofile',
      'loadfile',
      'load',
      'collectgarbage',
    ]) {
      state.pushNil();
      state.setGlobal(name);
    }

    int toast(LuaState ls) {
      final text = ls.optString(1, '') ?? '';
      _log(plugin, 'CIP: $text');
      unawaited(
        NotificationService().showNotification(
          title: plugin['name']?.toString() ?? 'CIP',
          body: text,
        ),
      );
      return 0;
    }

    int deniedCapability(LuaState ls) {
      ls.pushNil();
      ls.pushString('capability is not available in this Windows host build');
      return 2;
    }

    int fileRead(LuaState ls) {
      if (!permissions.contains('files.local')) return deniedCapability(ls);
      ls.pushNil();
      ls.pushString('use app_file_pick() to let the user choose a file');
      return 2;
    }

    int camera(LuaState ls) {
      if (!permissions.contains('camera')) return deniedCapability(ls);
      ls.pushNil();
      ls.pushString('use app_camera_capture() to request a camera capture');
      return 2;
    }

    int storageGet(LuaState ls) {
      if (!permissions.contains('storage') &&
          !permissions.contains('storage.local')) {
        ls.pushNil();
        return 1;
      }
      final key = ls.optString(1, '') ?? '';
      final value = storage.getString('$storagePrefix$key');
      if (value == null) {
        ls.pushNil();
      } else {
        ls.pushString(value);
      }
      return 1;
    }

    int storageSet(LuaState ls) {
      if (!permissions.contains('storage') &&
          !permissions.contains('storage.local')) {
        return 0;
      }
      final key = ls.optString(1, '') ?? '';
      final value = ls.optString(2, '') ?? '';
      unawaited(storage.setString('$storagePrefix$key', value));
      return 0;
    }

    int storageRemove(LuaState ls) {
      if (!permissions.contains('storage') &&
          !permissions.contains('storage.local')) {
        return 0;
      }
      final key = ls.optString(1, '') ?? '';
      unawaited(storage.remove('$storagePrefix$key'));

      return 0;
    }

    int storageClear(LuaState ls) {
      if (!permissions.contains('storage') &&
          !permissions.contains('storage.local')) {
        return 0;
      }
      for (final key in storage.keys.where(
        (key) => key.startsWith(storagePrefix),
      )) {
        unawaited(storage.remove(key));
      }
      return 0;
    }

    int asset(LuaState ls) {
      final name = ls.optString(1, '') ?? '';
      if (name.isEmpty || name.contains('..') || name.contains('\\')) {
        ls.pushNil();
      } else {
        ls.pushString('cip://$id/assets/$name');
      }
      return 1;
    }

    int widgetFactory(LuaState ls) {
      if (ls.getTop() > 0 && ls.isTable(1)) {
        ls.pushValue(1);
      } else {
        ls.newTable();
      }
      return 1;
    }

    int widgetResult(LuaState ls) {
      if (ls.getTop() <= 0) {
        ls.pushNil();
        return 1;
      }
      final result = _luaValue(ls, -1);
      if (result is! Map) {
        ls.pushNil();
        return 1;
      }
      final normalized = _normalizeUiTree(Map<String, dynamic>.from(result));
      if (normalized == null) {
        ls.pushNil();
        return 1;
      }
      normalized['plugin_id'] = id;
      _uiResults[id] = normalized;
      notifyListeners();
      ls.pushValue(-1);
      return 1;
    }

    void installTable(String name, Map<String, DartFunction> functions) {
      state.newTable();
      for (final entry in functions.entries) {
        state.pushDartFunction(entry.value);
        state.setField(-2, entry.key);
      }
      state.setGlobal(name);
    }

    state.register('app_toast', toast);
    state.register('app_camera', camera);
    state.register('app_file_read', fileRead);
    state.register('app_storage_get', storageGet);
    state.register('app_storage_set', storageSet);
    state.register('app_storage_remove', storageRemove);
    state.register('app_storage_clear', storageClear);
    dynamic luaArgument(LuaState ls, int index) {
      final absolute = ls.absIndex(index);
      if (ls.isBoolean(absolute)) return ls.toBoolean(absolute);
      if (ls.isNumber(absolute)) return ls.toNumberX(absolute);
      if (ls.isString(absolute)) return ls.toStr(absolute);
      return null;
    }

    String? getUiText(String nodeId) {
      final node = _findUiNode(_uiResults[id], nodeId);
      return node?['text']?.toString();
    }

    int getText(LuaState ls) {
      final value = getUiText(ls.optString(1, '') ?? '');
      if (value == null) {
        ls.pushNil();
      } else {
        ls.pushString(value);
      }
      return 1;
    }

    int appendText(LuaState ls) {
      final nodeId = ls.optString(1, '') ?? '';
      final suffix = ls.optString(2, '') ?? '';
      final root = _uiResults[id];
      if (root != null) {
        _setUiFieldValue(root, nodeId, 'text', '${getUiText(nodeId) ?? ''}$suffix');
      }
      notifyListeners();
      return 0;
    }

    int getChecked(LuaState ls) {
      final checked = _findUiField(
            _uiResults[id],
            ls.optString(1, '') ?? '',
            'checked',
          ) ==
          true;
      ls.pushBoolean(checked);
      return 1;
    }

    int setChecked(LuaState ls) {
      final root = _uiResults[id];
      if (root != null) {
        _setUiFieldValue(
          root,
          ls.optString(1, '') ?? '',
          'checked',
          luaArgument(ls, 2) == true,
        );
      }
      notifyListeners();
      return 0;
    }

    int getVisible(LuaState ls) {
      final visible = _findUiField(
            _uiResults[id],
            ls.optString(1, '') ?? '',
            'visible',
          ) !=
          false;
      ls.pushBoolean(visible);
      return 1;
    }

    int focus(LuaState ls) {
      final nodeId = ls.optString(1, '') ?? '';
      final root = _uiResults[id];
      if (root != null) _setUiFieldValue(root, nodeId, 'focus_requested', true);
      notifyListeners();
      return 0;
    }

    int jsonDecodeApi(LuaState ls) {
      try {
        _pushLuaValue(ls, jsonDecode(ls.optString(1, '') ?? ''));
      } catch (_) {
        ls.pushNil();
      }
      return 1;
    }

    int jsonEncodeApi(LuaState ls) {
      ls.pushString(jsonEncode(_luaValue(ls, 1)));
      return 1;
    }

    int setUiField(LuaState ls, String field) {
      final nodeId = ls.optString(1, '') ?? '';
      final value = luaArgument(ls, 2)?.toString() ?? '';
      final root = _uiResults[id];
      if (root != null) _setUiField(root, nodeId, field, value);
      notifyListeners();
      return 0;
    }

    int setVisible(LuaState ls) => setUiField(ls, 'visible');
    int setEnabled(LuaState ls) => setUiField(ls, 'enabled');
    int setText(LuaState ls) => setUiField(ls, 'text');
    int setImage(LuaState ls) => setUiField(ls, 'src');
    int setHint(LuaState ls) => setUiField(ls, 'hint');

    state.register('app_asset', asset);
    state.registerAsync('app_http_get', (LuaState ls) async {
      if (!permissions.contains('network') &&
          !permissions.contains('network_external')) {
        ls.pushNil();
        ls.pushString('network permission is required');
        return 2;
      }
      final target = ls.optString(1, '') ?? '';
      final isLocal = target.startsWith('/') &&
          !target.contains('..') &&
          !target.contains('\\');
      final uri = Uri.tryParse(target);
      final isExternal = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          permissions.contains('network_external');
      if (!isLocal && !isExternal) {
        ls.pushNil();
        ls.pushString('invalid or unauthorized path');
        return 2;
      }
      final hasCallback = ls.getTop() >= 2 && ls.isFunction(2);
      var callbackRef = -1;
      if (hasCallback) {
        ls.pushValue(2);
        callbackRef = ls.ref(luaRegistryIndex);
      }
      dynamic value;
      String? error;
      try {
        value = isLocal
            ? await ApiService().getRaw(target)
            : await Dio().get<dynamic>(
                target,
                options: Options(responseType: ResponseType.json),
              ).then((response) => response.data);
      } catch (e) {
        error = e.toString();
      }
      if (callbackRef >= 0) {
        ls.rawGetI(luaRegistryIndex, callbackRef);
        if (value == null) {
          ls.pushNil();
        } else {
          ls.pushString(value is String ? value : jsonEncode(value));
        }
        if (error == null) {
          ls.pushNil();
        } else {
          ls.pushString(error);
        }
        await ls.callAsync(2, 0);
        ls.unRef(luaRegistryIndex, callbackRef);
        return 0;
      }
      if (value == null) {
        ls.pushNil();
        ls.pushString(error ?? 'request failed');
      } else {
        ls.pushString(value is String ? value : jsonEncode(value));
        ls.pushNil();
      }
      return 2;
    });
    state.register('app_set_text', setText);
    state.register('app_set_image', setImage);
    state.register('app_set_visible', setVisible);
    state.register('app_set_enabled', setEnabled);
    state.register('app_set_hint', setHint);
    state.register('app_get_text', getText);
    state.register('app_append_text', appendText);
    state.register('app_get_checked', getChecked);
    state.register('app_set_checked', setChecked);
    state.register('app_get_visible', getVisible);
    state.register('app_focus', focus);
    state.register('app_json_decode', jsonDecodeApi);
    state.register('app_json_encode', jsonEncodeApi);
    state.register('app_delay', (LuaState ls) {
      final milliseconds = (ls.toNumberX(1) ?? 0).clamp(0, 60000).toInt();
      if (ls.getTop() >= 2 && ls.isFunction(2)) {
        ls.pushValue(2);
        final callbackRef = ls.ref(luaRegistryIndex);
        Future<void>.delayed(Duration(milliseconds: milliseconds), () async {
          try {
            state.rawGetI(luaRegistryIndex, callbackRef);
            if (state.isFunction(-1)) await state.callAsync(0, 0);
          } finally {
            state.unRef(luaRegistryIndex, callbackRef);
          }
        });
      }
      return 0;
    });
    installTable('app', {
      'toast': toast,
      'camera': camera,
      'file_read': fileRead,
      'storage_get': storageGet,
      'storage_set': storageSet,
      'storage_remove': storageRemove,
      'storage_clear': storageClear,
      'asset': asset,
      'set_text': setText,
      'append_text': appendText,
      'get_text': getText,
      'set_image': setImage,
      'set_visible': setVisible,
      'get_visible': getVisible,
      'set_enabled': setEnabled,
      'set_hint': setHint,
      'get_checked': getChecked,
      'set_checked': setChecked,
      'focus': focus,
      'json_decode': jsonDecodeApi,
      'json_encode': jsonEncodeApi,
      'delay': (LuaState ls) {
        final milliseconds = (ls.toNumberX(1) ?? 0).clamp(0, 60000).toInt();
        if (ls.getTop() >= 2 && ls.isFunction(2)) {
          ls.pushValue(2);
          final callbackRef = ls.ref(luaRegistryIndex);
          Future<void>.delayed(Duration(milliseconds: milliseconds), () async {
            try {
              state.rawGetI(luaRegistryIndex, callbackRef);
              if (state.isFunction(-1)) await state.callAsync(0, 0);
            } finally {
              state.unRef(luaRegistryIndex, callbackRef);
            }
          });
        }
        return 0;
      },
    });
    installTable('ui', {
      'page': widgetFactory,
      'text': widgetFactory,
      'label': widgetFactory,
      'button': widgetFactory,
      'image': widgetFactory,
      'input': widgetFactory,
      'checkbox': widgetFactory,
      'list': widgetFactory,
      'scroll': widgetFactory,
      'spacer': widgetFactory,
    });
    state.register('ui_result', widgetResult);
    state.register('ui_clear', (LuaState ls) {
      _uiResults.remove(id);
      notifyListeners();
      return 0;
    });
    state.registerAsync('app_file_pick', (LuaState ls) async {
      if (!permissions.contains('files.local')) return deniedCapability(ls);
      try {
        final result = await pickFilesCompat(
          withData: false,
          allowMultiple: false,
        );
        final selectedFiles = filePickerFiles(result);
        final selected = selectedFiles.isNotEmpty ? selectedFiles.first : null;
        if (selected == null) {
          ls.pushNil();
          ls.pushString('file selection cancelled');
          return 2;
        }
        final bytes = await filePickerBytes(selected);
        if (bytes == null || bytes.isEmpty) {
          ls.pushNil();
          ls.pushString('file selection failed: unable to read selected file');
          return 2;
        }
        ls.pushString(
          jsonEncode({
            'name': selected.name,
            'size': bytes.length,
            'base64': base64Encode(bytes),
          }),
        );
        ls.pushNil();
      } catch (error) {
        ls.pushNil();
        ls.pushString('file selection failed: $error');
      }
      return 2;
    });
    state.registerAsync('app_camera_capture', (LuaState ls) async {
      if (!permissions.contains('camera')) return deniedCapability(ls);
      CameraController? controller;
      try {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          ls.pushNil();
          ls.pushString('no Windows camera is available');
          return 2;
        }
        controller = CameraController(
          cameras.first,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await controller.initialize();
        final picture = await controller.takePicture();
        ls.pushString(picture.path);
        ls.pushNil();
      } catch (error) {
        ls.pushNil();
        ls.pushString('camera capture failed: $error');
      } finally {
        await controller?.dispose();
      }
      return 2;
    });
    final status = await state.doStringAsync(mainLua);
    if (!status) throw Exception('CIP 执行失败：脚本语法或宿主调用无效');
    final top = state.getTop();
    if (top > 0) {
      Map<String, dynamic>? normalized;
      for (var index = top; index >= 1 && normalized == null; index--) {
        final returned = _luaValue(state, index);
        if (returned is Map) {
          normalized = _normalizeUiTree(Map<String, dynamic>.from(returned));
        }
      }
      if (normalized != null) {
        normalized['plugin_id'] = id;
        _uiResults[id] = normalized;
      }
    }
    _cipStates[id] = state;
    state.setTop(0);
    _log(plugin, 'CIP 执行完成');
    notifyListeners();
  }

  Future<void> executeCipCallback(
    String id,
    int callbackRef,
  ) async {
    await load();
    final state = _cipStates[id];
    if (state == null) throw Exception('CIP 页面已失效，请重新运行');
    state.setTop(0);
    state.rawGetI(luaRegistryIndex, callbackRef);
    if (!state.isFunction(-1)) {
      state.setTop(0);
      throw Exception('CIP 按钮回调不存在');
    }
    final status = await state.pCallAsync(0, luaMultret, 0);
    if (status != ThreadStatus.luaOk) {
      state.setTop(0);
      throw Exception('CIP 按钮执行失败');
    }
    final top = state.getTop();
    if (top > 0) {
      Map<String, dynamic>? normalized;
      for (var index = top; index >= 1 && normalized == null; index--) {
        final returned = _luaValue(state, index);
        if (returned is Map) {
          normalized = _normalizeUiTree(Map<String, dynamic>.from(returned));
        }
      }
      if (normalized != null) {
        normalized['plugin_id'] = id;
        _uiResults[id] = normalized;
      }
    }
    state.setTop(0);
    notifyListeners();
  }

  Map<String, dynamic>? _findUiNode(Map<String, dynamic>? node, String id) {
    if (node == null) return null;
    if (node['id']?.toString() == id) return node;
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map) {
          final found = _findUiNode(Map<String, dynamic>.from(child), id);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  dynamic _findUiField(Map<String, dynamic>? node, String id, String field) =>
      _findUiNode(node, id)?[field];

  void _setUiFieldValue(Map<String, dynamic> node, String id, String field, dynamic value) {
    if (node['id']?.toString() == id) node[field] = value;
    final children = node['children'];
    if (children is List) {
      for (var index = 0; index < children.length; index++) {
        final child = children[index];
        if (child is Map) {
          final childMap = Map<String, dynamic>.from(child);
          _setUiFieldValue(childMap, id, field, value);
          children[index] = childMap;
        }
      }
    }
  }

  void _setUiField(Map<String, dynamic> node, String id, String field, String value) =>
      _setUiFieldValue(node, id, field, value);

  void _pushLuaValue(LuaState ls, dynamic value, [int depth = 0]) {
    if (depth > 8 || value == null) {
      ls.pushNil();
    } else if (value is bool) {
      ls.pushBoolean(value);
    } else if (value is num) {
      ls.pushNumber(value.toDouble());
    } else if (value is String) {
      ls.pushString(value);
    } else if (value is List) {
      ls.newTable();
      for (var index = 0; index < value.length; index++) {
        _pushLuaValue(ls, value[index], depth + 1);
        ls.setI(-2, index + 1);
      }
    } else if (value is Map) {
      ls.newTable();
      for (final entry in value.entries) {
        _pushLuaValue(ls, entry.value, depth + 1);
        ls.setField(-2, entry.key.toString());
      }
    } else {
      ls.pushString(value.toString());
    }
  }

  bool _packetAlreadyClaimed(Map packet) {
    final claimed =
        packet['claimed'] ?? packet['is_claimed'] ?? packet['has_claimed'];
    return claimed == true || claimed?.toString().toLowerCase() == 'true';
  }

  String _packetFromUid(Map packet) {
    return (packet['from_uid'] ??
            packet['sender_uid'] ??
            packet['sender_id'] ??
            '')
        .toString();
  }

  double? _packetAmount(Map packet) {
    final value =
        packet['amount'] ?? packet['total_amount'] ?? packet['totalAmount'];
    return double.tryParse(value?.toString() ?? '');
  }

  double _doubleValue(dynamic value, double fallback) {
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
