import 'package:flutter/painting.dart';

class CacheService {
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;
  CacheService._();

  String scoped(String userId, String name) => 'oldchat:$userId:$name';
  Future<String> directory({String? userId}) async => '';
  Future<String> cacheDirectory({String? userId}) => directory(userId: userId);
  Future<void> ensureUserDirectory(String userId) async {}
  Future<void> writeJson(String key, Object value) async {}
  Future<dynamic> readJson(String key) async => null;
  Future<void> remove(String key) async {}
  Future<void> setLocation(String path) async {}
  Future<int> sizeBytes() async => 0;
  Future<int> get count async => 0;
  Future<void> clear() async {}
  Future<void> clearClientCache() async {
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<void> setCacheLocation(String path) => setLocation(path);
}
