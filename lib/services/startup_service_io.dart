import 'dart:io';

bool startupIsSupported() => Platform.isWindows;

bool startupIsEnabled() => false;

Future<void> startupSetEnabled(bool enabled) async {}

Future<int> startupCleanupOnStartup() async {
  if (!Platform.isWindows) return 0;
  var deleted = 0;
  final appData = Platform.environment['APPDATA'];
  final roots = <Directory>[];
  if (appData != null && appData.isNotEmpty) {
    roots.add(Directory('$appData${Platform.pathSeparator}OldChatForAllPlatform'));
    roots.add(Directory('$appData${Platform.pathSeparator}OldChat Desktop'));
  }
  roots.add(Directory.systemTemp);
  for (final root in roots) {
    if (!await root.exists()) continue;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.toLowerCase();
      final temporary = name.endsWith('.tmp') ||
          name.endsWith('.part') ||
          name.endsWith('.download') ||
          name.endsWith('.invalid') ||
          name.contains('native_reference') ||
          name.contains('angle.7z');
      if (!temporary) continue;
      try {
        await entity.delete();
        deleted++;
      } catch (_) {}
    }
  }
  return deleted;
}
