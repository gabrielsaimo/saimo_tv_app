import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
/// Carrega dados REMOTAMENTE do GitHub com cache local
/// Substitui o LazyMoviesService original para usar dados online
class JsonLazyService {
  static final JsonLazyService _instance = JsonLazyService._internal();
  factory JsonLazyService() => _instance;
  JsonLazyService._internal();

  // === Configurações ===
  /// URL base para carregar dados remotamente do GitHub
  static const String _remoteBaseUrl = 
      'https://raw.githubusercontent.com/gabrielsaimo/free-tv/main/public/data/enriched';
  
  /// Arquivo de categorias LOCAL (na pasta json/)
  static const String _localCategoriesFile = 'json/categories.json';
  
  /// Timeout para requisições HTTP
  static const Duration _httpTimeout = Duration(seconds: 30);
  
  /// Tempo de cache local (7 dias)
  static const Duration _localCacheTTL = Duration(days: 7);
  
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

  /// Carrega o índice de categorias (leve, ~5KB) - DO ARQUIVO LOCAL
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
      debugPrint('📂 Carregando índice de categorias LOCAL...');
      final stopwatch = Stopwatch()..start();

      // Carrega do arquivo local (assets)
      final content = await rootBundle.loadString(_localCategoriesFile);

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
  
  /// Busca conteúdo de URL remota
  Future<String?> _fetchFromRemote(String url) async {
    try {
      debugPrint('🌐 Buscando URL: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(_httpTimeout);
      
      if (response.statusCode == 200) {
        debugPrint('✅ HTTP 200 OK - ${response.body.length} bytes');
        return response.body;
      } else {
        debugPrint('❌ Erro HTTP ${response.statusCode}: $url');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Erro ao buscar $url: $e');
      return null;
    }
  }
  
  /// Carrega do cache local
  Future<String?> _loadFromLocalCache(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/json_cache/$filename');
      
      if (!file.existsSync()) {
        return null;
      }
      
      // Verifica se cache expirou
      final modified = file.lastModifiedSync();
      final age = DateTime.now().difference(modified);
      if (age > _localCacheTTL) {
        debugPrint('📁 Cache expirado: $filename');
        return null;
      }
      
      debugPrint('📁 Cache hit: $filename');
      return file.readAsStringSync();
    } catch (e) {
      debugPrint('⚠️ Erro ao ler cache: $e');
      return null;
    }
  }
  
  /// Salva no cache local
  Future<void> _saveToLocalCache(String filename, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/json_cache');
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      
      final file = File('${cacheDir.path}/$filename');
      await file.writeAsString(content);
      debugPrint('💾 Cache salvo: $filename');
    } catch (e) {
      debugPrint('⚠️ Erro ao salvar cache: $e');
    }
  }

  /// Carrega uma categoria específica (lazy loading)
  Future<JsonCategoryData?> loadCategory(String categoryId, {bool includeAdult = false}) async {
    // Verifica cache em memória
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
      
      // Tenta carregar do cache local primeiro
      String? content = await _loadFromLocalCache(filename);
      
      // Se não tem cache, carrega do GitHub
      if (content == null) {
        debugPrint('🌐 Buscando categoria do GitHub: $categoryId');
        final url = '$_remoteBaseUrl/$filename';
        content = await _fetchFromRemote(url);
        if (content != null) {
          await _saveToLocalCache(filename, content);
        }
      }
      
      if (content == null) {
        debugPrint('❌ Não foi possível carregar categoria: $categoryId');
        return null;
      }
      
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
    final results = await findBatchByTmdbIds([tmdbId], includeAdult: includeAdult);
    return results[tmdbId];
  }

  /// Busca múltiplos filmes/séries por lista de TMDB IDs (Busca em Lote Otimizada)
  /// Retorna um Map onde a chave é o ID do TMDB e o valor é o Movie encontrado.
  Future<Map<int, Movie>> findBatchByTmdbIds(List<int> tmdbIds, {bool includeAdult = false}) async {
    await loadCategoryIndex();
    
    final results = <int, Movie>{};
    final idsToFind = Set<int>.from(tmdbIds);
    
    // Se não há IDs para buscar, retorna vazio
    if (idsToFind.isEmpty) return results;

    debugPrint('🔍 findBatchByTmdbIds: Buscando ${idsToFind.length} itens...');
    
    // Otimização: Primeiro verifica nas categorias JÁ carregadas em memória (rápido)
    for (final cat in _categoryCache.keys) {
       final data = _categoryCache[cat];
       if (data == null) continue;
       
       // Verifica filmes
       for (final movie in data.movies) {
         if (movie.tmdb?.id != null && idsToFind.contains(movie.tmdb!.id)) {
           results[movie.tmdb!.id!] = movie;
           idsToFind.remove(movie.tmdb!.id); // Já achou, não precisa buscar mais
         }
       }
       // Verifica séries
       for (final series in data.series) {
         if (series.tmdb?.id != null && idsToFind.contains(series.tmdb!.id)) {
           results[series.tmdb!.id!] = series;
           idsToFind.remove(series.tmdb!.id);
         }
       }
       
       // Se achou tudo, retorna
       if (idsToFind.isEmpty) {
         debugPrint('✅ findBatchByTmdbIds: Todos encontrados no cache de memória');
         return results;
       }
    }

    // Se ainda faltam itens, busca nas categorias não carregadas (lento - I/O)
    // Ordena priorizando "Lançamentos" e "Primeiras" onde é mais provável ter hits
    final orderedCats = _categoryIndex!.toList()
      ..sort((a, b) {
         final aPriority = a.name.contains('Lançamento') ? 0 : 1;
         final bPriority = b.name.contains('Lançamento') ? 0 : 1;
         return aPriority.compareTo(bPriority);
      });

    for (final cat in orderedCats) {
      if (!includeAdult && cat.isAdult) continue;
      
      // Pula se já verificamos (estava em memória)
      if (_categoryCache.containsKey(cat.id)) continue; 
      
      final data = await loadCategory(cat.id);
      if (data == null) continue;
      
      // Verifica filmes e séries
      for (final movie in [...data.movies, ...data.series]) {
        if (movie.tmdb?.id != null && idsToFind.contains(movie.tmdb!.id)) {
          results[movie.tmdb!.id!] = movie;
          idsToFind.remove(movie.tmdb!.id);
        }
      }
      
      // YIELD: Allow UI to render between category loads to prevent freezing
      await Future.delayed(Duration.zero);

      // Otimização de memória: Se a categoria não estava carregada e foi carregada só pra isso,
      // podemos considerar descarregar se a memória estiver cheia (o _manageCacheSize já faz isso periodicamente),
      // mas como estamos num loop pesado, vamos deixar o LRU cuidar.

      if (idsToFind.isEmpty) break; // Achou tudo
    }
    
    debugPrint('🏁 findBatchByTmdbIds: Encontrados ${results.length}/${tmdbIds.length} itens');
    return results;
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
