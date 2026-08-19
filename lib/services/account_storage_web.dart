import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AccountStorage {
  AccountStorage._();
  static final AccountStorage instance = AccountStorage._();
  String? _userId;
  Map<String, dynamic> _values = {};
  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();
  String get userId => _userId ?? 'guest';

  String _key(String id) => 'oldchat.account.$id.settings';
  Future<void> load({String? userId}) async {
    final id = (userId ?? 'guest').trim().isEmpty
        ? 'guest'
        : (userId ?? 'guest').trim();
    _userId = id;
    final raw = (await _prefs).getString(_key(id));
    if (raw == null || raw.isEmpty) {
      _values = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      _values = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      _values = {};
    }
  }

  T? get<T>(String key) => _values[key] is T ? _values[key] as T : null;
  dynamic getValue(String key) => _values[key];
  Set<String> get keys => _values.keys.toSet();
  String? getString(String key) => get<String>(key);
  bool? getBool(String key) => get<bool>(key);
  int? getInt(String key) =>
      _values[key] is num ? (_values[key] as num).toInt() : null;
  double? getDouble(String key) =>
      _values[key] is num ? (_values[key] as num).toDouble() : null;
  Future<void> setString(String key, String value) => setValue(key, value);
  Future<void> setBool(String key, bool value) => setValue(key, value);
  Future<void> setInt(String key, int value) => setValue(key, value);
  Future<void> setDouble(String key, double value) => setValue(key, value);
  Future<void> setValue(String key, dynamic value) async {
    _values[key] = value;
    await (await _prefs).setString(_key(userId), jsonEncode(_values));
  }

  Future<void> remove(String key) async {
    _values.remove(key);
    await (await _prefs).setString(_key(userId), jsonEncode(_values));
  }

  Future<void> migrateLegacyKeys(Iterable<String> keys) async {
    final prefs = await _prefs;
    var changed = false;
    for (final key in keys) {
      if (_values.containsKey(key)) continue;
      final value = prefs.get(key);
      if (value is String || value is bool || value is num) {
        _values[key] = value;
        changed = true;
      }
    }
    if (changed)
      await (await _prefs).setString(_key(userId), jsonEncode(_values));
  }

  Future<void> resetSettings() async {
    final deviceId = _values['device_id'];
    _values = {if (deviceId is String) 'device_id': deviceId};
    await (await _prefs).setString(_key(userId), jsonEncode(_values));
  }

  Future<void> reset() async {
    if (_userId != null) await (await _prefs).remove(_key(_userId!));
    _userId = null;
    _values = {};
  }
}
