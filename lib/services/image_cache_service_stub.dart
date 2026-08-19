import 'package:flutter/material.dart';

class ImageCacheService {
  static final ImageCacheService instance = ImageCacheService._();
  ImageCacheService._();
  static void configure() {}
  ImageProvider provider(String url, {int cacheWidth = 512}) =>
      NetworkImage(url);
  Future<ImageProvider> cachedProvider(
    String url, {
    int cacheWidth = 512,
  }) async => provider(url, cacheWidth: cacheWidth);
  Future<dynamic> cachedFile(String url) async => null;
  Future<dynamic> existingFile(String url) async => null;
  Future<void> cacheInBackground(String url) async {}
  Future<dynamic> readJsonCache(String key) async => null;
  Future<void> writeJsonCache(String key, Object value) async {}
  void clear() {}
  void clearMemoryCache() {}
}
