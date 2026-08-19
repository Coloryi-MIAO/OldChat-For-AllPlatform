class AccountStorage {
  AccountStorage._();
  static final AccountStorage instance = AccountStorage._();
  String? _userId;
  final Map<String, dynamic> _values = {};
  String get userId => _userId ?? 'guest';
  Future<void> load({String? userId}) async => _userId = userId ?? 'guest';
  T? get<T>(String key) => _values[key] is T ? _values[key] as T : null;
  dynamic getValue(String key) => _values[key];
  Set<String> get keys => _values.keys.toSet();
  String? getString(String key) => get<String>(key);
  bool? getBool(String key) => get<bool>(key);
  int? getInt(String key) =>
      _values[key] is num ? (_values[key] as num).toInt() : null;
  double? getDouble(String key) =>
      _values[key] is num ? (_values[key] as num).toDouble() : null;
  Future<void> setString(String key, String value) => setValue(key, value);
  Future<void> setBool(String key, bool value) => setValue(key, value);
  Future<void> setInt(String key, int value) => setValue(key, value);
  Future<void> setDouble(String key, double value) => setValue(key, value);
  Future<void> setValue(String key, dynamic value) async =>
      _values[key] = value;
  Future<void> remove(String key) async => _values.remove(key);
  Future<void> migrateLegacyKeys(Iterable<String> keys) async {}
  Future<void> resetSettings() async => _values.clear();
  Future<void> reset() async {
    _userId = null;
    _values.clear();
  }
}
