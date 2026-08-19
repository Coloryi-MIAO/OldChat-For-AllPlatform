import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart' as pc;

import '../utils/constants.dart';
import 'auth_service.dart';
import 'account_storage.dart';

class WsSessionService {
  static final WsSessionService _instance = WsSessionService._internal();
  static final WsSessionService _httpInstance = WsSessionService._internal();
  factory WsSessionService({bool http = false}) =>
      http ? _httpInstance : _instance;
  WsSessionService._internal();

  final Dio _dio = Dio();
  crypto.SecretKey? _encKey;
  crypto.SecretKey? _macKey;
  Future<void>? _pendingHandshake;
  String? sessionId;

  Future<void> ensureReady() async {
    if (_encKey != null && _macKey != null && sessionId != null) return;
    if (_pendingHandshake != null) return _pendingHandshake!;
    _pendingHandshake = _handshake();
    try {
      await _pendingHandshake!;
    } finally {
      _pendingHandshake = null;
    }
  }

  Future<void> _handshake() async {
    final domain = pc.ECDomainParameters('prime256v1');
    final random = pc.FortunaRandom()
      ..seed(
        pc.KeyParameter(
          Uint8List.fromList(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    final generator = pc.ECKeyGenerator()
      ..init(
        pc.ParametersWithRandom(pc.ECKeyGeneratorParameters(domain), random),
      );
    final keyPair = generator.generateKeyPair();
    final clientDer = _publicKeyDer(keyPair.publicKey);
    final response = await _dio.post(
      '${Constants.baseUrl}${Constants.apiPath('/v1/auth/handshake')}',
      data: {
        'client_pub': base64Encode(clientDer),
        'client_random': base64Encode(
          List<int>.generate(16, (_) => Random.secure().nextInt(256)),
        ),
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final rawData = response.data;
    final data = _decodeMap(rawData);
    if (data == null || data.isEmpty) {
      reset();
      throw StateError('握手响应不是有效 JSON 对象');
    }
    final serverRaw = data['server_pub'] ?? data['server_public_key'];
    if (serverRaw == null) throw StateError('握手响应缺少服务器公钥');
    final serverKey = _parsePublicKey(
      base64Decode(serverRaw.toString()),
      domain,
    );
    final agreement = pc.ECDHBasicAgreement()..init(keyPair.privateKey);
    final shared = _bigIntBytes(agreement.calculateAgreement(serverKey), 32);
    final encHash = await crypto.Sha256().hash([
      ...shared,
      ...utf8.encode('enc'),
    ]);
    final macHash = await crypto.Sha256().hash([
      ...shared,
      ...utf8.encode('mac'),
    ]);
    _encKey = crypto.SecretKey(encHash.bytes);
    _macKey = crypto.SecretKey(macHash.bytes);
    sessionId = (data['session_id'] ?? data['sid'])?.toString();
    if (sessionId == null || sessionId!.isEmpty) {
      reset();
      throw StateError('握手响应缺少 session_id');
    }
  }

  List<int> _publicKeyDer(pc.ECPublicKey key) {
    final point = key.Q!.getEncoded(false);
    return [
      0x30,
      0x59,
      0x30,
      0x13,
      0x06,
      0x07,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x02,
      0x01,
      0x06,
      0x08,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x03,
      0x01,
      0x07,
      0x03,
      0x42,
      0x00,
      ...point,
    ];
  }

  pc.ECPublicKey _parsePublicKey(List<int> der, pc.ECDomainParameters domain) {
    const prefix = [
      0x30,
      0x59,
      0x30,
      0x13,
      0x06,
      0x07,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x02,
      0x01,
      0x06,
      0x08,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x03,
      0x01,
      0x07,
      0x03,
      0x42,
      0x00,
    ];
    if (der.length != prefix.length + 65 ||
        !_startsWith(der, prefix) ||
        der[prefix.length] != 0x04) {
      throw StateError('服务器公钥格式不受支持');
    }
    final point = domain.curve.decodePoint(der.sublist(prefix.length));
    if (point == null) throw StateError('服务器公钥解析失败');
    return pc.ECPublicKey(point, domain);
  }

  bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) return false;
    }
    return true;
  }

  List<int> _bigIntBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) throw StateError('ECDH shared secret 编码失败');
      bytes.add(byte);
    }
    return bytes.length > length ? bytes.sublist(bytes.length - length) : bytes;
  }

  Future<String?> decrypt(String raw) async {
    if (_encKey == null || _macKey == null) return null;
    final decoded = _decodeMap(raw);
    if (decoded == null) return null;
    if (decoded is! Map ||
        decoded['iv'] == null ||
        decoded['data'] == null ||
        decoded['mac'] == null)
      return null;
    try {
      final iv = base64Decode(decoded['iv'].toString());
      final ciphertext = base64Decode(decoded['data'].toString());
      final actualMac = base64Decode(decoded['mac'].toString());
      final mac = await crypto.Hmac.sha256().calculateMac([
        ...iv,
        ...ciphertext,
      ], secretKey: _macKey!);
      if (!_constantTimeEqual(actualMac, mac.bytes)) return null;
      final cipher = crypto.AesCbc.with256bits(
        macAlgorithm: crypto.MacAlgorithm.empty,
      );
      final clear = await cipher.decrypt(
        crypto.SecretBox(ciphertext, nonce: iv, mac: crypto.Mac.empty),
        secretKey: _encKey!,
      );
      return utf8.decode(clear, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> encrypt(String plainText) async {
    if (_encKey == null || _macKey == null) return null;
    try {
      final iv = List<int>.generate(16, (_) => Random.secure().nextInt(256));
      final cipher = crypto.AesCbc.with256bits(
        macAlgorithm: crypto.MacAlgorithm.empty,
      );
      final encrypted = await cipher.encrypt(
        utf8.encode(plainText),
        secretKey: _encKey!,
        nonce: iv,
      );
      final mac = await crypto.Hmac.sha256().calculateMac([
        ...iv,
        ...encrypted.cipherText,
      ], secretKey: _macKey!);
      return jsonEncode({
        'iv': base64Encode(iv),
        'data': base64Encode(encrypted.cipherText),
        'mac': base64Encode(mac.bytes),
      });
    } catch (_) {
      return null;
    }
  }

  Future<String?> getDeviceId() async {
    final storage = AccountStorage.instance;
    await storage.load(userId: AuthService().userId);
    final existing = storage.getString('device_id')?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final id =
        'flutter-${DateTime.now().millisecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    await storage.setString('device_id', id);
    return id;
  }

  Future<Map<String, String>> signHeaders(String path, String method) async {
    await ensureReady();
    final key = _macKey;
    final sid = sessionId;
    if (key == null || sid == null || sid.isEmpty) {
      throw StateError('v2 session not ready');
    }
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonceBytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    final nonce = base64Encode(nonceBytes).replaceAll('=', '');
    final cleanPath = path.split('?').first;
    final verb = method.trim().isEmpty ? 'GET' : method.trim().toUpperCase();
    final signing = utf8.encode('$verb\n$cleanPath\n$ts\n$nonce');
    final mac = await crypto.Hmac.sha256().calculateMac(
      signing,
      secretKey: key,
    );
    final deviceId = await getDeviceId();
    return {
      'X-Session': sid,
      'X-Ts': ts,
      'X-Sign-Time': ts,
      'X-Nonce': nonce,
      'X-Sign-Nonce': nonce,
      'X-Sign': base64Encode(mac.bytes).replaceAll('=', ''),
      if (deviceId != null && deviceId.isNotEmpty) 'X-Device-Id': deviceId,
    };
  }

  bool _constantTimeEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var result = 0;
    for (var i = 0; i < left.length; i++) {
      result |= left[i] ^ right[i];
    }
    return result == 0;
  }

  void reset() {
    _encKey?.destroy();
    _macKey?.destroy();
    _encKey = null;
    _macKey = null;
    sessionId = null;
  }
}
