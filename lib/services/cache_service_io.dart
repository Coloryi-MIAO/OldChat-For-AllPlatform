import 'dart:convert';
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
  final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};
  final Map<String, Future<Directory>> _directories =
      <String, Future<Directory>>{};
  Future<SharedPreferences>? _preferencesFuture;

  String _defaultUserCacheRoot(String userId) {
    final appData = Platform.environment['APPDATA'];
    final root = appData == null || appData.isEmpty
        ? _defaultDocumentsRoot()
        : '$appData${Platform.pathSeparator}OldChatForAllPlatform';
    return '$root${Platform.pathSeparator}accounts${Platform.pathSeparator}$userId';
  }

  String _defaultDocumentsRoot() {
    final documents = Platform.environment['USERPROFILE'] == null
        ? (Platform.environment['HOME'] ?? '.')
        : '${Platform.environment['USERPROFILE']}${Platform.pathSeparator}Documents';
    return '$documents${Platform.pathSeparator}OldChat_Documents';
  }

  String _protect(String value) =>
      value.isEmpty ? '' : _encryptedMarker + base64Encode(utf8.encode(value));

  String _unprotect(String value) {
    if (value.isEmpty) return '';
    if (!value.startsWith(_encryptedMarker)) return value;
    try {
      return utf8.decode(
        base64Decode(value.substring(_encryptedMarker.length)),
      );
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

  Future<void> writeJson(String key, Object value) {
    final snapshot = _protect(jsonEncode(value));
    final previous = _writeQueues[key] ?? Future<void>.value();
    final operation = previous.then<void>((_) async {
      final file = await _fileForKey(key);
      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      try {
        await temporary.writeAsString(snapshot, flush: true);
        try {
          await temporary.rename(file.path);
        } catch (_) {
          if (await file.exists()) await file.delete();
          await temporary.rename(file.path);
        }
      } finally {
        if (await temporary.exists()) {
          try {
            await temporary.delete();
          } catch (_) {}
        }
      }
    });
    _writeQueues[key] = operation.catchError((_) {});
    return operation;
  }

  Future<dynamic> readJson(String key) async {
    final pending = _writeQueues[key];
    if (pending != null) await pending;
    final file = await _fileForKey(key);
    String? encoded;
    if (await file.exists()) {
      encoded = await file.readAsString();
    } else {
      final prefs = await SharedPreferences.getInstance();
      encoded = prefs.getString(key);
      if (encoded != null && encoded!.isNotEmpty) {
        await file.parent.create(recursive: true);
        await file.writeAsString(encoded!, flush: true);
      }
    }
    final value = _unprotect(encoded ?? '');
    if (value.trim().isEmpty) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      try {
        if (await file.exists()) {
          await file.rename(
            '${file.path}.invalid-${DateTime.now().microsecondsSinceEpoch}',
          );
        }
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    final pending = _writeQueues[key];
    if (pending != null) await pending;
    final file = await _fileForKey(key);
    if (await file.exists()) await file.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  String scoped(String userId, String name) => 'oldchat:$userId:$name';

  Future<SharedPreferences> _preferences() =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  Future<Directory> directory({String? userId}) {
    final requestedUser = (userId ?? '').trim();
    final key = requestedUser.isEmpty ? '__default__' : requestedUser;
    final pending = _directories[key];
    if (pending != null) return pending;
    final future = () async {
      final prefs = await _preferences();
      final configured = _unprotect(
        prefs.getString(_locationKey)?.trim() ?? '',
      );
      final uid =
          (requestedUser.isEmpty
                  ? prefs.getString('user_id') ?? 'guest'
                  : requestedUser)
              .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final result = configured.isNotEmpty
          ? Directory(
              '$configured${Platform.pathSeparator}accounts${Platform.pathSeparator}$uid',
            )
          : Directory(_defaultUserCacheRoot(uid));
      await result.create(recursive: true);
      return result;
    }();
    _directories[key] = future;
    return future;
  }

  Future<String> location({String? userId}) async =>
      (await directory(userId: userId)).path;
  Future<void> ensureUserDirectory(String userId) async =>
      directory(userId: userId);

  Future<void> setLocation(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final prefs = await _preferences();
    _directories.clear();
    await prefs.setString(_locationKey, _protect(normalized));
    await Directory(normalized).create(recursive: true);
  }

  Future<int> sizeBytes() async {
    final root = await directory();
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clear() async => clearClientCache();
  Future<int> get count async => _countFiles();

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
    final prefs = await _preferences();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    final userId = (prefs.getString('user_id') ?? 'guest').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final configuredUserRoot = configured.isEmpty
        ? null
        : Directory(
            '$configured${Platform.pathSeparator}accounts${Platform.pathSeparator}$userId',
          );
    final roots = <Directory>{
      if (configuredUserRoot != null) configuredUserRoot,
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
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('oldchat:'),
    )) {
      await prefs.remove(key);
    }
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<String> cacheDirectory({String? userId}) async =>
      (await directory(userId: userId)).path;
  Future<void> setCacheLocation(String path) async => setLocation(path);
}
