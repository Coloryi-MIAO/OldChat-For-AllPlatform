import 'dart:io';

class DiagnosticsService {
  static Future<void> clearDnsCache() async {
    if (!Platform.isWindows) return;
    await Process.run('ipconfig', ['/flushdns']);
  }
}
