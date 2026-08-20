import 'dart:async';
import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart';
import 'download_progress_dialog.dart';

import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/image_cache_service.dart';
import '../services/video_cache_service.dart';
import '../utils/url_helper.dart';
import '../utils/video_support.dart';

class VideoPreview extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;

  const VideoPreview({super.key, required this.url, this.thumbnailUrl});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  String? _error;
  bool _visible = false;
  bool _loading = false;
  bool _thumbnailReady = false;

  String get _resolvedUrl => resolveMediaUrl(widget.url);
  String get _resolvedThumbnail => resolveMediaUrl(widget.thumbnailUrl);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        oldWidget.thumbnailUrl == widget.thumbnailUrl)
      return;
    final oldChewie = _chewieController;
    final oldController = _controller;
    _chewieController = null;
    _controller = null;
    _error = null;
    _loading = false;
    _visible = false;
    oldChewie?.dispose();
    oldController?.dispose();
    if (mounted) setState(() {});
  }

  void _startPlayback() {
    if (!_visible) {
      _checkVisibility();
    }
    if (_visible) {
      _tryInitialize();
    }
  }

  void _checkVisibility() {
    if (!mounted || _visible || _loading) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
      return;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final screen = MediaQuery.sizeOf(context);
    if (rect.bottom > 0 && rect.top < screen.height) {
      _visible = true;
    }
  }

  Future<void> _tryInitialize() async {
    if (_loading) return;
    if (!supportsEmbeddedVideo) {
      if (mounted) setState(() => _error = AppLocalizations.current.t('当前系统没有内置视频播放器，请使用浏览器打开'));
      return;
    }
    _loading = true;
    final watch = Stopwatch()..start();
    final uri = Uri.tryParse(_resolvedUrl);
    if (uri == null || !uri.hasScheme) {
      if (mounted) setState(() => _error = '视频链接无效');
      _loading = false;
      return;
    }
    try {
      final cache = VideoCacheService();
      final localFile = await cache.getCachedFile(_resolvedUrl);
      final token = AuthService().token;
      final controller = localFile != null
          ? VideoPlayerController.file(localFile)
          : VideoPlayerController.networkUrl(
              uri,
              httpHeaders: token == null || token.isEmpty
                  ? const <String, String>{}
                  : <String, String>{'Authorization': 'Bearer $token'},
            );
      if (localFile == null) {
        unawaited(cache.cacheInBackground(_resolvedUrl));
      }
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Colors.white38,
          bufferedColor: Colors.white70,
        ),
      );
      setState(() {
        _controller = controller;
        _chewieController = chewie;
      });
      watch.stop();
      print('[播放器慢] 视频初始化 ${watch.elapsedMilliseconds}ms ${widget.url}');
    } catch (error) {
      watch.stop();
      print('[播放器慢] 视频初始化失败 ${watch.elapsedMilliseconds}ms $error');
      if (mounted) setState(() => _error = '视频加载失败');
    } finally {
      _loading = false;
    }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(_resolvedUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSystemPlayer() async {
    final uri = Uri.tryParse(_resolvedUrl);
    if (uri == null) return;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd.exe', ['/c', 'start', '', uri.toString()]);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await _openBrowser();
    }
  }

  Widget _thumbnail() {
    if (_resolvedThumbnail.isEmpty) {
      return Container(color: Colors.black12);
    }
    final watch = Stopwatch()..start();
    return Image(
      image: ImageCacheService.instance.provider(
        _resolvedThumbnail,
        cacheWidth: 640,
      ),
      gaplessPlayback: true,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        watch.stop();
        debugPrint(
          '[图片慢] 视频缩略图 ${watch.elapsedMilliseconds}ms $_resolvedThumbnail',
        );
        return Container(color: Colors.black12);
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          _thumbnailReady = true;
          watch.stop();
          debugPrint(
            '[图片慢] 视频缩略图 ${watch.elapsedMilliseconds}ms $_resolvedThumbnail',
          );
          return child;
        }
        return child;
      },
    );
  }

  Future<void> _saveVideo() async {
    if (_resolvedUrl.isEmpty || !mounted) return;
    await DownloadProgressDialog.show(
      context,
      url: _resolvedUrl,
      fileName: 'oldchat_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      title: AppLocalizations.current.t('下载视频'),
    );
  }

  Widget _actions() {
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _openBrowser,
          icon: const Icon(Icons.open_in_browser, size: 16),
          label: Text(AppLocalizations.current.t('浏览器打开')),
        ),
        OutlinedButton.icon(
          onPressed: _openSystemPlayer,
          icon: const Icon(Icons.ondemand_video, size: 16),
          label: Text(AppLocalizations.current.t('系统播放器打开')),
        ),
        OutlinedButton.icon(
          onPressed: _saveVideo,
          icon: const Icon(Icons.download, size: 16),
          label: Text(AppLocalizations.current.t('下载视频')),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _checkVisibility();
    final player = _chewieController == null
        ? Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              _thumbnail(),
              if (_loading)
                Center(child: CircularProgressIndicator())
              else if (_error != null)
                Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else
                Center(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: AppLocalizations.current.t('播放视频'),
                      onPressed: _startPlayback,
                      icon: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                ),
            ],
          )
        : AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Chewie(controller: _chewieController!),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: double.infinity, height: 190, child: player),
        const SizedBox(height: 8),
        _actions(),
      ],
    );
  }
}
