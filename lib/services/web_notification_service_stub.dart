class WebNotificationService {
  Future<void> init() async {}
  Future<bool> requestPermission() async => false;
  Future<bool> show({
    required String title,
    required String body,
    String? payload,
  }) async => false;
}
