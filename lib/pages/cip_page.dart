import '../utils/file_picker_compat.dart';
import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/plugin_service.dart';
import '../services/api_service.dart';
import 'cip_run_page.dart';

class CipPage extends StatefulWidget {
  const CipPage({super.key});

  @override
  State<CipPage> createState() => _CipPageState();
}

class _CipPageState extends State<CipPage> {
  final _service = PluginService();
  bool _busy = false;
  bool _storeLoading = false;
  List<Map<String, dynamic>> _storeItems = const [];
  final Map<String, TextEditingController> _inputControllers = {};
  final Map<String, bool> _checkboxValues = {};

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _service.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    for (final controller in _inputControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Widget _buildUiNode(
    BuildContext context,
    Map<String, dynamic> node, [
    String? inheritedPluginId,
  ]) {
    final type = node['type']?.toString() ?? 'text';
    final pluginId = node['plugin_id']?.toString() ?? inheritedPluginId;
    final rawChildren = node['children'];
    final childMaps = rawChildren is List
        ? rawChildren.whereType<Map>()
        : rawChildren is Map
        ? rawChildren.values.whereType<Map>()
        : const <Map>[];
    final children = childMaps
        .map(
          (item) =>
              _buildUiNode(context, Map<String, dynamic>.from(item), pluginId),
        )
        .toList(growable: false);
    final nodeId = node['id']?.toString() ?? '';
    final visible = node['visible']?.toString().toLowerCase() != 'false';
    if (!visible) return const SizedBox.shrink();
    final height = double.tryParse(node['height']?.toString() ?? '');
    final margin = double.tryParse(node['margin']?.toString() ?? '') ?? 4;
    switch (type) {
      case 'page':
      case 'column':
      case 'list':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      case 'row':
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        );
      case 'button':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: margin),
          child: FilledButton(
            onPressed: _busy
                ? null
                : () => _runUiAction({
                    ...node,
                    if (pluginId != null) 'plugin_id': pluginId,
                  }),
            child: Text(
              context.tr.t(
                node['label']?.toString() ?? node['text']?.toString() ?? '操作',
              ),
            ),
          ),
        );
      case 'input':
        final controller = _inputControllers.putIfAbsent(
          nodeId,
          TextEditingController.new,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            maxLines: node['single_line']?.toString().toLowerCase() == 'false' ? null : 1,
            decoration: InputDecoration(
              labelText: context.tr.t(node['label']?.toString() ?? ''),
              hintText: context.tr.t(node['placeholder']?.toString() ?? ''),
            ),
          ),
        );
      case 'checkbox':
        final checked = _checkboxValues.putIfAbsent(
          nodeId,
          () => node['checked'] == true,
        );
        return CheckboxListTile(
          value: checked,
          onChanged: (value) =>
              setState(() => _checkboxValues[nodeId] = value ?? false),
          title: Text(
            context.tr.t(
              node['label']?.toString() ?? node['text']?.toString() ?? '选项',
            ),
          ),
        );
      case 'image':
        final url = node['src']?.toString() ?? node['url']?.toString() ?? '';
        return url.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: EdgeInsets.symmetric(vertical: margin),
                child: Image.network(url, height: height ?? 160, fit: BoxFit.contain),
              );
      case 'spacer':
        return SizedBox(height: height ?? 12);
      case 'text':
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            context.tr.t(
              node['text']?.toString() ?? node['value']?.toString() ?? '',
            ),
          ),
        );
    }
  }

  Future<void> _runUiAction(Map<String, dynamic> node) async {
    final action = node['action']?.toString();
    final pluginId = node['plugin_id']?.toString();
    final nodeId = node['id']?.toString() ?? '';
    if (action == 'clear') {
      if (pluginId != null && pluginId.isNotEmpty) {
        _service.clearUiResult(pluginId);
      }
      return;
    }
    final callbackRef = int.tryParse(node['callback_ref']?.toString() ?? '');
    if (callbackRef != null && pluginId != null && pluginId.isNotEmpty) {
      setState(() => _busy = true);
      try {
        await _service.executeCipCallback(pluginId, callbackRef);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.tr.t('CIP 执行失败')}：$error')),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    if (action != 'submit' && action != 'run') return;
    if (pluginId == null || pluginId.isEmpty) return;
    final plugin = _service.plugins.firstWhere(
      (item) => item['id']?.toString() == pluginId,
      orElse: () => <String, dynamic>{},
    );
    final script = plugin['cip_main']?.toString();
    if (script == null || script.isEmpty || plugin['enabled'] != true) return;
    setState(() => _busy = true);
    try {
      await _service.executeCip(
        pluginId,
        script,
        event: {
          'type': 'ui.action',
          'action': node['action'],
          'node_id': node['id'],
          'value': nodeId.isEmpty ? null : _inputControllers[nodeId]?.text,
          'values': {
            for (final entry in _inputControllers.entries) entry.key: entry.value.text,
            for (final entry in _checkboxValues.entries) entry.key: entry.value,
          },
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr.t('CIP 执行失败')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cip'],
      withData: false,
    );
    final selectedFiles = filePickerFiles(result);
    if (selectedFiles.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await filePickerBytes(selectedFiles.first);
      if (bytes == null || bytes.isEmpty) throw Exception('无法读取 CIP 文件');
      await _service.importCipBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.t('CIP 已导入，请在 CIP 中心启用后运行'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr.t('CIP 导入失败')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Map<String, dynamic> plugin) async {
    final id = plugin['id']?.toString() ?? '';
    final script = plugin['cip_main']?.toString();
    if (id.isEmpty || script == null || script.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _service.executeCip(id, script);
      final uiResult = _service.uiResult(id);
      if (!mounted) return;
      if (uiResult == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.t('CIP 没有返回界面'))),
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CipRunPage(pluginId: id, uiResult: uiResult),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr.t('CIP 执行失败')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadStore() async {
    if (_storeLoading) return;
    setState(() => _storeLoading = true);
    try {
      _storeItems = await ApiService().getCipStore();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr.t('CIP 商店加载失败')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _storeLoading = false);
    }
  }

  Future<void> _installStoreItem(Map<String, dynamic> item) async {
    setState(() => _busy = true);
    try {
      final bytes = await ApiService().downloadCipStoreItem(item);
      await _service.importCipBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.t('CIP 已下载并导入'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr.t('CIP 下载失败')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _localTab(BuildContext context, List<Map<String, dynamic>> cips) {
    if (cips.isEmpty) {
      return Center(child: Text(context.tr.t('暂无本地 CIP，点击右上角导入')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cips.length,
      itemBuilder: (context, index) {
        final plugin = cips[index];
        final enabled = plugin['enabled'] == true;
        final uiResult = _service.uiResult(plugin['id'].toString());
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: Text(plugin['name'].toString()),
                  subtitle: Text(
                    '${plugin['version']} · ${enabled ? context.tr.t('已启用') : context.tr.t('已停用')}',
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      Switch(
                        value: enabled,
                        onChanged: _busy
                            ? null
                            : (value) => _service.setEnabled(
                                  plugin['id'].toString(),
                                  value,
                                ),
                      ),
                      FilledButton(
                        onPressed: _busy || !enabled ? null : () => _run(plugin),
                        child: Text(context.tr.t('运行')),
                      ),
                    ],
                  ),
                ),
                if (uiResult != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CipRunPage(
                                    pluginId: plugin['id'].toString(),
                                    uiResult: uiResult,
                                  ),
                                ),
                              ),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(context.tr.t('打开运行界面')),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _storeTab(BuildContext context) {
    if (_storeLoading) return const Center(child: CircularProgressIndicator());
    if (_storeItems.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: _loadStore,
          icon: const Icon(Icons.refresh),
          label: Text(context.tr.t('加载 CIP 商店')),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadStore,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _storeItems.length,
        itemBuilder: (context, index) {
          final item = _storeItems[index];
          final name = (item['name'] ?? item['title'] ?? item['id'] ?? 'CIP').toString();
          final version = (item['version'] ?? '').toString();
          final description = (item['description'] ?? '').toString();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(name),
              subtitle: Text(
                [version, description]
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
              ),
              trailing: FilledButton(
                onPressed: _busy ? null : () => _installStoreItem(item),
                child: Text(context.tr.t('下载')),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cips = _service.plugins
        .where((plugin) => plugin['cip_main'] is String)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr.cip),
        actions: [
          IconButton(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.upload_file),
            tooltip: context.tr.t('导入 .cip'),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: context.tr.t('本地 CIP')),
                Tab(text: context.tr.t('CIP 商店')),
              ],
              onTap: (index) {
                if (index == 1 && _storeItems.isEmpty) _loadStore();
              },
            ),
            Expanded(
              child: TabBarView(
                children: [_localTab(context, cips), _storeTab(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
