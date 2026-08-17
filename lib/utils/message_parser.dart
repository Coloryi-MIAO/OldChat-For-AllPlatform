import 'dart:convert';

class MessageParser {
  static Map<String, dynamic> parseMessageBody(String body, String msgType) {
    if (body.trim().isEmpty) {
      return {
        'text': '',
        'quote': null,
        'mentions': const <Map<String, dynamic>>[],
        'buttons': const <Map<String, dynamic>>[],
        'recall': false,
        'redPacket': null,
      };
    }

    final obj = _decodeObject(body);
    if (obj != null) {
      final decoded = Map<String, dynamic>.from(obj);
      final nestedRedPacket = decoded['red_packet'];
      final hasPacketId =
          decoded.containsKey('packet_id') ||
          decoded.containsKey('packetId') ||
          decoded.containsKey('red_packet_id');
      final redPacket = hasPacketId || nestedRedPacket is Map
          ? (nestedRedPacket is Map
                ? Map<String, dynamic>.from(nestedRedPacket)
                : Map<String, dynamic>.from(decoded))
          : null;
      final normalizedButtons = _normalizeButtons(
        decoded['buttons'] ?? decoded['keyboard'],
      );
      if (redPacket != null) {
        final packet = Map<String, dynamic>.from(redPacket);
        final packetId =
            (packet['packet_id'] ?? packet['packetId'] ?? packet['id'] ?? '')
                .toString();
        for (final button in normalizedButtons) {
          if (button['action'] == 'claim_red_packet' &&
              (button['data'] as String).isEmpty) {
            button['data'] = packetId;
          }
        }
      }
      return {
        'text':
            decoded['text'] ??
            decoded['content'] ??
            (redPacket == null ? body : ''),
        'quote': _normalizeQuote(decoded['quote']),
        'mentions': _normalizeMentions(decoded['mentions']),
        'buttons': normalizedButtons,
        'recall': decoded['recall'] == true || decoded['msg_type'] == 'recall',
        'redPacket': redPacket,
      };
    }

    return {
      'text': body,
      'quote': null,
      'mentions': const <Map<String, dynamic>>[],
      'buttons': const <Map<String, dynamic>>[],
      'recall': false,
      'redPacket': null,
    };
  }

  static Map<String, dynamic>? _decodeObject(String body) {
    var candidate = body.trim();
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        if (decoded is String) {
          candidate = decoded.trim();
          continue;
        }
      } catch (_) {
        final repaired = candidate
            .replaceAll(r'\"', '"')
            .replaceAll(r'\[', '[')
            .replaceAll(r'\]', ']')
            .replaceAll(r'\{', '{')
            .replaceAll(r'\}', '}')
            .replaceAll(r'\_', '_')
            .replaceAll(r'\n', '\n');
        if (repaired == candidate) break;
        candidate = repaired;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _normalizeButtons(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final flat = <Map>[];
    for (final item in value) {
      if (item is Map) {
        flat.add(item);
      } else if (item is List) {
        flat.addAll(item.whereType<Map>());
      }
    }
    return flat
        .map((item) {
          final button = Map<String, dynamic>.from(item);
          final variant = button['v'];
          final label = (button['text'] ?? button['label'] ?? button['t'] ?? '')
              .toString();
          final action =
              button['action']?.toString() ??
              ((variant?.toString() == '3' || label.contains('领取'))
                  ? 'claim_red_packet'
                  : 'send_text');
          return {
            'text': label,
            'action': action,
            'data':
                (button['data'] ??
                        button['value'] ??
                        button['id'] ??
                        (variant?.toString() == '3'
                            ? button['packet_id'] ?? button['packetId'] ?? ''
                            : ''))
                    .toString(),
          };
        })
        .where((button) {
          return (button['text'] ?? '').toString().trim().isNotEmpty;
        })
        .toList();
  }

  static List<Map<String, dynamic>> _normalizeMentions(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) {
          final mention = Map<String, dynamic>.from(item);
          return {
            'uid': (mention['uid'] ?? mention['user_uid'] ?? '').toString(),
            'name':
                (mention['name'] ??
                        mention['display_name'] ??
                        mention['uid'] ??
                        '')
                    .toString(),
          };
        })
        .where((item) {
          return item['uid']!.toString().isNotEmpty;
        })
        .toList();
  }

  static Map<String, dynamic> parseV2(String body) {
    return parseMessageBody(body, 'text');
  }

  static Map<String, dynamic>? _normalizeQuote(dynamic value) {
    if (value is! Map) return null;
    final quote = Map<String, dynamic>.from(value);
    final rawText = quote['text'] ?? quote['body'] ?? quote['content'] ?? '';
    quote['text'] = rawText is String ? rawText : rawText.toString();
    quote['type'] = quote['type'] ?? quote['msg_type'] ?? 'text';
    quote['id'] = quote['id'] ?? quote['message_id'] ?? '';
    quote['from_uid'] = quote['from_uid'] ?? quote['uid'] ?? '';
    quote['from_name'] =
        quote['from_name'] ?? quote['sender'] ?? quote['from_uid'] ?? '';
    return quote;
  }

  static bool isV2(String body) {
    try {
      final obj = jsonDecode(body);
      return obj is Map && obj['v'] == 2;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> buildQuote(Map<String, dynamic> msg) {
    return {
      'id': msg['id'] ?? '',
      'from_uid': msg['from_uid'] ?? '',
      'from_name': msg['sender'] ?? msg['from_uid'] ?? '',
      'type': msg['msg_type'] ?? 'text',
      'text': _truncate((msg['body'] ?? '').toString(), 200),
    };
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  static String extractPlainText(String body) {
    final obj = _decodeObject(body);
    if (obj != null) {
      if (obj.containsKey('v') && obj.containsKey('text')) {
        return obj['text']?.toString() ?? body;
      }
      if (obj.containsKey('text')) {
        return obj['text']?.toString() ?? body;
      }
    }
    return body;
  }
}
