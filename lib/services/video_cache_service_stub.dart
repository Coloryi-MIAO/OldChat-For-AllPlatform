class VideoCacheService {
  static final VideoCacheService _instance = VideoCacheService._();
  factory VideoCacheService() => _instance;
  VideoCacheService._();

  Future<dynamic> getCachedFile(String url) async => null;
  Future<void> cacheInBackground(String url) async {}
  Future<dynamic> getLocalFile(String url) async {
    throw Exception('Local video caching is unavailable in this browser');
  }
}
