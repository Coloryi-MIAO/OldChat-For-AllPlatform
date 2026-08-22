import 'dart:async';
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'account_storage.dart';
import '../utils/constants.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/moment.dart';
import '../models/music.dart';
import '../models/emoji.dart';
import '../models/notification.dart';
import 'auth_service.dart';
import '../utils/navigation.dart';
import '../pages/login_page.dart';
import 'cache_service.dart';
import 'image_cache_service.dart';
import '../services/ai_settings_service.dart';
import 'ws_session_service.dart';

class ApiService {
  static final Map<String, DateTime> _v2CircuitOpenUntil = <String, DateTime>{};
  static const Duration _v2CircuitDuration = Duration(minutes: 2);

  bool _v2CircuitOpen(String path) {
    final until = _v2CircuitOpenUntil[path];
    if (until == null) return false;
    if (until.isBefore(DateTime.now())) {
      _v2CircuitOpenUntil.remove(path);
      return false;
    }
    return true;
  }

  void _openV2Circuit(String path) {
    _v2CircuitOpenUntil[path] = DateTime.now().add(_v2CircuitDuration);
    print('[API] v2 单端点熔断：$path，${_v2CircuitDuration.inSeconds} 秒内直接使用 v1');
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {'data': value};

  Future<Response<dynamic>> _requestV2WithV1Fallback(
    String method,
    String v2Path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    Future<Response<dynamic>> sendDirect(
      String path, {
      required bool v2,
    }) async {
      return _dio.request<dynamic>(
        path,
        options: Options(
          method: method,
          extra: {'_v2Attempt': v2, '_skipV2Signing': !v2},
          headers: v2 ? null : _cleanV2Headers(),
        ),
        data: data,
        queryParameters: queryParameters,
      );
    }

    final fallbackPath = _v1FallbackPath(v2Path);
    final endpointKey = v2Path.split('?').first;
    if (_v2CircuitOpen(endpointKey)) {
      if (fallbackPath == null) {
        throw StateError('v2 endpoint unavailable: $v2Path');
      }
      return sendDirect(fallbackPath, v2: false);
    }

    try {
      final response = await _sendV2WithGateway(
        method,
        v2Path,
        data: data,
        queryParameters: queryParameters,
      );
      if (_hasV2GatewayError(response.data)) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'v2 gateway error',
        );
      }
      return response;
    } on DioException catch (error) {
      final gatewayError =
          '${error.error}'.contains('gateway') ||
          '${error.error}'.contains('encrypted response invalid');
      if (!_canFallbackV2(error) && !gatewayError) rethrow;
      if (error.requestOptions.extra['_gatewayRetried'] != true) {
        WsSessionService(http: true).reset();
        try {
          final retry = await _sendV2WithGateway(
            method,
            v2Path,
            data: data,
            queryParameters: queryParameters,
          );
          if (!_hasV2GatewayError(retry.data)) return retry;
        } catch (_) {}
      }
      _openV2Circuit(endpointKey);
      if (fallbackPath != null) return sendDirect(fallbackPath, v2: false);
      rethrow;
    } catch (_) {
      if (fallbackPath == null) rethrow;
      _openV2Circuit(endpointKey);
      return sendDirect(fallbackPath, v2: false);
    }
  }

  Map<String, dynamic> _cleanV2Headers() => <String, dynamic>{};

  Future<Response<dynamic>> _sendV2WithGateway(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final session = WsSessionService(http: true);
    try {
      await session.ensureReady();
    } catch (_) {
      session.reset();
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        error: 'v2 session unavailable',
      );
    }
    final query = Uri(
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
    ).query;
    final payload = <String, dynamic>{
      'm': method.toUpperCase(),
      'p': path.split('?').first,
      'q': query,
      'b': data,
    };
    final headers = await session.signHeaders('/v2/gateway', 'POST');
    headers['Content-Type'] = 'application/json';
    final token = _auth.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final clearBody = jsonEncode(payload);
    final encryptedBody = await session.encrypt(clearBody);
    final response = await _dio.post<dynamic>(
      '/v2/gateway',
      data: encryptedBody == null ? payload : _decodeMap(encryptedBody),
      options: Options(
        headers: {
          ...headers,
          if (encryptedBody != null) ...{
            'X-Enc': '1',
            'X-Session': session.sessionId!,
            if (_auth.token case final token? when token.isNotEmpty)
              'X-Auth': await session.encrypt('Bearer $token'),
          },
        },
        extra: {
          '_v2Attempt': true,
          '_skipV2Signing': true,
          '_gatewayRequest': true,
        },
      ),
    );
    if (response.data is Map) {
      final envelope = Map<String, dynamic>.from(response.data as Map);
      if (envelope['iv'] != null &&
          envelope['data'] != null &&
          envelope['mac'] != null) {
        final decrypted = await session.decrypt(jsonEncode(envelope));
        if (decrypted == null) {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: 'gateway encrypted response invalid',
          );
        }
        response.data = _decodeMap(decrypted);
      }
    }
    final body = response.data is String
        ? _decodeMap(response.data)
        : response.data;
    response.data = body;
    if (body is Map && body.length == 1 && body['data'] is String) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'gateway returned non-JSON response',
      );
    }
    if (body is Map &&
        body['iv'] != null &&
        body['data'] != null &&
        body['mac'] != null) {
      final clear = await session.decrypt(jsonEncode(body));
      if (clear == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'gateway encrypted response invalid',
        );
      }
      final decoded = _decodeMap(clear);
      final code = decoded['code'] is num
          ? (decoded['code'] as num).toInt()
          : int.tryParse('${decoded['code']}');
      if (code != null && code != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'gateway code $code',
        );
      }
      response.data = decoded['body'] is Map
          ? Map<String, dynamic>.from(decoded['body'] as Map)
          : decoded;
      return response;
    }
    if (body is Map && body['code'] != null) {
      final code = body['code'] is num
          ? (body['code'] as num).toInt()
          : int.tryParse('${body['code']}');
      final inner = body['body'];
      if (code != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'gateway code $code',
        );
      }
      response.data = inner is Map ? inner : _decodeMap(inner);
    }
    return response;
  }

  Map<String, dynamic> _decodeMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final text = value.trim();
      if (text.isNotEmpty) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } on FormatException {
          print(
            '[API] 忽略非 JSON 响应：${text.substring(0, text.length > 80 ? 80 : text.length)}',
          );
        } catch (_) {}
      }
    }
    return <String, dynamic>{'data': value};
  }

  Future<Response<dynamic>?> _retryV2SessionOnce(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final session = WsSessionService(http: true);
    session.reset();
    try {
      await session.ensureReady();
      final headers = await session.signHeaders(path, method);
      return await _dio.request<dynamic>(
        path,
        options: Options(method: method, headers: headers),
        data: data,
        queryParameters: queryParameters,
      );
    } catch (_) {
      return null;
    }
  }

  // v2 请求在网关错误或 HTTP 400/401 时回退到对应 v1 路由。
  bool _canFallbackV2(DioException error) {
    final status = error.response?.statusCode;
    if (status == 400 ||
        status == 401 ||
        status == 404 ||
        (status != null && status >= 500))
      return true;
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  bool _hasV2GatewayError(dynamic data) {
    if (data is String) {
      final decoded = _decodeMap(data);
      return _hasV2GatewayError(decoded);
    }
    if (data is! Map) return false;
    final map = Map<String, dynamic>.from(data);
    final rawCode = map['code'] ?? map['status'];
    final code = rawCode is num ? rawCode.toInt() : int.tryParse('$rawCode');
    if (code == 400 || code == 401 || code == 404) return true;
    final nested = map['body'] is Map
        ? Map<String, dynamic>.from(map['body'] as Map)
        : const <String, dynamic>{};
    final text =
        '${map['error'] ?? map['message'] ?? map['code'] ?? map['status'] ?? nested['error'] ?? nested['message'] ?? nested['code'] ?? ''}'
            .toLowerCase();
    return text.contains('invalid_session') ||
        text.contains('missing_session') ||
        text.contains('bad_signature') ||
        text.contains('invalid signature') ||
        text.contains('missing device id');
  }

  String? _v1FallbackPath(String v2Path) {
    const mappings = <String, String>{
      '/v2/direct/messages/v2': '/v1/direct/messages/v2',
      '/v2/groups/messages/v2': '/v1/groups/messages/v2',
      '/v2/groups/messages/after': '/v1/groups/messages',
      '/v2/direct/read': '/v1/direct/read',
      '/v2/groups/read': '/v1/groups/read',
      '/v2/unread/direct': '/v1/direct/unread',
      '/v2/unread/groups': '/v1/groups/unread',
      '/v2/friends': '/v1/friends',
      '/v2/friends/requests': '/v1/friends/requests',
      '/v2/friends/request': '/v1/friends/request',
      '/v2/friends/respond': '/v1/friends/respond',
      '/v2/friends/remark': '/v1/friends/remark',
      '/v2/friends/delete': '/v1/friends/delete',
      '/v2/groups/list': '/v1/groups/list',
      '/v2/groups/create': '/v1/groups/create',
      '/v2/groups/join': '/v1/groups/join',
      '/v2/groups/members': '/v1/groups/members',
      '/v2/groups/requests': '/v1/groups/requests',
      '/v2/groups/invite': '/v1/groups/invite',
      '/v2/groups/approve': '/v1/groups/approve',
      '/v2/groups/admin': '/v1/groups/admin',
      '/v2/groups/avatar': '/v1/groups/avatar',
      '/v2/groups/name': '/v1/groups/name',
      '/v2/groups/settings': '/v1/groups/settings',
      '/v2/groups/announcement': '/v1/groups/announcement',
      '/v2/groups/announcement/read': '/v1/groups/announcement/read',
      '/v2/groups/kick': '/v1/groups/kick',
      '/v2/groups/leave': '/v1/groups/leave',
      '/v2/groups/dissolve': '/v1/groups/dissolve',
      '/v2/direct/send': '/v1/direct/send',
      '/v2/groups/message/send': '/v1/groups/message/send',
      '/v2/buttons/callback': '/v1/buttons/callback',
      '/v2/groups/invitations': '/v1/groups/invitations',
      '/v2/groups/invitations/respond': '/v1/groups/invitations/respond',
      '/v2/redpackets/send': '/v1/redpackets/send',
      '/v2/redpackets/claim': '/v1/redpackets/claim',
      '/v2/redpackets/': '/v1/redpackets/',
      '/v2/channels/discover': '/v1/channels/discover',
      '/v2/channels/states': '/v1/channels/states',
      '/v2/channels/notifications': '/v1/channels/notifications',
      '/v2/channels/subscribe': '/v1/channels/subscribe',
      '/v2/channels/unsubscribe': '/v1/channels/unsubscribe',
      '/v2/channels/posts/send': '/v1/channels/posts/send',
      '/v2/channels/read': '/v1/channels/read',
      '/v2/channels/posts/after': '/v1/channels/posts/after',
      '/v2/channels/reactions/toggle': '/v1/channels/reactions/toggle',
      '/v2/me/scratch': '/v1/me/scratch',
    };
    return mappings[v2Path];
  }

  Future<Response<dynamic>> _v2Request(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) => _requestV2WithV1Fallback(
    method,
    path,
    data: data,
    queryParameters: queryParameters,
  );

  dynamic _nestedValue(dynamic value, List<String> keys) {
    dynamic current = value;
    for (var depth = 0; depth < 4; depth++) {
      if (current is List) return current;
      if (current is! Map) return current;
      final map = Map<String, dynamic>.from(current);
      for (final key in keys) {
        if (map[key] is List) return map[key];
      }
      final next = map['data'] ?? map['result'] ?? map['payload'];
      if (next == null || identical(next, current)) return current;
      current = next;
    }
    return current;
  }

  List<dynamic> _nestedList(dynamic value, List<String> keys) {
    final raw = _nestedValue(value, keys);
    return raw is List ? raw : const <dynamic>[];
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: Constants.baseUrl,
      headers: {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.json,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );

  final AuthService _auth = AuthService();
  static Future<bool>? _authRecoveryFuture;
  static DateTime? _authRecoveryCooldownUntil;
  static bool _loginRedirectScheduled = false;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.baseUrl = Constants.baseUrl;
          options.extra['_startedAt'] = DateTime.now();
          final token = _auth.token;
          if (token != null && !options.uri.path.contains('/auth/handshake')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final path = options.uri.path;
          if (path.startsWith('/v2/') &&
              options.extra['_skipV2Signing'] != true) {
            final session = WsSessionService(http: true);
            try {
              final deviceId = await session.getDeviceId();
              if (deviceId != null && deviceId.isNotEmpty) {
                options.headers['X-Device-Id'] = deviceId;
              }
              await session.ensureReady();
              final signed = await session.signHeaders(path, options.method);
              options.headers.addAll(signed);
            } catch (error) {
              print('[API] v2 会话签名失败：$path $error');
            }
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          final path = e.requestOptions.path;
          final isAuthEndpoint =
              path.contains('/auth/login') ||
              path.contains('/auth/refresh') ||
              path.contains('/auth/logout');
          final alreadyRetried = e.requestOptions.extra['_authRetried'] == true;
          final v2SessionFailure =
              path.startsWith('/v2/') &&
              e.requestOptions.extra['_gatewayRequest'] != true &&
              _hasV2GatewayError(e.response?.data);
          if ((e.response?.statusCode == 400 ||
                  e.response?.statusCode == 401) &&
              v2SessionFailure &&
              e.requestOptions.extra['_v2Retried'] != true) {
            WsSessionService(http: true).reset();
            e.requestOptions.extra['_v2Retried'] = true;
            try {
              final retry = await _dio.fetch(e.requestOptions);
              return handler.resolve(retry);
            } catch (_) {}
          }
          final responseData = e.response?.data;
          final responseText = responseData is Map
              ? '${responseData['error'] ?? responseData['code'] ?? responseData['message'] ?? (responseData['body'] is Map ? (responseData['body'] as Map)['error'] : '')}'
                    .toLowerCase()
              : '${responseData ?? ''}'.toLowerCase();
          final isV2SessionFailure =
              path.startsWith('/v2/') &&
              e.requestOptions.extra['_gatewayRequest'] != true &&
              (responseText.contains('signature') ||
                  responseText.contains('session') ||
                  responseText.contains('device id'));
          if (e.response?.statusCode == 401 &&
              !isV2SessionFailure &&
              !alreadyRetried &&
              !isAuthEndpoint &&
              !_isPublicEndpoint(path) &&
              !_isNonSessionEndpoint(path)) {
            final result = await _handleUnauthorized();
            if (result) {
              final retry = await _retryRequest(e);
              return handler.resolve(retry);
            }
          }
          final started = e.requestOptions.extra['_startedAt'];
          if (started is DateTime) {
            print(
              '[API慢] ${e.requestOptions.method} ${e.requestOptions.path} ${DateTime.now().difference(started).inMilliseconds}ms',
            );
          }
          return handler.next(e);
        },
        onResponse: (response, handler) {
          final started = response.requestOptions.extra['_startedAt'];
          if (started is DateTime) {
            print(
              '[API] ${response.requestOptions.method} ${response.requestOptions.path} ${DateTime.now().difference(started).inMilliseconds}ms',
            );
          }
          return handler.next(response);
        },
      ),
    );
  }

  static String? extractUploadUrl(dynamic raw) {
    if (raw is String) {
      final value = raw.trim();
      return value.isEmpty ? null : value;
    }
    if (raw is List) {
      for (final item in raw) {
        final result = extractUploadUrl(item);
        if (result != null) return result;
      }
      return null;
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in const [
        'url',
        'download_url',
        'download_path',
        'media_url',
        'file_url',
        'path',
        'src',
      ]) {
        final result = extractUploadUrl(map[key]);
        if (result != null) return result;
      }
      for (final key in const ['data', 'file', 'media', 'result', 'payload']) {
        final result = extractUploadUrl(map[key]);
        if (result != null) return result;
      }
    }
    return null;
  }

  Map<String, dynamic> _normalizeSearchResponse(dynamic raw) {
    if (raw is List) return {'messages': raw};
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in const ['messages', 'results', 'items', 'records']) {
        if (map[key] is List) return {'messages': map[key], ...map};
      }
      final nested = map['data'];
      if (nested is List) return {'messages': nested, ...map};
      if (nested is Map) return _normalizeSearchResponse(nested);
    }
    return {'messages': const <dynamic>[]};
  }

  Exception _apiError(String prefix, DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['error'] ?? data['message'] ?? data['code'];
      if (detail != null) {
        final status = error.response?.statusCode;
        return Exception(
          '$prefix${status == null ? '' : ' ($status)'}: $detail',
        );
      }
    }
    final status = error.response?.statusCode;
    return Exception(
      '$prefix${status == null ? '' : ' ($status)'}: ${error.message ?? '网络错误'}',
    );
  }

  bool _isPublicEndpoint(String path) {
    return path.contains('/emoji/plaza') ||
        path.contains('/v1/me/checkin/wall') ||
        path.contains('/auth/handshake');
  }

  bool _isNonSessionEndpoint(String path) {
    return path.contains('/emoji/') ||
        path.contains('/checkin/') ||
        path.contains('/moments/') ||
        path.contains('/notifications');
  }

  Future<bool> _handleUnauthorized() {
    final active = ApiService._authRecoveryFuture;
    if (active != null) return active;
    final cooldown = ApiService._authRecoveryCooldownUntil;
    if (cooldown != null && cooldown.isAfter(DateTime.now()))
      return Future.value(false);
    final future = _recoverAuth();
    ApiService._authRecoveryFuture = future;
    return future.whenComplete(() {
      if (identical(ApiService._authRecoveryFuture, future)) {
        ApiService._authRecoveryFuture = null;
      }
    });
  }

  Future<bool> recoverAuthentication() => _handleUnauthorized();

  Future<bool> _recoverAuth() async {
    var rateLimited = false;
    final refreshToken = await _auth.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final data = await this.refreshToken(refreshToken);
        final accessToken = data['access_token'] ?? data['token'];
        if (accessToken != null && accessToken.toString().isNotEmpty) {
          await _auth.saveToken(
            accessToken.toString(),
            userId: data['user_id'] ?? data['uid'],
            refreshToken: data['refresh_token'] ?? refreshToken,
          );
          print('Token 刷新成功');
          ApiService._authRecoveryCooldownUntil = DateTime.now().add(
            const Duration(seconds: 3),
          );
          return true;
        }
      } catch (error) {
        rateLimited =
            error.toString().contains('(429)') ||
            error.toString().toLowerCase().contains('too many requests');
        print('Refresh token 失败: $error');
      }
    }

    if (rateLimited) {
      ApiService._authRecoveryCooldownUntil = DateTime.now().add(
        const Duration(seconds: 20),
      );
      print('认证接口被限流，20 秒内不重复刷新或自动登录');
      return false;
    }

    final username = _auth.savedUsername;
    final password = _auth.savedPassword;
    if (username != null &&
        username.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      try {
        print('尝试使用已保存账号自动登录');
        final data = await login(username, password);
        final accessToken = data['token'] ?? data['access_token'];
        if (accessToken != null && accessToken.toString().isNotEmpty) {
          await _auth.saveToken(
            accessToken.toString(),
            userId: data['userId'] ?? data['user_id'],
            refreshToken: data['refresh_token'],
          );
          print('自动登录成功');
          return true;
        }
      } catch (error) {
        final loginRateLimited =
            error.toString().contains('(429)') ||
            error.toString().toLowerCase().contains('too many requests');
        if (loginRateLimited) {
          ApiService._authRecoveryCooldownUntil = DateTime.now().add(
            const Duration(seconds: 20),
          );
          print('自动登录接口被限流，保留当前会话并在 20 秒后重试');
          return false;
        }
        print('自动登录失败: $error');
      }
    }

    ApiService._authRecoveryCooldownUntil = DateTime.now().add(
      const Duration(seconds: 20),
    );
    print('认证恢复失败，20 秒内不重复刷新或自动登录');
    if (!_auth.isLoggedIn) return false;
    await _auth.clear();
    if (!ApiService._loginRedirectScheduled) {
      ApiService._loginRedirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginPage()),
          (route) => false,
        );
      });
    }
    return false;
  }

  // 鈽?閲嶇瘯鍘熻姹?
  Future<Response<dynamic>> _retryRequest(DioException error) async {
    final options = error.requestOptions;
    options.extra['_authRetried'] = true;
    final token = _auth.token;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return _dio.fetch<dynamic>(options);
  }

  // ==================== 璁よ瘉 ====================

  String _clientPlatformName() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.trim();
      return build.isEmpty ? info.version : '${info.version}+$build';
    } catch (_) {
      return '1.4.8-beta.5+6';
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final deviceId = await WsSessionService(http: true).getDeviceId();
      final response = await _dio.post(
        Constants.loginPath,
        data: {
          'identifier': username,
          'username': username,
          'email': username,
          'password': password,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          'device_name': Constants.appName,
          'platform': _clientPlatformName(),
          'app_version': await _appVersion(),
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = _unwrapEnvelopeMap(response.data);
        final token = data['access_token'] ?? data['token'];
        final user = data['user'];
        final userId =
            data['user_id'] ??
            data['uid'] ??
            (user is Map ? user['uid'] ?? user['user_id'] : null);
        final refreshToken = data['refresh_token'];
        if (token == null || token.toString().trim().isEmpty) {
          throw Exception('服务器未返回登录令牌');
        }
        ApiService._loginRedirectScheduled = false;
        return {
          'token': token.toString(),
          'userId': userId,
          'refresh_token': refreshToken,
        };
      } else {
        throw Exception('Login failed: ${response.data}');
      }
    } on DioException catch (e) {
      throw _apiError('登录失败', e);
    }
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String emailCode,
    required String captchaId,
    required String captchaCode,
    required String deviceId,
    required String deviceName,
    String platform = 'windows',
    String appVersion = '1.4.5-beta.5+7',
    Map<String, dynamic>? captchaResult,
  }) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/auth/web/register'),
        data: {
          'email': email,
          'username': username,
          'password': password,
          'email_code': emailCode,
          'device_id': deviceId,
          'device_name': deviceName,
          'platform': platform,
          'app_version': appVersion,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      } else {
        throw Exception('Register failed');
      }
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Map<String, dynamic> _geetestFields(Map<String, dynamic> result) {
    return {
      'geetest_lot_number': result['lot_number'],
      'geetest_captcha_output': result['captcha_output'],
      'geetest_pass_token': result['pass_token'],
      'geetest_gen_time': result['gen_time'],
    };
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/auth/refresh'),
        data: {'refresh_token': refreshToken},
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('刷新 token 失败', e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(Constants.apiPath('/v1/auth/logout'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 楠岃瘉鐮?====================

  Future<Map<String, dynamic>> getCaptcha() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/auth/captcha'),
        options: Options(responseType: ResponseType.bytes),
      );
      final captchaId = response.headers.value('x-captcha-id') ?? '';
      final body = response.data;
      if (body is List<int>) {
        return {'captcha_id': captchaId, 'image_bytes': body};
      }
      if (body is Map) return Map<String, dynamic>.from(body);
      return {'captcha_id': captchaId};
    } on DioException catch (e) {
      throw Exception('获取验证码失败: ${e.message}');
    }
  }

  Future<void> sendEmailCode(
    String email,
    Map<String, dynamic> captchaResult,
  ) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/auth/email/send'),
        data: {
          'email': email,
          'purpose': 'register',
          ..._geetestFields(captchaResult),
        },
      );
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      throw Exception('鍙戦€侀獙璇佺爜澶辫触: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/auth/password/reset'),
        data: {'email': email, 'code': code, 'new_password': newPassword},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 濂藉弸 ====================

  Future<List<Conversation>> getFriends() async {
    try {
      final response = await _requestV2WithV1Fallback('GET', '/v2/friends');
      if (response.statusCode == 200) {
        final list = _nestedList(_unwrapEnvelopeMap(response.data), const [
          'friends',
          'items',
          'list',
        ]);
        return list
            .whereType<Map>()
            .map((raw) {
              final e = Map<String, dynamic>.from(raw);
              return Conversation.fromJson({
                ...e,
                'id': e['uid'] ?? e['ncuid'] ?? e['id'],
                'type': 'direct',
              });
            })
            .where((conversation) => conversation.id.trim().isNotEmpty)
            .toList();
      } else {
        throw Exception('Failed to load friends');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getFriendRequests() async {
    try {
      final response = await _requestV2WithV1Fallback(
        'GET',
        '/v2/friends/requests',
      );
      final value = _unwrapEnvelopeMap(response.data);
      final requests = _nestedList(value, const [
        'requests',
        'items',
        'list',
        'data',
        'result',
      ]);
      if (requests.isNotEmpty) value['requests'] = requests;
      return value;
    } on DioException catch (e) {
      throw _apiError('加载好友申请失败', e);
    }
  }

  Future<void> sendFriendRequest(String toUid) async {
    try {
      await _v2Request(
        'POST',
        '/v2/friends/request',
        data: {'to_uid': toUid.trim(), 'to_ncuid': toUid.trim()},
      );
    } on DioException catch (e) {
      throw _apiError('发送好友申请失败', e);
    }
  }

  Future<void> respondFriendRequest(String requestId, bool accept) async {
    try {
      await _v2Request(
        'POST',
        '/v2/friends/respond',
        data: {'request_id': requestId.trim(), 'accept': accept},
      );
    } on DioException catch (e) {
      throw _apiError('处理好友申请失败', e);
    }
  }

  Future<void> remarkFriend(String uid, String remark) async {
    try {
      await _v2Request(
        'POST',
        '/v2/friends/remark',
        data: {
          'uid': uid,
          'friend_uid': uid,
          'friend_ncuid': uid,
          'remark': remark,
          'remark_name': remark,
        },
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteFriend(String uid) async {
    try {
      await _v2Request(
        'POST',
        '/v2/friends/delete',
        data: {'uid': uid, 'friend_uid': uid, 'friend_ncuid': uid},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 缇よ亰 ====================

  Future<List<Conversation>> getGroups() async {
    try {
      final response = await _requestV2WithV1Fallback('GET', '/v2/groups/list');
      if (response.statusCode == 200) {
        final list = _nestedList(_unwrapEnvelopeMap(response.data), const [
          'groups',
          'items',
          'list',
        ]);
        return list
            .whereType<Map>()
            .map((raw) {
              final e = Map<String, dynamic>.from(raw);
              return Conversation.fromJson({
                ...e,
                'id': e['group_id'] ?? e['id'],
                'type': 'group',
              });
            })
            .where((conversation) => conversation.id.trim().isNotEmpty)
            .toList();
      } else {
        throw Exception('Failed to load groups');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createGroup(
    String name,
    List<String> members,
  ) async {
    try {
      final response = await _v2Request(
        'POST',
        '/v2/groups/create',
        data: {
          'name': name,
          'members': members,
          'member_uids': members,
          'member_ncuids': members,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> joinGroup(String groupId) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/join',
        data: {'group_id': groupId.trim()},
      );
    } on DioException catch (e) {
      throw _apiError('加入群聊失败', e);
    }
  }

  Future<void> approveGroupRequest(String requestId, bool accept) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/approve',
        data: {'request_id': requestId.trim(), 'accept': accept},
      );
    } on DioException catch (e) {
      throw _apiError('处理群聊申请失败', e);
    }
  }

  Future<Map<String, dynamic>> getGroupMembers(String groupId) async {
    try {
      final response = await _v2Request(
        'GET',
        '/v2/groups/members',
        queryParameters: {'group_id': groupId.trim()},
      );
      final raw = response.data;
      if (raw is Map && raw['members'] is List)
        return Map<String, dynamic>.from(raw);
      if (raw is Map && raw['data'] is Map) {
        return Map<String, dynamic>.from(raw['data'] as Map);
      }
      if (raw is Map && raw['data'] is List) {
        return {'members': raw['data']};
      }
      return {'members': const <dynamic>[]};
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getGroupRequests(String groupId) async {
    try {
      final response = await _requestV2WithV1Fallback(
        'GET',
        '/v2/groups/requests',
        queryParameters: {'group_id': groupId.trim()},
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('加载群聊申请失败', e);
    }
  }

  Future<Map<String, dynamic>> getAllGroupRequests() async {
    try {
      final response = await _requestV2WithV1Fallback(
        'GET',
        '/v2/groups/requests',
      );
      final value = _unwrapEnvelopeMap(response.data);
      final requests = _nestedList(value, const [
        'requests',
        'items',
        'list',
        'data',
        'result',
      ]);
      if (requests.isNotEmpty) value['requests'] = requests;
      return value;
    } on DioException catch (e) {
      throw _apiError('加载群聊申请失败', e);
    }
  }

  Future<Map<String, dynamic>> getGroupInvitations() async {
    try {
      final response = await _requestV2WithV1Fallback(
        'GET',
        '/v2/groups/invitations',
      );
      final value = _unwrapEnvelopeMap(response.data);
      final invitations = _nestedList(value, const [
        'invitations',
        'items',
        'list',
        'data',
        'result',
      ]);
      if (invitations.isNotEmpty) value['invitations'] = invitations;
      return value;
    } on DioException catch (e) {
      throw _apiError('加载群聊邀请失败', e);
    }
  }

  Future<void> respondGroupInvitation(String invitationId, bool accept) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/invitations/respond',
        data: {'invitation_id': invitationId.trim(), 'accept': accept},
      );
    } on DioException catch (e) {
      throw _apiError('处理群聊邀请失败', e);
    }
  }

  Future<void> inviteToGroup(String groupId, String uid) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/invite',
        data: {'group_id': groupId.trim(), 'user_uid': uid.trim()},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> setGroupAdmin(String groupId, String uid, bool isAdmin) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/admin',
        data: {'group_id': groupId, 'uid': uid, 'is_admin': isAdmin},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateGroupAvatar(String groupId, FormData formData) async {
    try {
      await _v2Request('POST', '/v2/groups/avatar', data: formData);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> kickGroupMember(String groupId, String uid) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/kick',
        data: {'group_id': groupId, 'uid': uid},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateGroupName(String groupId, String name) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/name',
        data: {'group_id': groupId, 'name': name},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateGroupSettings(
    String groupId,
    Map<String, dynamic> settings,
  ) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/settings',
        data: {'group_id': groupId, ...settings},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> setGroupAnnouncement(String groupId, String announcement) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/announcement',
        data: {'group_id': groupId, 'announcement': announcement},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> markAnnouncementRead(
    String groupId,
    String announcementId,
  ) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/announcement/read',
        data: {'group_id': groupId, 'announcement_id': announcementId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      await _v2Request('POST', '/v2/groups/leave', data: {'group_id': groupId});
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> dissolveGroup(String groupId) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/dissolve',
        data: {'group_id': groupId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 绉佽亰 ====================

  Future<Map<String, dynamic>> getDirectMessages({
    required String withUid,
    int limit = 100,
    int offset = 0,
    String? beforeCreatedAt,
    String? beforeId,
    int? afterCreatedAt,
    String? afterId,
  }) async {
    try {
      final queryParameters = <String, dynamic>{
        'with_uid': withUid,
        'limit': limit,
      };
      if (beforeCreatedAt != null) {
        queryParameters['before_created_at'] = beforeCreatedAt;
      }
      if (beforeId != null) {
        queryParameters['before_id'] = beforeId;
      }
      if (afterCreatedAt != null) {
        queryParameters['after_created_at'] = afterCreatedAt;
      }
      if (afterId != null && afterId.isNotEmpty) {
        queryParameters['after_id'] = afterId;
      }
      if (beforeCreatedAt == null &&
          beforeId == null &&
          afterCreatedAt == null) {
        queryParameters['offset'] = offset;
      }

      final response = await _requestV2WithV1Fallback(
        'GET',
        Constants.directMessagesPath,
        queryParameters: queryParameters,
      );
      if (response.statusCode == 200) {
        final data = _unwrapEnvelopeMap(response.data);
        final rawMessages = _nestedList(data, const [
          'messages',
          'items',
          'list',
          'data',
          'result',
        ]);
        final messages = rawMessages
            .whereType<Map>()
            .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        final rawHasMore = data['has_more'];
        final hasMore =
            rawHasMore == true ||
            rawHasMore?.toString().toLowerCase() == 'true';
        return {
          'messages': messages,
          'has_more': hasMore,
          'effective_offset': data['effective_offset'] ?? 0,
          'next_before_created_at': data['next_before_created_at'],
          'next_before_id': data['next_before_id'],
        };
      } else {
        throw Exception('Failed to load direct messages');
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) {
        try {
          final fallbackQuery = <String, dynamic>{
            'with_uid': withUid,
            'limit': limit,
            if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty)
              'before_created_at': beforeCreatedAt,
            if (beforeId != null && beforeId.isNotEmpty) 'before_id': beforeId,
            if (beforeCreatedAt == null &&
                beforeId == null &&
                afterCreatedAt == null)
              'offset': offset,
            if (afterCreatedAt != null) 'after_created_at': afterCreatedAt,
            if (afterId != null && afterId.isNotEmpty) 'after_id': afterId,
          };
          final response = await _dio.get(
            Constants.apiPath('/v1/direct/messages/v2'),
            queryParameters: fallbackQuery,
          );
          final data = _unwrapEnvelopeMap(response.data);
          final rawMessages = _nestedList(data, const [
            'messages',
            'items',
            'list',
            'data',
            'result',
          ]);
          final messages = rawMessages
              .whereType<Map>()
              .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
              .toList();
          final rawHasMore = data['has_more'];
          final hasMore =
              rawHasMore == true ||
              rawHasMore?.toString().toLowerCase() == 'true';
          return {
            'messages': messages,
            'has_more': hasMore,
            'effective_offset': data['effective_offset'] ?? offset,
            'next_before_created_at': data['next_before_created_at'],
            'next_before_id': data['next_before_id'],
          };
        } on DioException catch (fallbackError) {
          throw _apiError('加载私聊消息失败', fallbackError);
        }
      }
      throw _apiError('加载私聊消息失败', e);
    }
  }

  Future<Map<String, dynamic>> searchDirectMessages(
    String withUid,
    String query,
  ) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/direct/messages/search'),
        queryParameters: {'with_uid': withUid, 'keyword': query, 'limit': 100},
      );
      return _normalizeSearchResponse(response.data);
    } on DioException catch (e) {
      throw _apiError('搜索私聊记录失败', e);
    }
  }

  Future<Message> sendDirectMessage({
    required String toUid,
    required String body,
    String msgType = 'text',
    String? mediaUrl,
    String? thumbUrl,
    int durationMs = 0,
    int burnAfterSeconds = 0,
  }) async {
    try {
      final payload = {
        'to_uid': toUid,
        'to_ncuid': toUid,
        'body': body,
        'msg_type': msgType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (thumbUrl != null) 'thumb_url': thumbUrl,
        if (mediaUrl != null) 'original_url': mediaUrl,
        'duration_ms': durationMs,
        'burn_after_seconds': burnAfterSeconds,
      };
      final response = await _v2Request(
        'POST',
        '/v2/direct/send',
        data: payload,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return Message.fromJson(_unwrapMessage(response.data));
      } else {
        throw Exception('Send direct message failed');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  dynamic _unwrapMessage(dynamic raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in const ['message', 'data', 'result']) {
        if (map[key] is Map) return map[key];
      }
    }
    return raw;
  }

  Map<String, dynamic> _unwrapEnvelopeMap(dynamic raw) {
    if (raw is Map) {
      var map = Map<String, dynamic>.from(raw);
      for (var i = 0; i < 4; i++) {
        final body = map['body'];
        if (body is String) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map) {
              map = Map<String, dynamic>.from(decoded);
              continue;
            }
          } catch (_) {}
        }
        final nested = map['data'] ?? map['result'] ?? map['payload'];
        if (nested is Map) {
          map = {...map, ...Map<String, dynamic>.from(nested)};
          continue;
        }
        break;
      }
      return map;
    }
    return {'data': raw};
  }

  Future<void> sendTyping(
    String targetId,
    bool typing, {
    String type = 'direct',
  }) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/chats/typing'),
        data: {'target_id': targetId, 'typing': typing, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getDirectUnread() async {
    try {
      final response = await _requestV2WithV1Fallback(
        'POST',
        '/v2/unread/direct',
        data: {'limit': 200, 'offset': 0},
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('加载私聊未读失败', e);
    }
  }

  Future<void> markDirectRead(String withUid) async {
    try {
      await _v2Request(
        'POST',
        '/v2/direct/read',
        data: {'with_uid': withUid.trim()},
      );
    } on DioException catch (e) {
      throw _apiError('标记私聊已读失败', e);
    }
  }

  Future<void> openBurnMessage(String messageId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/direct/burn/open'),
        data: {'message_id': messageId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> recallDirectMessage(String messageId) async {
    try {
      await _dio.delete(Constants.apiPath('/v1/direct/messages/$messageId'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 缇よ亰娑堟伅 ====================

  Future<Map<String, dynamic>> getGroupMessages({
    required String groupId,
    int limit = 100,
    int offset = 0,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    try {
      final queryParameters = <String, dynamic>{
        'group_id': groupId,
        'limit': limit,
      };
      if (beforeCreatedAt != null) {
        queryParameters['before_created_at'] = beforeCreatedAt;
      }
      if (beforeId != null) {
        queryParameters['before_id'] = beforeId;
      }
      if (beforeCreatedAt == null && beforeId == null) {
        queryParameters['offset'] = offset;
      }

      final response = await _requestV2WithV1Fallback(
        'GET',
        Constants.groupMessagesPath,
        queryParameters: queryParameters,
      );
      if (response.statusCode == 200) {
        final data = _unwrapEnvelopeMap(response.data);
        final rawMessages = _nestedList(data, const [
          'messages',
          'items',
          'list',
          'data',
          'result',
        ]);
        final messages = rawMessages
            .whereType<Map>()
            .map((e) => Message.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final rawHasMore = data['has_more'];
        final hasMore =
            rawHasMore == true ||
            rawHasMore?.toString().toLowerCase() == 'true';
        return {
          'messages': messages,
          'has_more': hasMore,
          'effective_offset': data['effective_offset'] ?? 0,
          'next_before_created_at': data['next_before_created_at'],
          'next_before_id': data['next_before_id'],
        };
      } else {
        throw Exception('Failed to load group messages');
      }
    } on DioException catch (e) {
      throw _apiError('加载群聊消息失败', e);
    }
  }

  Future<Map<String, dynamic>> getGroupMessagesAfter(
    String groupId,
    int afterSeq, {
    int limit = 100,
  }) async {
    try {
      final response = await _requestV2WithV1Fallback(
        'GET',
        '/v2/groups/messages/after',
        queryParameters: {'group_id': groupId, 'seq': afterSeq, 'limit': limit},
      );
      final raw = response.data;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final rawMessages = _nestedList(data, const [
        'messages',
        'items',
        'list',
        'data',
        'result',
      ]);
      final messages = rawMessages
          .whereType<Map>()
          .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final rawHasMore = data['has_more'];
      final hasMore =
          rawHasMore == true || rawHasMore?.toString().toLowerCase() == 'true';
      return {
        'messages': messages,
        'has_more': hasMore,
        'next_group_seq':
            data['next_group_seq'] ?? data['server_group_seq'] ?? afterSeq,
        'server_group_seq': data['server_group_seq'],
      };
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> searchGroupMessages(
    String groupId,
    String query,
  ) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/groups/messages/search'),
        queryParameters: {'group_id': groupId, 'keyword': query, 'limit': 100},
      );
      return _normalizeSearchResponse(response.data);
    } on DioException catch (e) {
      throw _apiError('搜索群聊记录失败', e);
    }
  }

  Future<Message> sendGroupMessage({
    required String groupId,
    required String body,
    String msgType = 'text',
    String? mediaUrl,
    String? thumbUrl,
    int durationMs = 0,
    int burnAfterSeconds = 0,
  }) async {
    try {
      final payload = {
        'group_id': groupId,
        'body': body,
        'msg_type': msgType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (thumbUrl != null) 'thumb_url': thumbUrl,
        if (mediaUrl != null) 'original_url': mediaUrl,
        'duration_ms': durationMs,
        'burn_after_seconds': burnAfterSeconds,
      };
      final response = await _v2Request(
        'POST',
        '/v2/groups/message/send',
        data: payload,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return Message.fromJson(_unwrapMessage(response.data));
      } else {
        throw Exception('Send group message failed');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> sendGroupTyping(String groupId, bool typing) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/typing'),
        data: {'group_id': groupId, 'typing': typing},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getGroupUnread() async {
    try {
      final response = await _requestV2WithV1Fallback(
        'POST',
        '/v2/unread/groups',
        data: {'limit': 200, 'offset': 0},
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('加载群聊未读失败', e);
    }
  }

  Future<void> markGroupRead(String groupId) async {
    try {
      await _v2Request(
        'POST',
        '/v2/groups/read',
        data: {'group_id': groupId.trim()},
      );
    } on DioException catch (e) {
      throw _apiError('标记群聊已读失败', e);
    }
  }

  Future<void> openGroupBurnMessage(String messageId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/burn/open'),
        data: {'message_id': messageId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> recallGroupMessage(String messageId) async {
    try {
      await _dio.delete(Constants.apiPath('/v1/groups/messages/$messageId'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鐢ㄦ埛璧勬枡 ====================

  Future<Map<String, dynamic>> getUserProfile(String uid) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/users/profile'),
        queryParameters: {'uid': uid.trim()},
      );
      final raw = response.data;
      if (raw is Map && raw['data'] is Map) {
        return Map<String, dynamic>.from(raw['data'] as Map);
      }
      return Map<String, dynamic>.from(raw as Map);
    } on DioException catch (e) {
      throw _apiError('加载用户资料失败', e);
    }
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/me'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/profile'), data: data);
    } on DioException catch (e) {
      throw _apiError('更新个人资料失败', e);
    }
  }

  Future<void> updateUid(String newUid) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/uid'),
        data: {'uid': newUid.trim()},
      );
    } on DioException catch (e) {
      throw _apiError('更新 UID 失败', e);
    }
  }

  Future<void> updatePassword(String oldPassword, String newPassword) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/password'),
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateAvatar(FormData formData) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/avatar'), data: formData);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateCover(FormData formData) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/cover'), data: formData);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/delete'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 绾㈠寘锛堜慨澶嶏細娣诲姞鏃ュ織銆佹竻鐞嗙壒娈婂瓧绗︼級 ====================

  Future<Map<String, dynamic>> createRedPacket({
    required String targetId,
    required String amount,
    required String type,
    int count = 1,
    String title = '鎭枩鍙戣储',
    String? coverUrl,
  }) async {
    try {
      final amountInt = int.tryParse(amount) ?? 0;
      final payload = <String, dynamic>{
        'title': title.trim().isEmpty ? '鎭枩鍙戣储' : title.trim(),
        'total_amount': amountInt,
        'total_count': count > 0 ? count : 1,
        if (type == 'group') 'group_id': targetId else 'to_uid': targetId,
        if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
      };

      final response = await _dio.post(
        Constants.apiPath('/v1/redpackets/send'),
        data: payload,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
        final nested = data['data'] is Map
            ? Map<String, dynamic>.from(data['data'] as Map)
            : const <String, dynamic>{};
        final packetId =
            data['packet_id'] ??
            data['packetId'] ??
            data['id'] ??
            nested['packet_id'] ??
            nested['packetId'] ??
            nested['id'];
        if (packetId == null || packetId.toString().isEmpty) {
          throw Exception('服务器未返回红包 ID');
        }
        return {...data, 'packet_id': packetId.toString()};
      } else {
        throw Exception('绾㈠寘鍒涘缓澶辫触');
      }
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      if (error is String && error.isNotEmpty) {
        throw Exception(error);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> claimRedPacket(String packetId) async {
    try {
      final response = await _v2Request(
        'POST',
        '/v2/redpackets/claim',
        data: {'packet_id': packetId.trim()},
      );
      final value = response.data;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{'data': value};
    } on DioException catch (e) {
      throw _apiError('领取红包失败', e);
    }
  }

  Future<Map<String, dynamic>> getRedPacketInfo(String packetId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/redpackets/$packetId'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 涓婁紶鏂囦欢 ====================

  Future<Map<String, dynamic>> uploadFile(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/media'),
        data: formData,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      } else {
        throw Exception('Upload failed');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> voiceASR(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/voice/asr'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鍔ㄦ€?====================

  Future<Map<String, dynamic>> createMoment({
    required String body,
    String? imageUrl,
    List<String>? imageUrls,
  }) async {
    try {
      final urls =
          <String>[
                ...?imageUrls,
                if (imageUrl != null && imageUrl.isNotEmpty) imageUrl,
              ]
              .map((url) => url.trim())
              .where((url) => url.isNotEmpty)
              .toSet()
              .toList();
      final response = await _dio.post(
        Constants.apiPath('/v1/moments'),
        data: {
          'body': body,
          if (urls.length == 1) 'image_url': urls.first,
          if (urls.length > 1) 'image_url': jsonEncode(urls),
          if (urls.isNotEmpty) 'image_urls': urls,
          if (urls.isNotEmpty) 'images': urls,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMoments({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.momentsPath,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Failed to get moments');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getUserMoments(
    String uid, {
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/moments/user'),
        queryParameters: {'uid': uid, 'limit': limit, 'offset': offset},
      );
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Failed to get user moments');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeMoment(String momentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/like'),
        data: {'moment_id': momentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeMoment(String momentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/unlike'),
        data: {'moment_id': momentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMoment(String momentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/delete'),
        data: {'moment_id': momentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentMoment(
    String momentId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/moments/comment'),
        data: {'moment_id': momentId, 'body': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMomentComment(String commentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/comment/delete'),
        data: {'comment_id': commentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMomentComments(
    String momentId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/moments/comments'),
        queryParameters: {
          'moment_id': momentId,
          'limit': limit,
          'offset': offset,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<dynamic> readJsonCache(String key) =>
      ImageCacheService.instance.readJsonCache(key);

  Future<void> writeJsonCache(String key, Object value) =>
      ImageCacheService.instance.writeJsonCache(key, value);

  Future<Map<String, dynamic>> getPublicCourtCases({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases'),
        queryParameters: {'limit': limit, 'offset': offset, 'status': 'all'},
      );
      final value = _unwrapEnvelopeMap(response.data);
      final cases = _nestedList(response.data, const [
        'cases',
        'items',
        'list',
        'records',
        'results',
        'data',
        'result',
        'payload',
      ]);
      if (cases.isNotEmpty || response.data is List) value['cases'] = cases;
      return value;
    } on DioException catch (e) {
      throw _apiError('加载公开法庭失败', e);
    }
  }

  Future<Map<String, dynamic>> getPublicCourtCase(String caseId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases/$caseId'),
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('加载公开案件详情失败', e);
    }
  }

  Future<Map<String, dynamic>> votePublicCourtCase(
    String caseId,
    String vote, {
    String reason = '',
    String evidence = '',
  }) async {
    try {
      final normalizedReason = reason.trim();
      final normalizedEvidence = evidence.trim();
      final response = await _dio.post(
        Constants.apiPath('/v1/public-court/cases/$caseId/vote'),
        data: {
          'vote': vote,
          'decision': vote,
          'reason': normalizedReason,
          'statement': normalizedReason,
          'evidence': normalizedEvidence,
          'evidence_url': normalizedEvidence,
        },
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('提交公开法庭投票失败', e);
    }
  }

  Future<Map<String, dynamic>> submitPublicCourtStatement(
    String caseId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/public-court/cases/$caseId/statement'),
        data: {'reason': text, 'evidence': ''},
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('提交公开法庭陈述失败', e);
    }
  }

  Future<Map<String, dynamic>> getPublicCourtVotes(String caseId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases/$caseId/votes'),
      );
      final value = _unwrapEnvelopeMap(response.data);
      final nested = value['data'];
      if (nested is Map) value.addAll(Map<String, dynamic>.from(nested));
      return value;
    } on DioException catch (e) {
      throw _apiError('加载案件投票失败', e);
    }
  }

  Future<Map<String, dynamic>> getPublicCourtDiscussions(String caseId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases/$caseId/discussions'),
      );
      final value = _unwrapEnvelopeMap(response.data);
      final items = _nestedList(value, const [
        'discussions',
        'items',
        'list',
        'records',
        'results',
        'data',
      ]);
      if (items.isNotEmpty) value['discussions'] = items;
      return value;
    } on DioException catch (e) {
      throw _apiError('加载案件讨论失败', e);
    }
  }

  Future<Map<String, dynamic>> submitPublicCourtDiscussion(
    String caseId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/public-court/cases/$caseId/discussion'),
        data: {'body': text},
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _apiError('提交案件讨论失败', e);
    }
  }

  Future<void> withdrawPublicCourtStatement(String caseId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/public-court/cases/$caseId/withdraw'),
      );
    } on DioException catch (e) {
      throw _apiError('撤回案件陈述失败', e);
    }
  }

  // ==================== 闊充箰骞垮満 ====================

  Future<Map<String, dynamic>> getMusicPlaza({
    int limit = 20,
    int offset = 0,
    String? endpoint,
    String? query,
  }) async {
    final path = endpoint ?? Constants.apiPath('/v1/music/plaza');
    try {
      final response = await _dio.get(
        path,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMyMusic() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/mine'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> uploadMusic(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/music/plaza/upload'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> updateMusic(
    String musicId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/music/plaza/update'),
        data: {'music_id': musicId, ...data},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<String> getExternalText(String url) async {
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        headers: const {'Accept': 'text/plain, text/*;q=0.9, */*;q=0.1'},
      ),
    ).get<String>(url);
    return response.data ?? '';
  }

  Future<Map<String, dynamic>> getMusicLyrics(String musicId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/lyrics'),
        queryParameters: {'item_id': musicId},
      );
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 ||
          e.response?.statusCode == 405 ||
          e.response?.statusCode == 400) {
        final response = await _dio.post(
          Constants.apiPath('/v1/music/plaza/lyrics'),
          data: {'music_id': musicId},
        );
        final data = response.data;
        return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<String> getMusicLyricsText(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/delete'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMultipleMusic(List<String> musicIds) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/mine/delete-batch'),
        data: {'music_ids': musicIds},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/like'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/unlike'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentMusic(String musicId, String text) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/music/plaza/comment'),
        data: {'music_id': musicId, 'text': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMusicComment(String commentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/comment/delete'),
        data: {'comment_id': commentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMusicComments(
    String musicId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/comments'),
        queryParameters: {
          'music_id': musicId,
          'limit': limit,
          'offset': offset,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMusicRanking() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/ranking'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> playMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/play'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 琛ㄦ儏骞垮満 ====================

  Future<Map<String, dynamic>> getEmojiPlaza({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/emoji/plaza'),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMyEmojis() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/emoji/plaza/mine'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> uploadEmoji(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/emoji/plaza/upload'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> saveEmoji(String emojiId) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/emoji/plaza/save'),
        data: {'emoji_id': emojiId},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteEmoji(String emojiId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/emoji/plaza/delete'),
        data: {'emoji_id': emojiId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鏀惰棌 ====================

  Future<List<Map<String, dynamic>>> discoverChannels({
    String query = '',
  }) async {
    try {
      final response = await _v2Request(
        'GET',
        '/v2/channels/discover',
        queryParameters: {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'limit': 50,
        },
      );
      final unwrapped = _unwrapEnvelopeMap(response.data);
      final raw = _nestedValue(unwrapped, const [
        'channels',
        'items',
        'list',
        'data',
        'result',
        'payload',
      ]);
      return raw is List
          ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const [];
    } on DioException catch (e) {
      throw _apiError('加载频道失败', e);
    }
  }

  Future<Map<String, dynamic>> getChannelStates() async {
    try {
      final response = await _v2Request('GET', '/v2/channels/states');
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _apiError('加载频道状态失败', e);
    }
  }

  Future<Map<String, dynamic>> setChannelNotifications(
    String channelId,
    String level,
  ) async {
    try {
      final response = await _v2Request(
        'POST',
        '/v2/channels/notifications',
        data: {'channel_id': channelId, 'notification_level': level},
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _apiError('设置频道通知失败', e);
    }
  }

  Future<Map<String, dynamic>> subscribeChannel(String channelId) async {
    try {
      final r = await _v2Request(
        'POST',
        '/v2/channels/subscribe',
        data: {'channel_id': channelId},
      );
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _apiError('订阅频道失败', e);
    }
  }

  Future<Map<String, dynamic>> unsubscribeChannel(String channelId) async {
    try {
      final r = await _v2Request(
        'POST',
        '/v2/channels/unsubscribe',
        data: {'channel_id': channelId},
      );
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _apiError('取消订阅失败', e);
    }
  }

  Future<Map<String, dynamic>> sendChannelPost(
    String channelId,
    String text, {
    String? mediaUrl,
  }) async {
    try {
      final r = await _v2Request(
        'POST',
        '/v2/channels/posts/send',
        data: {
          'channel_id': channelId,
          'body': text.trim(),
          'content_text': text.trim(),
          'msg_type': mediaUrl != null && mediaUrl.trim().isNotEmpty
              ? 'image'
              : 'text',
          'type': mediaUrl != null && mediaUrl.trim().isNotEmpty
              ? 'image'
              : 'text',
          if (mediaUrl != null && mediaUrl.trim().isNotEmpty)
            'media_url': mediaUrl.trim(),
        },
      );
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _apiError('发布频道消息失败', e);
    }
  }

  Future<void> markChannelRead(String channelId, int seq) async {
    try {
      await _v2Request(
        'POST',
        '/v2/channels/read',
        data: {'channel_id': channelId.trim(), 'read_seq': seq},
      );
    } on DioException catch (e) {
      throw _apiError('标记频道已读失败', e);
    }
  }

  Future<List<Map<String, dynamic>>> getChannelPosts(
    String channelId, {
    int seq = 0,
  }) async {
    try {
      final r = await _v2Request(
        'GET',
        '/v2/channels/posts/after',
        queryParameters: {
          'channel_id': channelId,
          'after_seq': seq,
          'seq': seq,
          'limit': 100,
        },
      );
      final data = _unwrapEnvelopeMap(r.data);
      final raw = _nestedValue(data, const [
        'posts',
        'items',
        'list',
        'data',
        'result',
        'payload',
      ]);
      return raw is List
          ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const [];
    } on DioException catch (e) {
      throw _apiError('加载频道帖子失败', e);
    }
  }

  Future<Map<String, dynamic>> toggleChannelReaction(
    String channelId,
    String postId,
    String emoji,
  ) async {
    try {
      final r = await _v2Request(
        'POST',
        '/v2/channels/reactions/toggle',
        data: {'channel_id': channelId, 'post_id': postId, 'emoji': emoji},
      );
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _apiError('更新频道回应失败', e);
    }
  }

  Future<Map<String, dynamic>> callbackButton({
    required String messageId,
    required String conversationType,
    required String conversationId,
    required int buttonIndex,
    required String action,
    String formData = '',
  }) async {
    try {
      final response = await _v2Request(
        'POST',
        '/v2/buttons/callback',
        data: {
          'msg_id': messageId,
          'to_type': conversationType,
          'to_id': conversationId,
          'btn_index': buttonIndex,
          'tid': DateTime.now().microsecondsSinceEpoch.toString(),
          'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
          'action': action,
          if (formData.isNotEmpty) 'form_data': formData,
        },
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw _apiError('执行消息按钮失败', e);
    }
  }

  Future<Map<String, dynamic>> getFavorites() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/favorites'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> addFavorite(String targetId, String type) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/favorites/add'),
        data: {'target_id': targetId, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> removeFavorite(String targetId, String type) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/favorites/remove'),
        data: {'target_id': targetId, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 閫氱煡 ====================

  Future<Map<String, dynamic>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/notifications'),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final value = _asMap(response.data);
      final items = _nestedList(response.data, const [
        'items',
        'notifications',
        'list',
        'data',
        'result',
        'payload',
      ]);
      if (items.isNotEmpty || response.data is List) value['items'] = items;
      return _unwrapEnvelopeMap(value);
    } on DioException catch (e) {
      throw _apiError('加载系统通知失败', e);
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    throw UnsupportedError('系统通知已读仅保存在本地');
  }

  // ==================== 涓炬姤 ====================

  Future<Map<String, dynamic>> reportUser(String uid, String reason) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/reports/user'),
        data: {'uid': uid, 'reason': reason},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> reportGroup(
    String groupId,
    String reason,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/reports/group'),
        data: {'group_id': groupId, 'reason': reason},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 绛惧埌澧?====================

  Future<Map<String, dynamic>> getCheckinWall() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/me/checkin/wall'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> postCheckinWall(
    String text, {
    List<String>? mediaUrls,
  }) async {
    try {
      final urls = (mediaUrls ?? const <String>[])
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final response = await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall'),
        data: {
          'content_text': text.trim(),
          if (urls.isNotEmpty) 'image_urls': urls,
        },
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{'data': response.data};
    } on DioException catch (e) {
      throw _apiError('发布签到留言失败', e);
    }
  }

  Future<void> likeCheckinWall(String postId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall/like'),
        data: {'post_id': postId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeCheckinWall(String postId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall/unlike'),
        data: {'post_id': postId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentCheckinWall(
    String postId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall/comment'),
        data: {'post_id': postId, 'text': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getCheckinWallComments(
    String postId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/me/checkin/wall/comments'),
        queryParameters: {'post_id': postId, 'limit': limit, 'offset': offset},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getScratchCard() async {
    try {
      final response = await _v2Request('GET', '/v2/me/scratch');
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('加载每日刮刮乐失败', e);
    }
  }

  Future<Map<String, dynamic>> scratchCard() async {
    try {
      final response = await _v2Request(
        'POST',
        '/v2/me/scratch',
        data: const <String, dynamic>{},
      );
      return _unwrapEnvelopeMap(response.data);
    } on DioException catch (e) {
      throw _apiError('刮刮乐失败', e);
    }
  }

  // ==================== AI ====================
  // ==================== AI ====================

  Future<Map<String, dynamic>> getAIQuota() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/ai/quota'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> chatWithAI(
    String message, {
    String? model,
    AISettings? settings,
  }) async {
    if (settings != null &&
        settings.apiKey.trim().isNotEmpty &&
        settings.baseUrl.trim().isNotEmpty) {
      final base = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final endpoint = base.endsWith('/chat/completions')
          ? base
          : '$base/chat/completions';
      final response =
          await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Authorization': 'Bearer ${settings.apiKey.trim()}',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          ).post(
            endpoint,
            data: {
              'messages': [
                {'role': 'user', 'content': message},
              ],
              if (model != null) 'model': model,
            },
          );
      return Map<String, dynamic>.from(response.data as Map);
    }
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/ai/chat/completions'),
        data: {
          'messages': [
            {'role': 'user', 'content': message},
          ],
          if (model != null) 'model': model,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<({String baseUrl, String apiKey})?> _customAIOptions() async {
    final settings = await AISettingsService.load();
    final apiKey = settings.apiKey.trim();
    final baseUrl = settings.baseUrl.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) return null;
    return (baseUrl: baseUrl, apiKey: apiKey);
  }

  // ==================== 绛惧埌 ====================

  Future<Map<String, dynamic>> dailyCheckin() async {
    try {
      final response = await _dio.post(Constants.apiPath('/v1/me/checkin'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 璁惧绠＄悊 ====================

  Future<Map<String, dynamic>> getDevices() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/me/devices'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> cleanupDevices() async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/devices/cleanup'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> cleanupOtherDevices() async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/devices/cleanup-others'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鍙嶉 ====================

  Future<Map<String, dynamic>> submitFeedback(
    String type,
    String content, {
    List<String>? images,
  }) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/feedback'),
        data: {
          'type': type,
          'content': content,
          if (images != null) 'images': images,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 璧勬簮鍖?====================

  Future<Map<String, dynamic>> getResourceSections() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/sections'),
        queryParameters: {'limit': 200, 'offset': 0},
      );
      final data = response.data;
      debugPrint('[资源广场] sections-json=${jsonEncode(data)}');
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      debugPrint(
        '[资源广场] sections error ${e.response?.statusCode}: ${e.response?.data}',
      );
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createResourceSection(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/resources/sections'),
        data: data,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteResourceSection(String sectionId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/sections/delete'),
        data: {'section_id': sectionId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> uploadResource(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/resources/upload'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getResourceQuota() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/me/resources/quota'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getResourceItems({
    int limit = 20,
    int offset = 0,
    String? sectionId,
  }) async {
    try {
      final normalizedSectionId = sectionId?.trim();
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/items'),
        queryParameters: {
          if (normalizedSectionId != null && normalizedSectionId.isNotEmpty)
            'section_id': normalizedSectionId,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = response.data;
      debugPrint(
        '[资源广场] items-json=${jsonEncode(<String, dynamic>{'section_id': normalizedSectionId, 'limit': limit, 'offset': offset, 'response': data})}',
      );
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      debugPrint(
        '[资源广场] items error ${e.response?.statusCode}: ${e.response?.data}',
      );
      final data = e.response?.data;
      final detail = data is Map
          ? (data['error'] ?? data['message'] ?? data['code'])
          : null;
      throw Exception('资源列表请求失败${detail == null ? '' : '：$detail'}');
    }
  }

  Future<Map<String, dynamic>> searchResources(String query) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/search'),
        queryParameters: {'q': query.trim()},
      );
      final data = response.data;
      debugPrint(
        '[资源广场] search-json=${jsonEncode(<String, dynamic>{'query': query.trim(), 'response': data})}',
      );
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      debugPrint(
        '[资源广场] search error ${e.response?.statusCode}: ${e.response?.data}',
      );
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteResource(String resourceId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/items/delete'),
        data: {'resource_id': resourceId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeResource(String resourceId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/like'),
        data: {'resource_id': resourceId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeResource(String resourceId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/unlike'),
        data: {'resource_id': resourceId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentResource(
    String resourceId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/resources/comment'),
        data: {'resource_id': resourceId, 'text': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getResourceComments(
    String resourceId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/comments'),
        queryParameters: {
          'resource_id': resourceId,
          'limit': limit,
          'offset': offset,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteResourceComment(String commentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/comment/delete'),
        data: {'comment_id': commentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> reportResource(String resourceId, String reason) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/report'),
        data: {'resource_id': resourceId, 'reason': reason},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<dynamic> getRaw(String path) async {
    if (!path.startsWith('/') || path.contains('..') || path.contains('://')) {
      throw Exception('Invalid API path');
    }
    final response = await _dio.get(Constants.apiPath(path));
    return response.data;
  }
}
