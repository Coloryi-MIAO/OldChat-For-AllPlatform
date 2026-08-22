import 'package:universal_io/io.dart';

import 'package:flutter/services.dart';

class NativeWindowService {
  static const _channel = MethodChannel('oldchat/native_window');

  static Future<void> flashTaskbar({int count = 3}) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('flashTaskbar', {'count': count});
    } catch (_) {}
  }
}
