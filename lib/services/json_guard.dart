import 'dart:convert';

T? tryDecodeJson<T>(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is T ? decoded : null;
  } on FormatException {
    return null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? tryDecodeJsonMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is! String) return null;
  final decoded = tryDecodeJson<Object?>(value);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
}

List<dynamic>? tryDecodeJsonList(dynamic value) {
  if (value is List) return List<dynamic>.from(value);
  if (value is! String) return null;
  final decoded = tryDecodeJson<Object?>(value);
  return decoded is List ? List<dynamic>.from(decoded) : null;
}
