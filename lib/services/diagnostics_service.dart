import 'package:universal_io/io.dart';

class DiagnosticsService {
  static Future<void> clearDnsCache() async {
    if (!Platform.isWindows) return;
    await Process.run('ipconfig', ['/flushdns']);
  }
}
