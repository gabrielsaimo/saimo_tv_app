import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../services/json_catalog_service.dart';
import '../services/storage_service.dart';

/// Provider otimizado para gerenciar filmes e séries
/// Features: lazy loading, paginação, cache inteligente, isolates
/// Agora usa catálogo JSON pré-processado para melhor performance
class MoviesProvider with ChangeNotifier {
  final JsonCatalogService _catalogService = JsonCatalogService();
  
  // Estado
  List<Movie> _allMovies = [];
  Map<String, List<Movie>> _moviesByCategory = {};
  Map<String, List<Movie>> _moviesByGenre = {}; // Mapeamento por gênero
  List<GroupedSeries> _groupedSeries = [];
  bool _isLoading = false;
  String? _error;
  String _selectedCategory = 'Todos';
  String _selectedGenre = ''; // Gênero selecionado para filtro
  String _searchQuery = '';
  MovieFilterType _filterType = MovieFilterType.all;
  bool _showAdultContent = false;

  // === PAGINAÇÃO ===
  static const int _pageSize = 30; // Reduzido para Fire TV
  Map<String, int> _categoryLoadedCount = {};
  
  int get pageSize => _pageSize;

  // Getters
  List<Movie> get allMovies => _allMovies;
  Map<String, List<Movie>> get moviesByCategory => _moviesByCategory;
  Map<String, List<Movie>> get moviesByGenre => _moviesByGenre;
  List<GroupedSeries> get groupedSeries => _groupedSeries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  String get selectedGenre => _selectedGenre;
  String get searchQuery => _searchQuery;
  MovieFilterType get filterType => _filterType;
  bool get showAdultContent => _showAdultContent;
  
  /// Lista de todos os gêneros disponíveis
  List<String> get availableGenres {
    final genres = _moviesByGenre.keys.toList();
    genres.sort();
    return genres;
  }
  
  /// Gêneros com contagem
  Map<String, int> get genresWithCount {
    final result = <String, int>{};
    for (final entry in _moviesByGenre.entries) {
      result[entry.key] = entry.value.length;
    }
    return result;
  }

  /// Ordem preferencial das categorias (principais primeiro)
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

  /// Lista de categorias disponíveis (filtradas por tipo selecionado)
  List<String> get availableCategories {
    // Pega todas as categorias do mapa
    var categories = _moviesByCategory.keys.toList();
    
    // Filtra por tipo se necessário
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
    
    // Ordena categorias: primeiro as conhecidas, depois alfabeticamente
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
  
  /// Categorias com contagem para exibição na "Todos"
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
  
  /// Obtém filmes de uma categoria específica (filtrados por tipo)
  List<Movie> getMoviesForCategory(String category) {
    final movies = _moviesByCategory[category] ?? [];
    return _filteredByType(movies);
  }
  
  /// Carrega mais itens de uma categoria (scroll infinito)
  void loadMoreForCategory(String category) {
    final current = _categoryLoadedCount[category] ?? _pageSize;
    final movies = _filteredByType(_moviesByCategory[category] ?? []);
    
    if (current < movies.length) {
      _categoryLoadedCount[category] = (current + _pageSize).clamp(0, movies.length);
      notifyListeners();
    }
  }
  
  /// Verifica se tem mais itens
  bool hasMoreForCategory(String category) {
    final current = _categoryLoadedCount[category] ?? _pageSize;
    final movies = _filteredByType(_moviesByCategory[category] ?? []);
    return current < movies.length;
  }
  
  /// Obtém séries agrupadas de uma categoria específica
  List<GroupedSeries> getSeriesForCategory(String category) {
    debugPrint('🔍 getSeriesForCategory: category="$category"');
    debugPrint('   _groupedSeries.length=${_groupedSeries.length}');
    if (_groupedSeries.isNotEmpty) {
      debugPrint('   Primeiras 3 categorias: ${_groupedSeries.take(3).map((s) => s.category).toList()}');
    }
    var series = _groupedSeries.where((s) => s.category == category).toList();
    debugPrint('   Encontradas após filtro: ${series.length}');
    if (!_showAdultContent) {
      series = series.where((s) => !s.isAdult).toList();
    }
    return series;
  }

  /// Filmes da categoria selecionada
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
    
    // Retorna TODOS - ListView.builder renderiza apenas os visíveis
    return movies;
  }

  /// Séries agrupadas filtradas (LIMITADO para performance)
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
    
    // Retorna TODAS - ListView.builder renderiza apenas as visíveis
    return series;
  }

  /// Filtra por tipo (filme/série)
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

  /// Carrega todos os filmes e séries dos JSONs (lazy loading por categoria)
  Future<void> loadMovies() async {
    if (_isLoading) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Verifica se modo adulto está desbloqueado
      final storage = StorageService();
      _showAdultContent = await storage.isAdultModeUnlocked();

      // Carrega índice de categorias primeiro (leve)
      final categories = await _catalogService.loadCategoriesIndex();
      
      // Carrega todas as categorias dos JSONs
      final allMovies = <Movie>[];
      final byCategory = <String, List<Movie>>{};
      final byGenre = <String, List<Movie>>{}; // Mapeamento por gênero
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
        
        // Mapeia por gênero
        for (final movie in categoryMovies) {
          final genres = movie.tmdb?.genres ?? [];
          for (final genre in genres) {
            byGenre.putIfAbsent(genre, () => []).add(movie);
          }
        }
      }
      
      _allMovies = allMovies;
      _moviesByCategory = byCategory;
      _moviesByGenre = byGenre;
      _groupedSeries = groupedSeriesList;
      
      // Conta itens com cast para debug
      final itemsWithCast = _allMovies.where((m) => m.tmdb?.cast != null && m.tmdb!.cast!.isNotEmpty).length;
      
      debugPrint('🎬 DEBUG loadMovies:');
      debugPrint('   _allMovies.length=${_allMovies.length}');
      debugPrint('   Itens com cast: $itemsWithCast');
      debugPrint('   _moviesByCategory.keys=${_moviesByCategory.keys.toList()}');
      debugPrint('   _groupedSeries.length=${_groupedSeries.length}');
      if (_groupedSeries.isNotEmpty) {
        final categories = _groupedSeries.map((s) => s.category).toSet().toList();
        debugPrint('   Categorias em groupedSeries: $categories');
      }
      
      // Inicializa contadores de paginação
      _categoryLoadedCount = {};
      for (final cat in _moviesByCategory.keys) {
        _categoryLoadedCount[cat] = _pageSize;
      }
      
      _error = null;
      debugPrint('✅ Catálogo JSON carregado: ${_allMovies.length} itens em ${_moviesByCategory.length} categorias');
      debugPrint('   📊 ${_moviesByGenre.length} gêneros mapeados');
    } catch (e) {
      _error = 'Erro ao carregar filmes: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Seleciona uma categoria
  void selectCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  /// Define o filtro de tipo
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

  /// Define a query de busca
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Limpa a busca
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }
  
  /// Seleciona um gênero para filtro
  void selectGenre(String genre) {
    _selectedGenre = genre;
    notifyListeners();
  }
  
  /// Limpa o filtro de gênero
  void clearGenreFilter() {
    _selectedGenre = '';
    notifyListeners();
  }
  
  /// Obtém filmes por gênero
  List<Movie> getMoviesByGenre(String genre) {
    return _moviesByGenre[genre] ?? [];
  }
  
  /// Busca filmes/séries por nome (título TMDB ou nome)
  List<Movie> searchByName(String query) {
    if (query.isEmpty) return [];
    final lowerQuery = query.toLowerCase();
    return _allMovies.where((movie) {
      final name = movie.name.toLowerCase();
      final tmdbTitle = movie.tmdb?.title?.toLowerCase() ?? '';
      final originalTitle = movie.tmdb?.originalTitle?.toLowerCase() ?? '';
      return name.contains(lowerQuery) || 
             tmdbTitle.contains(lowerQuery) || 
             originalTitle.contains(lowerQuery);
    }).toList();
  }
  
  /// Busca filmes/séries por ID do TMDB
  Movie? findByTmdbId(int tmdbId) {
    try {
      return _allMovies.firstWhere((m) => m.tmdb?.id == tmdbId);
    } catch (_) {
      return null;
    }
  }
  
  /// Busca filmes/séries que tenham um ator específico no elenco
  List<Movie> findByActorId(int actorId) {
    debugPrint('🔍 findByActorId($actorId) - Total filmes: ${_allMovies.length}');
    final results = _allMovies.where((movie) {
      final cast = movie.tmdb?.cast ?? [];
      return cast.any((actor) => actor.id == actorId);
    }).toList();
    debugPrint('   Encontrados: ${results.length}');
    return results;
  }
  
  /// Busca filmes/séries que tenham um ator específico pelo nome
  List<Movie> findByActorName(String actorName) {
    debugPrint('🔍 findByActorName($actorName) - Total filmes: ${_allMovies.length}');
    final lowerName = actorName.toLowerCase();
    final results = _allMovies.where((movie) {
      final cast = movie.tmdb?.cast ?? [];
      return cast.any((actor) => actor.name.toLowerCase().contains(lowerName));
    }).toList();
    debugPrint('   Encontrados: ${results.length}');
    return results;
  }

  /// Busca um filme/episódio pelo ID
  Movie? getMovieById(String id) {
    try {
      return _allMovies.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Busca uma série agrupada pelo ID
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
      
      // Recarrega os dados
      _catalogService.clearCache();
      await loadMovies();
    }
  }

  /// Limpa cache e recarrega
  Future<void> refresh() async {
    _catalogService.clearCache();
    await loadMovies();
  }

  /// Obtém estatísticas
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
}

/// Tipo de filtro de conteúdo
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
