import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../services/account_storage.dart';

class Constants {
  static const String baseUrlKey = 'base_url';
  static const String apiVersionKey = 'api_version';
  static const String defaultBaseUrl = 'https://oc.mcl0.dpdns.org';
  static const String fallbackBaseUrl = 'http://154.9.24.232:8080';
  static const String hiddenFallbackServer = fallbackBaseUrl;
  static const String backupServer = fallbackBaseUrl;
  static const String mediaFallbackServer = fallbackBaseUrl;

  static String get resourceBaseUrl => defaultBaseUrl;
  static const String appName = 'OldChat For AllPlatform';
  static const String appAumid = 'ColoryiOldChatForAllPlatform';
  static const String appClsid = '936C39FC-6BBC-4A57-B8F8-7C627E401B2F';

  static String _baseUrl = defaultBaseUrl;
  static String _apiVersion = 'v2';

  static String get apiVersion => _apiVersion;

  static String apiPath(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    if (!normalized.startsWith('/v1/')) return normalized;
    return '/v1/${normalized.substring(4)}';
  }

  static String get baseUrl => kIsWeb ? Uri.base.origin : _baseUrl;

  static List<String> _customServers = <String>[];

  static List<String> get visibleServers => {
    defaultBaseUrl,
    fallbackBaseUrl,
    ..._customServers,
  }.toList(growable: false);

  static List<String> get mediaServers => {
    defaultBaseUrl,
    fallbackBaseUrl,
  }.toList(growable: false);

  static bool _isServerUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static Future<void> loadServers() async {
    final raw = AccountStorage.instance.getString('preferred_servers');
    if (raw == null || raw.trim().isEmpty) {
      _customServers = <String>[];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      _customServers = decoded is List
          ? decoded
                .map((e) => e.toString())
                .where(_isServerUrl)
                .toSet()
                .toList()
          : <String>[];
    } catch (_) {
      _customServers = <String>[];
    }
  }

  static Future<void> saveCustomServers(List<String> servers) async {
    _customServers = servers
        .map((e) => e.trim())
        .where(_isServerUrl)
        .toSet()
        .toList();
    await AccountStorage.instance.setString(
      'preferred_servers',
      jsonEncode(_customServers),
    );
  }

  static Future<void> resetAccountSettings() async {
    _baseUrl = defaultBaseUrl;
    _apiVersion = 'v2';
    _customServers = <String>[];
    await AccountStorage.instance.resetSettings();
  }

  static Future<void> loadBaseUrl() async {
    final storage = AccountStorage.instance;
    await storage.load();
    final savedBaseUrl = storage.getString(baseUrlKey)?.trim();
    _baseUrl = kIsWeb
        ? Uri.base.origin
        : savedBaseUrl == null ||
                savedBaseUrl.isEmpty ||
                savedBaseUrl.contains('60.205.94.101')
            ? defaultBaseUrl
            : savedBaseUrl;
    await loadServers();
    _apiVersion = 'v2';
    await storage.setString(apiVersionKey, 'v2');
  }

  static Future<void> saveBaseUrl(String url) async {
    final normalized = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!_isServerUrl(normalized)) {
      throw ArgumentError.value(url, 'url', '服务器地址无效');
    }
    _baseUrl = normalized;
    await AccountStorage.instance.setString(baseUrlKey, _baseUrl);
  }

  static Future<void> saveApiVersion(String version) async {
    _apiVersion = 'v2';
    await AccountStorage.instance.setString(apiVersionKey, _apiVersion);
  }

  static String get loginPath => '/v1/auth/login';
  static String get directMessagesPath => '/v2/direct/messages/v2';
  static String get groupMessagesPath => '/v2/groups/messages/v2';
  static String get momentsPath => '/v2/moments/feed';
  static String get wsPath => '/v2/ws';

  static String resolveMediaUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    if (value.startsWith('cip://')) return value;
    if (value.startsWith('channel-private:')) {
      return '$baseUrl/channel-media/${value.substring('channel-private:'.length)}';
    }
    if (value.contains('/channel-media/')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return '$baseUrl${value.startsWith('/') ? '' : '/'}$value';
  }

  static const String geetestCaptchaId = '769d069177e132e46eeba07a6210cf3a';
  static const String tokenKey = 'access_token';
  static const String userIdKey = 'user_id';
  static const String refreshTokenKey = 'refresh_token';
  static const String savedUsernameKey = 'saved_username'; // ★ 新增
  static const String savedPasswordKey = 'saved_password';
  static const String rememberPasswordKey = 'remember_password';
  static const String desktopNotificationsKey = 'desktop_notifications_enabled';
  static const String taskbarFlashKey = 'taskbar_flash_notification';
  static const String multiSessionReceptionKey =
      'multi_session_message_reception';
  static const String messageOrderCorrectionKey = 'message_order_correction';
  static const String autoUpdateKey = 'auto_update_enabled';
  static const String updateChannelKey = 'update_channel';
  static const String splashDurationKey = 'splash_duration_seconds';
  static const String scratchCardCacheKey = 'scratch_card_cache';
  static const String languageKey = 'app_language';
  static const String aria2EndpointKey = 'aria2_rpc_endpoint';
  static const String aria2SecretKey = 'aria2_rpc_secret';
}
