import 'package:flutter/material.dart';

import '../services/plugin_service.dart';
import '../services/app_localizations.dart';

class ToolsHubPage extends StatefulWidget {
  final bool more;

  const ToolsHubPage({super.key, this.more = false});

  @override
  State<ToolsHubPage> createState() => _ToolsHubPageState();
}

class _ToolEntry {
  final String id;
  final String label;
  final IconData icon;
  final String route;

  const _ToolEntry(this.id, this.label, this.icon, this.route);
}

class _ToolsHubPageState extends State<ToolsHubPage> {
  final _pluginService = PluginService();
  Map<String, dynamic> _buttonConfig = {};
  bool _loading = true;

  static const _tools = <_ToolEntry>[
    _ToolEntry('moments', '动态', Icons.dynamic_feed_outlined, '/moments'),
    _ToolEntry('court', '公开法庭', Icons.gavel_outlined, '/public_court'),
    _ToolEntry('emoji', '表情广场', Icons.emoji_emotions_outlined, '/emoji_plaza'),
    _ToolEntry(
      'notifications',
      '通知',
      Icons.notifications_none,
      '/notifications',
    ),
    _ToolEntry('channels', '频道', Icons.campaign_outlined, '/channels'),
    _ToolEntry('scratch', '每日刮刮乐', Icons.local_activity_outlined, '/scratch'),
    _ToolEntry('plugins', '插件', Icons.extension_outlined, '/plugins'),
    _ToolEntry('cip', 'CIP 小程序', Icons.widgets_outlined, '/cip'),
    _ToolEntry(
      'friend_requests',
      '好友申请',
      Icons.person_add_alt_1,
      '/friend_requests',
    ),
    _ToolEntry(
      'group_requests',
      '群聊申请',
      Icons.group_add_outlined,
      '/group_requests',
    ),
  ];

  static const _more = <_ToolEntry>[
    _ToolEntry('favorites', '我的收藏', Icons.star_outline, '/favorites'),
    _ToolEntry('checkin', '签到墙', Icons.event_available, '/checkin_wall'),
    _ToolEntry('ai', 'AI 助手', Icons.smart_toy_outlined, '/ai_chat'),
    _ToolEntry('settings', '设置', Icons.settings_outlined, '/settings'),
    _ToolEntry('about', '关于 OldChat', Icons.info_outline, '/about'),
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await _pluginService.load();
    final plugin = _pluginService.plugins.firstWhere(
      (item) => item['id'] == 'oldchat.function-buttons',
      orElse: () => <String, dynamic>{},
    );
    final config = plugin['config'];
    if (!mounted) return;
    setState(() {
      _buttonConfig = config is Map ? Map<String, dynamic>.from(config) : {};
      _loading = false;
    });
  }

  List<_ToolEntry> _entries() {
    final source = widget.more ? _more : _tools;
    final hidden =
        (_buttonConfig['hidden'] as List?)?.map((e) => e.toString()).toSet() ??
        {};
    final order =
        (_buttonConfig['order'] as List?)?.map((e) => e.toString()).toList() ??
        [];
    final byId = {for (final entry in source) entry.id: entry};
    final result = <_ToolEntry>[];
    for (final id in order) {
      final entry = byId.remove(id);
      if (entry != null && !hidden.contains(id)) result.add(entry);
    }
    for (final entry in source) {
      if (byId.containsKey(entry.id) && !hidden.contains(entry.id))
        result.add(entry);
    }
    return result;
  }

  Future<void> _editButtons() async {
    final all = [..._tools, ..._more];
    final hidden = ((_buttonConfig['hidden'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    final visible = all.where((item) => !hidden.contains(item.id)).toList();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.current.t('编辑功能按钮')),
          content: SizedBox(
            width: 460,
            height: 500,
            child: ReorderableListView.builder(
              itemCount: visible.length,
              onReorder: (oldIndex, newIndex) {
                setDialogState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = visible.removeAt(oldIndex);
                  visible.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final item = visible[index];
                return CheckboxListTile(
                  key: ValueKey(item.id),
                  value: true,
                  title: Text(item.label),
                  secondary: const Icon(Icons.drag_handle),
                  onChanged: (_) {},
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.current.t('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'order': visible.map((item) => item.id).toList(),
                'hidden': all
                    .where((item) => !visible.contains(item))
                    .map((item) => item.id)
                    .toList(),
              }),
              child: Text(AppLocalizations.current.t('保存')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _pluginService.updateConfig('oldchat.function-buttons', result);
    if (mounted) setState(() => _buttonConfig = result);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final tr = context.tr;
    final entries = _entries();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.more ? tr.more : tr.tools),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _editButtons,
            icon: const Icon(Icons.tune),
            tooltip: tr.functionButtonEditor,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? Center(
              child: Text(
                tr.text(
                  '没有可显示的入口，请到设置中恢复默认设置',
                  'No entries are visible. Restore the default settings.',
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 112,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final item = entries[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pushNamed(context, item.route),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon, size: 30, color: primary),
                          const SizedBox(height: 8),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
