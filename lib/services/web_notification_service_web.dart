import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'notification_navigation.dart';

class WebNotificationService {
  Future<void> init() async {}

  Future<bool> requestPermission() async {
    if (web.Notification.permission == 'granted') return true;
    if (web.Notification.permission == 'denied') return false;
    try {
      final permission = await web.Notification.requestPermission().toDart;
      return permission.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  Future<bool> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!await requestPermission()) return false;
      final notification = web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          tag: 'oldchat-${DateTime.now().microsecondsSinceEpoch}',
          requireInteraction: false,
        ),
      );
      notification.onclick = ((web.Event _) {
        notification.close();
        if (payload != null && payload.isNotEmpty) {
          navigateFromWebNotification(payload);
        }
      }).toJS;
      return true;
    } catch (_) {
      return false;
    }
  }
}
