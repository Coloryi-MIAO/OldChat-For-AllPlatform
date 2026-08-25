import 'package:universal_io/io.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
  });

  static Future<void> show(
    BuildContext context, {
    required ReleaseInfo release,
    required String currentVersion,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        release: release,
        currentVersion: currentVersion,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  CancelToken? _cancelToken;
  bool _downloading = false;
  bool _cancelRequested = false;
  bool _installing = false;
  double? _progress;
  int _received = 0;
  int _total = -1;
  String? _downloadedPath;
  String? _error;

  @override
  void dispose() {
    _cancelToken?.cancel('update dialog closed');
    super.dispose();
  }

  void _cancelDownload() {
    if (!_downloading || _cancelRequested) return;
    _cancelRequested = true;
    _cancelToken?.cancel('user cancelled');
    if (mounted) {
      setState(() {
        _downloading = false;
        _error = '已取消下载';
      });
    }
  }

  Future<void> _download() async {
    if (_downloading || _installing) return;
    if (widget.release.downloadUrl == null) {
      await launchUrl(
        Uri.parse(widget.release.htmlUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
      _received = 0;
      _total = -1;
    });
    _cancelRequested = false;
    _cancelToken = CancelToken();
    try {
      final file = await UpdateService().downloadRelease(
        widget.release,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      if (mounted && !_cancelRequested) {
        setState(() {
          _downloadedPath = file.path;
          _downloading = false;
        });
        await _installAndRestart();
      } else if (await file.exists()) {
        await file.delete();
      }
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || _cancelRequested) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _error = '已取消下载';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = error.message ?? '下载失败';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _installAndRestart() async {
    final path = _downloadedPath;
    if (path == null || _installing) return;
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await Navigator.of(context).maybePop();
      await UpdateService().installAndExit(File(path));
    } catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = '无法启动更新程序：$error';
        });
      }
    }
  }

  Future<void> _openDownloaded() async {
    final path = _downloadedPath;
    if (path == null) return;
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', path]);
    } else {
      await launchUrl(Uri.file(path));
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final progress = _progress;
    final maxContentHeight = MediaQuery.sizeOf(context).height * 0.58;
    return AlertDialog(
      title: Text(AppLocalizations.current.t('发现新版本 ${release.tagName}')),
      content: SizedBox(
        width: 560,
        height: maxContentHeight.clamp(260.0, 520.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.current.t('当前版本：${widget.currentVersion}')),
              Text(AppLocalizations.current.t('最新版本：${release.name}')),
              if (release.publishedAt != null)
                Text(AppLocalizations.current.t('发布时间：${release.publishedAt!.toLocal()}')),
              const SizedBox(height: 14),
              Text(
                '本次更新',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    release.body.trim().isEmpty ? '暂无更新说明' : release.body.trim(),
                  ),
                ),
              ),
              if (_downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? '正在下载… ${_size(_received)}'
                      : '${(progress * 100).toStringAsFixed(0)}%（${_size(_received)} / ${_size(_total)}）',
                ),
              ],
              if (_downloadedPath != null && !_installing) ...[
                const SizedBox(height: 14),
                Text(AppLocalizations.current.t('下载完成，点击“立即更新”后将启动更新程序并关闭当前 OldChat。')),
              ],
              if (_installing) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(AppLocalizations.current.t('正在启动更新程序，即将关闭当前 OldChat…')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_downloadedPath != null && !_installing)
          TextButton(onPressed: _openDownloaded, child: Text(AppLocalizations.current.t('打开位置'))),
        TextButton(
          onPressed: _installing
              ? null
              : _downloading
              ? _cancelDownload
              : () => Navigator.pop(context),
          child: Text(_downloading
              ? (_cancelRequested ? '正在取消…' : '取消下载')
              : '稍后'),
        ),
        FilledButton(
          onPressed: _downloading || _installing
              ? null
              : _downloadedPath == null
              ? _download
              : _installAndRestart,
          child: Text(
            widget.release.downloadUrl == null
                ? '查看发布页'
                : _downloadedPath == null
                ? '下载更新'
                : '立即更新',
          ),
        ),
      ],
    );
  }
}
