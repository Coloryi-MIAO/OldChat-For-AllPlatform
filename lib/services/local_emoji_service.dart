import 'dart:convert';

import 'account_storage.dart';

class LocalEmojiService {
  static final LocalEmojiService instance = LocalEmojiService._();
  LocalEmojiService._();

  static const _key = 'oldchat_local_emojis';

  Future<List<Map<String, dynamic>>> list() async {
    await AccountStorage.instance.load();
    final raw = AccountStorage.instance.getString(_key);
    if (raw == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> save(Map<String, dynamic> emoji) async {
    final items = await list();
    items.removeWhere((item) => item['id']?.toString() == emoji['id']?.toString());
    items.insert(0, Map<String, dynamic>.from(emoji));
    await AccountStorage.instance.setString(_key, jsonEncode(items.take(500).toList()));
  }

  Future<void> remove(String id) async {
    final items = await list();
    items.removeWhere((item) => item['id']?.toString() == id);
    await AccountStorage.instance.setString(_key, jsonEncode(items));
  }
}
