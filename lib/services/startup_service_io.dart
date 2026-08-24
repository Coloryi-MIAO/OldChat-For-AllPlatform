import 'package:universal_io/io.dart';

bool startupIsSupported() => Platform.isWindows;

const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _valueName = 'OldChat For AllPlatform';
const _appDataDirectory = 'OldChatForAllPlatform';

String? _registryValue() {
  if (!Platform.isWindows) return null;
  try {
    final result = Process.runSync(
      'reg.exe',
      ['query', _runKey, '/v', _valueName],
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final output = '${result.stdout}';
    final line = output.split(RegExp(r'\r?\n')).cast<String?>().firstWhere(
          (line) => line != null && line.contains(_valueName),
          orElse: () => null,
        );
    return line?.trim();
  } catch (_) {
    return null;
  }
}

bool startupIsEnabled() => _registryValue() != null;

Future<void> startupSetEnabled(bool enabled) async {
  if (!Platform.isWindows) return;
  if (!enabled) {
    final result = await Process.run(
      'reg.exe',
      ['delete', _runKey, '/v', _valueName, '/f'],
      runInShell: true,
    );
    if (result.exitCode != 0 && !'${result.stderr}'.contains('unable to find')) {
      throw ProcessException('reg.exe', [], '${result.stderr}', result.exitCode);
    }
    return;
  }
  final executable = File(Platform.resolvedExecutable).absolute.path;
  final escaped = executable.replaceAll("'", "''");
  final command = "powershell.exe -NoProfile -WindowStyle Hidden -Command \"Start-Process -FilePath '$escaped' -WindowStyle Hidden\"";
  final result = await Process.run(
    'reg.exe',
    ['add', _runKey, '/v', _valueName, '/t', 'REG_SZ', '/d', command, '/f'],
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw ProcessException('reg.exe', [], '${result.stderr}', result.exitCode);
  }
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
