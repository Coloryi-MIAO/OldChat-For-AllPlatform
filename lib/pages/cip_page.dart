import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _service.load();
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cip'],
      withData: false,
    );
    final selectedFiles = filePickerFiles(result);
    final path = selectedFiles.isNotEmpty ? selectedFiles.first.path : null;
    if (path == null || path.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _service.importCipFile(File(path));
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
                return Card(
                  child: ListTile(
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
                );
              },
            ),
    );
  }
}
