import 'package:flutter/material.dart';
import '../pages/chat_page.dart';
import '../utils/navigation.dart';

void navigateFromWebNotification(String payload) {
  final parts = payload.split('|');
  if (parts.length != 2) return;
  navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatPage(
    conversationId: parts[1],
    type: parts[0],
    title: 'Chat',
  )));
}
