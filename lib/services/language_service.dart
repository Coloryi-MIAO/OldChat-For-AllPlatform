import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'app_localizations.dart';
import 'account_storage.dart';

class LanguageController extends ChangeNotifier {
  String _language = 'zh';

  String get language => _language;
  bool get isEnglish => _language == 'en';

  Future<void> load() async {
    await AccountStorage.instance.load();
    _language = AccountStorage.instance.getString(Constants.languageKey) == 'en'
        ? 'en'
        : 'zh';
    AppLocalizations.setCurrent(Locale(_language));
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    final normalized = value == 'en' ? 'en' : 'zh';
    if (_language == normalized) return;
    _language = normalized;
    AppLocalizations.setCurrent(Locale(normalized));
    notifyListeners();
    await AccountStorage.instance.setString(Constants.languageKey, normalized);
  }

  String text(String zh, String en) => isEnglish ? en : zh;
}
