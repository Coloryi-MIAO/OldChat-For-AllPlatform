import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';

import '../services/download_service.dart';

class DownloadProgressDialog extends StatefulWidget {
  final String url;
  final String fileName;
  final String title;

  const DownloadProgressDialog({
    super.key,
    required this.url,
    required this.fileName,
    this.title = '下载文件',
  });

  static Future<String?> show(
    BuildContext context, {
    required String url,
    required String fileName,
    String title = '下载文件',
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadProgressDialog(url: url, fileName: fileName, title: title),
    );
  }

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  final _cancelToken = CancelToken();
  bool _started = false;
  bool _downloading = false;
  DownloadProgress? _progress;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (_downloading && !_cancelToken.isCancelled) _cancelToken.cancel('下载窗口已关闭');
    super.dispose();
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final result = await DownloadService.download(
        widget.url,
        fileName: widget.fileName,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _path = result.path;
      });
    } on DioException catch (error) {
      if (!mounted || CancelToken.isCancel(error)) return;
      setState(() {
        _downloading = false;
        _error = error.message ?? '下载失败';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = error.toString();
        });
      }
    }
  }

  void _cancel() {
    if (_downloading) {
      _cancelToken.cancel('用户取消下载');
      Navigator.pop(context);
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final fraction = progress?.fraction;
    final percent = fraction == null ? null : (fraction * 100).clamp(0, 100);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.current.t('文件：${widget.fileName}'), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            if (_downloading) ...[
              LinearProgressIndicator(value: fraction),
              const SizedBox(height: 8),
              Text(
                fraction == null
                    ? '下载中… ${_size(progress?.received ?? 0)}'
                    : '${percent!.toStringAsFixed(0)}%（${_size(progress!.received)} / ${_size(progress.total)}）',
              ),
            ],
            if (_path != null) ...[
              const SizedBox(height: 10),
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(height: 6),
              Text(AppLocalizations.current.t('下载完成，文件已保存到 Windows“下载”文件夹。')),
              SelectableText(_path!, maxLines: 2),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (_downloading)
          TextButton(onPressed: _cancel, child: Text(AppLocalizations.current.t('取消'))),
        if (!_downloading && _path == null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.current.t('关闭')),
          ),
        if (!_downloading)
          FilledButton(
            onPressed: _path == null
                ? () {
                    _started = false;
                    _start();
                  }
                : () => Navigator.pop(context, _path),
            child: Text(AppLocalizations.current.t(_path == null ? '重试' : '完成')),
          ),
      ],
    );
  }
}
