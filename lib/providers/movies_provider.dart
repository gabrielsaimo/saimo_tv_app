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

  /// Lista de categorias disponíveis (do índice do catálogo)
  List<String> get availableCategories {
    if (!_catalogService.isIndexLoaded) return ['Todos'];
    
    var categories = _catalogService.categories.map((c) => c.name).toList();
    
    // Filtro por tipo se necessário (baseado na info da categoria se possível, 
    // mas por hora mantemos a lista completa e filtramos o conteúdo)
    // Se quisermos filtrar categorias vazias, precisaríamos carregar tudo, o que não queremos.
    // Então retornamos todas do índice.
    
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
  /// Agora suporta busca global lazy-loaded via CatalogService se necessário
  List<Movie> get filteredMovies {
    // Se não tem busca, retorna da categoria atual
    if (_searchQuery.isEmpty) {
      return currentCategoryMovies;
    }
    
    // Se tem busca, filtramos o que temos em memória (loaded)
    // Nota: Para busca global REAL em todo catálogo (mesmo não carregado),
    // precisaríamos usar uma chamada async e armazenar o resultado em uma lista separada de busca.
    // Como filteredMovies é um getter, não pode ser async.
    // Vamos filtrar o que temos carregado (_allMovies).
    // Se o usuário quiser buscar tudo, idealmente usaríamos um método 'performSearch' que popula uma lista 'searchResults'.
    // Para este fix rápido, vamos manter filtragem em memória mas sabendo que é parcial.
    
    final query = _searchQuery.toLowerCase();
    return _allMovies.where((movie) {
      final searchable = '${movie.name} ${movie.seriesName ?? ''} ${movie.category}'.toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  // Lista de resultados de busca global (async)
  List<Movie> _globalSearchResults = [];
  List<Movie> get globalSearchResults => _globalSearchResults;
  bool _isSearchingGlobal = false;
  bool get isSearchingGlobal => _isSearchingGlobal;

  /// Executa busca global usando o serviço de catálogo
  Future<void> performGlobalSearch(String query) async {
    if (query.length < 3) return;
    
    _isSearchingGlobal = true;
    notifyListeners();
    
    try {
      final results = await _catalogService.search(query, includeAdult: _showAdultContent);
      _globalSearchResults = results;
    } catch (e) {
      debugPrint('Erro busca global: $e');
      _globalSearchResults = [];
    } finally {
      _isSearchingGlobal = false;
      notifyListeners();
    }
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

  /// Carrega filmes e séries (apenas índice e categorias iniciais)
  Future<void> loadMovies() async {
    if (_isLoading) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final storage = StorageService();
      _showAdultContent = await storage.isAdultModeUnlocked();

      // 1. Carrega índice
      await _catalogService.loadCategoriesIndex();
      
      // 2. Carrega APENAS a primeira categoria (Lançamentos) para ter algo na tela
      // Isso evita o travamento inicial de carregar 50 JSONs
      if (availableCategories.length > 1) {
        final firstCategory = availableCategories[1]; // [0] é Todos
        await loadCategory(firstCategory);
      }
      
      _error = null;
    } catch (e) {
      _error = 'Erro ao carregar catálogo: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carrega uma categoria específica sob demanda
  Future<void> loadCategory(String categoryName) async {
    // Se já carregou, ignora (exceto se for refresh forçado, mas isso seria outro metodo)
    if (_moviesByCategory.containsKey(categoryName)) return;

    final catInfo = _catalogService.getCategoryByName(categoryName);
    if (catInfo == null) return;

    // Se for adulto e não tiver permissão, ignora
    if (catInfo.isAdult && !_showAdultContent) return;

    try {
      debugPrint('📥 MoviesProvider: Carregando $categoryName...');
      final result = await _catalogService.loadCategory(catInfo.file);
      
      if (result != null) {
        _addCategoryDataToMemory(categoryName, result);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao carregar categoria $categoryName: $e');
    }
  }

  /// Adiciona dados de uma categoria carregada às listas em memória
  void _addCategoryDataToMemory(String categoryName, CategoryParseResult result) {
    // Combina
    final categoryMovies = [...result.movies, ...result.series];
    
    // Atualiza mapa de categorias
    _moviesByCategory[categoryName] = categoryMovies;
    
    // Atualiza lista geral (cuidado com duplicatas se a mesma movie estiver em várias cats)
    // Para simplificar e performance, vamos adicionar apenas se não tiver ID duplicado seria caro verificar tudo.
    // Mas como Lazy Loading implica que _allMovies não é "ALL" e sim "ALL LOADED", ok.
    _allMovies.addAll(categoryMovies); 
    // Nota: Em um app real complexo, usaríamos um Map<Id, Movie> para _allMovies para evitar dups.
    // Mas aqui vamos confiar que categorias são disjuntas ou aceitar dups por enquanto para não travar iterando tudo.

    // Atualiza grouped series
    _groupedSeries.addAll(result.groupedSeries);

    // Mapeia por gênero (apenas dos novos itens)
    for (final movie in categoryMovies) {
      final genres = movie.tmdb?.genres ?? [];
      for (final genre in genres) {
        _moviesByGenre.putIfAbsent(genre, () => []).add(movie);
      }
    }
    
    // Inicializa contador de paginação
    _categoryLoadedCount[categoryName] = _pageSize;
  }


  /// Seleciona uma categoria e carrega se necessário
  void selectCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
      
      if (category != 'Todos' && !_moviesByCategory.containsKey(category)) {
        loadCategory(category);
      }
    }
  }

  /// Verifica se uma categoria já foi carregada
  bool isCategoryLoaded(String category) {
    if (category == 'Todos') return true;
    return _moviesByCategory.containsKey(category);
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
    if (query.length >= 3) {
      performGlobalSearch(query);
    } else {
      _globalSearchResults = [];
    }
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
