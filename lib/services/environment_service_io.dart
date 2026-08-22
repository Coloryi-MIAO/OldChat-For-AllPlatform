import 'package:universal_io/io.dart';

class EnvironmentSnapshot {
  final String platform;
  final String operatingSystem;
  final String architecture;
  final String buildMode;
  final String executablePath;
  final String cachePath;
  final int cacheBytes;
  final bool cacheExists;
  final bool webView2Installed;

  const EnvironmentSnapshot({
    required this.platform,
    required this.operatingSystem,
    required this.architecture,
    required this.buildMode,
    required this.executablePath,
    required this.cachePath,
    required this.cacheBytes,
    required this.cacheExists,
    required this.webView2Installed,
  });

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'operating_system': operatingSystem,
    'architecture': architecture,
    'build_mode': buildMode,
    'executable_path': executablePath,
    'cache_path': cachePath,
    'cache_exists': cacheExists,
    'cache_bytes': cacheBytes,
    'webview2_installed': webView2Installed,
  };
}

class EnvironmentService {
  Future<EnvironmentSnapshot> inspect({required String cachePath}) async {
    final cache = Directory(cachePath);
    var bytes = 0;
    if (await cache.exists()) {
      await for (final entity in cache.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
    }
    final webView2 =
        Platform.isWindows &&
        (Platform.environment['ProgramFiles(x86)'] ?? '').isNotEmpty;
    return EnvironmentSnapshot(
      platform: Platform.operatingSystem,
      operatingSystem: Platform.operatingSystemVersion,
      architecture: Platform.version.split(' ').first,
      buildMode: const bool.fromEnvironment('dart.vm.product')
          ? 'release'
          : 'debug/profile',
      executablePath: Platform.resolvedExecutable,
      cachePath: cachePath,
      cacheBytes: bytes,
      cacheExists: await cache.exists(),
      webView2Installed: webView2,
    );
  }
}
