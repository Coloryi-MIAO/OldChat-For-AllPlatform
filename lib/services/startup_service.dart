import 'startup_service_stub.dart'
    if (dart.library.io) 'startup_service_io.dart';

class StartupService {
  static bool get isSupported => startupIsSupported();

  static bool isEnabled() => startupIsEnabled();

  static Future<void> setEnabled(bool enabled) => startupSetEnabled(enabled);

  static Future<void> cleanupOnStartup() => startupCleanupOnStartup();
}
