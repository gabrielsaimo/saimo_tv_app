import 'package:flutter/material.dart';
import '../services/storage_service.dart';

/// Provider de favoritos
class FavoritesProvider with ChangeNotifier {
  final StorageService _storage = StorageService();
  
  List<String> _favorites = [];
  bool _isLoading = false;

  // Getters
  List<String> get favorites => _favorites;
  bool get isLoading => _isLoading;
  int get count => _favorites.length;

  /// Carrega favoritos do storage
  Future<void> loadFavorites() async {
    _isLoading = true;
    notifyListeners();

    try {
      _favorites = await _storage.getFavorites();
    } catch (e) {
      _favorites = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Verifica se um canal é favorito
  bool isFavorite(String channelId) {
    return _favorites.contains(channelId);
  }

  /// Adiciona ou remove um favorito
  Future<void> toggleFavorite(String channelId) async {
    if (_favorites.contains(channelId)) {
      _favorites.remove(channelId);
      await _storage.removeFavorite(channelId);
    } else {
      _favorites.add(channelId);
      await _storage.addFavorite(channelId);
    }
    notifyListeners();
  }

  /// Adiciona um favorito
  Future<void> addFavorite(String channelId) async {
    if (!_favorites.contains(channelId)) {
      _favorites.add(channelId);
      await _storage.addFavorite(channelId);
      notifyListeners();
    }
  }

  /// Remove um favorito
  Future<void> removeFavorite(String channelId) async {
    if (_favorites.contains(channelId)) {
      _favorites.remove(channelId);
      await _storage.removeFavorite(channelId);
      notifyListeners();
    }
  }

  /// Limpa todos os favoritos
  Future<void> clearFavorites() async {
    _favorites.clear();
    await _storage.saveFavorites([]);
    notifyListeners();
  }

  /// Reordena favoritos
  Future<void> reorderFavorites(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _favorites.removeAt(oldIndex);
    _favorites.insert(newIndex, item);
    await _storage.saveFavorites(_favorites);
    notifyListeners();
  }
}
