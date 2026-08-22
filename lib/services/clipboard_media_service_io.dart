import 'package:universal_io/io.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'clipboard_media.dart';

Future<List<ClipboardMedia>> readClipboardFileMedia() async {
  if (!Platform.isWindows) return const <ClipboardMedia>[];
  const script = r'''Add-Type -AssemblyName System.Windows.Forms
$files = [Windows.Forms.Clipboard]::GetFileDropList()
foreach ($file in $files) {
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    $bytes = [IO.File]::ReadAllBytes($file)
    $name = [IO.Path]::GetFileName($file)
    $encoded = [Convert]::ToBase64String($bytes)
    [Console]::WriteLine("$name`t$encoded")
  }
}''';
  try {
    final result = await Process.run('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-Command', script,
    ], runInShell: false);
    if (result.exitCode != 0) return const <ClipboardMedia>[];
    final media = <ClipboardMedia>[];
    for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final separator = line.indexOf('\t');
      if (separator <= 0) continue;
      try {
        media.add(ClipboardMedia(
          name: line.substring(0, separator),
          bytes: Uint8List.fromList(base64Decode(line.substring(separator + 1))),
        ));
      } catch (_) {}
    }
    return media;
  } catch (_) {
    return const <ClipboardMedia>[];
  }
}

Future<ClipboardMedia?> readClipboardImageMedia() async {
  if (!Platform.isWindows) return null;
  const script = r'''Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if ([Windows.Forms.Clipboard]::ContainsImage()) {
  $image = [Windows.Forms.Clipboard]::GetImage()
  $ms = New-Object IO.MemoryStream
  $image.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
  $encoded = [Convert]::ToBase64String($ms.ToArray())
  [Console]::WriteLine($encoded)
  $ms.Dispose()
  $image.Dispose()
}''';
  try {
    final result = await Process.run('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-Command', script,
    ], runInShell: false);
    if (result.exitCode != 0) return null;
    final encoded = result.stdout.toString().trim();
    if (encoded.isEmpty) return null;
    return ClipboardMedia(name: 'clipboard-image.png', bytes: Uint8List.fromList(base64Decode(encoded)));
  } catch (_) {
    return null;
  }
}
