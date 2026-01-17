import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';

/// Índice de categoria do catálogo JSON
class JsonCategoryIndex {
  final String id;
  final String name;
  final String file;
  final int count;
  final bool isAdult;

  const JsonCategoryIndex({
    required this.id,
    required this.name,
    required this.file,
    required this.count,
    required this.isAdult,
  });

  factory JsonCategoryIndex.fromJson(Map<String, dynamic> json) {
    final file = json['file'] as String;
    return JsonCategoryIndex(
      id: file.replaceAll('.json', ''),
      name: json['name'] as String,
      file: file,
      count: json['count'] as int? ?? 0,
      isAdult: json['isAdult'] as bool? ?? false,
    );
  }
}

/// Dados de uma categoria carregada
class JsonCategoryData {
  final String category;
  final List<Movie> movies;
  final List<Movie> series;
  final DateTime loadedAt;

  const JsonCategoryData({
    required this.category,
    required this.movies,
    required this.series,
    required this.loadedAt,
  });

  int get totalCount => movies.length + series.length;
}

/// Serviço otimizado para carregar catálogo JSON com lazy loading
/// 
/// Substitui o LazyMoviesService original para usar a pasta json/
/// com os arquivos categories.json e arquivos individuais por categoria
class JsonLazyService {
  static final JsonLazyService _instance = JsonLazyService._internal();
  factory JsonLazyService() => _instance;
  JsonLazyService._internal();

  // === Configurações ===
  // IMPORTANTE: Agora usa a pasta json/enriched que contém dados TMDB
  static const String _jsonPath = 'json/enriched';
  static const String _categoriesFile = 'json/categories.json'; // Caminho absoluto
  static const int _maxCategoriesInMemory = 8;
  static const int _cacheTTLMinutes = 60;

  // === Estado ===
  List<JsonCategoryIndex>? _categoryIndex;
  final Map<String, JsonCategoryData> _categoryCache = {};
  final List<String> _cacheOrder = [];
  bool _isLoadingIndex = false;
  int _totalMovies = 0;
  int _totalSeries = 0;
  int _totalAdult = 0;

  // === Getters ===
  bool get isIndexLoaded => _categoryIndex != null;
  List<JsonCategoryIndex> get categories => _categoryIndex ?? [];
  int get totalMovies => _totalMovies;
  int get totalSeries => _totalSeries;
  int get totalAdult => _totalAdult;
  int get cachedCategoriesCount => _categoryCache.length;

  /// Patterns para detectar episódios
  static final List<RegExp> _episodePatterns = [
    RegExp(r'S\d+\s*E\d+', caseSensitive: false),
    RegExp(r'T\d+\s*E\d+', caseSensitive: false),
    RegExp(r'\d+\s*x\s*\d+', caseSensitive: false),
    RegExp(r'Temporada\s*\d+', caseSensitive: false),
    RegExp(r'Temp\.?\s*\d+', caseSensitive: false),
    RegExp(r'Season\s*\d+', caseSensitive: false),
  ];

  /// Patterns para extrair info de série
  static final List<RegExp> _seriesInfoPatterns = [
    RegExp(r'^(.+?)\s*S(\d+)\s*E(\d+)', caseSensitive: false),
    RegExp(r'^(.+?)\s*T(\d+)\s*E(\d+)', caseSensitive: false),
    RegExp(r'^(.+?)\s*(\d+)\s*x\s*(\d+)', caseSensitive: false),
  ];

  /// Carrega o índice de categorias (leve, ~5KB)
  Future<List<JsonCategoryIndex>> loadCategoryIndex() async {
    if (_categoryIndex != null) {
      return _categoryIndex!;
    }

    if (_isLoadingIndex) {
      while (_isLoadingIndex) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _categoryIndex ?? [];
    }

    _isLoadingIndex = true;

    try {
      debugPrint('📂 Carregando índice de categorias JSON...');
      final stopwatch = Stopwatch()..start();

      final content = await rootBundle.loadString(_categoriesFile);
      final data = jsonDecode(content) as List<dynamic>;

      _categoryIndex = data
          .map((c) => JsonCategoryIndex.fromJson(c as Map<String, dynamic>))
          .toList();

      // Calcula totais
      _totalMovies = 0;
      _totalSeries = 0;
      _totalAdult = 0;
      for (final cat in _categoryIndex!) {
        if (cat.isAdult) {
          _totalAdult += cat.count;
        }
        // Estima séries vs filmes pelo nome
        if (cat.name.contains('📺') || 
            cat.name.toLowerCase().contains('series') ||
            cat.name.toLowerCase().contains('novela') ||
            cat.name.toLowerCase().contains('dorama')) {
          _totalSeries += cat.count;
        } else {
          _totalMovies += cat.count;
        }
      }

      stopwatch.stop();
      debugPrint('✅ Índice carregado em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   📁 ${_categoryIndex!.length} categorias');
      debugPrint('   🎬 $_totalMovies filmes, 📺 $_totalSeries séries, 🔞 $_totalAdult adulto');

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
  Future<JsonCategoryData?> loadCategory(String categoryId, {bool includeAdult = false}) async {
    // Verifica cache
    if (_categoryCache.containsKey(categoryId)) {
      final cached = _categoryCache[categoryId]!;
      final age = DateTime.now().difference(cached.loadedAt).inMinutes;
      if (age < _cacheTTLMinutes) {
        _updateLRU(categoryId);
        debugPrint('📦 Cache hit: $categoryId');
        return cached;
      } else {
        _categoryCache.remove(categoryId);
        _cacheOrder.remove(categoryId);
      }
    }

    debugPrint('📥 Carregando categoria: $categoryId');
    final stopwatch = Stopwatch()..start();

    try {
      final filename = '$categoryId.json';
      final content = await rootBundle.loadString('$_jsonPath/$filename');
      
      // Parse em isolate
      final parsed = await compute(_parseCategoryContent, content);

      final categoryData = JsonCategoryData(
        category: parsed.categoryName,
        movies: parsed.movies,
        series: parsed.series,
        loadedAt: DateTime.now(),
      );

      // Gerencia cache LRU
      _manageCacheSize();
      _categoryCache[categoryId] = categoryData;
      _cacheOrder.add(categoryId);

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

  /// Parse em isolate
  static _ParseResult _parseCategoryContent(String content) {
    final data = jsonDecode(content) as List<dynamic>;
    
    final movies = <Movie>[];
    final series = <Movie>[];
    String categoryName = '';

    for (final item in data) {
      final json = item as Map<String, dynamic>;
      final movie = Movie.fromJson(json);
      
      if (categoryName.isEmpty) {
        categoryName = movie.category;
      }

      // Detecta série pelo tipo ou padrão no nome
      final isSeries = movie.type == MovieType.series || _isSeriesByName(movie.name);
      
      if (isSeries) {
        final seriesInfo = _parseSeriesInfo(movie.name);
        if (seriesInfo != null) {
          series.add(movie.copyWith(
            type: MovieType.series,
            seriesName: seriesInfo.baseName,
            season: seriesInfo.season,
            episode: seriesInfo.episode,
          ));
        } else {
          series.add(movie.copyWith(type: MovieType.series));
        }
      } else {
        movies.add(movie);
      }
    }

    return _ParseResult(
      movies: movies,
      series: series,
      categoryName: categoryName,
    );
  }

  static bool _isSeriesByName(String name) {
    return _episodePatterns.any((pattern) => pattern.hasMatch(name));
  }

  static ({String baseName, int season, int episode})? _parseSeriesInfo(String name) {
    for (final pattern in _seriesInfoPatterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        return (
          baseName: match.group(1)!.trim(),
          season: int.parse(match.group(2)!),
          episode: int.parse(match.group(3)!),
        );
      }
    }
    return null;
  }

  void _updateLRU(String key) {
    _cacheOrder.remove(key);
    _cacheOrder.add(key);
  }

  void _manageCacheSize() {
    while (_categoryCache.length >= _maxCategoriesInMemory && _cacheOrder.isNotEmpty) {
      final oldest = _cacheOrder.removeAt(0);
      _categoryCache.remove(oldest);
      debugPrint('🗑️ Cache eviction: $oldest');
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

  /// Busca em categorias no cache
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

  /// Busca global (carrega todas as categorias)
  Future<List<Movie>> searchAll(String query, {int limit = 50, bool includeAdult = false}) async {
    await loadCategoryIndex();
    
    final lower = query.toLowerCase();
    final results = <Movie>[];
    
    for (final cat in _categoryIndex!) {
      if (results.length >= limit) break;
      if (!includeAdult && cat.isAdult) continue;
      
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

  /// Busca filmes/séries por ID do ator (em todas as categorias carregadas)
  Future<List<Movie>> findByActorId(int actorId, {bool includeAdult = false}) async {
    await loadCategoryIndex();
    
    final results = <Movie>[];
    final seenIds = <String>{};
    
    // Busca em todas as categorias
    for (final cat in _categoryIndex!) {
      if (!includeAdult && cat.isAdult) continue;
      
      final data = await loadCategory(cat.id);
      if (data == null) continue;
      
      for (final movie in [...data.movies, ...data.series]) {
        if (seenIds.contains(movie.id)) continue;
        
        final cast = movie.tmdb?.cast ?? [];
        if (cast.any((actor) => actor.id == actorId)) {
          results.add(movie);
          seenIds.add(movie.id);
        }
      }
    }
    
    debugPrint('🔍 findByActorId($actorId): encontrados ${results.length} itens');
    return results;
  }

  /// Busca filmes/séries por nome do ator (em todas as categorias carregadas)
  Future<List<Movie>> findByActorName(String actorName, {bool includeAdult = false}) async {
    await loadCategoryIndex();
    
    final lowerName = actorName.toLowerCase();
    final results = <Movie>[];
    final seenIds = <String>{};
    
    // Busca em todas as categorias
    for (final cat in _categoryIndex!) {
      if (!includeAdult && cat.isAdult) continue;
      
      final data = await loadCategory(cat.id);
      if (data == null) continue;
      
      for (final movie in [...data.movies, ...data.series]) {
        if (seenIds.contains(movie.id)) continue;
        
        final cast = movie.tmdb?.cast ?? [];
        if (cast.any((actor) => actor.name.toLowerCase().contains(lowerName))) {
          results.add(movie);
          seenIds.add(movie.id);
        }
      }
    }
    
    debugPrint('🔍 findByActorName($actorName): encontrados ${results.length} itens');
    return results;
  }

  /// Busca filme/série por TMDB ID (em todas as categorias carregadas)
  Future<Movie?> findByTmdbId(int tmdbId, {bool includeAdult = false}) async {
    await loadCategoryIndex();
    
    for (final cat in _categoryIndex!) {
      if (!includeAdult && cat.isAdult) continue;
      
      final data = await loadCategory(cat.id);
      if (data == null) continue;
      
      for (final movie in [...data.movies, ...data.series]) {
        if (movie.tmdb?.id == tmdbId) {
          debugPrint('🔍 findByTmdbId($tmdbId): encontrado ${movie.name}');
          return movie;
        }
      }
    }
    
    debugPrint('🔍 findByTmdbId($tmdbId): não encontrado');
    return null;
  }

  /// Obtém categoria pelo nome
  JsonCategoryIndex? getCategoryByName(String name) {
    return _categoryIndex?.firstWhere(
      (c) => c.name == name,
      orElse: () => const JsonCategoryIndex(id: '', name: '', file: '', count: 0, isAdult: false),
    );
  }

  /// Obtém categoria pelo ID
  JsonCategoryIndex? getCategoryById(String id) {
    return _categoryIndex?.firstWhere(
      (c) => c.id == id,
      orElse: () => const JsonCategoryIndex(id: '', name: '', file: '', count: 0, isAdult: false),
    );
  }

  /// Verifica se categoria está no cache
  bool isCategoryLoaded(String categoryId) {
    return _categoryCache.containsKey(categoryId);
  }

  /// Obtém dados do cache
  JsonCategoryData? getCategoryFromCache(String categoryId) {
    return _categoryCache[categoryId];
  }

  /// Limpa cache
  void clearCache() {
    _categoryCache.clear();
    _cacheOrder.clear();
    debugPrint('🧹 Cache JSON limpo');
  }

  /// Limpa tudo
  void clearAll() {
    _categoryIndex = null;
    _categoryCache.clear();
    _cacheOrder.clear();
    _totalMovies = 0;
    _totalSeries = 0;
    _totalAdult = 0;
    debugPrint('🧹 Cache e índice JSON limpos');
  }

  /// Estatísticas de memória
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
}

/// Classe auxiliar para resultado do parse
class _ParseResult {
  final List<Movie> movies;
  final List<Movie> series;
  final String categoryName;

  const _ParseResult({
    required this.movies,
    required this.series,
    required this.categoryName,
  });
}

/// Extensão para agrupar séries
extension JsonCategoryDataGrouping on JsonCategoryData {
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
