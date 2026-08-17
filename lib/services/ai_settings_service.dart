import 'account_storage.dart';

class AISettings {
  final String apiKey;
  final String baseUrl;
  final String model;

  const AISettings({this.apiKey = '', this.baseUrl = '', this.model = ''});

  bool get isConfigured => apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty;
}

class AISettingsService {
  static const _apiKey = 'ai_personal_api_key';
  static const _baseUrl = 'ai_personal_base_url';
  static const _model = 'ai_personal_model';

  static Future<AISettings> load() async {
    await AccountStorage.instance.load();
    final storage = AccountStorage.instance;
    return AISettings(
      apiKey: storage.getString(_apiKey) ?? '',
      baseUrl: storage.getString(_baseUrl) ?? '',
      model: storage.getString(_model) ?? '',
    );
  }

  static Future<void> save({required String apiKey, required String baseUrl, String model = ''}) async {
    await AccountStorage.instance.setString(_apiKey, apiKey.trim());
    await AccountStorage.instance.setString(_baseUrl, baseUrl.trim());
    await AccountStorage.instance.setString(_model, model.trim());
  }
}
