import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/image_cache_service.dart';
import '../utils/url_helper.dart';

class CachedImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int cacheWidth;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const CachedImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth = 768,
    this.errorBuilder,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  File? _file;
  List<String> _candidates = const [];
  int _candidateIndex = 0;
  bool _loading = true;
  bool _failed = false;
  bool _failureScheduled = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _failureScheduled = false;
    _loading = true;
    _failed = false;
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final candidates = resolveMediaCandidates(widget.url);
    if (mounted) {
      setState(() {
        _candidates = candidates;
        _candidateIndex = 0;
        _loading = true;
        _failed = candidates.isEmpty;
      });
    }
    final existing = await ImageCacheService.instance.existingFile(widget.url);
    if (!mounted || generation != _loadGeneration) return;
    if (existing != null) {
      setState(() {
        _file = existing;
        _loading = false;
        _failed = false;
      });
      return;
    }
    final cached = await ImageCacheService.instance.cachedFile(widget.url);
    if (!mounted || generation != _loadGeneration) return;
    if (cached != null) {
      setState(() {
        _file = cached;
        _loading = false;
        _failed = false;
      });
      return;
    }
    if (mounted && generation == _loadGeneration) {
      setState(() {
        _loading = false;
        _failed = false;
      });
    }
  }

  void _advanceAfterNetworkFailure(Object error, StackTrace stack) {
    if (!mounted || _failureScheduled) return;
    _failureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _failureScheduled = false;
      if (!mounted) return;
      if (_candidateIndex + 1 < _candidates.length) {
        setState(() {
          _candidateIndex++;
          _loading = true;
        });
        return;
      }
      if (_file == null) setState(() => _failed = true);
    });
  }

  Widget _fallback(BuildContext context, Object error, StackTrace? stack) {
    return widget.errorBuilder?.call(context, error, stack) ??
        SizedBox(width: widget.width, height: widget.height);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _candidates.isEmpty) {
      return _fallback(context, Exception('图片链接无效'), StackTrace.current);
    }
    if (_file != null) {
      return Image(
        image: ResizeImage(FileImage(_file!), width: widget.cacheWidth),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, error, stack) => _fallback(context, error, stack),
      );
    }
    final provider = ImageCacheService.instance.provider(
      _candidates[_candidateIndex],
      cacheWidth: widget.cacheWidth,
    );
    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, error, stack) {
        _advanceAfterNetworkFailure(error, stack ?? StackTrace.current);
        return _loading
            ? SizedBox(
                width: widget.width,
                height: widget.height,
                child: const ColoredBox(color: Color(0x14000000)),
              )
            : _fallback(context, error, stack);
      },
    );
  }
}
