import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../utils/url_helper.dart';
import '../utils/image_saver.dart';
import '../services/image_cache_service.dart';
import '../services/aria2_service.dart';

class ImageViewer extends StatefulWidget {
  final String imageUrl;
  final List<String> imageUrls;
  final int initialIndex;

  const ImageViewer({
    super.key,
    required this.imageUrl,
    this.imageUrls = const [],
    this.initialIndex = 0,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _controller;
  late final List<String> _urls;
  late int _currentIndex;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final values = <String>[];
    final source = widget.imageUrls.isNotEmpty
        ? widget.imageUrls
        : <String>[widget.imageUrl];
    for (final raw in source) {
      final url = resolveMediaUrl(raw).trim();
      if (url.isNotEmpty && !values.contains(url)) values.add(url);
    }
    final current = resolveMediaUrl(widget.imageUrl).trim();
    if (current.isNotEmpty && !values.contains(current)) {
      values.insert(widget.initialIndex.clamp(0, values.length), current);
    }
    if (values.isEmpty && current.isNotEmpty) values.add(current);
    _urls = values;
    _currentIndex = _urls.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _urls.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveImage() async {
    if (_isSaving || _urls.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final url = _urls[_currentIndex];
      try {
        final gid = await Aria2Service().addUri(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.current.t('已交给 aria2 下载（任务 $gid）'))),
          );
        }
      } catch (_) {
        final path = await ImageSaver.saveImage(url);
        if (path == null) throw Exception('保存失败');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.current.t('图片已保存到：$path'))),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('保存失败：$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= _urls.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Widget _navigationButton({required bool previous}) {
    final enabled = previous
        ? _currentIndex > 0
        : _currentIndex < _urls.length - 1;
    return IconButton(
      onPressed: enabled
          ? () => _goTo(_currentIndex + (previous ? -1 : 1))
          : null,
      icon: Icon(previous ? Icons.chevron_left : Icons.chevron_right, size: 42),
      color: Colors.white,
      disabledColor: Colors.white24,
      tooltip: AppLocalizations.current.t(previous ? '上一张' : '下一张'),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black45,
        padding: const EdgeInsets.all(6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(AppLocalizations.current.t('没有可显示的图片'), style: TextStyle(color: Colors.white)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _urls.length > 1
            ? Text(AppLocalizations.current.t('${_currentIndex + 1} / ${_urls.length}'))
            : null,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _isSaving
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download, color: Colors.white),
            onPressed: _isSaving ? null : _saveImage,
            tooltip: AppLocalizations.current.t('保存当前图片'),
          ),
        ],
      ),
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: _urls.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (_, __) => Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            builder: (_, index) => PhotoViewGalleryPageOptions(
              imageProvider: ImageCacheService.instance.provider(
                _urls[index],
                cacheWidth: 1600,
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              initialScale: PhotoViewComputedScale.contained,
            ),
          ),
          if (_urls.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _navigationButton(previous: true),
              ),
            ),
          if (_urls.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _navigationButton(previous: false),
              ),
            ),
        ],
      ),
    );
  }
}
