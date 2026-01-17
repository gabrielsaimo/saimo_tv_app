import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';

/// Índice de categoria do catálogo
class CategoryInfo {
  final String id;
  final String name;
  final int movieCount;
  final int seriesCount;
  final int adultCount;
  final int totalCount;
  final int pages;          // Número de páginas (para categorias grandes)
  final bool hasMovies;     // Se tem arquivo _movies separado

  const CategoryInfo({
    required this.id,
    required this.name,
    required this.movieCount,
    required this.seriesCount,
    required this.adultCount,
    required this.totalCount,
    this.pages = 1,
    this.hasMovies = false,
  });

  factory CategoryInfo.fromJson(Map<String, dynamic> json) {
    return CategoryInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      movieCount: json['movieCount'] as int? ?? 0,
      seriesCount: json['seriesCount'] as int? ?? 0,
      adultCount: json['adultCount'] as int? ?? 0,
      totalCount: json['totalCount'] as int? ?? 0,
      pages: json['pages'] as int? ?? 1,
      hasMovies: json['hasMovies'] as bool? ?? false,
    );
  }
  
  /// Verifica se a categoria é paginada
  bool get isPaginated => pages > 1;
}

/// Dados de uma categoria carregada
class CategoryData {
  final String category;
  final int page;
  final int totalPages;
  final List<Movie> movies;
  final List<Movie> series;
  final DateTime loadedAt;

  const CategoryData({
    required this.category,
    this.page = 1,
    this.totalPages = 1,
    required this.movies,
    required this.series,
    required this.loadedAt,
  });

  int get totalCount => movies.length + series.length;
  bool get hasMorePages => page < totalPages;
}

/// Serviço otimizado para carregamento LAZY de filmes/séries
/// 
/// Principais otimizações:
/// - Carrega apenas o índice de categorias inicialmente (~5KB)
/// - Carrega cada categoria sob demanda
/// - Cache LRU para manter apenas N categorias em memória
/// - Libera memória automaticamente quando ultrapassa limite
/// - Parsing em isolate para não travar a UI
class LazyMoviesService {
  static final LazyMoviesService _instance = LazyMoviesService._internal();
  factory LazyMoviesService() => _instance;
  LazyMoviesService._internal();

  // === Configurações ===
  static const int _maxCategoriesInMemory = 5; // Máximo de categorias no cache
  static const int _cacheTTLMinutes = 30; // Tempo de vida do cache
  static const String _catalogPath = 'assets/catalog';

  // === Estado ===
  List<CategoryInfo>? _categoryIndex;
  final Map<String, CategoryData> _categoryCache = {};
  final List<String> _cacheOrder = []; // LRU order
  bool _isLoadingIndex = false;
  int _totalMovies = 0;
  int _totalSeries = 0;
  int _totalAdult = 0;

  // === Getters ===
  bool get isIndexLoaded => _categoryIndex != null;
  List<CategoryInfo> get categories => _categoryIndex ?? [];
  int get totalMovies => _totalMovies;
  int get totalSeries => _totalSeries;
  int get totalAdult => _totalAdult;
  int get cachedCategoriesCount => _categoryCache.length;

  /// Carrega apenas o índice de categorias (leve, ~5KB)
  Future<List<CategoryInfo>> loadCategoryIndex() async {
    if (_categoryIndex != null) {
      return _categoryIndex!;
    }

    if (_isLoadingIndex) {
      // Aguarda carregamento em andamento
      while (_isLoadingIndex) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _categoryIndex ?? [];
    }

    _isLoadingIndex = true;

    try {
      debugPrint('📂 Carregando índice de categorias...');
      final stopwatch = Stopwatch()..start();

      final content = await rootBundle.loadString('$_catalogPath/index.json');
      final data = jsonDecode(content) as Map<String, dynamic>;

      _totalMovies = data['totalMovies'] as int? ?? 0;
      _totalSeries = data['totalSeries'] as int? ?? 0;
      _totalAdult = data['totalAdult'] as int? ?? 0;

      final categoriesJson = data['categories'] as List<dynamic>;
      _categoryIndex = categoriesJson
          .map((c) => CategoryInfo.fromJson(c as Map<String, dynamic>))
          .toList();

      stopwatch.stop();
      debugPrint('✅ Índice carregado em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   📁 ${_categoryIndex!.length} categorias');
      debugPrint('   🎬 $_totalMovies filmes, 📺 $_totalSeries séries');

      return _categoryIndex!;
    } catch (e, stack) {
      debugPrint('❌ Erro ao carregar índice: $e');
      debugPrint('Stack: $stack');
      _categoryIndex = [];
      return [];
    } finally {
      _isLoadingIndex = false;
    }
  }

  /// Carrega uma categoria específica (lazy loading)
  /// Para categorias paginadas, carrega a primeira página por padrão
  Future<CategoryData?> loadCategory(String categoryId, {bool includeAdult = false, int page = 1}) async {
    final cacheKey = '$categoryId${page > 1 ? "_p$page" : ""}';
    
    // Verifica cache primeiro
    if (_categoryCache.containsKey(cacheKey)) {
      final cached = _categoryCache[cacheKey]!;
      
      // Verifica se cache expirou
      final age = DateTime.now().difference(cached.loadedAt).inMinutes;
      if (age < _cacheTTLMinutes) {
        // Atualiza ordem LRU
        _updateLRU(cacheKey);
        debugPrint('📦 Cache hit: $cacheKey');
        return cached;
      } else {
        // Remove cache expirado
        _categoryCache.remove(cacheKey);
        _cacheOrder.remove(cacheKey);
      }
    }

    debugPrint('📥 Carregando categoria: $categoryId (página $page)');
    final stopwatch = Stopwatch()..start();

    try {
      // Determina o arquivo a carregar
      String filename;
      final categoryInfo = getCategoryById(categoryId);
      
      if (categoryInfo != null && categoryInfo.isPaginated && page > 0) {
        filename = '${categoryId}_p$page';
      } else {
        filename = categoryId;
      }
      
      // Carrega arquivo da categoria
      final content = await rootBundle.loadString('$_catalogPath/$filename.json');
      
      // Parse em isolate para não travar UI
      final data = await compute(_parseCategory, content);

      // Cria dados da categoria
      final categoryData = CategoryData(
        category: data['category'] as String,
        page: data['page'] as int? ?? 1,
        totalPages: data['totalPages'] as int? ?? 1,
        movies: (data['movies'] as List<dynamic>)
            .map((m) => Movie.fromJson(m as Map<String, dynamic>))
            .toList(),
        series: (data['series'] as List<dynamic>)
            .map((m) => Movie.fromJson(m as Map<String, dynamic>))
            .toList(),
        loadedAt: DateTime.now(),
      );

      // Gerencia cache LRU
      _addToCache(cacheKey, categoryData);

      stopwatch.stop();
      debugPrint('✅ Categoria carregada em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   🎬 ${categoryData.movies.length} filmes, 📺 ${categoryData.series.length} séries');

      return categoryData;
    } catch (e, stack) {
      debugPrint('❌ Erro ao carregar categoria $categoryId: $e');
      debugPrint('Stack: $stack');
      return null;
    }
  }

  /// Carrega filmes de uma categoria paginada (arquivo _movies)
  Future<List<Movie>> loadCategoryMovies(String categoryId) async {
    final cacheKey = '${categoryId}_movies';
    
    // Verifica cache
    if (_categoryCache.containsKey(cacheKey)) {
      return _categoryCache[cacheKey]!.movies;
    }
    
    try {
      final content = await rootBundle.loadString('$_catalogPath/${categoryId}_movies.json');
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      final movies = (data['movies'] as List<dynamic>)
          .map((m) => Movie.fromJson(m as Map<String, dynamic>))
          .toList();
      
      // Armazena no cache
      final categoryData = CategoryData(
        category: data['category'] as String,
        page: 0,
        totalPages: 1,
        movies: movies,
        series: [],
        loadedAt: DateTime.now(),
      );
      _addToCache(cacheKey, categoryData);
      
      return movies;
    } catch (e) {
      debugPrint('❌ Erro ao carregar filmes de $categoryId: $e');
      return [];
    }
  }

  /// Carrega próxima página de uma categoria
  Future<CategoryData?> loadNextPage(String categoryId, int currentPage) async {
    final categoryInfo = getCategoryById(categoryId);
    if (categoryInfo == null || currentPage >= categoryInfo.pages) {
      return null;
    }
    return loadCategory(categoryId, page: currentPage + 1);
  }

  /// Parse de categoria em isolate
  static Map<String, dynamic> _parseCategory(String content) {
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Carrega conteúdo adulto de uma categoria (separado)
  Future<List<Movie>> loadCategoryAdult(String categoryId) async {
    try {
      final content = await rootBundle.loadString('$_catalogPath/${categoryId}_adult.json');
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      return (data['items'] as List<dynamic>)
          .map((m) => Movie.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Arquivo não existe ou erro
      return [];
    }
  }

  /// Pré-carrega as categorias mais populares
  Future<void> preloadTopCategories({int count = 3}) async {
    await loadCategoryIndex();
    
    if (_categoryIndex == null || _categoryIndex!.isEmpty) return;

    final topCategories = _categoryIndex!.take(count);
    
    for (final cat in topCategories) {
      await loadCategory(cat.id);
    }
  }

  /// Busca em todas as categorias carregadas (rápido)
  List<Movie> searchInCache(String query) {
    final lower = query.toLowerCase();
    final results = <Movie>[];
    
    for (final data in _categoryCache.values) {
      for (final movie in data.movies) {
        if (_matchesSearch(movie, lower)) {
          results.add(movie);
        }
      }
      for (final series in data.series) {
        if (_matchesSearch(series, lower)) {
          results.add(series);
        }
      }
    }
    
    return results;
  }

  /// Busca global (carrega todas as categorias - usar com cuidado)
  Future<List<Movie>> searchAll(String query, {int limit = 50}) async {
    await loadCategoryIndex();
    
    final lower = query.toLowerCase();
    final results = <Movie>[];
    
    for (final cat in _categoryIndex!) {
      if (results.length >= limit) break;
      
      final data = await loadCategory(cat.id);
      if (data == null) continue;
      
      for (final movie in data.movies) {
        if (results.length >= limit) break;
        if (_matchesSearch(movie, lower)) {
          results.add(movie);
        }
      }
      
      for (final series in data.series) {
        if (results.length >= limit) break;
        if (_matchesSearch(series, lower)) {
          results.add(series);
        }
      }
    }
    
    return results;
  }

  bool _matchesSearch(Movie movie, String query) {
    final searchable = '${movie.name} ${movie.seriesName ?? ''}'.toLowerCase();
    return searchable.contains(query);
  }

  /// Adiciona ao cache com gerenciamento LRU
  void _addToCache(String categoryId, CategoryData data) {
    // Remove categoria mais antiga se cache cheio
    while (_cacheOrder.length >= _maxCategoriesInMemory) {
      final oldest = _cacheOrder.removeAt(0);
      _categoryCache.remove(oldest);
      debugPrint('🗑️ Cache eviction: $oldest');
    }

    _categoryCache[categoryId] = data;
    _cacheOrder.add(categoryId);
  }

  /// Atualiza ordem LRU (move para o final)
  void _updateLRU(String categoryId) {
    _cacheOrder.remove(categoryId);
    _cacheOrder.add(categoryId);
  }

  /// Limpa todo o cache
  void clearCache() {
    _categoryCache.clear();
    _cacheOrder.clear();
    debugPrint('🧹 Cache limpo');
  }

  /// Limpa índice e cache (força recarregamento)
  void clearAll() {
    _categoryIndex = null;
    _categoryCache.clear();
    _cacheOrder.clear();
    _totalMovies = 0;
    _totalSeries = 0;
    _totalAdult = 0;
    debugPrint('🧹 Tudo limpo');
  }

  /// Obtém estatísticas de memória
  Map<String, dynamic> getMemoryStats() {
    int cachedMovies = 0;
    int cachedSeries = 0;
    
    for (final data in _categoryCache.values) {
      cachedMovies += data.movies.length;
      cachedSeries += data.series.length;
    }

    return {
      'categoriesInMemory': _categoryCache.length,
      'maxCategories': _maxCategoriesInMemory,
      'cachedMovies': cachedMovies,
      'cachedSeries': cachedSeries,
      'totalMovies': _totalMovies,
      'totalSeries': _totalSeries,
      'cacheOrder': _cacheOrder,
    };
  }

  /// Obtém informação de uma categoria pelo nome
  CategoryInfo? getCategoryByName(String name) {
    if (_categoryIndex == null) return null;
    try {
      return _categoryIndex!.firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Obtém informação de uma categoria pelo ID
  CategoryInfo? getCategoryById(String id) {
    if (_categoryIndex == null) return null;
    try {
      return _categoryIndex!.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Verifica se uma categoria está no cache
  bool isCategoryLoaded(String categoryId) {
    return _categoryCache.containsKey(categoryId);
  }

  /// Obtém dados de uma categoria do cache (se disponível)
  CategoryData? getCategoryFromCache(String categoryId) {
    return _categoryCache[categoryId];
  }
}

/// Extensão para agrupar séries de uma CategoryData
extension CategoryDataGrouping on CategoryData {
  /// Agrupa episódios em séries
  List<GroupedSeries> get groupedSeries {
    final Map<String, List<Movie>> seriesMap = {};
    
    for (final episode in series) {
      if (episode.seriesName != null) {
        final key = episode.seriesName!;
        seriesMap.putIfAbsent(key, () => []).add(episode);
      }
    }
    
    final grouped = <GroupedSeries>[];
    
    for (final entry in seriesMap.entries) {
      final episodes = entry.value;
      if (episodes.isEmpty) continue;
      
      final first = episodes.first;
      
      final Map<int, List<Movie>> seasonMap = {};
      for (final ep in episodes) {
        final season = ep.season ?? 1;
        seasonMap.putIfAbsent(season, () => []).add(ep);
      }
      
      final seasons = seasonMap.entries.map((e) {
        final eps = e.value..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
        return MapEntry(e.key, eps);
      }).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      
      grouped.add(GroupedSeries(
        id: '${first.seriesName!.hashCode}_${category.hashCode}',
        name: first.seriesName!,
        logo: first.logo,
        category: category,
        seasons: Map.fromEntries(seasons),
        isAdult: first.isAdult,
      ));
    }
    
    grouped.sort((a, b) => a.name.compareTo(b.name));
    return grouped;
  }
}
