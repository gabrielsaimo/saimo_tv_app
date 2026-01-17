import 'package:flutter/material.dart';
import '../services/storage_service.dart';

/// Provider de configurações
class SettingsProvider with ChangeNotifier {
  final StorageService _storage = StorageService();

  bool _autoPlay = true;
  bool _showEpg = true;
  bool _adultModeUnlocked = false;
  bool _adultModeEnabled = false;
  double _volume = 1.0;
  String _preferredQuality = 'auto';
  bool _enableSubtitles = false;
  int _secretClickCount = 0;

  static const int _secretClickThreshold = 15;

  // Getters
  bool get autoPlay => _autoPlay;
  bool get showEpg => _showEpg;
  bool get adultModeUnlocked => _adultModeUnlocked;
  bool get adultModeEnabled => _adultModeEnabled;
  double get volume => _volume;
  String get preferredQuality => _preferredQuality;
  bool get enableSubtitles => _enableSubtitles;
  int get secretClickCount => _secretClickCount;
  int get secretClicksRemaining => _secretClickThreshold - _secretClickCount;

  /// Carrega configurações
  Future<void> loadSettings() async {
    try {
      _autoPlay = await _storage.getSetting('autoPlay', true);
      _showEpg = await _storage.getSetting('showEpg', true);
      _adultModeUnlocked = await _storage.isAdultModeUnlocked();
      _adultModeEnabled = await _storage.getSetting('adultModeEnabled', false);
      _volume = await _storage.getSetting('volume', 1.0);
      _preferredQuality = await _storage.getSetting('preferredQuality', 'auto');
      _enableSubtitles = await _storage.getSetting('enableSubtitles', false);
      _secretClickCount = await _storage.getAdultClicks();
      notifyListeners();
    } catch (e) {
      // Usa valores padrão em caso de erro
    }
  }

  /// Define autoPlay
  Future<void> setAutoPlay(bool value) async {
    _autoPlay = value;
    await _storage.setSetting('autoPlay', value);
    notifyListeners();
  }

  /// Define showEpg
  Future<void> setShowEpg(bool value) async {
    _showEpg = value;
    await _storage.setSetting('showEpg', value);
    notifyListeners();
  }

  /// Define volume
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await _storage.setSetting('volume', _volume);
    notifyListeners();
  }

  /// Define qualidade preferida
  Future<void> setPreferredQuality(String value) async {
    _preferredQuality = value;
    await _storage.setSetting('preferredQuality', value);
    notifyListeners();
  }

  /// Define legendas
  Future<void> setEnableSubtitles(bool value) async {
    _enableSubtitles = value;
    await _storage.setSetting('enableSubtitles', value);
    notifyListeners();
  }

  /// Processa clique secreto para desbloquear modo adulto
  Future<bool> processSecretClick() async {
    _secretClickCount++;
    await _storage.setAdultClicks(_secretClickCount);

    if (_secretClickCount >= _secretClickThreshold && !_adultModeUnlocked) {
      _adultModeUnlocked = true;
      await _storage.setAdultModeUnlocked(true);
      notifyListeners();
      return true; // Desbloqueado!
    }

    notifyListeners();
    return false;
  }

  /// Reseta contador de cliques secretos
  Future<void> resetSecretClicks() async {
    _secretClickCount = 0;
    await _storage.setAdultClicks(0);
    notifyListeners();
  }

  /// Ativa/desativa modo adulto (requer desbloqueio)
  Future<void> setAdultModeEnabled(bool value) async {
    if (!_adultModeUnlocked) return;
    
    _adultModeEnabled = value;
    await _storage.setSetting('adultModeEnabled', value);
    notifyListeners();
  }

  /// Bloqueia modo adulto novamente
  Future<void> lockAdultMode() async {
    _adultModeUnlocked = false;
    _adultModeEnabled = false;
    _secretClickCount = 0;
    await _storage.setAdultModeUnlocked(false);
    await _storage.setSetting('adultModeEnabled', false);
    await _storage.setAdultClicks(0);
    notifyListeners();
  }

  /// Reseta todas as configurações
  Future<void> resetSettings() async {
    _autoPlay = true;
    _showEpg = true;
    _volume = 1.0;
    _preferredQuality = 'auto';
    _enableSubtitles = false;
    
    await _storage.setSetting('autoPlay', true);
    await _storage.setSetting('showEpg', true);
    await _storage.setSetting('volume', 1.0);
    await _storage.setSetting('preferredQuality', 'auto');
    await _storage.setSetting('enableSubtitles', false);
    
    notifyListeners();
  }
}
