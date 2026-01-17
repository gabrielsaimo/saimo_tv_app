import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Serviço de armazenamento local
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  /// Inicializa o serviço
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Garante que o serviço está inicializado
  Future<SharedPreferences> _getPrefs() async {
    if (_prefs == null) {
      await init();
    }
    return _prefs!;
  }

  // ===== Favoritos =====

  static const String _favoritesKey = 'saimo_tv_favorites';

  Future<List<String>> getFavorites() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_favoritesKey) ?? [];
  }

  Future<void> saveFavorites(List<String> favorites) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_favoritesKey, favorites);
  }

  Future<void> addFavorite(String channelId) async {
    final favorites = await getFavorites();
    if (!favorites.contains(channelId)) {
      favorites.add(channelId);
      await saveFavorites(favorites);
    }
  }

  Future<void> removeFavorite(String channelId) async {
    final favorites = await getFavorites();
    favorites.remove(channelId);
    await saveFavorites(favorites);
  }

  Future<bool> isFavorite(String channelId) async {
    final favorites = await getFavorites();
    return favorites.contains(channelId);
  }

  // ===== Último canal assistido =====

  static const String _lastChannelKey = 'saimo_tv_last_channel';

  Future<String?> getLastChannel() async {
    final prefs = await _getPrefs();
    return prefs.getString(_lastChannelKey);
  }

  Future<void> saveLastChannel(String channelId) async {
    final prefs = await _getPrefs();
    await prefs.setString(_lastChannelKey, channelId);
  }

  // ===== Configurações =====

  static const String _settingsKey = 'saimo_tv_settings';

  Future<Map<String, dynamic>> getSettings() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_settingsKey);
    if (json != null) {
      return jsonDecode(json) as Map<String, dynamic>;
    }
    return _defaultSettings;
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await _getPrefs();
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }

  Future<T> getSetting<T>(String key, T defaultValue) async {
    final settings = await getSettings();
    return settings[key] as T? ?? defaultValue;
  }

  Future<void> setSetting<T>(String key, T value) async {
    final settings = await getSettings();
    settings[key] = value;
    await saveSettings(settings);
  }

  static const Map<String, dynamic> _defaultSettings = {
    'autoPlay': true,
    'volume': 1.0,
    'showEpg': true,
    'adultModeUnlocked': false,
    'adultModeEnabled': false,
    'lastVolume': 1.0,
    'preferredQuality': 'auto',
    'enableSubtitles': false,
  };

  // ===== Modo Adulto =====

  static const String _adultModeKey = 'saimo_tv_adult_mode';
  static const String _adultClicksKey = 'saimo_tv_adult_clicks';

  Future<bool> isAdultModeUnlocked() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_adultModeKey) ?? false;
  }

  Future<void> setAdultModeUnlocked(bool unlocked) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_adultModeKey, unlocked);
  }

  Future<int> getAdultClicks() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_adultClicksKey) ?? 0;
  }

  Future<void> setAdultClicks(int clicks) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_adultClicksKey, clicks);
  }

  // ===== Histórico =====

  static const String _historyKey = 'saimo_tv_history';
  static const int _maxHistoryItems = 50;

  Future<List<String>> getHistory() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_historyKey) ?? [];
  }

  Future<void> addToHistory(String channelId) async {
    final history = await getHistory();
    
    // Remove se já existe para mover para o início
    history.remove(channelId);
    
    // Adiciona no início
    history.insert(0, channelId);
    
    // Limita o tamanho
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }
    
    final prefs = await _getPrefs();
    await prefs.setStringList(_historyKey, history);
  }

  Future<void> clearHistory() async {
    final prefs = await _getPrefs();
    await prefs.remove(_historyKey);
  }

  // ===== Progresso de Filmes/Séries =====

  static const String _movieProgressPrefix = 'saimo_tv_movie_progress_';

  Future<int> getMovieProgress(String movieId) async {
    final prefs = await _getPrefs();
    return prefs.getInt('$_movieProgressPrefix$movieId') ?? 0;
  }

  Future<void> saveMovieProgress(String movieId, int seconds) async {
    final prefs = await _getPrefs();
    await prefs.setInt('$_movieProgressPrefix$movieId', seconds);
  }

  Future<void> clearMovieProgress(String movieId) async {
    final prefs = await _getPrefs();
    await prefs.remove('$_movieProgressPrefix$movieId');
  }

  // ===== Favoritos de Filmes =====

  static const String _movieFavoritesKey = 'saimo_tv_movie_favorites';

  Future<List<String>> getMovieFavorites() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_movieFavoritesKey) ?? [];
  }

  Future<void> saveMovieFavorites(List<String> favorites) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_movieFavoritesKey, favorites);
  }

  Future<void> addMovieFavorite(String movieId) async {
    final favorites = await getMovieFavorites();
    if (!favorites.contains(movieId)) {
      favorites.add(movieId);
      await saveMovieFavorites(favorites);
    }
  }

  Future<void> removeMovieFavorite(String movieId) async {
    final favorites = await getMovieFavorites();
    favorites.remove(movieId);
    await saveMovieFavorites(favorites);
  }

  // ===== Último Modo (TV ou Filmes) =====

  static const String _lastModeKey = 'saimo_tv_last_mode';

  Future<String> getLastMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_lastModeKey) ?? 'tv';
  }

  Future<void> saveLastMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_lastModeKey, mode);
  }

  // ===== Limpar tudo =====

  Future<void> clearAll() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }
}
