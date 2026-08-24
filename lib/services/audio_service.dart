import 'package:flutter/foundation.dart';
import '../utils/url_helper.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  String? _currentUrl;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final List<VoidCallback> _listeners = [];

  String? get currentUrl => _currentUrl;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  Future<void> init() async {}

  Future<void> play(String url) async {
    if (url.isEmpty) return;
    _currentUrl = resolveMediaUrl(url);
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _notifyListeners();
  }

  Future<void> pause() async {}

  Future<void> resume() async {}

  Future<void> stop() async {
    _currentUrl = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _notifyListeners();
  }

  Future<void> seek(Duration position) async {}

  void dispose() {
    _listeners.clear();
  }
}
