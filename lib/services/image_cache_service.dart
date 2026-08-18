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
    BaseOptions(receiveTimeout: const Duration(seconds: 45)),
  );

  static void configure() {
    imageCache.maximumSize = 300;
    imageCache.maximumSizeBytes = 128 * 1024 * 1024;
  }

  ImageCacheService._();

  ImageProvider provider(String url, {int cacheWidth = 512}) {
    final normalized = url.trim();
    final isSignedChannelMedia = normalized.contains('/channel-media/');
    final token = AuthService().token;
    final headers = isSignedChannelMedia || token == null || token.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    return ResizeImage(
      NetworkImage(normalized, headers: headers),
      width: cacheWidth,
    );
  }

  Future<ImageProvider> cachedProvider(
    String url, {
    int cacheWidth = 512,
  }) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return const AssetImage('assets/app_icon.png');
    final file = await cachedFile(normalized);
    if (file != null && await file.exists()) {
      return ResizeImage(FileImage(file), width: cacheWidth);
    }
    return provider(normalized, cacheWidth: cacheWidth);
  }

  Future<File?> cachedFile(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return null;
    final candidates = resolveMediaCandidates(normalized);
    for (final candidate in candidates) {
      final existing = await existingFile(candidate);
      if (existing != null) return existing;
    }
    final existing = await existingFile(normalized);
    if (existing != null) return existing;
    final uid = AuthService().userId ?? 'guest';
    final directory = await CacheService().directory(userId: uid);
    final file = File(
      '${directory.path}${Platform.pathSeparator}media_${_key(normalized)}',
    );
    if (await file.exists() && await file.length() > 0) return file;
    try {
      final token = AuthService().token;
      final headers = <String, String>{
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'User-Agent': 'OldChat For AllPlatform/1.4.5',
        if (token != null && token.isNotEmpty && !normalized.contains('/channel-media/'))
          'Authorization': 'Bearer $token',
      };
      Response<List<int>>? response;
      Object? lastError;
      for (final candidate in candidates.isEmpty ? <String>[normalized] : candidates) {
        try {
          response = await _dio.get<List<int>>(
            candidate,
            options: Options(
              followRedirects: true,
              validateStatus: (status) => status != null && status < 400,
              responseType: ResponseType.bytes,
              headers: headers,
            ),
          );
          if (response.statusCode == 200 || response.statusCode == 206) break;
        } catch (error) {
          lastError = error;
        }
      }
      if (response == null || response.statusCode == null || response.statusCode! >= 400) {
        throw lastError ?? Exception('媒体下载失败');
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('媒体下载失败：HTTP ${response.statusCode}');
      }
      final bytes = response.data;
      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
      if (bytes == null || bytes.isEmpty || contentType.contains('text/html') || contentType.contains('application/json')) return null;
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      return file;
    } catch (error) {
      debugPrint('[图片慢] 持久化缓存失败 $normalized $error');
      return null;
    }
  }

  Future<File?> existingFile(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return null;
    final uid = AuthService().userId ?? 'guest';
    final directory = await CacheService().directory(userId: uid);
    final file = File(
      '${directory.path}${Platform.pathSeparator}media_${_key(normalized)}',
    );
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

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
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  void clearMemoryCache() => clear();
}
