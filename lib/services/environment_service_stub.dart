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
  final bool mediaKitConfigured;
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
    required this.mediaKitConfigured,
  });
}

class EnvironmentService {
  Future<EnvironmentSnapshot> inspect({required String cachePath}) async =>
      const EnvironmentSnapshot(
        platform: 'web',
        operatingSystem: 'Browser',
        architecture: 'web',
        buildMode: 'release',
        executablePath: '',
        cachePath: 'browser-storage',
        cacheBytes: 0,
        cacheExists: true,
        webView2Installed: false,
        mediaKitConfigured: false,
      );
}
