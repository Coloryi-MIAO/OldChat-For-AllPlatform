import 'dart:io';

Future<List<String>> clipboardFilePaths() async {
  if (!Platform.isWindows) return const <String>[];
  final script = r'''Add-Type -AssemblyName System.Windows.Forms
$files = [Windows.Forms.Clipboard]::GetFileDropList()
foreach ($file in $files) { [Console]::WriteLine($file) }''';
  try {
    final process = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-Command',
      script,
    ], runInShell: false);
    if (process.exitCode != 0) return const <String>[];
    return process.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && File(value).existsSync())
        .toList(growable: false);
  } catch (_) {
    return const <String>[];
  }
}
