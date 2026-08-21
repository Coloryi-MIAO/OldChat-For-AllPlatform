import '../utils/file_picker_compat.dart';
import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/plugin_service.dart';

class CipPage extends StatefulWidget {
  const CipPage({super.key});

  @override
  State<CipPage> createState() => _CipPageState();
}

class _CipPageState extends State<CipPage> {
  final _service = PluginService();
  bool _busy = false;
  final Map<String, TextEditingController> _inputControllers = {};
  final Map<String, bool> _checkboxValues = {};

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _service.load();
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
          padding: const EdgeInsets.symmetric(vertical: 4),
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
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Image.network(url, height: 160, fit: BoxFit.contain),
              );
      case 'spacer':
        return const SizedBox(height: 12);
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
    if (action == 'submit' || action == 'run') {
      if (pluginId == null || pluginId.isEmpty) return;
      final plugin = _service.plugins.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id']?.toString() == pluginId,
        orElse: () => null,
      );
      final script = plugin?['cip_main']?.toString();
      if (script == null || script.isEmpty) return;
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
    final script = plugin['cip_main']?.toString();
    if (script == null || script.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _service.executeCip(plugin['id'].toString(), script);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr.t('CIP 已执行'))));
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
      body: cips.isEmpty
          ? Center(child: Text(context.tr.t('暂无本地 CIP，点击右上角导入')))
          : ListView.builder(
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
                                onPressed: _busy || !enabled
                                    ? null
                                    : () => _run(plugin),
                                child: Text(context.tr.t('运行')),
                              ),
                            ],
                          ),
                        ),
                        if (uiResult != null) ...[
                          const Divider(),
                          _buildUiNode(
                            context,
                            uiResult,
                            plugin['id'].toString(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
