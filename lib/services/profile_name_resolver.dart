import 'api_service.dart';
import 'auth_service.dart';
import 'cache_service.dart';

class ProfileNameResolver {
  static final Map<String, Future<String>> _inFlight =
      <String, Future<String>>{};

  static Future<String> resolve(String uid, {String? fallback}) {
    final normalized = uid.trim();
    final fallbackName = fallback?.trim().isNotEmpty == true
        ? fallback!.trim()
        : normalized;
    if (normalized.isEmpty) return Future<String>.value(fallbackName);
    final existing = _inFlight[normalized];
    if (existing != null) return existing;
    final future = _resolve(normalized, fallbackName);
    _inFlight[normalized] = future;
    future.whenComplete(() => _inFlight.remove(normalized));
    return future;
  }

  static Future<String> _resolve(String uid, String fallback) async {
    try {
      final profile = await ApiService().getUserProfile(uid);
      final name =
          (profile['display_name'] ??
                  profile['nickname'] ??
                  profile['username'] ??
                  fallback)
              .toString()
              .trim();
      final resolved = name.isEmpty ? fallback : name;
      final userId = (await _userId()) ?? 'guest';
      await CacheService().writeJson(
        CacheService().scoped(userId, 'profile:$uid'),
        profile,
      );
      return resolved;
    } catch (_) {
      final userId = (await _userId()) ?? 'guest';
      final cached = await CacheService().readJson(
        CacheService().scoped(userId, 'profile:$uid'),
      );
      if (cached is Map) {
        final name =
            (cached['display_name'] ??
                    cached['nickname'] ??
                    cached['username'] ??
                    fallback)
                .toString()
                .trim();
        if (name.isNotEmpty) return name;
      }
      return fallback;
    }
  }

  static Future<String?> _userId() async {
    return AuthService().userId;
  }
}
