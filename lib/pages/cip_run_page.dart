import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/plugin_service.dart';

class CipRunPage extends StatefulWidget {
  final String pluginId;
  final Map<String, dynamic> uiResult;

  const CipRunPage({
    super.key,
    required this.pluginId,
    required this.uiResult,
  });

  @override
  State<CipRunPage> createState() => _CipRunPageState();
}

class _CipRunPageState extends State<CipRunPage> {
  final _service = PluginService();
  final Map<String, TextEditingController> _inputs = {};
  final Map<String, bool> _checks = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    for (final controller in _inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _action(Map<String, dynamic> node) async {
    final callback = int.tryParse(node['callback_ref']?.toString() ?? '');
    if (callback == null) return;
    setState(() => _busy = true);
    try {
      await _service.executeCipCallback(widget.pluginId, callback);
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

  Widget _node(Map<String, dynamic> node) {
    final type = node['type']?.toString() ?? 'text';
    final visible = node['visible']?.toString().toLowerCase() != 'false';
    if (!visible) return const SizedBox.shrink();
    final children = (node['children'] is List ? node['children'] as List : const [])
        .whereType<Map>()
        .map((child) => _node(Map<String, dynamic>.from(child)))
        .toList(growable: false);
    final id = node['id']?.toString() ?? '';
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
            onPressed: _busy ? null : () => _action(node),
            child: Text(context.tr.t(node['label']?.toString() ?? node['text']?.toString() ?? '操作')),
          ),
        );
      case 'input':
        final controller = _inputs.putIfAbsent(id, TextEditingController.new);
        return Padding(
          padding: EdgeInsets.symmetric(vertical: margin),
          child: TextField(
            controller: controller,
            maxLines: node['single_line']?.toString().toLowerCase() == 'false' ? null : 1,
            decoration: InputDecoration(
              labelText: context.tr.t(node['label']?.toString() ?? ''),
              hintText: context.tr.t(node['placeholder']?.toString() ?? node['hint']?.toString() ?? ''),
            ),
          ),
        );
      case 'checkbox':
        final checked = _checks.putIfAbsent(id, () => node['checked'] == true);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: checked,
          onChanged: (value) => setState(() => _checks[id] = value ?? false),
          title: Text(context.tr.t(node['label']?.toString() ?? node['text']?.toString() ?? '选项')),
        );
      case 'image':
        final url = node['src']?.toString() ?? node['url']?.toString() ?? '';
        return url.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: EdgeInsets.symmetric(vertical: margin),
                child: Image.network(url, height: height ?? 180, fit: BoxFit.contain),
              );
      case 'spacer':
        return SizedBox(height: height ?? 12);
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(context.tr.t(node['text']?.toString() ?? node['value']?.toString() ?? '')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _service.uiResult(widget.pluginId) ?? widget.uiResult;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr.t('CIP 运行'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [_node(result)],
      ),
    );
  }
}
