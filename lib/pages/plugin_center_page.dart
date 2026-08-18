import 'package:flutter/material.dart';
import 'dart:io';
import '../utils/file_picker_compat.dart';
import 'package:provider/provider.dart';
import '../services/app_localizations.dart';
import '../services/plugin_service.dart';
import '../services/theme_service.dart';

class PluginCenterPage extends StatefulWidget {
  const PluginCenterPage({super.key});

  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage> {
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

  Future<void> _toggle(Map<String, dynamic> plugin, bool value) async {
    try {
      await _service.setEnabled(plugin['id'].toString(), value);
    } catch (error) {
      _show('插件状态修改失败：$error');
    }
  }

  Future<void> _configure(Map<String, dynamic> plugin) async {
    final config = plugin['config'] is Map
        ? Map<String, dynamic>.from(plugin['config'])
        : <String, dynamic>{};
    var autoClaim = config['auto_claim'] == true;
    var maxPerMinute = int.tryParse('${config['max_per_minute'] ?? 3}') ?? 3;
    var dailyLimit = int.tryParse('${config['daily_limit'] ?? 30}') ?? 30;
    var minRemainingCount =
        int.tryParse('${config['min_remaining_count'] ?? 1}') ?? 1;
    var skipExpired = config['skip_expired'] != false;
    var skipClaimed = config['skip_claimed'] != false;
    var minAmount = double.tryParse('${config['min_amount'] ?? 0}') ?? 0;
    var maxAmount = double.tryParse('${config['max_amount'] ?? 0}') ?? 0;
    var onlyUnclaimed = config['only_unclaimed'] != false;
    var skipSelf = config['skip_self'] != false;
    var contains = config['contains']?.toString() ?? '';
    var reply = config['reply']?.toString() ?? '';
    final savedConversationTypes = config['conversation_types'] is List
        ? (config['conversation_types'] as List)
              .map((value) => value.toString())
              .toSet()
        : <String>{config['conversation_type']?.toString() ?? 'direct'};
    final conversationTypes = savedConversationTypes
        .where((value) => value == 'direct' || value == 'group')
        .toSet();
    if (conversationTypes.isEmpty) conversationTypes.add('direct');
    var cooldownSeconds = int.tryParse('${config['cooldown_seconds'] ?? 60}') ?? 60;
    final maxPerMinuteController = TextEditingController(text: '$maxPerMinute');
    final dailyLimitController = TextEditingController(text: '$dailyLimit');
    final cooldownController = TextEditingController(text: '$cooldownSeconds');
    final containsController = TextEditingController(text: contains);
    final replyController = TextEditingController(text: reply);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(plugin['name'].toString()),
          // ★ 修复：使用 SizedBox + SingleChildScrollView + 动态高度
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: SingleChildScrollView(
              child: plugin['id'] == 'oldchat.redpacket-helper'
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('自动领取红包')),
                          subtitle: Text(
                            AppLocalizations.current.t('默认关闭；请自行确认风险'),
                          ),
                          value: autoClaim,
                          onChanged: (value) =>
                              setDialogState(() => autoClaim = value),
                        ),
                        TextField(
                          keyboardType: TextInputType.number,
                          controller: maxPerMinuteController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('每分钟最多领取'),
                          ),
                          onChanged: (value) =>
                              maxPerMinute = int.tryParse(value) ?? 3,
                        ),
                        TextField(
                          keyboardType: TextInputType.number,
                          controller: dailyLimitController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('每日最多领取'),
                          ),
                          onChanged: (value) =>
                              dailyLimit = int.tryParse(value) ?? 30,
                        ),
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('红包至少剩余份数'),
                          ),
                          controller: TextEditingController(
                            text: '$minRemainingCount',
                          ),
                          onChanged: (value) =>
                              minRemainingCount = int.tryParse(value) ?? 1,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('跳过已过期红包')),
                          value: skipExpired,
                          onChanged: (value) =>
                              setDialogState(() => skipExpired = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('跳过已领取红包')),
                          value: skipClaimed,
                          onChanged: (value) =>
                              setDialogState(() => skipClaimed = value),
                        ),
                        TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('最低红包金额'),
                          ),
                          controller: TextEditingController(text: '$minAmount'),
                          onChanged: (value) =>
                              minAmount = double.tryParse(value) ?? 0,
                        ),
                        TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('最高红包金额，0为不限'),
                          ),
                          controller: TextEditingController(text: '$maxAmount'),
                          onChanged: (value) =>
                              maxAmount = double.tryParse(value) ?? 0,
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('仅领取未领取红包')),
                          value: onlyUnclaimed,
                          onChanged: (value) =>
                              setDialogState(() => onlyUnclaimed = value ?? true),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('跳过自己发出的红包')),
                          value: skipSelf,
                          onChanged: (value) =>
                              setDialogState(() => skipSelf = value ?? true),
                        ),
                      ],
                    )
                  : plugin['id'] == 'oldchat.auto-reply'
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppLocalizations.current.t('适用会话'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('私聊')),
                          value: conversationTypes.contains('direct'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              conversationTypes.add('direct');
                            } else if (conversationTypes.length > 1) {
                              conversationTypes.remove('direct');
                            }
                          }),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AppLocalizations.current.t('群聊')),
                          value: conversationTypes.contains('group'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              conversationTypes.add('group');
                            } else if (conversationTypes.length > 1) {
                              conversationTypes.remove('group');
                            }
                          }),
                        ),
                        TextField(
                          controller: containsController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('触发关键词'),
                          ),
                          onChanged: (value) => contains = value,
                        ),
                        TextField(
                          controller: replyController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('自动回复内容'),
                          ),
                          maxLines: 3,
                          onChanged: (value) => reply = value,
                        ),
                        TextField(
                          keyboardType: TextInputType.number,
                          controller: cooldownController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.current.t('自动回复冷却秒数'),
                          ),
                          onChanged: (value) =>
                              cooldownSeconds = int.tryParse(value) ?? 60,
                        ),
                      ],
                    )
                  : Text(plugin['description'].toString()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.current.t('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'auto_claim': autoClaim,
                'max_per_minute': maxPerMinute.clamp(1, 30),
                'daily_limit': dailyLimit.clamp(1, 500),
                'min_remaining_count': minRemainingCount.clamp(0, 100000),
                'skip_expired': skipExpired,
                'skip_claimed': skipClaimed,
                'min_amount': minAmount.clamp(0, 1000000),
                'max_amount': maxAmount.clamp(0, 1000000),
                'only_unclaimed': onlyUnclaimed,
                'skip_self': skipSelf,
                'contains': contains,
                'reply': reply,
                'conversation_types': conversationTypes.toList(),
                'conversation_type': conversationTypes.first,
                'cooldown_seconds': cooldownSeconds.clamp(0, 86400),
              }),
              child: Text(AppLocalizations.current.t('保存')),
            ),
          ],
        ),
      ),
    );

    maxPerMinuteController.dispose();
    dailyLimitController.dispose();
    containsController.dispose();
    replyController.dispose();
    cooldownController.dispose();
    if (result != null) {
      await _service.updateConfig(plugin['id'].toString(), result);
    }
  }

  Future<void> _approve(String id) async {
    setState(() => _busy = true);
    try {
      await _service.approvePending(id);
      _show('审核通过并已执行');
    } catch (error) {
      _show('执行失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyTheme(Map<String, dynamic> plugin) async {
    try {
      await _service.applyTheme(
        plugin['id'].toString(),
        context.read<AppThemeController>(),
      );
      _show('主题已应用');
    } catch (error) {
      _show('主题应用失败：$error');
    }
  }

  Future<void> _importPackage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['oldchat-plugin'],
      withData: false,
    );
    final selectedFiles = filePickerFiles(result);
    final path = selectedFiles.isNotEmpty ? selectedFiles.first.path : null;
    if (path == null || path.isEmpty) return;
    final extension = path.split('.').last.toLowerCase();
    if (extension != 'oldchat-plugin') {
      _show(AppLocalizations.current.t('仅支持 .oldchat-plugin 文件；CIP 请在 CIP 中心导入'));
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.importPluginFile(File(path));
      _show(AppLocalizations.current.t('插件已导入并保存到本地'));
    } catch (error) {
      _show('${AppLocalizations.current.t('导入失败')}：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPlugin(Map<String, dynamic> plugin) async {
    setState(() => _busy = true);
    try {
      final isCip = plugin['cip_main']?.toString().isNotEmpty == true;
      final bytes = isCip
          ? await _service.exportCip(plugin['id'].toString())
          : await _service.exportPlugin(plugin['id'].toString());
      final extension = isCip ? 'cip' : 'oldchat-plugin';
      final path = filePickerPath(
        await FilePicker.saveFile(
          dialogTitle: context.tr.t('导出插件'),
          fileName: '${plugin['id']}.$extension',
          type: FileType.custom,
          allowedExtensions: [extension],
          bytes: bytes,
          lockParentWindow: true,
        ),
      );
      if (path != null && mounted) _show('${context.tr.t('插件已导出：')}$path');
    } catch (error) {
      if (mounted) _show('${context.tr.t('插件导出失败：')}$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('插件中心')),
        actions: [
          IconButton(
            onPressed: _busy ? null : _importPackage,
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: AppLocalizations.current.t('导入 .oldchat-plugin'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._service.plugins
              .where((plugin) =>
                  plugin['id'] != 'oldchat.function-buttons' &&
                  !(plugin['cip_main'] is String &&
                      (plugin['cip_main'] as String).trim().isNotEmpty))
              .map(_buildPlugin),
          if (_service.pendingActions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              AppLocalizations.current.t('待审核操作'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            ..._service.pendingActions.map(
              (item) => Card(
                child: ListTile(
                  title: Text('${item['plugin_name']} · ${item['type']}'),
                  subtitle: Text('${item['data']}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () => _approve(item['id'].toString()),
                        icon: const Icon(Icons.check, color: Colors.green),
                        tooltip: AppLocalizations.current.t('通过并执行'),
                      ),
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  _service.rejectPending(item['id'].toString()),
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: AppLocalizations.current.t('拒绝'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlugin(Map<String, dynamic> plugin) {
    final enabled = plugin['enabled'] == true;
    final permissions =
        (plugin['permissions'] as List?)
            ?.map((value) => value.toString())
            .join('、') ??
        '';
    final name = plugin['builtIn'] == true
        ? context.tr.t(plugin['name'].toString())
        : plugin['name'].toString();
    final description = plugin['builtIn'] == true
        ? context.tr.t(plugin['description'].toString())
        : plugin['description'].toString();
    final status = enabled ? context.tr.t('运行中') : context.tr.t('已停用');
    return Card(
      child: ExpansionTile(
        leading: Icon(
          plugin['builtIn'] == true ? Icons.verified : Icons.extension,
        ),
        title: Text(name),
        subtitle: Text('${plugin['version']} · $status'),
        trailing: Switch(
          value: enabled,
          onChanged: (value) => _toggle(plugin, value),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.current.t('权限：$permissions'),
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => _configure(plugin),
                      child: Text(context.tr.t('配置')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _exportPlugin(plugin),
                      child: Text(context.tr.t('导出')),
                    ),
                    if (plugin['theme'] is Map) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: enabled ? () => _applyTheme(plugin) : null,
                        child: Text(context.tr.t('应用主题')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}