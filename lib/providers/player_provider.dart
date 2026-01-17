import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/storage_service.dart';

/// Provider do player de vídeo
class PlayerProvider with ChangeNotifier {
  final StorageService _storage = StorageService();

  Channel? _currentChannel;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  double _volume = 1.0;
  String _quality = 'Auto';
  bool _showControls = true;
  bool _isFullscreen = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Getters
  Channel? get currentChannel => _currentChannel;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  double get volume => _volume;
  String get quality => _quality;
  bool get showControls => _showControls;
  bool get isFullscreen => _isFullscreen;
  Duration get position => _position;
  Duration get duration => _duration;

  /// Define o canal atual
  Future<void> setChannel(Channel channel) async {
    _currentChannel = channel;
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();

    // Salva como último canal assistido
    await _storage.saveLastChannel(channel.id);
    await _storage.addToHistory(channel.id);
  }

  /// Define estado de carregamento
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Define estado de reprodução
  void setPlaying(bool playing) {
    _isPlaying = playing;
    notifyListeners();
  }

  /// Define erro
  void setError(String? message) {
    _hasError = message != null;
    _errorMessage = message;
    _isLoading = false;
    notifyListeners();
  }

  /// Limpa erro
  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Toggle mute
  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  /// Define mute
  void setMuted(bool muted) {
    _isMuted = muted;
    notifyListeners();
  }

  /// Define volume
  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    if (_volume > 0) {
      _isMuted = false;
    }
    notifyListeners();
  }

  /// Aumenta volume
  void increaseVolume([double step = 0.1]) {
    setVolume(_volume + step);
  }

  /// Diminui volume
  void decreaseVolume([double step = 0.1]) {
    setVolume(_volume - step);
  }

  /// Define qualidade
  void setQuality(String q) {
    _quality = q;
    notifyListeners();
  }

  /// Toggle controles
  void toggleControls() {
    _showControls = !_showControls;
    notifyListeners();
  }

  /// Define visibilidade dos controles
  void setControlsVisible(bool visible) {
    _showControls = visible;
    notifyListeners();
  }

  /// Toggle fullscreen
  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    notifyListeners();
  }

  /// Define fullscreen
  void setFullscreen(bool fullscreen) {
    _isFullscreen = fullscreen;
    notifyListeners();
  }

  /// Atualiza posição
  void updatePosition(Duration pos) {
    _position = pos;
    // Não notifica para evitar rebuilds excessivos
  }

  /// Atualiza duração
  void updateDuration(Duration dur) {
    _duration = dur;
    notifyListeners();
  }

  /// Reset do player
  void reset() {
    _currentChannel = null;
    _isPlaying = false;
    _isMuted = false;
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _showControls = true;
    notifyListeners();
  }

  /// Carrega último canal assistido
  Future<Channel?> getLastChannel(List<Channel> channels) async {
    final lastId = await _storage.getLastChannel();
    if (lastId == null) return null;

    try {
      return channels.firstWhere((c) => c.id == lastId);
    } catch (_) {
      return null;
    }
  }
}
