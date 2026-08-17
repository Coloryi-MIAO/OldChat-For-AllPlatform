import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum UpdateChannel { all, beta, stable }

class ReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final String? downloadUrl;
  final int? downloadSize;
  final bool prerelease;
  final DateTime? publishedAt;

  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.downloadUrl,
    required this.downloadSize,
    required this.prerelease,
    required this.publishedAt,
  });
}

class UpdateService {
  static const repository = 'Coloryi-MIAO/OldChat-For-AllPlatform';
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com',
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    return build.isEmpty ? info.version : '${info.version}.${build.replaceFirst(RegExp(r'^\\+'), '')}';
  }

  Future<ReleaseInfo?> latest(UpdateChannel channel) async {
    final response = await _dio.get<List<dynamic>>(
      '/repos/$repository/releases',
      queryParameters: {'per_page': 30},
    );
    final releases = (response.data ?? const <dynamic>[])
        .whereType<Map>()
        .map((raw) => _parse(Map<String, dynamic>.from(raw)))
        .where((release) => _matches(release, channel))
        .toList();
    releases.sort(
      (a, b) => (b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return releases.isEmpty ? null : releases.first;
  }

  Future<ReleaseInfo?> available(UpdateChannel channel) async {
    final current = await currentVersion();
    final release = await latest(channel);
    if (release == null || _compare(release.tagName, current) <= 0) return null;
    return release;
  }

  Future<ReleaseInfo?> availableForCurrentWindows(UpdateChannel channel) async {
    if (!Platform.isWindows) return null;
    return available(channel);
  }

  Future<File> downloadRelease(
    ReleaseInfo release, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final url = release.downloadUrl;
    if (url == null || url.isEmpty) throw Exception('该版本没有 Windows 下载文件');
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}OldChatUpdates',
    );
    await directory.create(recursive: true);
    final tagName = _safeFileName(release.tagName).replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final sourceName = url.split('/').last.split('?').first;
    final sourceExtension = sourceName.contains('.')
        ? sourceName.substring(sourceName.lastIndexOf('.'))
        : '.exe';
    final extension = sourceExtension.toLowerCase() == '.exe' ? '.exe' : sourceExtension;
    final name = 'OldChat-$tagName$extension';
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    if (await file.exists()) await file.delete();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 30),
        headers: {'Accept': 'application/octet-stream'},
      ),
    );
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
    final total = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        release.downloadSize ??
        -1;
    var received = 0;
    final sink = file.openWrite();
    try {
      onProgress?.call(0, total);
      await for (final chunk in response.data!.stream) {
        if (cancelToken?.isCancelled == true) {
          throw DioException.requestCancelled(
            requestOptions: response.requestOptions,
            reason: '更新下载已取消',
          );
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return file;
  }

  Future<void> installAndExit(File installer) async {
    if (!Platform.isWindows) throw Exception('OldChat 更新器仅支持 Windows');
    if (!await installer.exists()) throw Exception('更新安装包不存在');
    final updater = File(
      '${installer.parent.path}${Platform.pathSeparator}oldchat-updater.ps1',
    );
    final escapedInstaller = installer.path.replaceAll("'", "''");
    final escapedPid = pid.toString();
    final escapedApp = Platform.resolvedExecutable.replaceAll("'", "''");
    final escapedWorkdir = File(Platform.resolvedExecutable).parent.path.replaceAll("'", "''");
    await updater.writeAsString('''
\$ErrorActionPreference = 'Stop'
\$installer = '$escapedInstaller'
\$oldProcessId = '$escapedPid'
\$appPath = '$escapedApp'
\$workdir = '$escapedWorkdir'
while (Get-Process -Id \$oldProcessId -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 250 }
Start-Process -FilePath \$installer -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait
if (Test-Path -LiteralPath \$appPath) { Start-Process -FilePath \$appPath -WorkingDirectory \$workdir }
Remove-Item -LiteralPath \$installer -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath \$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
''');
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', updater.path],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  String _safeFileName(String value) {
    var name = Uri.decodeComponent(value.trim());
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty || name == '.' || name == '..') return 'OldChat-update.exe';
    if (!name.toLowerCase().endsWith('.exe')) name = '$name.exe';
    return name;
  }

  String _releaseFileName(ReleaseInfo release) {
    final raw = release.downloadUrl?.split('/').last.split('?').first ?? '';
    final name = _safeFileName(raw);
    return name.toLowerCase().endsWith('.exe') ? name : 'OldChat-update.exe';
  }

  ReleaseInfo _parse(Map<String, dynamic> raw) {
    final assets = raw['assets'] is List ? raw['assets'] as List : const [];
    final windowsAsset = assets
        .whereType<Map>()
        .map((asset) => Map<String, dynamic>.from(asset))
        .firstWhere(
          (asset) => _isWindowsAsset(asset['name']?.toString() ?? ''),
          orElse: () => <String, dynamic>{},
        );
    return ReleaseInfo(
      tagName: (raw['tag_name'] ?? raw['name'] ?? '').toString(),
      name: (raw['name'] ?? raw['tag_name'] ?? '').toString(),
      body: (raw['body'] ?? '').toString(),
      htmlUrl: (raw['html_url'] ?? '').toString(),
      downloadUrl: windowsAsset['browser_download_url']?.toString(),
      downloadSize: (windowsAsset['size'] as num?)?.toInt(),
      prerelease: raw['prerelease'] == true,
      publishedAt: DateTime.tryParse((raw['published_at'] ?? '').toString()),
    );
  }

  bool _matches(ReleaseInfo release, UpdateChannel channel) {
    if (release.tagName.isEmpty) return false;
    switch (channel) {
      case UpdateChannel.all:
        return true;
      case UpdateChannel.beta:
        return release.prerelease ||
            release.tagName.toLowerCase().contains('beta') ||
            release.tagName.toLowerCase().contains('alpha');
      case UpdateChannel.stable:
        return !release.prerelease &&
            !release.tagName.toLowerCase().contains('beta') &&
            !release.tagName.toLowerCase().contains('alpha');
    }
  }

  bool _isWindowsAsset(String name) {
    final value = name.toLowerCase();
    return value.endsWith('.exe') ||
        value.contains('windows') ||
        value.contains('win64') ||
        value.contains('win-x64');
  }

  int _compare(String left, String right) {
    final a = _parts(left);
    final b = _parts(right);
    for (var i = 0; i < a.length; i++) {
      final result = a[i].compareTo(b[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  List<int> _parts(String value) {
    final match = RegExp(
      r'v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-.]?beta[-.]?(\d+))?(?:(?:[-+]?build[._-]?(\d+))|(?:\+(\d+)))?',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return const [0, 0, 0, 0];
    return [
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      int.tryParse(match.group(4) ?? '') ?? 0,
      int.tryParse(match.group(5) ?? match.group(6) ?? '') ?? 0,
    ];
  }
}
