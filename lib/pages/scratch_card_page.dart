import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_localizations.dart';
import '../services/cache_service.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class ScratchCardPage extends StatefulWidget {
  const ScratchCardPage({super.key});

  @override
  State<ScratchCardPage> createState() => _ScratchCardPageState();
}

class _ScratchCardPageState extends State<ScratchCardPage> {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _scratching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _cacheKey => CacheService().scoped(
    AuthService().userId ?? 'guest',
    Constants.scratchCardCacheKey,
  );

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    final cached = await CacheService().readJson(_cacheKey);
    if (cached is Map) {
      final envelope = Map<String, dynamic>.from(cached);
      final cachedDate = envelope['date']?.toString();
      final cachedState = envelope['state'];
      if (cachedDate == _todayKey() && cachedState is Map && mounted) {
        setState(() {
          _state = Map<String, dynamic>.from(cachedState);
          _loading = false;
          _error = null;
        });
        return;
      }
    }
    try {
      final value = await ApiService().getScratchCard();
      await CacheService().writeJson(_cacheKey, {
        'date': _todayKey(),
        'state': value,
      });
      if (!mounted) return;
      setState(() {
        _state = value;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _scratch() async {
    if (_scratching || _alreadyScratched) return;
    setState(() {
      _scratching = true;
      _error = null;
    });
    try {
      final result = await ApiService().scratchCard();
      await CacheService().writeJson(_cacheKey, {
        'date': _todayKey(),
        'state': result,
      });
      if (!mounted) return;
      setState(() {
        _state = result;
        _scratching = false;
      });
      final reward = _intValue(result['total_reward']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reward > 0
                ? '${context.tr.t('恭喜获得')} $reward ${context.tr.t('金币余额')}'
                : context.tr.t('今日未中奖'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scratching = false;
        _error = error.toString();
      });
    }
  }

  bool get _alreadyScratched =>
      _state?['already_scratched'] == true || _state?['already_done'] == true;

  int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<dynamic> _slotsFromState(Map<String, dynamic>? state) {
    final raw =
        state?['slots'] ??
        state?['cards'] ??
        state?['rewards'] ??
        state?['results'];
    final values = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
    if (values.isEmpty) {
      for (var index = 1; index <= 5; index++) {
        final value =
            state?['card_$index'] ??
            state?['slot_$index'] ??
            state?['reward_$index'];
        if (value != null) values.add(value);
      }
    }
    while (values.length < 5) values.add({'label': context.tr.t('谢谢惠顾')});
    return values.take(5).toList();
  }

  String _slotLabel(dynamic value) {
    if (value is Map) {
      final amount = _intValue(
        value['amount'] ?? value['reward'] ?? value['coins'],
      );
      final label = value['label']?.toString().trim();
      if (label != null && label.isNotEmpty) return label;
      if (amount == 0) return context.tr.t('谢谢惠顾');
      return '$amount ${context.tr.t('金币余额')}';
    }
    final amount = _intValue(value);
    if (amount == 0) return context.tr.t('谢谢惠顾');
    return '$amount ${context.tr.t('金币余额')}';
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final state = _state;
    final alreadyDone = _alreadyScratched;
    final reward = _intValue(state?['total_reward']);
    final balance = _intValue(state?['coin_balance']);
    final slots = _slotsFromState(state);

    return Scaffold(
      appBar: AppBar(title: Text(tr.scratchCard)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading && state == null
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            alreadyDone
                                ? tr.t('今日已刮奖，明天再来吧')
                                : tr.t('中奖概率很高，每天可刮一次'),
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text('${tr.t('金币余额')}：$balance'),
                          if (alreadyDone && reward > 0)
                            Text('${tr.t('今日已刮得')}：$reward'),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final slot in slots)
                                Container(
                                  width: 108,
                                  height: 88,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: alreadyDone
                                          ? [
                                              Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer,
                                              Theme.of(
                                                context,
                                              ).colorScheme.secondaryContainer,
                                            ]
                                          : [
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    _slotLabel(slot),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: alreadyDone
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            onPressed: alreadyDone || _scratching
                                ? null
                                : _scratch,
                            icon: _scratching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome),
                            label: Text(
                              _scratching
                                  ? tr.t('刮奖中…')
                                  : alreadyDone
                                  ? tr.t('明日再来')
                                  : tr.t('刮一刮'),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
