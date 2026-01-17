import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../services/json_catalog_service.dart';
import '../services/storage_service.dart';

/// Provider otimizado para gerenciar filmes e séries
/// Features: lazy loading, paginação, cache inteligente
/// Agora usa catálogo JSON pré-processado
class MoviesProvider with ChangeNotifier {
  final JsonCatalogService _catalogService = JsonCatalogService();
  
  // === ESTADO ===
  List<Movie> _allMovies = [];
  Map<String, List<Movie>> _moviesByCategory = {};
  List<GroupedSeries> _groupedSeries = [];
  bool _isLoading = false;
  String? _error;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';
  MovieFilterType _filterType = MovieFilterType.all;
  bool _showAdultContent = false;

  // === PAGINAÇÃO ===
  static const int _pageSize = 50;
  Map<String, int> _categoryLoadedCount = {};
  bool _hasMoreItems = true;

  // === GETTERS ===
  List<Movie> get allMovies => _allMovies;
  Map<String, List<Movie>> get moviesByCategory => _moviesByCategory;
  List<GroupedSeries> get groupedSeries => _groupedSeries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  MovieFilterType get filterType => _filterType;
  bool get showAdultContent => _showAdultContent;
  bool get hasMoreItems => _hasMoreItems;
  int get pageSize => _pageSize;

  /// Ordem preferencial das categorias
  static const List<String> _categoryOrder = [
    'Lançamentos',
    'Netflix',
    'Prime Video',
    'Disney+',
    'Max',
    'Paramount+',
    'Apple TV+',
    'Globoplay',
    'Novelas',
    'Doramas',
    'Animes',
    'Programas de TV',
  ];

  /// Lista de categorias disponíveis (filtradas por tipo)
  List<String> get availableCategories {
    var categories = _moviesByCategory.keys.toList();
    
    if (_filterType != MovieFilterType.all) {
      categories = categories.where((cat) {
        final movies = _moviesByCategory[cat] ?? [];
        if (_filterType == MovieFilterType.movies) {
          return movies.any((m) => m.type == MovieType.movie);
        } else if (_filterType == MovieFilterType.series) {
          return movies.any((m) => m.type == MovieType.series);
        }
        return true;
      }).toList();
    }
    
    categories.sort((a, b) {
      final indexA = _categoryOrder.indexOf(a);
      final indexB = _categoryOrder.indexOf(b);
      
      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(indexB);
      } else if (indexA != -1) {
        return -1;
      } else if (indexB != -1) {
        return 1;
      }
      return a.compareTo(b);
    });
    
    return ['Todos', ...categories];
  }
  
  /// Categorias com contagem
  Map<String, int> get categoriesWithCount {
    final result = <String, int>{};
    for (final cat in availableCategories) {
      if (cat == 'Todos') continue;
      final movies = _filteredByType(_moviesByCategory[cat] ?? []);
      if (movies.isNotEmpty) {
        result[cat] = movies.length;
      }
    }
    return result;
  }

  /// Obtém filmes paginados de uma categoria (LAZY LOADING)
  List<Movie> getMoviesForCategoryPaginated(String category, {int? limit}) {
    final movies = _moviesByCategory[category] ?? [];
    final filtered = _filteredByType(movies);
    
    final loadedCount = _categoryLoadedCount[category] ?? _pageSize;
    final maxItems = limit ?? loadedCount;
    
    return filtered.take(maxItems).toList();
  }

  /// Obtém filmes de uma categoria (todos)
  List<Movie> getMoviesForCategory(String category) {
    final movies = _moviesByCategory[category] ?? [];
    return _filteredByType(movies);
  }
  
  /// Carrega mais itens de uma categoria (para scroll infinito)
  void loadMoreForCategory(String category) {
    final current = _categoryLoadedCount[category] ?? _pageSize;
    final movies = _filteredByType(_moviesByCategory[category] ?? []);
    
    if (current < movies.length) {
      _categoryLoadedCount[category] = (current + _pageSize).clamp(0, movies.length);
      notifyListeners();
    }
  }
  
  /// Verifica se tem mais itens para carregar
  bool hasMoreForCategory(String category) {
    final current = _categoryLoadedCount[category] ?? _pageSize;
    final movies = _filteredByType(_moviesByCategory[category] ?? []);
    return current < movies.length;
  }

  /// Obtém séries de uma categoria
  List<GroupedSeries> getSeriesForCategory(String category) {
    var series = _groupedSeries.where((s) => s.category == category).toList();
    if (!_showAdultContent) {
      series = series.where((s) => !s.isAdult).toList();
    }
    return series;
  }

  /// Filmes da categoria atual
  List<Movie> get currentCategoryMovies {
    if (_selectedCategory == 'Todos') {
      return _filteredByType(_allMovies);
    }
    return _filteredByType(_moviesByCategory[_selectedCategory] ?? []);
  }

  /// Filmes filtrados pela busca (LIMITADO para performance)
  List<Movie> get filteredMovies {
    var movies = currentCategoryMovies;
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      movies = movies.where((movie) {
        final searchable = '${movie.name} ${movie.seriesName ?? ''} ${movie.category}'.toLowerCase();
        return searchable.contains(query);
      }).toList();
    }
    
    // Limita resultado para performance
    return movies.take(500).toList();
  }

  /// Séries filtradas (LIMITADO para performance)
  List<GroupedSeries> get filteredGroupedSeries {
    var series = _groupedSeries;
    
    if (_selectedCategory != 'Todos') {
      series = series.where((s) => s.category == _selectedCategory).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      series = series.where((s) => s.name.toLowerCase().contains(query)).toList();
    }
    
    if (!_showAdultContent) {
      series = series.where((s) => !s.isAdult).toList();
    }
    
    // Limita para performance
    return series.take(200).toList();
  }

  /// Filtra por tipo
  List<Movie> _filteredByType(List<Movie> movies) {
    switch (_filterType) {
      case MovieFilterType.movies:
        return movies.where((m) => m.type == MovieType.movie).toList();
      case MovieFilterType.series:
        return movies.where((m) => m.type == MovieType.series).toList();
      case MovieFilterType.all:
        return movies;
    }
  }

  /// Carrega todos os filmes dos JSONs (lazy loading por categoria)
  Future<void> loadMovies() async {
    if (_isLoading) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Verifica modo adulto
      final storage = StorageService();
      _showAdultContent = await storage.isAdultModeUnlocked();

      // Carrega índice de categorias primeiro (leve)
      final categories = await _catalogService.loadCategoriesIndex();
      
      // Carrega todas as categorias dos JSONs
      final allMovies = <Movie>[];
      final byCategory = <String, List<Movie>>{};
      final groupedSeriesList = <GroupedSeries>[];
      
      for (final cat in categories) {
        // Pula adultos se não habilitado
        if (cat.isAdult && !_showAdultContent) continue;
        
        final result = await _catalogService.loadCategory(cat.file, includeAdult: _showAdultContent);
        if (result == null) continue;
        
        // Combina filmes e séries
        final categoryMovies = [...result.movies, ...result.series];
        allMovies.addAll(categoryMovies);
        byCategory[cat.name] = categoryMovies;
        groupedSeriesList.addAll(result.groupedSeries);
      }
      
      _allMovies = allMovies;
      _moviesByCategory = byCategory;
      _groupedSeries = groupedSeriesList;
      
      // Inicializa contadores de paginação
      _categoryLoadedCount = {};
      for (final cat in _moviesByCategory.keys) {
        _categoryLoadedCount[cat] = _pageSize;
      }
      
      _error = null;
      debugPrint('✅ Catálogo JSON carregado: ${_allMovies.length} itens em ${_moviesByCategory.length} categorias');
    } catch (e) {
      _error = 'Erro ao carregar filmes: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Seleciona categoria
  void selectCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  /// Define filtro de tipo
  void setFilterType(MovieFilterType type) {
    if (_filterType != type) {
      _filterType = type;
      // Reset paginação ao mudar filtro
      _categoryLoadedCount = {};
      for (final cat in _moviesByCategory.keys) {
        _categoryLoadedCount[cat] = _pageSize;
      }
      notifyListeners();
    }
  }

  /// Define query de busca
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Limpa busca
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  /// Busca filme pelo ID
  Movie? getMovieById(String id) {
    try {
      return _allMovies.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Busca série pelo ID
  GroupedSeries? getSeriesById(String id) {
    try {
      return _groupedSeries.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Ativa/desativa modo adulto
  Future<void> setAdultMode(bool enabled) async {
    if (_showAdultContent != enabled) {
      _showAdultContent = enabled;
      _catalogService.clearCache();
      await loadMovies();
    }
  }

  /// Estatísticas
  Map<String, int> get statistics {
    return {
      'total': _allMovies.length,
      'movies': _allMovies.where((m) => m.type == MovieType.movie).length,
      'series': _allMovies.where((m) => m.type == MovieType.series).length,
      'categories': _moviesByCategory.keys.length,
      'groupedSeries': _groupedSeries.length,
      'adult': _allMovies.where((m) => m.isAdult).length,
    };
  }

  /// Limpa cache e recarrega
  Future<void> refresh() async {
    _catalogService.clearCache();
    await loadMovies();
  }
}

/// Tipo de filtro
enum MovieFilterType {
  all,
  movies,
  series;

  String get label {
    switch (this) {
      case MovieFilterType.all:
        return 'Todos';
      case MovieFilterType.movies:
        return 'Filmes';
      case MovieFilterType.series:
        return 'Séries';
    }
  }

  String get icon {
    switch (this) {
      case MovieFilterType.all:
        return '📽️';
      case MovieFilterType.movies:
        return '🎬';
      case MovieFilterType.series:
        return '📺';
    }
  }
}
