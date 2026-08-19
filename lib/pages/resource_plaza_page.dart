import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../utils/file_picker_compat.dart';
import '../services/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/image_viewer.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/image_cache_service.dart';
import '../utils/url_helper.dart';
import '../widgets/cached_image.dart';
import '../widgets/download_progress_dialog.dart';

class ResourcePlazaPage extends StatefulWidget {
  const ResourcePlazaPage({super.key});

  @override
  State<ResourcePlazaPage> createState() => _ResourcePlazaPageState();
}

class _ResourcePlazaPageState extends State<ResourcePlazaPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;
  bool _uploading = false;
  int _offset = 0;
  bool _hasMore = true;
  String? _error;
  String? _selectedSectionId;
  int _itemsRequestGeneration = 0;
  final ScrollController _sectionsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCachedItems());
    unawaited(_restoreCachedSections());
    unawaited(_loadSections());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sectionsScrollController.dispose();
    super.dispose();
  }

  String _cacheKey() =>
      'resource_plaza:${_selectedSectionId ?? 'all'}:${_searchController.text.trim()}';

  Future<void> _restoreCachedItems() async {
    final cached = await ImageCacheService.instance.readJsonCache(_cacheKey());
    if (!mounted || cached is! List) return;
    final items = _itemsFrom(cached);
    if (items.isEmpty) return;
    setState(() {
      _items = items;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _restoreCachedSections() async {
    final cached = await ImageCacheService.instance.readJsonCache(
      'resource_sections',
    );
    if (!mounted || cached is! List) return;
    final sections = cached
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) => _value(item, const [
            'id',
            'section_id',
            'key',
            'slug',
          ]).isNotEmpty,
        )
        .toList();
    if (sections.isEmpty) return;
    setState(() {
      _sections = sections;
    });
  }

  Future<void> _cacheItems(List<Map<String, dynamic>> items) async {
    await ImageCacheService.instance.writeJsonCache(_cacheKey(), items);
  }

  List<Map<String, dynamic>> _itemsFrom(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _value(
    Map<String, dynamic> item,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty)
        return value.toString();
    }
    return fallback;
  }

  List<String> _urls(Map<String, dynamic> item) {
    final result = <String>[];

    void add(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final nested in value) add(nested);
        return;
      }
      if (value is Map) {
        add(
          value['url'] ??
              value['download_url'] ??
              value['file_url'] ??
              value['path'],
        );
        return;
      }
      final text = value.toString().trim();
      if (text.isEmpty) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is List || decoded is Map) {
          add(decoded);
          return;
        }
      } catch (_) {}
      final url = resolveMediaUrl(text);
      if (url.isNotEmpty && !result.contains(url)) result.add(url);
    }

    for (final key in const [
      'image_urls',
      'image_url',
      'images',
      'media_urls',
      'media_url',
      'attachments',
      'thumbnail_url',
      'download_url',
      'download_path',
      'file_url',
      'media_url',
      'url',
      'src',
      'file',
      'resource',
    ]) {
      add(item[key]);
    }
    return result;
  }

  String _url(Map<String, dynamic> item) {
    final urls = _urls(item);
    return urls.isEmpty ? '' : urls.first;
  }

  Future<void> _loadSections() async {
    try {
      final data = await ApiService().getResourceSections();
      debugPrint('[资源广场] sections-json=$data');
      final nestedData = data['data'];
      final raw =
          data['sections'] ??
          data['categories'] ??
          data['tabs'] ??
          data['items'] ??
          data['list'] ??
          (nestedData is Map
              ? (nestedData['sections'] ??
                    nestedData['categories'] ??
                    nestedData['tabs'] ??
                    nestedData['items'] ??
                    nestedData['list'])
              : nestedData) ??
          data;
      final sections = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where(
                  (item) => _value(item, const [
                    'id',
                    'section_id',
                    'key',
                    'slug',
                  ]).isNotEmpty,
                )
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final selectedStillExists =
          _selectedSectionId != null &&
          sections.any(
            (item) =>
                _value(item, const ['id', 'section_id', 'key', 'slug']) ==
                _selectedSectionId,
          );
      final selected = selectedStillExists ? _selectedSectionId : null;
      final changed = selected != _selectedSectionId;
      setState(() {
        _sections = sections;
        _selectedSectionId = selected;
      });
      await ImageCacheService.instance.writeJsonCache(
        'resource_sections',
        sections,
      );
      if (!mounted) return;
      await _restoreCachedItems();
      if (changed || _items.isEmpty) await _load();
    } catch (error) {
      debugPrint('[资源广场] sections error: $error');
      if (mounted && _items.isEmpty) {
        await _load();
      }
    }
  }

  Future<void> _load({bool reset = true}) async {
    final requestGeneration = ++_itemsRequestGeneration;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
      });
    }
    try {
      final api = ApiService();
      final query = _searchController.text.trim();
      final data = query.isEmpty
          ? await api.getResourceItems(
              limit: 50,
              offset: _offset,
              sectionId: _selectedSectionId,
            )
          : await api.searchResources(query);
      debugPrint('[资源广场] items-json=$data');
      final raw =
          data['items'] ??
          (data['response'] is Map
              ? data['response']['items']
              : data['response']) ??
          (data['data'] is Map ? data['data']['items'] : data['data']) ??
          data['resources'] ??
          data['list'] ??
          data;
      final next = _itemsFrom(raw);
      if (!mounted || requestGeneration != _itemsRequestGeneration) return;
      final merged = reset ? next : <Map<String, dynamic>>[..._items, ...next];
      final byId = <String, Map<String, dynamic>>{};
      for (final item in merged) {
        final id = _value(item, const ['id', 'resource_id', 'uid', 'url']);
        if (id.isNotEmpty) byId[id] = item;
      }
      final unique = byId.values.toList();
      setState(() {
        _items = unique;
        _offset = reset ? next.length : _offset + next.length;
        _hasMore =
            data['has_more'] == true || (query.isEmpty && next.length >= 50);
        _loading = false;
        _error = null;
      });
      await _cacheItems(unique);
    } catch (error) {
      if (!mounted || requestGeneration != _itemsRequestGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.pickFile();
    if (result == null) return;
    final bytes = await filePickerBytes(result);
    if (bytes == null || bytes.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: result.name),
      });
      await ApiService().uploadResource(form);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('资源上传成功'))),
        );
        await _load();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('上传失败：$error'))),
        );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    final url = _url(item);
    if (url.isEmpty || !mounted) return;
    final fileName = DownloadService.fileNameFromMessage(
      _value(item, const ['name', 'filename', 'title', 'resource_name']),
      url,
    );
    await DownloadProgressDialog.show(
      context,
      url: url,
      fileName: fileName,
      title: AppLocalizations.current.t('下载资源'),
    );
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final url = _url(item);
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _buildResourceLeading(Map<String, dynamic> item, Color primary) {
    final urls = _urls(item);
    final url = urls.isEmpty ? '' : urls.first;
    final name = _value(item, const [
      'name',
      'filename',
      'file_name',
      'original_name',
      'title',
    ], '');
    final type = _value(item, const [
      'mime_type',
      'content_type',
      'type',
    ]).toLowerCase();
    final isImage =
        type.startsWith('image/') ||
        RegExp(
          r'\.(png|jpe?g|gif|webp|bmp)(?:[?#].*)?$',
          caseSensitive: false,
        ).hasMatch(name) ||
        RegExp(
          r'\.(png|jpe?g|gif|webp|bmp)(?:[?#].*)?$',
          caseSensitive: false,
        ).hasMatch(url);
    if (isImage && url.isNotEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewer(imageUrl: url, imageUrls: urls),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedImage(
            url,
            width: 48,
            height: 48,
            cacheWidth: 96,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CircleAvatar(
              backgroundColor: primary.withOpacity(.12),
              child: Icon(Icons.image, color: primary),
            ),
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: primary.withOpacity(.12),
      child: Icon(Icons.folder, color: primary),
    );
  }

  Widget _buildSectionTabs() {
    if (_sections.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 50,
      child: Scrollbar(
        controller: _sectionsScrollController,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.depth == 0,
        child: ListView.separated(
          controller: _sectionsScrollController,
          padding: const EdgeInsets.only(bottom: 8, right: 12),
          scrollDirection: Axis.horizontal,
          itemCount: _sections.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            if (index == 0) {
              return ChoiceChip(
                selected: _selectedSectionId == null,
                label: Text(AppLocalizations.current.t('全部')),
                onSelected: (_) {
                  if (_selectedSectionId == null) return;
                  setState(() => _selectedSectionId = null);
                  unawaited(_load());
                },
              );
            }
            final section = _sections[index - 1];
            final sectionId = _value(section, const [
              'id',
              'section_id',
              'key',
              'slug',
            ]);
            final selected = sectionId == _selectedSectionId;
            return ChoiceChip(
              selected: selected,
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  _value(section, const [
                    'name',
                    'title',
                    'section_name',
                    'label',
                  ], '未命名分区'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              onSelected: (_) {
                if (selected || sectionId.isEmpty) return;
                setState(() => _selectedSectionId = sectionId);
                unawaited(_load());
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemsBody() {
    if (_loading && _items.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.current.t('加载失败：$_error')),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _load(),
              child: Text(AppLocalizations.current.t('重试')),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(AppLocalizations.current.t('该分区暂无资源')));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Center(
            child: TextButton(
              onPressed: _loading ? null : () => _load(reset: false),
              child: Text(AppLocalizations.current.t('加载更多')),
            ),
          );
        }
        final item = _items[index];
        final title = _value(item, const [
          'name',
          'filename',
          'title',
          'resource_name',
        ], '未命名资源');
        final description = _value(item, const [
          'description',
          'body',
          'section_name',
        ]);
        return Card(
          child: ListTile(
            leading: _buildResourceLeading(
              item,
              Theme.of(context).primaryColor,
            ),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: description.isEmpty
                ? null
                : Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'open') _open(item);
                if (value == 'download') _download(item);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'open',
                  child: Text(AppLocalizations.current.t('打开')),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Text(AppLocalizations.current.t('下载')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('资源广场')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.upload_file),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: AppLocalizations.current.t('搜索资源'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _load();
                  },
                  icon: const Icon(Icons.clear),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildSectionTabs(),
          ),
          Expanded(child: _buildItemsBody()),
        ],
      ),
    );
  }
}
