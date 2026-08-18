import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:dio/dio.dart';

import 'auth_service.dart';
import 'cache_service.dart';
import '../utils/url_helper.dart';

class ImageCacheService {
  static final ImageCacheService instance = ImageCacheService._();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 3),
    ),
  );
  final Map<String, Future<File?>> _downloads = <String, Future<File?>>{};
  final Map<String, DateTime> _failedUntil = <String, DateTime>{};
  static const _failureCooldown = Duration(seconds: 8);

  static void configure() {
    imageCache.maximumSize = 300;
    imageCache.maximumSizeBytes = 128 * 1024 * 1024;
  }

  ImageCacheService._();

  ImageProvider provider(String url, {int cacheWidth = 512}) {
    final normalized = url.trim();
    final token = AuthService().token;
    final headers = normalized.contains('/channel-media/') || token == null || token.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    return ResizeImage(NetworkImage(normalized, headers: headers), width: cacheWidth);
  }

  Future<ImageProvider> cachedProvider(String url, {int cacheWidth = 512}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return const AssetImage('assets/app_icon.png');
    final file = await cachedFile(normalized);
    if (file != null) return ResizeImage(FileImage(file), width: cacheWidth);
    return provider(normalized, cacheWidth: cacheWidth);
  }

  Future<File?> cachedFile(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return null;
    final failedUntil = _failedUntil[normalized];
    if (failedUntil != null && failedUntil.isAfter(DateTime.now())) return null;
    final existing = await _findExisting(normalized);
    if (existing != null) return existing;
    final pending = _downloads[normalized];
    if (pending != null) return pending;
    final future = _download(normalized);
    _downloads[normalized] = future;
    try {
      return await future;
    } finally {
      if (identical(_downloads[normalized], future)) _downloads.remove(normalized);
    }
  }

  Future<File?> _download(String normalized) async {
    final candidates = resolveMediaCandidates(normalized);
    final uid = AuthService().userId ?? 'guest';
    final directory = await CacheService().directory(userId: uid);
    final file = File('${directory.path}${Platform.pathSeparator}media_${_key(normalized)}');
    final token = AuthService().token;
    final headers = <String, String>{
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'User-Agent': 'OldChat For AllPlatform/1.4.5',
      if (token != null && token.isNotEmpty && !normalized.contains('/channel-media/'))
        'Authorization': 'Bearer $token',
    };
    Object? lastError;
    for (final candidate in candidates.isEmpty ? <String>[normalized] : candidates) {
      try {
        final response = await _dio.get<List<int>>(
          candidate,
          options: Options(
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
            responseType: ResponseType.bytes,
            headers: headers,
          ),
        );
        final bytes = response.data;
        final contentType = response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
        if ((response.statusCode != 200 && response.statusCode != 206) ||
            bytes == null || bytes.isEmpty ||
            contentType.contains('text/html') || contentType.contains('application/json')) {
          continue;
        }
        final temporary = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
        await temporary.writeAsBytes(bytes, flush: true);
        try {
          await temporary.rename(file.path);
        } catch (_) {
          if (await file.exists()) await file.delete();
          await temporary.rename(file.path);
        }
        return file;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      _failedUntil[normalized] = DateTime.now().add(_failureCooldown);
      debugPrint('[图片慢] 持久化缓存失败 $normalized $lastError');
    }
    return null;
  }

  Future<File?> _findExisting(String url) async {
    final normalized = url.trim();
    final uid = AuthService().userId ?? 'guest';
    final directory = await CacheService().directory(userId: uid);
    for (final candidate in <String>[normalized, ...resolveMediaCandidates(normalized)].toSet()) {
      final file = File('${directory.path}${Platform.pathSeparator}media_${_key(candidate)}');
      if (await file.exists() && await file.length() > 0) return file;
    }
    return null;
  }

  Future<File?> existingFile(String url) => _findExisting(url);

  Future<void> cacheInBackground(String url) async {
    try {
      await cachedFile(url);
    } catch (error) {
      debugPrint('[图片慢] 后台缓存失败 ${url.trim()} $error');
    }
  }

  Future<dynamic> readJsonCache(String key) async {
    try {
      final uid = AuthService().userId ?? 'guest';
      return await CacheService().readJson(CacheService().scoped(uid, key));
    } catch (error) {
      debugPrint('[缓存] 读取 JSON 失败 $key $error');
      return null;
    }
  }

  Future<void> writeJsonCache(String key, Object value) async {
    try {
      final uid = AuthService().userId ?? 'guest';
      await CacheService().writeJson(CacheService().scoped(uid, key), value);
    } catch (error) {
      debugPrint('[缓存] 写入 JSON 失败 $key $error');
    }
  }

  String _key(String value) {
    final encoded = base64UrlEncode(utf8.encode(value)).replaceAll('=', '');
    return encoded.length > 120 ? encoded.substring(0, 120) : encoded;
  }

  void clear() {
    _failedUntil.clear();
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  void clearMemoryCache() => clear();
}
