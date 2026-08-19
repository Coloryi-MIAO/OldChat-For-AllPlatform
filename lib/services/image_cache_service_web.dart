import 'package:flutter/material.dart';
import 'cache_service.dart';

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
  Future<dynamic> readJsonCache(String key) =>
      CacheService().readJson(CacheService().scoped('web', key));
  Future<void> writeJsonCache(String key, Object value) =>
      CacheService().writeJson(CacheService().scoped('web', key), value);
  void clear() {
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  void clearMemoryCache() => clear();
}
