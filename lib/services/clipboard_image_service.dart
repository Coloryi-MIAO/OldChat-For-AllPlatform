import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ClipboardImageService {
  static final ClipboardImageService _instance = ClipboardImageService._();
  factory ClipboardImageService() => _instance;
  ClipboardImageService._();

  Process? _worker;
  StreamSubscription<List<int>>? _stdout;
  StreamSubscription<List<int>>? _stderr;
  final StreamController<String> _images = StreamController<String>.broadcast();
  bool _starting = false;
  String? _latestImagePath;

  Stream<String> get images => _images.stream;

  Future<void> start() async {
    if (!Platform.isWindows || _worker != null || _starting) return;
    _starting = true;
    try {
      final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$last = ''
while ($true) {
  try {
    if ([Windows.Forms.Clipboard]::ContainsImage()) {
      $image = [Windows.Forms.Clipboard]::GetImage()
      $ms = New-Object System.IO.MemoryStream
      $image.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
      $bytes = $ms.ToArray()
      $hash = [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))
      if ($hash -ne $last) {
        $last = $hash
        $out = [Console]::OpenStandardOutput()
        $out.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
        $out.Write($bytes, 0, $bytes.Length)
        $out.Flush()
      }
      $ms.Dispose()
      $image.Dispose()
    } elseif ($last -ne '') {
      $last = ''
      $out = [Console]::OpenStandardOutput()
      $out.Write([BitConverter]::GetBytes([int]-1), 0, 4)
      $out.Flush()
    }
  } catch {}
  Start-Sleep -Milliseconds 100
}
''';
      _worker = await Process.start(
        'powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-STA',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ],
        mode: ProcessStartMode.normal,
        includeParentEnvironment: true,
        runInShell: false,
      );
      _stdout = _worker!.stdout.listen(_handleBytes);
      _stderr = _worker!.stderr.listen((_) {});
      _worker!.exitCode.then((_) {
        _stopSubscriptions();
        _worker = null;
        if (Platform.isWindows) {
          Future<void>.delayed(const Duration(seconds: 2), start);
        }
      });
    } catch (error) {
      debugPrint('[剪贴板监控] 启动失败：$error');
      _worker = null;
    } finally {
      _starting = false;
    }
  }

  final List<int> _buffer = <int>[];

  void _handleBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    while (_buffer.length >= 4) {
      final length =
          _buffer[0] |
          (_buffer[1] << 8) |
          (_buffer[2] << 16) |
          (_buffer[3] << 24);
      if (length == -1) {
        _buffer.removeRange(0, 4);
        _latestImagePath = null;
        continue;
      }
      if (length <= 0 || length > 32 * 1024 * 1024) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < length + 4) return;
      final imageBytes = _buffer.sublist(4, length + 4);
      _buffer.removeRange(0, length + 4);
      _saveBytes(imageBytes);
    }
  }

  void _saveBytes(List<int> bytes) {
    try {
      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}oldchat-clipboard',
      )..createSync(recursive: true);
      final path =
          '${directory.path}${Platform.pathSeparator}paste-${DateTime.now().microsecondsSinceEpoch}.png';
      File(path).writeAsBytesSync(bytes, flush: true);
      _latestImagePath = path;
      _images.add(path);
    } catch (_) {}
  }

  Future<String?> saveClipboardImage(String path) async {
    if (!Platform.isWindows) return null;
    await start();
    for (var attempt = 0; attempt < 40; attempt++) {
      final source = _latestImagePath;
      if (source != null && await File(source).exists()) {
        try {
          await File(source).copy(path);
          return path;
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  void _stopSubscriptions() {
    _stdout?.cancel();
    _stderr?.cancel();
    _stdout = null;
    _stderr = null;
  }

  Future<void> dispose() async {
    _stopSubscriptions();
    _worker?.kill();
    _worker = null;
    await _images.close();
  }
}
