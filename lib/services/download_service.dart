import 'dart:convert';
import 'package:universal_io/io.dart';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../utils/url_helper.dart';
import '../utils/file_picker_compat.dart';
import 'aria2_service.dart';

class DownloadResult {
  final bool usedAria2;
  final String? gid;
  final String? path;

  const DownloadResult({this.usedAria2 = false, this.gid, this.path});
}

class DownloadProgress {
  final int received;
  final int total;
  final double? fraction;

  const DownloadProgress({
    required this.received,
    required this.total,
    required this.fraction,
  });
}

class DownloadService {
  static String fileNameFromMessage(String? body, String? url) {
    final raw = (body ?? '').trim();
    final candidates = <String>[];
    if (raw.isNotEmpty) {
      final labeled = _extractLabeledFileName(raw);
      if (labeled != null) candidates.add(labeled);
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final key in const [
            'file_name',
            'filename',
            'name',
            'original_name',
            'resource_name',
            'title',
          ]) {
            final value = decoded[key]?.toString().trim();
            if (value != null && value.isNotEmpty) candidates.add(value);
          }
        }
      } catch (_) {}
      if (!_looksLikeEnvelope(raw)) candidates.add(raw);
    }
    for (final candidate in candidates) {
      final safe = _safeFileName(candidate);
      if (safe != null && !_looksLikeEnvelope(candidate)) return safe;
    }
    return _nameFromUrl(url ?? '');
  }

  static Future<DownloadResult> download(
    String url, {
    String? fileName,
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
    bool preferAria2 = false,
  }) async {
    final normalizedUrl = resolveMediaUrl(url).trim();
    if (normalizedUrl.isEmpty) throw Exception('下载地址为空');
    final normalizedName = fileName == null || fileName.trim().isEmpty
        ? null
        : fileNameFromMessage(fileName, normalizedUrl);

    if (preferAria2 && await Aria2Service().isConfigured) {
      try {
        final gid = await Aria2Service().addUri(
          normalizedUrl,
          fileName: normalizedName ?? _nameFromUrl(normalizedUrl),
        );
        return DownloadResult(usedAria2: true, gid: gid);
      } catch (_) {}
    }

    final path = await _streamDownload(
      normalizedUrl,
      fileName: normalizedName,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return DownloadResult(path: path);
  }

  static Future<String?> saveWithDialog(String path, {String? fileName}) async {
    final source = File(path);
    if (!await source.exists()) throw Exception('下载文件不存在');
    final selectedPath = filePickerPath(
      await FilePicker.saveFile(
        dialogTitle: '保存文件',
        fileName: fileNameFromMessage(fileName, path),
        bytes: await source.readAsBytes(),
        lockParentWindow: true,
      ),
    );
    if (selectedPath == null || selectedPath.isEmpty) return null;
    if (selectedPath != source.path) await source.copy(selectedPath);
    return selectedPath;
  }

  static Future<String> _streamDownload(
    String url, {
    String? fileName,
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final downloads = await _downloadsDirectory();
    await downloads.create(recursive: true);
    final token = AuthService().token;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 30),
        headers: {
          'Accept': '*/*',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      ),
    );
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final headerName = _fileNameFromContentDisposition(
      response.headers.value('content-disposition'),
    );
    final requestedName = fileName == null || _looksLikeEnvelope(fileName)
        ? null
        : _safeFileName(fileName);
    final name = requestedName ?? headerName ?? _nameFromUrl(url);
    final target = await _uniqueFile(downloads, name);
    final total =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        -1;
    var received = 0;
    final sink = target.openWrite();
    try {
      onProgress?.call(
        DownloadProgress(
          received: 0,
          total: total,
          fraction: total > 0 ? 0 : null,
        ),
      );
      await for (final chunk in response.data!.stream) {
        if (cancelToken?.isCancelled == true) {
          throw DioException.requestCancelled(
            requestOptions: response.requestOptions,
            reason: '下载已取消',
          );
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          DownloadProgress(
            received: received,
            total: total,
            fraction: total > 0 ? (received / total).clamp(0, 1) : null,
          ),
        );
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    return target.path;
  }

  static Future<Directory> _downloadsDirectory() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home${Platform.pathSeparator}Downloads');
      }
    }
    return Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}Downloads',
    );
  }

  static Future<File> _uniqueFile(Directory directory, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    var file = File('${directory.path}${Platform.pathSeparator}$name');
    var index = 1;
    while (await file.exists()) {
      file = File(
        '${directory.path}${Platform.pathSeparator}$stem ($index)$extension',
      );
      index++;
    }
    return file;
  }

  static String? _extractLabeledFileName(String value) {
    final match = RegExp(
      r'(?:文件|文件名)\s*[_：: ]\s*(.+?)(?:\s*[_ ]大小\s*[_：: ]|\s+大小\s*[:：]|$)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) {
      final result = match.group(1)?.trim();
      if (result != null && result.isNotEmpty) return result;
    }
    return null;
  }

  static bool _looksLikeEnvelope(String value) {
    final trimmed = value.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']')) ||
        RegExp(r'^文件(?:名)?\s*[_：: ]', caseSensitive: false).hasMatch(trimmed) ||
        (trimmed.contains('大小') && trimmed.length > 80);
  }

  static String? _fileNameFromContentDisposition(String? value) {
    if (value == null || value.isEmpty) return null;
    final encoded = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    if (encoded != null) return _safeFileName(Uri.decodeComponent(encoded));
    final quoted = RegExp(
      r'filename\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    if (quoted != null) return _safeFileName(quoted);
    final plain = RegExp(
      r'filename\s*=\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    return _safeFileName(plain);
  }

  static String? _safeFileName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) return null;
    var normalized = name.split(RegExp(r'[\\/]')).last.trim();
    normalized = normalized.replaceFirst(RegExp(r'^文件[_：: ]*'), '');
    normalized = normalized
        .replaceFirst(RegExp(r'[_ ]大小[_：: ].*$', caseSensitive: false), '')
        .trim();
    final safe = normalized
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    if (safe.isEmpty || safe == '.' || safe == '..') return null;
    return safe;
  }

  static String _nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? '';
    final candidate = path.split('/').last;
    final decoded = Uri.decodeComponent(candidate);
    final safe = _safeFileName(decoded);
    if (safe != null && !_looksLikeEnvelope(safe) && safe.contains('.'))
      return safe;
    return 'oldchat_download_${DateTime.now().millisecondsSinceEpoch}.bin';
  }
}
