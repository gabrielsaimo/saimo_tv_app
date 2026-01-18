import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../services/storage_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider para gerenciar favoritos de filmes e séries
/// Armazena em cache local para acesso rápido
class MovieFavoritesProvider with ChangeNotifier {
  final StorageService _storage = StorageService();
  
  // Cache de IDs favoritos
  Set<String> _favoriteIds = {};
  
  // Cache de objetos Movie favoritos (para exibição rápida)
  List<Movie> _favoriteMovies = [];
  
  bool _isLoading = false;
  bool _isInitialized = false;

  // Getters
  Set<String> get favoriteIds => _favoriteIds;
  List<Movie> get favoriteMovies => _favoriteMovies;
  List<Movie> get favorites => _favoriteMovies; // Alias para facilitar uso
  bool get isLoading => _isLoading;
  int get count => _favoriteIds.length;
  bool get isEmpty => _favoriteIds.isEmpty;
  bool get isNotEmpty => _favoriteIds.isNotEmpty;

  /// Inicializa o provider carregando favoritos do cache
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      // Carrega IDs dos favoritos
      final ids = await _storage.getMovieFavorites();
      _favoriteIds = ids.toSet();
      
      // Carrega objetos Movie do cache
      await _loadCachedMovies();
      
      _isInitialized = true;
    } catch (e) {
      debugPrint('Erro ao carregar favoritos: $e');
      _favoriteIds = {};
      _favoriteMovies = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carrega os objetos Movie do cache local
  Future<void> _loadCachedMovies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('movie_favorites_cache');
      
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        _favoriteMovies = decoded
            .map((json) => Movie.fromJson(json as Map<String, dynamic>))
            .where((m) => _favoriteIds.contains(m.id))
            .toList();
      }
    } catch (e) {
      debugPrint('Erro ao carregar cache de favoritos: $e');
      _favoriteMovies = [];
    }
  }

  /// Salva os objetos Movie no cache local
  Future<void> _saveCachedMovies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_favoriteMovies.map((m) => m.toJson()).toList());
      await prefs.setString('movie_favorites_cache', json);
    } catch (e) {
      debugPrint('Erro ao salvar cache de favoritos: $e');
    }
  }

  /// Verifica se um filme/série é favorito
  bool isFavorite(String movieId) {
    return _favoriteIds.contains(movieId);
  }

  /// Adiciona ou remove um favorito
  Future<void> toggleFavorite(Movie movie) async {
    if (_favoriteIds.contains(movie.id)) {
      await removeFavorite(movie.id);
    } else {
      await addFavorite(movie);
    }
  }

  /// Adiciona um favorito
  Future<void> addFavorite(Movie movie) async {
    if (_favoriteIds.contains(movie.id)) return;

    _favoriteIds.add(movie.id);
    _favoriteMovies.insert(0, movie); // Adiciona no início
    notifyListeners();

    // Salva no storage
    await _storage.addMovieFavorite(movie.id);
    await _saveCachedMovies();
  }

  /// Remove um favorito
  Future<void> removeFavorite(String movieId) async {
    if (!_favoriteIds.contains(movieId)) return;

    _favoriteIds.remove(movieId);
    _favoriteMovies.removeWhere((m) => m.id == movieId);
    notifyListeners();

    // Remove do storage
    await _storage.removeMovieFavorite(movieId);
    await _saveCachedMovies();
  }

  /// Limpa todos os favoritos
  Future<void> clearFavorites() async {
    _favoriteIds.clear();
    _favoriteMovies.clear();
    notifyListeners();

    await _storage.saveMovieFavorites([]);
    await _saveCachedMovies();
  }

  /// Obtém filme favorito por ID (do cache)
  Movie? getFavoriteById(String movieId) {
    try {
      return _favoriteMovies.firstWhere((m) => m.id == movieId);
    } catch (_) {
      return null;
    }
  }

  /// Atualiza um filme no cache (quando dados TMDB são carregados)
  Future<void> updateFavorite(Movie movie) async {
    final index = _favoriteMovies.indexWhere((m) => m.id == movie.id);
    if (index >= 0) {
      _favoriteMovies[index] = movie;
      await _saveCachedMovies();
      notifyListeners();
    }
  }

  /// Filmes favoritos (não séries)
  List<Movie> get favoriteMoviesOnly {
    return _favoriteMovies.where((m) => m.type == MovieType.movie).toList();
  }

  /// Séries favoritas
  List<Movie> get favoriteSeriesOnly {
    return _favoriteMovies.where((m) => m.type == MovieType.series).toList();
  }
}
