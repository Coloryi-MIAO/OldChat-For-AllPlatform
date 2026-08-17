import 'dart:convert';
import 'package:dio/dio.dart';
import 'account_storage.dart';
import 'auth_service.dart';

class Aria2Service {
  static final Aria2Service _instance = Aria2Service._internal();
  factory Aria2Service() => _instance;
  Aria2Service._internal();

  static const endpointKey = 'aria2_rpc_endpoint';
  static const secretKey = 'aria2_rpc_secret';
  static const defaultEndpoint = 'http://127.0.0.1:6800/jsonrpc';

  Future<Map<String, String>> settings() async {
    await AccountStorage.instance.load();
    final storage = AccountStorage.instance;
    return {
      'endpoint': storage.getString(endpointKey) ?? defaultEndpoint,
      'secret': storage.getString(secretKey) ?? '',
      'configured': (storage.getBool('aria2_configured') ?? false).toString(),
    };
  }

  Future<Map<String, String>> loadSettings() => settings();

  Future<bool> get isConfigured async {
    final config = await settings();
    final endpoint = config['endpoint']?.trim() ?? '';
    if (config['configured'] != 'true' || endpoint.isEmpty) return false;
    return _isEndpointReachable(endpoint, config['secret']?.trim() ?? '');
  }

  Future<bool> _isEndpointReachable(String endpoint, String secret) async {
    if (endpoint.isEmpty) return false;
    try {
      final params = <dynamic>[
        if (secret.isNotEmpty)
          secret.startsWith('token:') ? secret : 'token:$secret',
      ];
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(milliseconds: 800),
        receiveTimeout: const Duration(milliseconds: 800),
      )).post(endpoint, data: jsonEncode({
        'jsonrpc': '2.0',
        'id': 'oldchat-test',
        'method': 'aria2.getVersion',
        'params': params,
      }));
      final data = response.data is String ? jsonDecode(response.data) : response.data;
      return data is Map && data['error'] == null;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveSettings({required String endpoint, required String secret}) async {
    final normalizedEndpoint = endpoint.trim();
    final normalizedSecret = secret.trim();
    await AccountStorage.instance.setString(
      endpointKey,
      normalizedEndpoint.isEmpty ? defaultEndpoint : normalizedEndpoint,
    );
    await AccountStorage.instance.setString(secretKey, normalizedSecret);
    await AccountStorage.instance.setBool(
      'aria2_configured',
      normalizedEndpoint.isNotEmpty,
    );
  }

  Future<String> addUri(String url, {String? fileName}) async {
    final value = url.trim();
    if (value.isEmpty) throw Exception('下载地址为空');
    final config = await settings();
    final secret = config['secret']!.trim();
    final rpcToken = secret.isEmpty
        ? null
        : (secret.startsWith('token:') ? secret : 'token:$secret');
    final options = <String, dynamic>{};
    if (fileName != null && fileName.trim().isNotEmpty) {
      options['out'] = fileName.trim();
    }
    final accessToken = AuthService().token;
    if (accessToken != null && accessToken.isNotEmpty) {
      options['http-header'] = <String>['Authorization: Bearer $accessToken'];
    }
    final params = <dynamic>[
      if (rpcToken != null) rpcToken,
      [value],
      options,
    ];
    final response = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    )).post(
      config['endpoint']!,
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': DateTime.now().microsecondsSinceEpoch,
        'method': 'aria2.addUri',
        'params': params,
      }),
    );
    final data = response.data is String ? jsonDecode(response.data) : response.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']['message'] ?? 'aria2 添加任务失败');
    }
    final gid = data is Map ? data['result']?.toString() : null;
    if (gid == null || gid.isEmpty) throw Exception('aria2 未返回任务 ID');
    return gid;
  }
}
