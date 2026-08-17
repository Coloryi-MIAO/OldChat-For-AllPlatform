import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const _locationKey = 'client_cache_directory';
  static const _encryptedMarker = 'dpapi:';

  String _defaultUserCacheRoot(String userId) {
    final appData = Platform.environment['APPDATA'];
    final root = appData == null || appData.isEmpty
        ? _defaultDocumentsRoot()
        : '$appData${Platform.pathSeparator}OldChat_For_AllPlatform';
    return '$root${Platform.pathSeparator}accounts${Platform.pathSeparator}$userId';
  }

  String _defaultDocumentsRoot() {
    final documents = Platform.environment['USERPROFILE'] == null
        ? (Platform.environment['HOME'] ?? '.')
        : '${Platform.environment['USERPROFILE']}${Platform.pathSeparator}Documents';
    return '$documents${Platform.pathSeparator}OldChat_Documents';
  }

  String _protect(String value) {
    if (value.isEmpty) return '';
    return _encryptedMarker + base64Encode(utf8.encode(value));
  }

  String _unprotect(String value) {
    if (value.isEmpty) return '';
    if (!value.startsWith(_encryptedMarker)) return value;
    try {
      return utf8.decode(base64Decode(value.substring(_encryptedMarker.length)));
    } on FormatException {
      return '';
    } catch (_) {
      return '';
    }
  }

  String _userIdFromKey(String key) {
    const prefix = 'oldchat:';
    if (!key.startsWith(prefix)) return '';
    final rest = key.substring(prefix.length);
    final separator = rest.indexOf(':');
    return separator == -1 ? rest : rest.substring(0, separator);
  }

  String _safeFileName(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<File> _fileForKey(String key) async {
    final userId = _userIdFromKey(key);
    final dir = await directory(userId: userId.isEmpty ? null : userId);
    return File(
      '${dir.path}${Platform.pathSeparator}${_safeFileName(key)}.json.enc',
    );
  }

  Future<void> writeJson(String key, Object value) async {
    final watch = Stopwatch()..start();
    final file = await _fileForKey(key);
    await file.writeAsString(_protect(jsonEncode(value)), flush: true);
    watch.stop();
    print('[缓存慢] 写入 ${watch.elapsedMilliseconds}ms ${file.path}');
  }

  Future<dynamic> readJson(String key) async {
    final watch = Stopwatch()..start();
    final file = await _fileForKey(key);
    String? encoded;
    if (await file.exists()) {
      encoded = await file.readAsString();
    } else {
      final prefs = await SharedPreferences.getInstance();
      encoded = prefs.getString(key);
      if (encoded != null && encoded!.isNotEmpty) {
        await file.writeAsString(encoded!, flush: true);
      }
    }
    final value = _unprotect(encoded ?? '');
    watch.stop();
    print('[缓存慢] 读取 ${watch.elapsedMilliseconds}ms ${file.path}');
    if (value.trim().isEmpty) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      try {
        if (await file.exists()) {
          await file.rename(
            '${file.path}.invalid-${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    final file = await _fileForKey(key);
    if (await file.exists()) await file.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  String scoped(String userId, String name) => 'oldchat:$userId:$name';

  Future<Directory> directory({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    if (configured.isNotEmpty) {
      final dir = Directory(configured);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final uid = (userId ?? prefs.getString('user_id') ?? 'guest').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final result = Directory(_defaultUserCacheRoot(uid));
    await result.create(recursive: true);
    return result;
  }

  Future<String> location({String? userId}) async =>
      (await directory(userId: userId)).path;

  Future<void> ensureUserDirectory(String userId) async {
    await directory(userId: userId);
  }

  Future<void> setLocation(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationKey, _protect(normalized));
    await Directory(normalized).create(recursive: true);
  }

  Future<int> sizeBytes() async {
    final roots = <Directory>{};
    final prefs = await SharedPreferences.getInstance();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    if (configured.isNotEmpty) {
      roots.add(Directory(configured));
    } else {
      final uid = (prefs.getString('user_id') ?? 'guest').replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      roots.add(Directory(_defaultUserCacheRoot(uid)));
    }
    var total = 0;
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clear() async => clearClientCache();

  Future<int> get count async => await _countFiles();

  Future<int> _calculateSizeBytes() async {
    final root = await directory();
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<int> _countFiles() async {
    final root = await directory();
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total++;
    }
    return total;
  }

  Future<void> clearClientCache() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    final userId = (prefs.getString('user_id') ?? 'guest').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final roots = <Directory>{
      Directory(
        configured.isNotEmpty ? configured : _defaultUserCacheRoot(userId),
      ),
      Directory(_defaultUserCacheRoot('guest')),
      Directory(_defaultUserCacheRoot(userId)),
      await getTemporaryDirectory(),
      await getApplicationCacheDirectory(),
    };
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith('oldchat:'))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<String> cacheDirectory({String? userId}) async =>
      (await directory(userId: userId)).path;

  Future<void> setCacheLocation(String path) async => setLocation(path);
}
