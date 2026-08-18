import 'package:flutter/material.dart';
import '../services/app_localizations.dart';

import '../services/api_service.dart';

class RequestListPage extends StatefulWidget {
  final bool groups;

  const RequestListPage({super.key, this.groups = false});

  @override
  State<RequestListPage> createState() => _RequestListPageState();
}

class _RequestListPageState extends State<RequestListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _safe(Future<Map<String, dynamic>> future) async {
    try {
      return await future;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      if (widget.groups) {
        final results = await Future.wait([
          _safe(api.getAllGroupRequests()),
          _safe(api.getGroupInvitations()),
        ]);
        final items = <Map<String, dynamic>>[];
        for (final data in results) {
          final raw = data['requests'] ?? data['invitations'] ?? data['items'] ?? data['data'] ?? data['result'];
          if (raw is List) {
            for (final value in raw.whereType<Map>()) {
              final item = Map<String, dynamic>.from(value);
              final status = '${item['status'] ?? 'pending'}'.toLowerCase();
              if (status == 'pending' || status == '0' || status == 'waiting') items.add(item);
            }
          }
        }
        final seen = <String>{};
        items.removeWhere((item) {
          final id = '${item['id'] ?? item['request_id'] ?? item['invitation_id'] ?? ''}';
          return id.isNotEmpty && !seen.add(id);
        });
        if (mounted) setState(() => _items = items);
      } else {
        final friends = await api.getFriends();
        final friendIds = friends.map((item) => item.id).toSet();
        final data = await api.getFriendRequests();
        final raw = data['requests'] ?? data['items'] ?? data['data'] ?? data['result'];
        final items = raw is List
            ? raw.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).where((item) {
                final status = '${item['status'] ?? 'pending'}'.toLowerCase();
                return (status == 'pending' || status == '0' || status == 'waiting') && !friendIds.contains(item['from_uid']);
              }).toList()
            : <Map<String, dynamic>>[];
        if (mounted) setState(() => _items = items);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(Map<String, dynamic> item, bool accept) async {
    final id = '${item['id'] ?? item['request_id'] ?? item['invitation_id'] ?? ''}';
    if (id.isEmpty) return;
    try {
      if (widget.groups) {
        if (item['invitation_id'] != null) {
          await ApiService().respondGroupInvitation(id, accept);
        } else {
          await ApiService().approveGroupRequest(id, accept);
        }
      } else {
        await ApiService().respondFriendRequest(id, accept);
      }
      if (mounted) {
        setState(() => _items.remove(item));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accept ? '已接受申请' : '已拒绝申请')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.current.t('处理失败：$error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.groups ? '群聊申请' : '好友申请';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(AppLocalizations.current.t('加载失败：$_error')))
              : _items.isEmpty
                  ? Center(child: Text(AppLocalizations.current.t('暂无$title')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final name = '${item['from_display_name'] ?? item['from_name'] ?? item['inviter_name'] ?? item['from_uid'] ?? '未知用户'}';
                          final subtitle = widget.groups
                              ? '$name 邀请/申请加入 ${item['group_name'] ?? item['group_name_text'] ?? item['group_id'] ?? '群聊'}'
                              : '请求添加您为好友';
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Icon(widget.groups ? Icons.group_add : Icons.person_add)),
                              title: Text(subtitle),
                              subtitle: Text(item['message']?.toString() ?? name),
                              trailing: Wrap(
                                children: [
                                  IconButton(onPressed: () => _respond(item, true), icon: const Icon(Icons.check, color: Colors.green)),
                                  IconButton(onPressed: () => _respond(item, false), icon: const Icon(Icons.close, color: Colors.red)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
