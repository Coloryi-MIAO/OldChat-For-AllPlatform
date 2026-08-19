import 'package:flutter/material.dart';
import '../utils/file_picker_compat.dart';
import 'package:dio/dio.dart';
import '../services/app_localizations.dart';
import '../services/api_service.dart';

class PublicCourtPage extends StatefulWidget {
  const PublicCourtPage({super.key});

  @override
  State<PublicCourtPage> createState() => _PublicCourtPageState();
}

class _PublicCourtPageState extends State<PublicCourtPage> {
  final _api = ApiService();
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in const [
        'cases',
        'items',
        'list',
        'records',
        'results',
        'data',
        'result',
      ]) {
        final nested = _list(map[key]);
        if (nested.isNotEmpty) return nested;
      }
    }
    return [];
  }

  String _text(
    Map<String, dynamic> value,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final item = value[key];
      if (item != null && item.toString().trim().isNotEmpty)
        return item.toString();
    }
    return fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getPublicCourtCases(limit: 50);
      final raw =
          data['cases'] ??
          data['items'] ??
          data['list'] ??
          data['data'] ??
          data;
      if (!mounted) return;
      setState(() {
        _cases = _list(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openCase(Map<String, dynamic> item) async {
    final id = _text(item, const ['id', 'case_id']);
    if (id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicCourtCasePage(caseId: id, summary: item),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t('公开法庭')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.current.t('加载失败：$_error')),
                  TextButton(
                    onPressed: _load,
                    child: Text(AppLocalizations.current.t('重试')),
                  ),
                ],
              ),
            )
          : _cases.isEmpty
          ? Center(child: Text(AppLocalizations.current.t('暂无公开案件')))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _cases.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = _cases[index];
                final title = _text(item, const [
                  'title',
                  'subject',
                  'name',
                  'case_title',
                  'case_name',
                ], '未命名案件');
                final summary = _text(item, const [
                  'summary',
                  'description',
                  'content',
                  'body',
                  'report_reason',
                ]);
                final status = _text(item, const ['status', 'state']);
                return Card(
                  child: ListTile(
                    title: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (summary.isNotEmpty)
                          Text(
                            summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (status.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '状态：$status',
                              style: TextStyle(color: primary),
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openCase(item),
                  ),
                );
              },
            ),
    );
  }
}

class PublicCourtCasePage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> summary;
  const PublicCourtCasePage({
    super.key,
    required this.caseId,
    this.summary = const {},
  });

  @override
  State<PublicCourtCasePage> createState() => _PublicCourtCasePageState();
}

class _PublicCourtCasePageState extends State<PublicCourtCasePage> {
  final _api = ApiService();
  final _statementController = TextEditingController();
  final _discussionController = TextEditingController();
  PlatformFile? _evidenceFile;
  Map<String, dynamic> _case = {};
  List<Map<String, dynamic>> _discussions = [];
  Map<String, dynamic> _votes = {};
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _case = Map<String, dynamic>.from(widget.summary);
    _load();
  }

  @override
  void dispose() {
    _statementController.dispose();
    _discussionController.dispose();
    super.dispose();
  }

  String _text(
    Map<String, dynamic> value,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final item = value[key];
      if (item != null && item.toString().trim().isNotEmpty)
        return item.toString();
    }
    return fallback;
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in const [
        'discussions',
        'items',
        'list',
        'data',
        'result',
      ]) {
        final nested = _list(map[key]);
        if (nested.isNotEmpty) return nested;
      }
    }
    return [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getPublicCourtCase(widget.caseId),
        _api.getPublicCourtVotes(widget.caseId),
        _api.getPublicCourtDiscussions(widget.caseId),
      ]);
      final caseData = results[0];
      final voteData = results[1];
      final discussionData = results[2];
      final raw =
          discussionData['discussions'] ??
          discussionData['items'] ??
          discussionData['data'] ??
          discussionData;
      if (!mounted) return;
      setState(() {
        _case = {
          ..._case,
          ...caseData,
          if (caseData['data'] is Map)
            ...Map<String, dynamic>.from(caseData['data']),
          if (caseData['case'] is Map)
            ...Map<String, dynamic>.from(caseData['case']),
          if (caseData['case_detail'] is Map)
            ...Map<String, dynamic>.from(caseData['case_detail']),
          if (caseData['detail'] is Map)
            ...Map<String, dynamic>.from(caseData['detail']),
        };
        _votes = {
          ..._votes,
          ...voteData,
          if (voteData['data'] is Map)
            ...Map<String, dynamic>.from(voteData['data']),
        };
        _discussions = _list(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickEvidence() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final files = filePickerFiles(result);
    if (files.isEmpty || !mounted) return;
    setState(() => _evidenceFile = files.first);
  }

  Future<String> _uploadEvidence() async {
    final file = _evidenceFile;
    if (file == null) return '';
    final bytes = await filePickerBytes(file);
    if (bytes == null || bytes.isEmpty) throw Exception('无法读取证据图片');
    final result = await _api.uploadFile(
      FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      }),
    );
    return ApiService.extractUploadUrl(result) ?? '';
  }

  Future<void> _vote(String vote) async {
    final reason = _statementController.text.trim();
    if (reason.isEmpty || _sending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('请先写下观点'))),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final evidence = await _uploadEvidence();
      final apiVote = vote == 'support'
          ? 'ban'
          : vote == 'oppose'
          ? 'keep'
          : vote;
      await _api.votePublicCourtCase(
        widget.caseId,
        apiVote,
        reason: reason,
        evidence: evidence,
      );
      _statementController.clear();
      if (mounted) {
        setState(() => _evidenceFile = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('观点与投票已提交'))),
        );
        _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('投票失败：$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendDiscussion() async {
    final text = _discussionController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.submitPublicCourtDiscussion(widget.caseId, text);
      _discussionController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('讨论已提交'))),
        );
        _load();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('提交讨论失败：$error'))),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendStatement() async {
    final text = _statementController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.submitPublicCourtStatement(widget.caseId, text);
      _statementController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('陈述已提交'))),
        );
        _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.current.t('提交失败：$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final title = _text(_case, const [
      'title',
      'subject',
      'name',
      'case_title',
      'case_name',
    ], '公开案件');
    final content = _text(_case, const [
      'content',
      'description',
      'summary',
      'body',
      'report_reason',
    ]);
    final reporter = _text(_case, const [
      'reporter_name',
      'reporter',
      'plaintiff',
      '原告',
    ]);
    final defendant = _text(_case, const ['defendant_name', 'defendant', '被告']);
    final evidence = _text(_case, const ['report_evidence', 'evidence']);
    final defense = _text(_case, const [
      'defense_reason',
      'defense',
      'defendant_reason',
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: _loading && _case.isEmpty
          ? Center(child: CircularProgressIndicator())
          : _error != null && _case.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.current.t('加载失败：$_error')),
                  TextButton(
                    onPressed: _load,
                    child: Text(AppLocalizations.current.t('重试')),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (content.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        content,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '案件 #${_text(_case, const ['id', 'case_id'], widget.caseId)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          context.tr.text(
                            '状态：${_text(_case, const ['status'], '未知')}',
                            'Status: ${_text(_case, const ['status'], 'Unknown')}',
                          ),
                        ),
                        Text(
                          context.tr.text(
                            '举报人：${reporter.isEmpty ? '未知' : reporter}',
                            'Reporter: ${reporter.isEmpty ? 'Unknown' : reporter}',
                          ),
                        ),
                        Text(
                          context.tr.text(
                            '被告：${defendant.isEmpty ? '未知' : defendant}',
                            'Defendant: ${defendant.isEmpty ? 'Unknown' : defendant}',
                          ),
                        ),
                        Text(
                          context.tr.text(
                            '举报理由：${_text(_case, const ['report_reason', 'reason'], '无')}',
                            'Report reason: ${_text(_case, const ['report_reason', 'reason'], 'None')}',
                          ),
                        ),
                        Text(
                          context.tr.text(
                            '辩护理由：${defense.isEmpty ? '未辩护' : defense}',
                            'Defense: ${defense.isEmpty ? 'No defense' : defense}',
                          ),
                        ),
                        if (evidence.isNotEmpty)
                          Text(
                            context.tr.text(
                              '举报证据：$evidence',
                              'Evidence: $evidence',
                            ),
                          ),
                        if (_case['verdict'] != null)
                          Text(
                            context.tr.text(
                              '裁决：${_case['verdict']}',
                              'Verdict: ${_case['verdict']}',
                            ),
                          ),
                        if (_case['ban_hours'] != null)
                          Text(
                            context.tr.text(
                              '封禁时长：${_case['ban_hours']} 小时',
                              'Ban duration: ${_case['ban_hours']} hours',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_votes.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '投票：${_votes['ban_vote_count'] ?? _votes['ban'] ?? _votes['support'] ?? _votes['supports'] ?? 0} 封禁 · ${_votes['keep_vote_count'] ?? _votes['keep'] ?? _votes['oppose'] ?? _votes['opposes'] ?? 0} 保留',
                      ),
                    ),
                  ),
                Text(
                  AppLocalizations.current.t('写下观点后选择投票，可选上传图片'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _statementController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: AppLocalizations.current.t('写下你的观点'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _sending ? null : _pickEvidence,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _evidenceFile == null
                            ? AppLocalizations.current.t('上传图片')
                            : _evidenceFile!.name,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _sending ? null : () => _vote('ban'),
                        icon: const Icon(Icons.thumb_up_alt_outlined),
                        label: Text(AppLocalizations.current.t('支持并提交')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : () => _vote('keep'),
                    icon: const Icon(Icons.thumb_down_alt_outlined),
                    label: Text(AppLocalizations.current.t('反对并提交')),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '讨论 (${_discussions.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _discussionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: AppLocalizations.current.t('参与讨论'),
                  ),
                ),
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: _sending ? null : _sendDiscussion,
                    child: Text(AppLocalizations.current.t('发布讨论')),
                  ),
                ),
                if (_discussions.isEmpty)
                  Text(
                    AppLocalizations.current.t('暂无讨论'),
                    style: TextStyle(color: Colors.grey),
                  ),
                ..._discussions.map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        _text(item, const [
                          'display_name',
                          'username',
                          'uid',
                        ], '用户'),
                      ),
                      subtitle: Text(
                        _text(item, const ['content', 'text', 'body'], ''),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
