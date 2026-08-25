import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../utils/url_helper.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
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
    for (var listener in _listeners) {
      listener();
    }
  }

  Future<void> init() async {
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      _notifyListeners();
    });
    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      _notifyListeners();
    });
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _notifyListeners();
    });
  }

  Future<void> play(String url) async {
    if (url.isEmpty) return;
    final fullUrl = resolveMediaUrl(url);
    if (_currentUrl == fullUrl && _isPlaying) {
      await _player.pause();
      return;
    }
    if (_currentUrl == fullUrl && !_isPlaying) {
      await _player.resume();
      return;
    }
    await _player.stop();
    _currentUrl = fullUrl;
    await _player.play(UrlSource(fullUrl));
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.resume();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentUrl = null;
    _position = Duration.zero;
    _notifyListeners();
  }

  // ★ 新增 seek 方法
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  void dispose() {
    _player.dispose();
  }
}
