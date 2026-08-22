import 'dart:convert';
import 'package:universal_io/io.dart';

import 'package:dio/dio.dart';

import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../utils/url_helper.dart';

class VideoCacheService {
  static final VideoCacheService _instance = VideoCacheService._internal();
  factory VideoCacheService() => _instance;
  VideoCacheService._internal();

  Future<File?> getCachedFile(String url) async {
    final resolved = resolveMediaUrl(url);
    if (resolved.isEmpty) return null;
    final directoryPath = await CacheService().cacheDirectory(
      userId: AuthService().userId ?? 'guest',
    );
    final uri = Uri.tryParse(resolved);
    final extension = uri?.path.split('.').last;
    final safeExtension = extension != null && extension.length <= 5
        ? extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        : 'mp4';
    final key = base64UrlEncode(utf8.encode(resolved)).replaceAll('=', '');
    final safeKey = key.length > 120 ? key.substring(0, 120) : key;
    final prefix = '${directoryPath}${Platform.pathSeparator}video_$safeKey';
    final candidates = <File>[
      File('$prefix.$safeExtension'),
      File('$prefix.mp4'),
      File('$prefix.webm'),
      File('$prefix.mov'),
      File('$prefix.mkv'),
    ];
    for (final file in candidates) {
      if (await file.exists() && await file.length() > 0) return file;
    }
    return null;
  }

  Future<void> cacheInBackground(String url) async {
    try {
      await getLocalFile(url);
    } catch (_) {}
  }

  Future<File> getLocalFile(String url) async {
    final resolved = resolveMediaUrl(url);
    if (resolved.isEmpty) throw Exception('视频链接无效');
    final cached = await getCachedFile(resolved);
    if (cached != null) return cached;
    final directoryPath = await CacheService().cacheDirectory(
      userId: AuthService().userId ?? 'guest',
    );
    final uri = Uri.tryParse(resolved);
    final extension = uri?.path.split('.').last;
    final safeExtension = extension != null && extension.length <= 5
        ? extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        : 'mp4';
    final key = base64UrlEncode(utf8.encode(resolved)).replaceAll('=', '');
    final safeKey = key.length > 120 ? key.substring(0, 120) : key;
    final tempFile = File(
      '${directoryPath}${Platform.pathSeparator}video_$safeKey.$safeExtension',
    );
    if (await tempFile.exists() && await tempFile.length() > 0) return tempFile;
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    final token = AuthService().token;
    final downloadDio = Dio(
      BaseOptions(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      ),
    );
    final response = await downloadDio.download(
      resolved,
      tempFile.path,
      options: Options(
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
        responseType: ResponseType.bytes,
      ),
    );
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('视频下载失败: ${response.statusCode}');
    }
    final contentType =
        response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
    if (contentType.contains('text/html') ||
        contentType.contains('application/json')) {
      try {
        await tempFile.delete();
      } catch (_) {}
      throw Exception('视频接口返回了错误响应');
    }
    if (await tempFile.length() == 0) throw Exception('视频文件为空');

    if (contentType.contains('video/') && !tempFile.path.endsWith('.mp4')) {
      final newExtension = contentType.split('/').last.split(';').first;
      final targetFile = File(
        '${directoryPath}${Platform.pathSeparator}video_$safeKey.$newExtension',
      );
      await tempFile.copy(targetFile.path);
      return targetFile;
    }
    return tempFile;
  }
}
