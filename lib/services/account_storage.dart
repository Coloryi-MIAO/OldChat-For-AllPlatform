import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class AccountStorage {
  AccountStorage._();

  static final AccountStorage instance = AccountStorage._();

  String? _userId;
  Directory? _directory;
  Map<String, dynamic> _values = <String, dynamic>{};
  final Map<String, Future<void>> _saveQueues = <String, Future<void>>{};

  String get userId => _userId ?? 'guest';

  Future<void> load({String? userId}) async {
    final normalized = (userId ?? AuthService().userId ?? 'guest').trim();
    final id = normalized.isEmpty ? 'guest' : normalized;
    if (_directory != null && _userId == id) return;
    await _waitForSave(id);
    _userId = id;
    _directory = await _accountDirectory(id);
    final file = File('${_directory!.path}${Platform.pathSeparator}settings.json');
    _values = <String, dynamic>{};
    if (!await file.exists()) return;
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is Map) _values = Map<String, dynamic>.from(decoded);
    } on FormatException {
      try {
        await file.rename('${file.path}.invalid-${DateTime.now().microsecondsSinceEpoch}');
      } catch (_) {}
    } catch (_) {}
  }

  T? get<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  dynamic getValue(String key) => _values[key];
  Set<String> get keys => _values.keys.toSet();
  String? getString(String key) => get<String>(key);
  bool? getBool(String key) => get<bool>(key);
  int? getInt(String key) => _values[key] is num ? (_values[key] as num).toInt() : null;
  double? getDouble(String key) => _values[key] is num ? (_values[key] as num).toDouble() : null;

  Future<void> setString(String key, String value) => setValue(key, value);
  Future<void> setBool(String key, bool value) => setValue(key, value);
  Future<void> setInt(String key, int value) => setValue(key, value);
  Future<void> setDouble(String key, double value) => setValue(key, value);

  Future<void> setValue(String key, dynamic value) async {
    if (value == null) {
      _values.remove(key);
    } else if (value is String || value is bool || value is num) {
      _values[key] = value;
    } else {
      throw ArgumentError.value(value, 'value', 'Only JSON scalar values are supported');
    }
    await _save();
  }

  Future<void> remove(String key) async {
    _values.remove(key);
    await _save();
  }

  // ★ 修改点：增加重试机制，最多重试 3 次，每次延迟递增
  Future<void> _save() {
    final id = _userId ?? userId;
    final snapshot = jsonEncode(Map<String, dynamic>.from(_values));
    final directoryFuture = _accountDirectory(id);
    final previous = _saveQueues[id] ?? Future<void>.value();
    final operation = previous.then<void>((_) async {
      final directory = await directoryFuture;
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}${Platform.pathSeparator}settings.json',
      );
      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );

      // 重试循环
      int retry = 0;
      while (retry < 3) {
        try {
          await temporary.writeAsString(snapshot, flush: true);
          try {
            await temporary.rename(file.path);
          } on FileSystemException {
            if (await file.exists()) await file.delete();
            if (!await temporary.exists()) rethrow;
            await temporary.rename(file.path);
          }
          // 成功则跳出循环
          break;
        } on FileSystemException catch (e) {
          retry++;
          if (retry >= 3) rethrow; // 重试次数用尽，抛出异常
          // 延迟后重试（50ms, 100ms, 150ms）
          await Future.delayed(Duration(milliseconds: 50 * retry));
        } finally {
          // 清理临时文件（如果还存在）
          if (await temporary.exists()) {
            try {
              await temporary.delete();
            } catch (_) {}
          }
        }
      }
    });
    _saveQueues[id] = operation.catchError((_) {});
    return operation;
  }

  Future<void> _waitForSave(String id) async {
    final pending = _saveQueues[id];
    if (pending != null) await pending;
  }

  Future<Directory> _accountDirectory(String id) async {
    final appData = Platform.isWindows ? Platform.environment['APPDATA'] : null;
    final root = appData == null || appData.isEmpty
        ? await getApplicationSupportDirectory()
        : Directory('$appData${Platform.pathSeparator}OldChat_For_AllPlatform');
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return Directory('${root.path}${Platform.pathSeparator}accounts${Platform.pathSeparator}$safeId');
  }

  Future<void> migrateLegacyKeys(Iterable<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final key in keys) {
      if (_values.containsKey(key)) continue;
      final value = prefs.get(key);
      if (value is String || value is bool || value is num) {
        _values[key] = value;
        changed = true;
      }
    }
    if (changed) await _save();
  }

  Future<void> resetSettings() async {
    final deviceId = _values['device_id'];
    _values = <String, dynamic>{if (deviceId is String) 'device_id': deviceId};
    await _save();
  }

  Future<void> reset() async {
    await Future.wait(_saveQueues.values.toList());
    _userId = null;
    _directory = null;
    _values = <String, dynamic>{};
  }
}