import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../utils/url_helper.dart';
import 'cached_image.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final int unreadCount;
  final bool isActive;
  final bool isPinned;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onSecondaryTapDown,
    this.unreadCount = 0,
    this.isActive = false,
    this.isPinned = false,
  });

  String _previewText() {
    final message = conversation.lastMessage;
    if (message == null) return conversation.id;
    final text = message.displayText.trim();
    if (text.isNotEmpty) return text;
    switch (message.msgType) {
      case 'image': return '[图片]';
      case 'video': return '[视频]';
      case 'audio':
      case 'voice': return '[语音]';
      case 'file': return '[文件]';
      case 'red_packet':
      case 'redpacket': return '[红包]';
      default: return conversation.id;
    }
  }

  String _formatTime(int timestamp) {
    if (timestamp <= 0) return '';
    final milliseconds = timestamp > 1000000000000 ? timestamp : timestamp * 1000;
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (date.year == now.year) return '${date.month}/${date.day}';
    return '${date.year}/${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = resolveMediaUrl(conversation.avatar);
    final displayName = conversation.name?.trim().isNotEmpty == true ? conversation.name!.trim() : '未知';
    final initial = displayName.characters.first;
    final lastMessage = conversation.lastMessage;
    final time = _formatTime(lastMessage?.createdAt ?? 0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          tileColor: isActive ? Colors.blue.shade50 : null,
          leading: avatarUrl.isEmpty
              ? CircleAvatar(child: Text(initial))
              : ClipOval(
                  child: CachedImage(
                    avatarUrl,
                    width: 40,
                    height: 40,
                    cacheWidth: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => CircleAvatar(child: Text(initial)),
                  ),
                ),
          title: Row(
            children: [
              Expanded(child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (isPinned) const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.push_pin, size: 14, color: Colors.orange),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(child: Text(_previewText(), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (lastMessage != null) ...[
                const SizedBox(width: 8),
                Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ],
          ),
          trailing: SizedBox(
            width: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                if (unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: Text(unreadCount > 99 ? '99+' : '$unreadCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
              ],
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
