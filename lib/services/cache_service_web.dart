import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;
  CacheService._();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();
  String scoped(String userId, String name) => 'oldchat:$userId:$name';
  Future<String> directory({String? userId}) async => 'browser-storage';
  Future<String> cacheDirectory({String? userId}) => directory(userId: userId);
  Future<void> ensureUserDirectory(String userId) async {}

  Future<void> writeJson(String key, Object value) async {
    final prefs = await _prefs;
    await prefs.setString(key, jsonEncode(value));
  }

  Future<dynamic> readJson(String key) async {
    final raw = (await _prefs).getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async => (await _prefs).remove(key);
  Future<void> setLocation(String path) async {}
  Future<int> sizeBytes() async {
    final prefs = await _prefs;
    return prefs
        .getKeys()
        .where((key) => key.startsWith('oldchat:'))
        .fold<int>(
          0,
          (total, key) => total + (prefs.getString(key)?.length ?? 0),
        );
  }

  Future<int> get count async => (await _prefs)
      .getKeys()
      .where((key) => key.startsWith('oldchat:'))
      .length;

  Future<void> clear() => clearClientCache();
  Future<void> clearClientCache() async {
    final prefs = await _prefs;
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith('oldchat:'))
            .toList()) {
      await prefs.remove(key);
    }
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<void> setCacheLocation(String path) => setLocation(path);
}
