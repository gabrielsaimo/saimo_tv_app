import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';

/// Informações de uma categoria do catálogo JSON
class JsonCategoryInfo {
  final String name;
  final String file;
  final int count;
  final bool isAdult;

  const JsonCategoryInfo({
    required this.name,
    required this.file,
    required this.count,
    required this.isAdult,
  });

  factory JsonCategoryInfo.fromJson(Map<String, dynamic> json) {
    return JsonCategoryInfo(
      name: json['name'] as String,
      file: json['file'] as String,
      count: json['count'] as int? ?? 0,
      isAdult: json['isAdult'] as bool? ?? false,
    );
  }
  
  /// ID gerado a partir do nome do arquivo
  String get id => file.replaceAll('.json', '');
}

/// Resultado do parsing de uma categoria
class CategoryParseResult {
  final List<Movie> movies;
  final List<Movie> series;
  final List<GroupedSeries> groupedSeries;
  final String categoryName;

  const CategoryParseResult({
    required this.movies,
    required this.series,
    required this.groupedSeries,
    required this.categoryName,
  });
}

/// Serviço otimizado para carregar catálogo a partir de arquivos JSON
/// 
/// Vantagens sobre o parser M3U8:
/// - Dados já estruturados e prontos para uso
/// - Carregamento muito mais rápido
/// - Suporte a lazy loading por categoria
/// - Menor uso de memória (carrega sob demanda)
/// - Dados enriquecidos com TMDB (poster, sinopse, elenco, etc)
class JsonCatalogService {
  static final JsonCatalogService _instance = JsonCatalogService._internal();
  factory JsonCatalogService() => _instance;
  JsonCatalogService._internal();

  // === Configurações ===
  // IMPORTANTE: Agora usa a pasta json/enriched que contém dados TMDB
  static const String _jsonPath = 'json/enriched';
  static const String _categoriesPath = 'json/categories.json'; // categories.json fica na pasta json/
  static const int _maxCategoriesInMemory = 8;
  static const int _cacheTTLMinutes = 60;

  // === Cache ===
  List<JsonCategoryInfo>? _categoriesIndex;
  final Map<String, CategoryParseResult> _categoryCache = {};
  final List<String> _cacheOrder = []; // LRU order
  bool _isLoadingIndex = false;

  // === Stats ===
  int _totalMovies = 0;
  int _totalSeries = 0;

  // === Getters ===
  bool get isIndexLoaded => _categoriesIndex != null;
  List<JsonCategoryInfo> get categories => _categoriesIndex ?? [];
  int get totalMovies => _totalMovies;
  int get totalSeries => _totalSeries;
  int get cachedCategoriesCount => _categoryCache.length;

  /// Patterns para detectar episódios no nome
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

  /// Carrega o índice de categorias (leve)
  Future<List<JsonCategoryInfo>> loadCategoriesIndex() async {
    if (_categoriesIndex != null) {
      return _categoriesIndex!;
    }

    if (_isLoadingIndex) {
      while (_isLoadingIndex) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _categoriesIndex ?? [];
    }

    _isLoadingIndex = true;

    try {
      debugPrint('📂 Carregando índice de categorias JSON...');
      final stopwatch = Stopwatch()..start();

      final content = await rootBundle.loadString(_categoriesPath);
      final data = jsonDecode(content) as List<dynamic>;

      _categoriesIndex = data
          .map((c) => JsonCategoryInfo.fromJson(c as Map<String, dynamic>))
          .toList();

      // Calcula totais
      _totalMovies = 0;
      _totalSeries = 0;
      for (final cat in _categoriesIndex!) {
        if (cat.name.contains('📺') || cat.name.toLowerCase().contains('series') || 
            cat.name.toLowerCase().contains('novela') || cat.name.toLowerCase().contains('dorama')) {
          _totalSeries += cat.count;
        } else {
          _totalMovies += cat.count;
        }
      }

      stopwatch.stop();
      debugPrint('✅ Índice carregado em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   📁 ${_categoriesIndex!.length} categorias');
      debugPrint('   🎬 $_totalMovies filmes, 📺 $_totalSeries séries');

      return _categoriesIndex!;
    } catch (e, stack) {
      debugPrint('❌ Erro ao carregar índice: $e');
      debugPrint('Stack: $stack');
      _categoriesIndex = [];
      return [];
    } finally {
      _isLoadingIndex = false;
    }
  }

  /// Carrega uma categoria específica (lazy loading)
  Future<CategoryParseResult?> loadCategory(String categoryFile, {bool includeAdult = false}) async {
    final cacheKey = categoryFile;
    
    // Verifica cache
    if (_categoryCache.containsKey(cacheKey)) {
      _updateLRU(cacheKey);
      debugPrint('📦 Cache hit: $cacheKey');
      return _categoryCache[cacheKey];
    }

    debugPrint('📥 Carregando categoria: $categoryFile');
    final stopwatch = Stopwatch()..start();

    try {
      final content = await rootBundle.loadString('$_jsonPath/$categoryFile');
      
      // Parse em isolate
      final result = await compute(_parseCategoryInIsolate, content);

      // Gerencia cache LRU
      _manageCacheSize();
      _categoryCache[cacheKey] = result;
      _cacheOrder.add(cacheKey);

      stopwatch.stop();
      debugPrint('✅ Categoria carregada em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   🎬 ${result.movies.length} filmes, 📺 ${result.series.length} séries');

      return result;
    } catch (e, stack) {
      debugPrint('❌ Erro ao carregar categoria $categoryFile: $e');
      debugPrint('Stack: $stack');
      return null;
    }
  }

  /// Carrega todas as categorias (para busca global ou exibição completa)
  Future<Map<String, CategoryParseResult>> loadAllCategories({bool includeAdult = false}) async {
    final index = await loadCategoriesIndex();
    final results = <String, CategoryParseResult>{};

    for (final cat in index) {
      if (!includeAdult && cat.isAdult) continue;
      
      final result = await loadCategory(cat.file, includeAdult: includeAdult);
      if (result != null) {
        results[cat.name] = result;
      }
    }

    return results;
  }

  /// Parse em isolate
  static CategoryParseResult _parseCategoryInIsolate(String content) {
    final data = jsonDecode(content) as List<dynamic>;
    
    final movies = <Movie>[];
    final series = <Movie>[];
    final groupedSeries = <GroupedSeries>[];
    String categoryName = '';

    for (final item in data) {
      final json = item as Map<String, dynamic>;
      final movie = Movie.fromJson(json);
      
      if (categoryName.isEmpty) {
        categoryName = movie.category;
      }

      // O novo formato JSON já define type corretamente
      // Séries têm type="series" e já vêm com episodes estruturados
      if (movie.type == MovieType.series) {
        series.add(movie);
        
        // Se a série já tem episódios estruturados, cria GroupedSeries
        if (movie.episodes != null && movie.episodes!.isNotEmpty) {
          final Map<int, List<Movie>> seasonMap = {};
          
          movie.episodes!.forEach((seasonStr, eps) {
            final seasonNum = int.tryParse(seasonStr) ?? 1;
            // Cria Movie para cada episódio para manter compatibilidade
            for (final ep in eps) {
              final epMovie = Movie(
                id: ep.id,
                name: ep.name,
                url: ep.url,
                logo: movie.posterUrl,
                category: movie.category,
                type: MovieType.series,
                isAdult: movie.isAdult,
                seriesName: movie.tmdb?.title ?? movie.name,
                season: seasonNum,
                episode: ep.episode,
                tmdb: movie.tmdb,
              );
              seasonMap.putIfAbsent(seasonNum, () => []).add(epMovie);
            }
          });
          
          // Ordena episódios por número
          final seasons = seasonMap.entries.map((e) {
            final eps = e.value..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
            return MapEntry(e.key, eps);
          }).toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          
          groupedSeries.add(GroupedSeries(
            id: movie.id,
            name: movie.tmdb?.title ?? movie.name,
            logo: movie.posterUrl,
            category: movie.category,
            seasons: Map.fromEntries(seasons),
            isAdult: movie.isAdult,
            tmdb: movie.tmdb,
          ));
        }
      } else {
        // Filmes
        movies.add(movie);
      }
    }

    groupedSeries.sort((a, b) => a.name.compareTo(b.name));
    
    debugPrint('📊 _parseCategoryInIsolate: categoryName="$categoryName"');
    debugPrint('   movies=${movies.length}, series=${series.length}, groupedSeries=${groupedSeries.length}');

    return CategoryParseResult(
      movies: movies,
      series: series,
      groupedSeries: groupedSeries,
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
      debugPrint('🧹 Removido do cache: $oldest');
    }
  }

  /// Busca em todas as categorias carregadas
  Future<List<Movie>> search(String query, {bool includeAdult = false}) async {
    final index = await loadCategoriesIndex();
    final results = <Movie>[];
    final lowerQuery = query.toLowerCase();

    for (final cat in index) {
      if (!includeAdult && cat.isAdult) continue;

      final categoryData = await loadCategory(cat.file, includeAdult: includeAdult);
      if (categoryData == null) continue;

      // Busca em filmes
      for (final movie in categoryData.movies) {
        if (movie.name.toLowerCase().contains(lowerQuery)) {
          results.add(movie);
        }
      }

      // Busca em séries
      for (final series in categoryData.series) {
        final searchable = '${series.name} ${series.seriesName ?? ''}'.toLowerCase();
        if (searchable.contains(lowerQuery)) {
          results.add(series);
        }
      }
    }

    return results;
  }

  /// Obtém categoria por ID (nome do arquivo sem .json)
  JsonCategoryInfo? getCategoryById(String id) {
    return _categoriesIndex?.firstWhere(
      (c) => c.id == id,
      orElse: () => const JsonCategoryInfo(name: '', file: '', count: 0, isAdult: false),
    );
  }

  /// Obtém categoria por nome
  JsonCategoryInfo? getCategoryByName(String name) {
    return _categoriesIndex?.firstWhere(
      (c) => c.name == name,
      orElse: () => const JsonCategoryInfo(name: '', file: '', count: 0, isAdult: false),
    );
  }

  /// Limpa todo o cache
  void clearCache() {
    _categoryCache.clear();
    _cacheOrder.clear();
    debugPrint('🧹 Cache JSON limpo');
  }

  /// Limpa tudo incluindo índice
  void clearAll() {
    clearCache();
    _categoriesIndex = null;
    debugPrint('🧹 Cache e índice JSON limpos');
  }
}
