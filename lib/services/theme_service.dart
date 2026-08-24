import 'dart:convert';

import 'package:flutter/material.dart';
import 'account_storage.dart';

class AppThemeController extends ChangeNotifier {
  static const _pinkKey = 'pink_theme_enabled';
  static const _fontKey = 'app_font_family';
  static const _pluginThemeKey = 'plugin_theme';
  static const _scaleKey = 'app_scale_factor';

  bool _isPink = true;
  String _fontFamily = 'HarmonyOS Sans SC';
  Map<String, dynamic>? _pluginTheme;
  double _scaleFactor = 1.0;

  bool get isPink => _isPink;
  String get fontFamily => _fontFamily;
  Map<String, dynamic>? get pluginTheme => _pluginTheme;
  double get scaleFactor => _scaleFactor;

  Future<void> load() async {
    final storage = AccountStorage.instance;
    await storage.load();
    _isPink = storage.getBool(_pinkKey) ?? true;
    final saved = storage.getString(_fontKey);
    _fontFamily = saved == 'Microsoft YaHei' || saved == 'HarmonyOS Sans SC'
        ? saved!
        : 'HarmonyOS Sans SC';
    final savedScale = storage.getDouble(_scaleKey);
    _scaleFactor = savedScale == null ? 1.0 : savedScale.clamp(0.5, 5.0).toDouble();
    final raw = storage.getString(_pluginThemeKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) _pluginTheme = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }

  Future<void> setScaleFactor(double value) async {
    final normalized = value.clamp(0.5, 5.0).toDouble();
    if ((_scaleFactor - normalized).abs() < 0.001) return;
    _scaleFactor = normalized;
    notifyListeners();
    await AccountStorage.instance.setDouble(_scaleKey, normalized);
  }

  Future<void> setFontFamily(String value) async {
    if (value != 'Microsoft YaHei' && value != 'HarmonyOS Sans SC') return;
    if (_fontFamily == value) return;
    _fontFamily = value;
    notifyListeners();
    await AccountStorage.instance.setString(_fontKey, value);
  }

  Future<void> setPluginTheme(Map<String, dynamic>? theme) async {
    _pluginTheme = theme == null ? null : Map<String, dynamic>.from(theme);
    notifyListeners();
    if (_pluginTheme == null) {
      await AccountStorage.instance.remove(_pluginThemeKey);
    } else {
      await AccountStorage.instance.setString(
        _pluginThemeKey,
        jsonEncode(_pluginTheme),
      );
    }
  }

  Future<void> clearPluginTheme() => setPluginTheme(null);

  Future<void> setPink(bool value) async {
    if (_isPink == value) return;
    _isPink = value;
    notifyListeners();
    await AccountStorage.instance.setBool(_pinkKey, value);
  }
}
