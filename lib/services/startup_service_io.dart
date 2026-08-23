import 'dart:ffi';
import 'package:universal_io/io.dart';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

bool startupIsSupported() => Platform.isWindows;

const _runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
const _valueName = 'OldChat For AllPlatform';
const _appDataDirectory = 'OldChatForAllPlatform';

bool startupIsEnabled() {
  if (!Platform.isWindows) return false;
  return using((arena) {
    final key = arena<Pointer>();
    final result = RegOpenKeyEx(
      HKEY_CURRENT_USER,
      arena.pcwstr(_runPath),
      0,
      KEY_READ,
      key,
    );
    if (!result.isOk) return false;
    try {
      final type = arena<Uint32>();
      final size = arena<Uint32>()..value = 32768;
      final buffer = arena<Uint16>(16384);
      final status = RegQueryValueEx(
        HKEY(key.value),
        arena.pcwstr(_valueName),
        type,
        buffer.cast<Uint8>(),
        size,
      );
      return status.isOk && buffer.value != 0;
    } finally {
      RegCloseKey(HKEY(key.value));
    }
  });
}

Future<void> startupSetEnabled(bool enabled) async {
  if (!Platform.isWindows) return;
  using((arena) {
    final key = arena<Pointer>();
    final createResult = RegCreateKeyEx(
      HKEY_CURRENT_USER,
      arena.pcwstr(_runPath),
      null,
      REG_OPTION_NON_VOLATILE,
      KEY_WRITE,
      nullptr,
      key,
      nullptr,
    );
    if (!createResult.isOk) {
      throw WindowsException(createResult.toHRESULT());
    }
    final hKey = HKEY(key.value);
    try {
      if (!enabled) {
        final result = RegDeleteValue(hKey, arena.pcwstr(_valueName));
        if (!result.isOk && result != ERROR_FILE_NOT_FOUND) {
          throw WindowsException(result.toHRESULT());
        }
        return;
      }
      final executable = File(Platform.resolvedExecutable).absolute.path;
      final escapedExecutable = executable.replaceAll("'", "''");
      final command = "powershell.exe -NoProfile -WindowStyle Hidden -Command \"Start-Process -FilePath '$escapedExecutable' -WindowStyle Hidden\"";
      final value = arena.pcwstr(command);
      final result = RegSetValueEx(
        hKey,
        arena.pcwstr(_valueName),
        REG_SZ,
        value.cast<Uint8>(),
        (command.length + 1) * 2,
      );
      if (!result.isOk) throw WindowsException(result.toHRESULT());
    } finally {
      RegCloseKey(hKey);
    }
  });
}

Future<int> startupCleanupOnStartup() async {
  if (!Platform.isWindows) return 0;
  var deleted = 0;
  final appData = Platform.environment['APPDATA'];
  final roots = <Directory>[];
  if (appData != null && appData.isNotEmpty) {
    roots.add(Directory('$appData${Platform.pathSeparator}$_appDataDirectory'));
    roots.add(Directory('$appData${Platform.pathSeparator}OldChat Desktop'));
  }
  roots.add(Directory.systemTemp);
  for (final root in roots) {
    if (!await root.exists()) continue;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.toLowerCase();
      final temporary =
          name.endsWith('.tmp') ||
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
