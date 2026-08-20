import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';

import '../services/download_service.dart';

class DownloadDialog extends StatefulWidget {
  final String url;
  final String fileName;

  const DownloadDialog({
    super.key,
    required this.url,
    required this.fileName,
  });

  static Future<String?> show(
    BuildContext context, {
    required String url,
    required String fileName,
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadDialog(url: url, fileName: fileName),
    );
  }

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  final _cancelToken = CancelToken();
  int _received = 0;
  int _total = 0;
  bool _downloading = true;
  bool _cancelled = false;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_download());
  }

  @override
  void dispose() {
    if (_downloading && !_cancelToken.isCancelled) {
      _cancelToken.cancel('download dialog closed');
    }
    super.dispose();
  }

  Future<void> _download() async {
    try {
      final result = await DownloadService.download(
        widget.url,
        fileName: widget.fileName,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _received = progress.received;
            _total = progress.total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _path = result.path;
        _downloading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _cancelled = CancelToken.isCancel(error);
        _error = _cancelled ? '已取消下载' : (error.message ?? '下载失败');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _cancelled = false;
        _error = error.toString();
      });
    }
  }

  void _cancel() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel('user cancelled');
    Navigator.of(context).pop();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    final title = _path == null ? '文件：${widget.fileName}' : '下载完成';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_downloading) ...[
              Text(
                _total > 0
                    ? '大小：${_formatBytes(_total)} 下载中…'
                    : '正在获取文件大小，下载中…',
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? '已下载 ${_formatBytes(_received)}'
                    : '${(progress * 100).toStringAsFixed(0)}%（${_formatBytes(_received)} / ${_formatBytes(_total)}）',
              ),
            ],
            if (_path != null) ...[
              Text(AppLocalizations.current.t('文件已保存到 Windows 下载文件夹。')),
              const SizedBox(height: 8),
              SelectableText(_path!, maxLines: 2),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        if (_downloading)
          TextButton(onPressed: _cancel, child: Text(AppLocalizations.current.t('取消'))),
        if (!_downloading)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_path),
            child: Text(AppLocalizations.current.t(_path == null && !_cancelled ? '重试' : '关闭')),
          ),
      ],
    );
  }
}
