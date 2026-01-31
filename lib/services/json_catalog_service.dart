import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
    this.count = 0,
    this.isAdult = false,
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

/// Serviço otimizado para carregar catálogo a partir de arquivos JSON remotos
/// 
/// - Lista de categorias gerada dinamicamente
/// - Os dados das categorias são carregados remotamente do GitHub
/// - Cache local para funcionamento offline
/// - Suporte a lazy loading por categoria
/// - Dados enriquecidos com TMDB (poster, sinopse, elenco, etc)
class JsonCatalogService {
  static final JsonCatalogService _instance = JsonCatalogService._internal();
  factory JsonCatalogService() => _instance;
  JsonCatalogService._internal();

  // === Configurações ===
  /// URL base para carregar dados remotamente do GitHub
  static const String _remoteBaseUrl = 
      'https://raw.githubusercontent.com/gabrielsaimo/free-tv/main/public/data/enriched';
  
  /// Timeout para requisições HTTP
  static const Duration _httpTimeout = Duration(seconds: 30);
  
  /// Tempo de cache local (6 horas - atualiza frequentemente para pegar novos conteúdos)
  static const Duration _localCacheTTL = Duration(hours: 6);
  
  /// Tempo para iniciar refresh em background (30 minutos)
  static const Duration _backgroundRefreshAge = Duration(minutes: 30);
  
  static const int _maxCategoriesInMemory = 8;

  // === Lista de categorias disponíveis (gerada dinamicamente) ===
  static const List<JsonCategoryInfo> _availableCategories = [
    // Lançamentos e Destaques
    JsonCategoryInfo(name: '🎬 Lançamentos', file: 'lancamentos.json'),
    JsonCategoryInfo(name: '⭐ Sugestão da Semana', file: 'sugestao-da-semana.json'),
    
    // Streaming Platforms
    JsonCategoryInfo(name: '📺 Netflix', file: 'netflix.json'),
    JsonCategoryInfo(name: '📺 Prime Video', file: 'prime-video.json'),
    JsonCategoryInfo(name: '📺 Disney+', file: 'disney.json'),
    JsonCategoryInfo(name: '📺 Max', file: 'max.json'),
    JsonCategoryInfo(name: '📺 Globoplay', file: 'globoplay.json'),
    JsonCategoryInfo(name: '📺 Apple TV+', file: 'apple-tv.json'),
    JsonCategoryInfo(name: '📺 Paramount+', file: 'paramount.json'),
    JsonCategoryInfo(name: '📺 Star+', file: 'star.json'),
    JsonCategoryInfo(name: '📺 Crunchyroll', file: 'crunchyroll.json'),
    JsonCategoryInfo(name: '📺 Funimation', file: 'funimation.json'),
    JsonCategoryInfo(name: '📺 Discovery+', file: 'discovery.json'),
    JsonCategoryInfo(name: '📺 AMC+', file: 'amc-plus.json'),
    JsonCategoryInfo(name: '📺 Claro Video', file: 'claro-video.json'),
    JsonCategoryInfo(name: '📺 Play Plus', file: 'play-plus.json'),
    JsonCategoryInfo(name: '📺 Pluto TV', file: 'plutotv.json'),
    JsonCategoryInfo(name: '📺 Lionsgate+', file: 'lionsgate.json'),
    JsonCategoryInfo(name: '📺 Univer', file: 'univer.json'),
    JsonCategoryInfo(name: '📺 DirectTV', file: 'directv.json'),
    
    // Gêneros
    JsonCategoryInfo(name: '🎬 4K UHD', file: '4k-uhd.json'),
    JsonCategoryInfo(name: '🎬 Ação', file: 'acao.json'),
    JsonCategoryInfo(name: '🎬 Comédia', file: 'comedia.json'),
    JsonCategoryInfo(name: '🎬 Drama', file: 'drama.json'),
    JsonCategoryInfo(name: '🎬 Terror', file: 'terror.json'),
    JsonCategoryInfo(name: '🎬 Ficção Científica', file: 'ficcao-cientifica.json'),
    JsonCategoryInfo(name: '🎬 Animação', file: 'animacao.json'),
    JsonCategoryInfo(name: '🎬 Fantasia', file: 'fantasia.json'),
    JsonCategoryInfo(name: '🎬 Aventura', file: 'aventura.json'),
    JsonCategoryInfo(name: '🎬 Romance', file: 'romance.json'),
    JsonCategoryInfo(name: '🎬 Suspense', file: 'suspense.json'),
    JsonCategoryInfo(name: '🎬 Crime', file: 'crime.json'),
    JsonCategoryInfo(name: '🎬 Documentário', file: 'documentario.json'),
    JsonCategoryInfo(name: '🎬 Guerra', file: 'guerra.json'),
    JsonCategoryInfo(name: '🎬 Faroeste', file: 'faroeste.json'),
    JsonCategoryInfo(name: '🎬 Família', file: 'familia.json'),
    JsonCategoryInfo(name: '🎬 Infantil', file: 'infantil.json'),
    
    // Séries e Novelas
    JsonCategoryInfo(name: '📺 Doramas', file: 'doramas.json'),
    JsonCategoryInfo(name: '📺 Novelas', file: 'novelas.json'),
    JsonCategoryInfo(name: '📺 Novelas Turcas', file: 'novelas-turcas.json'),
    JsonCategoryInfo(name: '📺 Programas de TV', file: 'programas-de-tv.json'),
    
    // Especiais
    JsonCategoryInfo(name: '🎬 Legendados', file: 'legendados.json'),
    JsonCategoryInfo(name: '📺 Legendadas', file: 'legendadas.json'),
    JsonCategoryInfo(name: '🎬 Nacionais', file: 'nacionais.json'),
    JsonCategoryInfo(name: '🇧🇷 Brasil Paralelo', file: 'brasil-paralelo.json'),
    JsonCategoryInfo(name: '🎬 Cinema', file: 'cinema.json'),
    JsonCategoryInfo(name: '🎬 Stand-up Comedy', file: 'stand-up-comedy.json'),
    JsonCategoryInfo(name: '🎬 Shows', file: 'shows.json'),
    JsonCategoryInfo(name: '⚽ Esportes', file: 'esportes.json'),
    JsonCategoryInfo(name: '✝️ Religiosos', file: 'religiosos.json'),
    JsonCategoryInfo(name: '📺 SBT', file: 'sbt.json'),
    JsonCategoryInfo(name: '🎬 Outras Produtoras', file: 'outras-produtoras.json'),
    JsonCategoryInfo(name: '🎬 Dublagem Não Oficial', file: 'dublagem-nao-oficial.json'),
    
    // Coleções
    JsonCategoryInfo(name: '🦸 Marvel UCM', file: 'marvel-ucm.json'),
    JsonCategoryInfo(name: '🎬 Coleção Harry Potter', file: 'colecao-harry-potter.json'),
    JsonCategoryInfo(name: '🎬 Coleção Senhor dos Anéis', file: 'colecao-o-senhor-dos-aneis.json'),
    JsonCategoryInfo(name: '🎬 Coleção Homem-Aranha', file: 'colecao-homem-aranha.json'),
    JsonCategoryInfo(name: '🎬 Coleção John Wick', file: 'colecao-jhon-wick.json'),
    JsonCategoryInfo(name: '🎬 Coleção Alien', file: 'colecao-alien.json'),
    JsonCategoryInfo(name: '🎬 Coleção Exterminador do Futuro', file: 'colecao-exterminador-do-futuro.json'),
    JsonCategoryInfo(name: '🎬 Coleção Mad Max', file: 'colecao-mad-max.json'),
    JsonCategoryInfo(name: '🎬 Coleção Jogos Vorazes', file: 'colecao-jogos-vorazes.json'),
    JsonCategoryInfo(name: '🎬 Coleção Jogos Mortais', file: 'colecao-jogos-mortais.json'),
    JsonCategoryInfo(name: '🎬 Coleção MIB', file: 'colecao-mib-homens-de-preto.json'),
    JsonCategoryInfo(name: '🎬 Coleção Shrek', file: 'colecao-shrek.json'),
    JsonCategoryInfo(name: '🎬 Coleção Toy Story', file: 'colecao-toy-story.json'),
    JsonCategoryInfo(name: '🎬 Coleção Crepúsculo', file: 'colecao-crepusculo.json'),
    JsonCategoryInfo(name: '🎬 Coleção American Pie', file: 'colecao-american-pie.json'),
    JsonCategoryInfo(name: '🎬 Coleção Todo Mundo em Pânico', file: 'colecao-todo-mundo-em-panico.json'),
    JsonCategoryInfo(name: '🎬 Coleção Denzel Washington', file: 'colecao-denzel-washignton.json'),
    
    // Adultos (marcados como isAdult)
    JsonCategoryInfo(name: '🔞 Adultos', file: 'adultos.json', isAdult: true),
    JsonCategoryInfo(name: '🔞 Adultos - Bella da Semana', file: 'adultos-bella-da-semana.json', isAdult: true),
    JsonCategoryInfo(name: '🔞 Adultos - Legendado', file: 'adultos-legendado.json', isAdult: true),
  ];

  // === Cache ===
  List<JsonCategoryInfo>? _categoriesIndex;
  final Map<String, CategoryParseResult> _categoryCache = {};
  final List<String> _cacheOrder = []; // LRU order
  bool _isLoadingIndex = false;
  
  /// Diretório de cache local
  Directory? _cacheDir;

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

  // =====================================================
  // === Métodos para carregar dados remotos ===
  // =====================================================

  /// Inicializa o diretório de cache local
  Future<void> _initCacheDir() async {
    if (_cacheDir != null) return;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/json_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao criar diretório de cache: $e');
    }
  }

  /// Carrega dados JSON (do cache local ou da rede)
  Future<String?> _loadJsonData(String url, String cacheFilename) async {
    await _initCacheDir();
    
    // Tenta carregar do cache local primeiro
    final cachedData = await _loadFromLocalCache(cacheFilename);
    if (cachedData != null) {
      debugPrint('📦 Cache local: $cacheFilename');
      // Atualiza cache em background se estiver antigo
      _refreshCacheInBackground(url, cacheFilename);
      return cachedData;
    }
    
    // Se não tem cache, baixa da rede
    return await _loadFromNetwork(url, cacheFilename);
  }

  /// Carrega dados do cache local
  Future<String?> _loadFromLocalCache(String filename) async {
    if (_cacheDir == null) return null;
    
    try {
      final file = File('${_cacheDir!.path}/$filename');
      if (!await file.exists()) return null;
      
      // Verifica se o cache expirou
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      if (age > _localCacheTTL) {
        debugPrint('⏰ Cache expirado: $filename (${age.inDays} dias)');
        return null;
      }
      
      return await file.readAsString();
    } catch (e) {
      debugPrint('⚠️ Erro ao ler cache local: $e');
      return null;
    }
  }

  /// Carrega dados da rede
  Future<String?> _loadFromNetwork(String url, String cacheFilename) async {
    debugPrint('🌐 Baixando: $url');
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(_httpTimeout);
      
      if (response.statusCode == 200) {
        final data = response.body;
        
        // Salva no cache local
        await _saveToLocalCache(cacheFilename, data);
        
        debugPrint('✅ Baixado: $cacheFilename (${(data.length / 1024).toStringAsFixed(1)} KB)');
        return data;
      } else {
        debugPrint('❌ Erro HTTP ${response.statusCode}: $url');
        return null;
      }
    } on TimeoutException {
      debugPrint('⏱️ Timeout ao baixar: $cacheFilename');
      return null;
    } catch (e) {
      debugPrint('❌ Erro de rede: $e');
      return null;
    }
  }

  /// Salva dados no cache local
  Future<void> _saveToLocalCache(String filename, String data) async {
    if (_cacheDir == null) return;
    
    try {
      final file = File('${_cacheDir!.path}/$filename');
      await file.writeAsString(data);
    } catch (e) {
      debugPrint('⚠️ Erro ao salvar cache: $e');
    }
  }

  /// Atualiza cache em background se estiver antigo
  void _refreshCacheInBackground(String url, String filename) {
    Future.microtask(() async {
      if (_cacheDir == null) return;
      
      try {
        final file = File('${_cacheDir!.path}/$filename');
        if (!await file.exists()) return;
        
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified);
        
        // Se o cache é mais antigo que _backgroundRefreshAge, atualiza em background
        if (age > _backgroundRefreshAge) {
          debugPrint('🔄 Atualizando cache em background: $filename');
          await _loadFromNetwork(url, filename);
        }
      } catch (e) {
        // Ignora erros em background
      }
    });
  }

  /// Limpa todo o cache local
  Future<void> clearLocalCache() async {
    await _initCacheDir();
    if (_cacheDir == null) return;
    
    try {
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      debugPrint('🗑️ Cache local limpo');
    } catch (e) {
      debugPrint('⚠️ Erro ao limpar cache: $e');
    }
  }

  /// Carrega o índice de categorias (lista estática)
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
      debugPrint('📂 Carregando índice de categorias...');
      final stopwatch = Stopwatch()..start();

      // Usa a lista estática de categorias disponíveis
      _categoriesIndex = List.from(_availableCategories);

      // Calcula totais estimados
      _totalMovies = _categoriesIndex!.where((cat) => 
          !cat.name.contains('📺') && 
          !cat.name.toLowerCase().contains('novela') && 
          !cat.name.toLowerCase().contains('dorama')).length * 500; // Estimativa
      
      _totalSeries = _categoriesIndex!.where((cat) => 
          cat.name.contains('📺') || 
          cat.name.toLowerCase().contains('novela') || 
          cat.name.toLowerCase().contains('dorama')).length * 200; // Estimativa

      stopwatch.stop();
      debugPrint('✅ Índice carregado em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   📁 ${_categoriesIndex!.length} categorias');
      debugPrint('   🎬 ~$_totalMovies filmes, 📺 ~$_totalSeries séries (estimado)');

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

  /// Carrega uma categoria específica (lazy loading) do servidor remoto
  Future<CategoryParseResult?> loadCategory(String categoryFile, {bool includeAdult = false}) async {
    final cacheKey = categoryFile;
    
    // Verifica cache em memória
    if (_categoryCache.containsKey(cacheKey)) {
      _updateLRU(cacheKey);
      debugPrint('📦 Cache hit: $cacheKey');
      return _categoryCache[cacheKey];
    }

    debugPrint('📥 Carregando categoria: $categoryFile');
    final stopwatch = Stopwatch()..start();

    try {
      final url = '$_remoteBaseUrl/$categoryFile';
      final content = await _loadJsonData(url, categoryFile);
      
      if (content == null || content.isEmpty) {
        throw Exception('Dados vazios para categoria: $categoryFile');
      }
      
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

  /// Força atualização de uma categoria (ignora cache)
  Future<CategoryParseResult?> forceRefreshCategory(String categoryFile, {bool includeAdult = false}) async {
    debugPrint('🔄 Forçando refresh: $categoryFile');
    
    // Remove do cache em memória
    _categoryCache.remove(categoryFile);
    _cacheOrder.remove(categoryFile);
    
    // Remove do cache local
    await _initCacheDir();
    if (_cacheDir != null) {
      final file = File('${_cacheDir!.path}/$categoryFile');
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ Cache local removido: $categoryFile');
      }
    }
    
    // Recarrega da rede
    return await loadCategory(categoryFile, includeAdult: includeAdult);
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
