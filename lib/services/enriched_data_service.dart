import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/enriched_movie.dart';

/// Serviço de dados enriquecidos do TMDB
/// 
/// Este serviço carrega dados pré-processados dos arquivos JSON enriched,
/// evitando chamadas à API do TMDB em tempo real.
class EnrichedDataService {
  static final EnrichedDataService _instance = EnrichedDataService._internal();
  factory EnrichedDataService() => _instance;
  EnrichedDataService._internal();

  // === Configurações ===
  static const String _enrichedPath = 'json/enriched';
  static const int _maxCategoriesInMemory = 10;

  // === Cache ===
  final Map<String, List<EnrichedMovie>> _dataCache = {};
  final Map<String, EnrichedCategoryInfo> _categoryCache = {};
  final List<String> _cacheOrder = []; // LRU order
  
  // === Índices ===
  final Map<int, _ActorData> _actorIndex = {};
  final Set<String> _genreSet = {};
  final Set<String> _yearSet = {};
  final Set<String> _certificationSet = {};
  final Map<String, Set<String>> _keywordIndex = {};
  final Map<int, String> _tmdbIdIndex = {}; // tmdbId -> movieId
  
  // === Estado ===
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  // === Getters ===
  bool get isInitialized => _isInitialized;
  int get cachedCategoriesCount => _dataCache.length;

  /// Categorias de streaming principais
  static const List<String> streamingCategories = [
    '📺 Netflix',
    '📺 Prime Video',
    '📺 Disney+',
    '📺 Max',
    '📺 Globoplay',
    '📺 Apple TV+',
    '📺 Paramount+',
    '📺 Star+',
    '📺 Crunchyroll',
    '📺 Discovery+',
  ];

  /// Categorias de gênero
  static const List<String> genreCategories = [
    '🎬 Ação',
    '🎬 Comédia',
    '🎬 Drama',
    '🎬 Terror',
    '🎬 Ficção Científica',
    '🎬 Animação',
    '🎬 Fantasia',
    '🎬 Aventura',
    '🎬 Romance',
    '🎬 Suspense',
    '🎬 Crime',
    '🎬 Documentário',
  ];

  /// Categorias adultas (só aparecem quando desbloqueado)
  static const List<EnrichedCategoryInfo> adultCategories = [
    EnrichedCategoryInfo(
      name: '🔞 Adultos',
      file: 'adultos.json',
      isAdult: true,
    ),
    EnrichedCategoryInfo(
      name: '🔞 Adultos - Bella da Semana',
      file: 'adultos-bella-da-semana.json',
      isAdult: true,
    ),
    EnrichedCategoryInfo(
      name: '🔞 Adultos - Legendado',
      file: 'adultos-legendado.json',
      isAdult: true,
    ),
  ];

  /// Lista de categorias disponíveis
  static const List<EnrichedCategoryInfo> enrichedCategories = [
    EnrichedCategoryInfo(name: '🎬 Lançamentos', file: 'lancamentos.json'),
    EnrichedCategoryInfo(name: '📺 Netflix', file: 'netflix.json'),
    EnrichedCategoryInfo(name: '📺 Prime Video', file: 'prime-video.json'),
    EnrichedCategoryInfo(name: '📺 Disney+', file: 'disney.json'),
    EnrichedCategoryInfo(name: '📺 Max', file: 'max.json'),
    EnrichedCategoryInfo(name: '📺 Globoplay', file: 'globoplay.json'),
    EnrichedCategoryInfo(name: '📺 Apple TV+', file: 'apple-tv.json'),
    EnrichedCategoryInfo(name: '📺 Paramount+', file: 'paramount.json'),
    EnrichedCategoryInfo(name: '📺 Star+', file: 'star.json'),
    EnrichedCategoryInfo(name: '📺 Crunchyroll', file: 'crunchyroll.json'),
    EnrichedCategoryInfo(name: '📺 Funimation', file: 'funimation.json'),
    EnrichedCategoryInfo(name: '📺 Discovery+', file: 'discovery.json'),
    EnrichedCategoryInfo(name: '🎬 4K UHD', file: '4k-uhd.json'),
    EnrichedCategoryInfo(name: '🎬 Ação', file: 'acao.json'),
    EnrichedCategoryInfo(name: '🎬 Comédia', file: 'comedia.json'),
    EnrichedCategoryInfo(name: '🎬 Drama', file: 'drama.json'),
    EnrichedCategoryInfo(name: '🎬 Terror', file: 'terror.json'),
    EnrichedCategoryInfo(name: '🎬 Ficção Científica', file: 'ficcao-cientifica.json'),
    EnrichedCategoryInfo(name: '🎬 Animação', file: 'animacao.json'),
    EnrichedCategoryInfo(name: '🎬 Fantasia', file: 'fantasia.json'),
    EnrichedCategoryInfo(name: '🎬 Aventura', file: 'aventura.json'),
    EnrichedCategoryInfo(name: '🎬 Romance', file: 'romance.json'),
    EnrichedCategoryInfo(name: '🎬 Suspense', file: 'suspense.json'),
    EnrichedCategoryInfo(name: '🎬 Crime', file: 'crime.json'),
    EnrichedCategoryInfo(name: '🎬 Documentário', file: 'documentario.json'),
    EnrichedCategoryInfo(name: '📺 Doramas', file: 'doramas.json'),
    EnrichedCategoryInfo(name: '📺 Novelas', file: 'novelas.json'),
    EnrichedCategoryInfo(name: '🎬 Legendados', file: 'legendados.json'),
    EnrichedCategoryInfo(name: '📺 Legendadas', file: 'legendadas.json'),
    EnrichedCategoryInfo(name: '🎬 Nacionais', file: 'nacionais.json'),
    EnrichedCategoryInfo(name: '🇧🇷 Brasil Paralelo', file: 'brasil-paralelo.json'),
  ];

  /// Retorna todas as categorias (com ou sem adulto)
  List<EnrichedCategoryInfo> getAllCategories({bool includeAdult = false}) {
    if (includeAdult) {
      return [...enrichedCategories, ...adultCategories];
    }
    return enrichedCategories;
  }

  /// Inicializa o serviço carregando categorias prioritárias
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    try {
      debugPrint('🎬 Inicializando dados enriched...');
      final startTime = DateTime.now();

      // Carrega categorias prioritárias em paralelo
      final priorityCategories = [
        '🎬 Lançamentos',
        '📺 Netflix',
        '📺 Prime Video',
        '📺 Disney+',
        '📺 Max',
      ];

      await Future.wait(
        priorityCategories.map((cat) => loadEnrichedCategory(cat)),
      );

      _isInitialized = true;
      final duration = DateTime.now().difference(startTime);
      debugPrint('✅ Dados enriched inicializados em ${duration.inMilliseconds}ms');

      _initCompleter!.complete();

      // Carrega resto em background
      _loadRemainingCategories(priorityCategories);
    } catch (e) {
      debugPrint('❌ Erro ao inicializar dados enriched: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }

    return _initCompleter!.future;
  }

  /// Carrega categorias restantes em background
  Future<void> _loadRemainingCategories(List<String> alreadyLoaded) async {
    final otherCategories = enrichedCategories
        .where((c) => !alreadyLoaded.contains(c.name))
        .map((c) => c.name)
        .toList();

    // Carrega em lotes de 3 para não sobrecarregar
    for (var i = 0; i < otherCategories.length; i += 3) {
      final batch = otherCategories.skip(i).take(3).toList();
      await Future.wait(batch.map((cat) => loadEnrichedCategory(cat)));
      await Future.delayed(const Duration(milliseconds: 100));
    }

    debugPrint('✅ Todas as categorias carregadas!');
  }

  /// Carrega uma categoria de dados enriched
  Future<List<EnrichedMovie>> loadEnrichedCategory(String categoryName) async {
    // Verifica cache primeiro
    if (_dataCache.containsKey(categoryName)) {
      _updateCacheLRU(categoryName);
      return _dataCache[categoryName]!;
    }

    // Encontra o arquivo da categoria
    EnrichedCategoryInfo? category = enrichedCategories
        .firstWhere((c) => c.name == categoryName, orElse: () => adultCategories
            .firstWhere((c) => c.name == categoryName, orElse: () => throw Exception('Categoria não encontrada: $categoryName')));

    try {
      final jsonString = await rootBundle.loadString('$_enrichedPath/${category.file}');
      final List<dynamic> jsonData = json.decode(jsonString);

      final List<EnrichedMovie> movies = [];

      for (final item in jsonData) {
        final itemMap = item as Map<String, dynamic>;
        
        // Verifica se é série ou filme
        if (itemMap['type'] == 'series' && itemMap['episodes'] != null) {
          movies.add(EnrichedSeries.fromJson(itemMap));
        } else {
          movies.add(EnrichedMovie.fromJson(itemMap));
        }
      }

      // Cacheia os dados
      _dataCache[categoryName] = movies;
      _updateCacheLRU(categoryName);

      // Atualiza info da categoria
      _categoryCache[categoryName] = EnrichedCategoryInfo(
        name: category.name,
        file: category.file,
        count: movies.length,
        isAdult: category.isAdult,
      );

      // Indexa dados
      _indexData(movies);

      // Limpa cache se necessário
      _cleanupCache();

      debugPrint('✅ Categoria "$categoryName" carregada: ${movies.length} itens');

      return movies;
    } catch (e) {
      debugPrint('❌ Erro ao carregar categoria "$categoryName": $e');
      return [];
    }
  }

  /// Indexa dados para busca rápida
  void _indexData(List<EnrichedMovie> movies) {
    for (final movie in movies) {
      if (movie.tmdb == null) continue;

      final tmdb = movie.tmdb!;

      // Indexa gêneros
      for (final genre in tmdb.genres) {
        _genreSet.add(genre);
      }

      // Indexa anos
      if (tmdb.year.isNotEmpty) {
        _yearSet.add(tmdb.year);
      }

      // Indexa classificações
      if (tmdb.certification != null) {
        _certificationSet.add(tmdb.certification!);
      }

      // Indexa keywords
      for (final kw in tmdb.keywords) {
        final kwLower = kw.toLowerCase();
        _keywordIndex.putIfAbsent(kwLower, () => {}).add(movie.id);
      }

      // Indexa TMDB ID
      _tmdbIdIndex[tmdb.id] = movie.id;

      // Indexa atores
      for (final actor in tmdb.cast) {
        if (!_actorIndex.containsKey(actor.id)) {
          _actorIndex[actor.id] = _ActorData(
            name: actor.name,
            photo: actor.photo,
            items: {},
          );
        }
        _actorIndex[actor.id]!.items.add(movie.id);
      }
    }
  }

  /// Atualiza ordem LRU do cache
  void _updateCacheLRU(String categoryName) {
    _cacheOrder.remove(categoryName);
    _cacheOrder.add(categoryName);
  }

  /// Limpa cache mantendo apenas as categorias mais recentes
  void _cleanupCache() {
    while (_cacheOrder.length > _maxCategoriesInMemory) {
      final oldest = _cacheOrder.removeAt(0);
      _dataCache.remove(oldest);
      debugPrint('🗑️  Cache LRU: removida categoria "$oldest"');
    }
  }

  /// Obtém todos os gêneros únicos disponíveis
  List<String> getAvailableGenres() {
    return _genreSet.toList()..sort();
  }

  /// Obtém todos os anos únicos disponíveis
  List<String> getAvailableYears() {
    final years = _yearSet.toList();
    years.sort((a, b) => int.parse(b).compareTo(int.parse(a)));
    return years;
  }

  /// Obtém todas as classificações indicativas disponíveis
  List<String> getAvailableCertifications() {
    const order = ['L', '10', '12', '14', '16', '18'];
    final certs = _certificationSet.toList();
    certs.sort((a, b) {
      final aIdx = order.indexOf(a);
      final bIdx = order.indexOf(b);
      if (aIdx == -1 && bIdx == -1) return a.compareTo(b);
      if (aIdx == -1) return 1;
      if (bIdx == -1) return -1;
      return aIdx.compareTo(bIdx);
    });
    return certs;
  }

  /// Busca filmes/séries por texto
  Future<List<EnrichedMovie>> searchContent(
    String query, {
    FilterOptions? filters,
  }) async {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) return [];

    final results = <EnrichedMovie>[];
    final seenIds = <String>{};

    for (final movies in _dataCache.values) {
      for (final movie in movies) {
        if (seenIds.contains(movie.id)) continue;

        // Busca no nome
        final matchesName = movie.name.toLowerCase().contains(normalizedQuery);

        // Busca no título TMDB
        final matchesTitle = movie.tmdb?.title.toLowerCase().contains(normalizedQuery) ?? false;

        // Busca no título original
        final matchesOriginal = movie.tmdb?.originalTitle?.toLowerCase().contains(normalizedQuery) ?? false;

        // Busca em keywords
        final matchesKeyword = movie.tmdb?.keywords.any(
              (kw) => kw.toLowerCase().contains(normalizedQuery),
            ) ?? false;

        // Busca no elenco
        final matchesCast = movie.tmdb?.cast.any(
              (actor) => actor.name.toLowerCase().contains(normalizedQuery),
            ) ?? false;

        if (matchesName || matchesTitle || matchesOriginal || matchesKeyword || matchesCast) {
          // Aplica filtros adicionais
          if (filters != null && !_matchesFilters(movie, filters)) {
            continue;
          }

          seenIds.add(movie.id);
          results.add(movie);
        }
      }
    }

    // Ordena por relevância
    results.sort((a, b) {
      final aExact = a.name.toLowerCase() == normalizedQuery ||
          a.tmdb?.title.toLowerCase() == normalizedQuery;
      final bExact = b.name.toLowerCase() == normalizedQuery ||
          b.tmdb?.title.toLowerCase() == normalizedQuery;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      // Por rating
      final aRating = a.tmdb?.rating ?? 0.0;
      final bRating = b.tmdb?.rating ?? 0.0;
      return bRating.compareTo(aRating);
    });

    return results;
  }

  /// Filtra conteúdo de uma categoria
  List<EnrichedMovie> filterContent(
    String categoryName,
    FilterOptions filters,
  ) {
    final movies = _dataCache[categoryName] ?? [];
    return _applyFiltersAndSort(movies, filters);
  }

  /// Filtra todo o conteúdo disponível (todas as categorias)
  List<EnrichedMovie> filterAllContent(FilterOptions filters) {
    final seenIds = <String>{};
    final results = <EnrichedMovie>[];

    for (final items in _dataCache.values) {
      for (final movie in items) {
        if (seenIds.contains(movie.id)) continue;
        if (_matchesFilters(movie, filters)) {
          seenIds.add(movie.id);
          results.add(movie);
        }
      }
    }

    return _sortMovies(results, filters.sortBy, filters.sortOrder);
  }

  /// Verifica se um filme atende aos filtros
  bool _matchesFilters(EnrichedMovie movie, FilterOptions filters) {
    // Filtro por tipo
    if (filters.type != 'all' && movie.type != filters.type) {
      return false;
    }

    // Filtro por gênero
    if (filters.genres.isNotEmpty) {
      if (movie.tmdb?.genres.any((g) => filters.genres.contains(g)) != true) {
        return false;
      }
    }

    // Filtro por ano
    if (filters.years.isNotEmpty) {
      if (!filters.years.contains(movie.tmdb?.year ?? '')) {
        return false;
      }
    }

    // Filtro por classificação
    if (filters.certifications.isNotEmpty) {
      if (!filters.certifications.contains(movie.tmdb?.certification ?? '')) {
        return false;
      }
    }

    // Filtro por rating mínimo
    if (filters.ratings.isNotEmpty) {
      final minRating = filters.ratings.map((r) => double.parse(r)).reduce((a, b) => a < b ? a : b);
      if ((movie.tmdb?.rating ?? 0.0) < minRating) {
        return false;
      }
    }

    return true;
  }

  /// Aplica filtros e ordenação
  List<EnrichedMovie> _applyFiltersAndSort(
    List<EnrichedMovie> movies,
    FilterOptions filters,
  ) {
    final filtered = movies.where((m) => _matchesFilters(m, filters)).toList();
    return _sortMovies(filtered, filters.sortBy, filters.sortOrder);
  }

  /// Ordena lista de filmes
  List<EnrichedMovie> _sortMovies(
    List<EnrichedMovie> movies,
    String sortBy,
    String sortOrder,
  ) {
    final sorted = List<EnrichedMovie>.from(movies);
    final order = sortOrder == 'asc' ? 1 : -1;

    sorted.sort((a, b) {
      int comparison = 0;

      switch (sortBy) {
        case 'name':
          comparison = (a.tmdb?.title ?? a.name).compareTo(b.tmdb?.title ?? b.name);
          break;
        case 'rating':
          comparison = (b.tmdb?.rating ?? 0.0).compareTo(a.tmdb?.rating ?? 0.0);
          break;
        case 'year':
          final aYear = int.tryParse(a.tmdb?.year ?? '0') ?? 0;
          final bYear = int.tryParse(b.tmdb?.year ?? '0') ?? 0;
          comparison = bYear.compareTo(aYear);
          break;
        case 'popularity':
        default:
          comparison = (b.tmdb?.popularity ?? 0.0).compareTo(a.tmdb?.popularity ?? 0.0);
          break;
      }

      return comparison * order;
    });

    return sorted;
  }

  /// Obtém filmografia de um ator
  ActorFilmography? getActorFilmography(int actorId) {
    final actorData = _actorIndex[actorId];
    if (actorData == null) return null;

    final movies = <EnrichedMovie>[];
    final series = <EnrichedSeries>[];

    for (final items in _dataCache.values) {
      for (final item in items) {
        if (actorData.items.contains(item.id)) {
          if (item is EnrichedSeries) {
            series.add(item);
          } else {
            movies.add(item);
          }
        }
      }
    }

    // Remove duplicatas
    final uniqueMovies = {for (var m in movies) m.id: m}.values.toList();
    final uniqueSeries = {for (var s in series) s.id: s}.values.toList();

    // Ordena por rating
    uniqueMovies.sort((a, b) => (b.tmdb?.rating ?? 0.0).compareTo(a.tmdb?.rating ?? 0.0));
    uniqueSeries.sort((a, b) => (b.tmdb?.rating ?? 0.0).compareTo(a.tmdb?.rating ?? 0.0));

    return ActorFilmography(
      actor: EnrichedCastMember(
        id: actorId,
        name: actorData.name,
        character: '',
        photo: actorData.photo,
      ),
      movies: uniqueMovies,
      series: uniqueSeries,
    );
  }

  /// Busca todos os atores disponíveis (para autocomplete)
  List<EnrichedCastMember> searchActors(String query) {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty || normalizedQuery.length < 2) return [];

    final results = <EnrichedCastMember>[];

    _actorIndex.forEach((id, data) {
      if (data.name.toLowerCase().contains(normalizedQuery)) {
        results.add(EnrichedCastMember(
          id: id,
          name: data.name,
          character: '',
          photo: data.photo,
        ));
      }
    });

    // Ordena por número de trabalhos
    results.sort((a, b) {
      final aCount = _actorIndex[a.id]?.items.length ?? 0;
      final bCount = _actorIndex[b.id]?.items.length ?? 0;
      return bCount.compareTo(aCount);
    });

    return results.take(20).toList();
  }

  /// Encontra um item por ID
  EnrichedMovie? findById(String id) {
    for (final movies in _dataCache.values) {
      try {
        final found = movies.firstWhere((m) => m.id == id);
        return found;
      } catch (_) {
        // Não encontrado nesta categoria, continuar
      }
    }
    return null;
  }

  /// Encontra item por TMDB ID
  EnrichedMovie? findByTmdbId(int tmdbId) {
    final movieId = _tmdbIdIndex[tmdbId];
    if (movieId == null) return null;
    return findById(movieId);
  }

  /// Obtém itens recomendados que existem no catálogo
  List<EnrichedMovie> getAvailableRecommendations(EnrichedMovie movie) {
    if (movie.tmdb?.recommendations.isEmpty ?? true) return [];

    final recommendations = <EnrichedMovie>[];

    for (final rec in movie.tmdb!.recommendations) {
      final found = findByTmdbId(rec.id);
      if (found != null) {
        recommendations.add(found);
      }
    }

    return recommendations.take(10).toList();
  }

  /// Obtém itens com gêneros similares
  List<EnrichedMovie> getSimilarByGenre(EnrichedMovie movie, {int limit = 10}) {
    if (movie.tmdb?.genres.isEmpty ?? true) return [];

    final movieGenres = movie.tmdb!.genres.toSet();
    final results = <({EnrichedMovie movie, double score})>[];
    final seenIds = {movie.id};

    for (final movies in _dataCache.values) {
      for (final m in movies) {
        if (seenIds.contains(m.id)) continue;
        if (m.type != movie.type) continue; // Mesmo tipo
        if (m.tmdb?.genres.isEmpty ?? true) continue;

        // Calcula score por gêneros em comum
        final commonGenres = m.tmdb!.genres.where((g) => movieGenres.contains(g)).length;
        if (commonGenres == 0) continue;

        final score = commonGenres * 10.0 + (m.tmdb!.rating);

        seenIds.add(m.id);
        results.add((movie: m, score: score));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).map((r) => r.movie).toList();
  }

  /// Obtém itens em destaque (mais bem avaliados)
  List<EnrichedMovie> getFeaturedItems({String? type, int limit = 20}) {
    final results = <EnrichedMovie>[];
    final seenIds = <String>{};

    for (final movies in _dataCache.values) {
      for (final movie in movies) {
        if (seenIds.contains(movie.id)) continue;
        if (type != null && movie.type != type) continue;
        if ((movie.tmdb?.rating ?? 0.0) < 7.0) continue;
        if (movie.tmdb?.poster == null) continue;

        seenIds.add(movie.id);
        results.add(movie);
      }
    }

    results.sort((a, b) => (b.tmdb?.rating ?? 0.0).compareTo(a.tmdb?.rating ?? 0.0));
    return results.take(limit).toList();
  }

  /// Obtém lançamentos recentes
  List<EnrichedMovie> getRecentReleases({int limit = 20}) {
    final results = <EnrichedMovie>[];
    final seenIds = <String>{};
    final currentYear = DateTime.now().year;

    for (final movies in _dataCache.values) {
      for (final movie in movies) {
        if (seenIds.contains(movie.id)) continue;

        final year = int.tryParse(movie.tmdb?.year ?? '0') ?? 0;
        if (year < currentYear - 2) continue; // Últimos 2 anos
        if (movie.tmdb?.poster == null) continue;

        seenIds.add(movie.id);
        results.add(movie);
      }
    }

    results.sort((a, b) {
      final aYear = int.tryParse(a.tmdb?.year ?? '0') ?? 0;
      final bYear = int.tryParse(b.tmdb?.year ?? '0') ?? 0;
      if (aYear != bYear) return bYear.compareTo(aYear);
      return (b.tmdb?.rating ?? 0.0).compareTo(a.tmdb?.rating ?? 0.0);
    });

    return results.take(limit).toList();
  }

  /// Limpa todo o cache
  void clearCache() {
    _dataCache.clear();
    _categoryCache.clear();
    _cacheOrder.clear();
    _actorIndex.clear();
    _genreSet.clear();
    _yearSet.clear();
    _certificationSet.clear();
    _keywordIndex.clear();
    _tmdbIdIndex.clear();
    _isInitialized = false;
    _initCompleter = null;
    debugPrint('🗑️  Cache limpo');
  }
}

/// Dados de um ator para indexação
class _ActorData {
  final String name;
  final String? photo;
  final Set<String> items;

  _ActorData({
    required this.name,
    this.photo,
    required this.items,
  });
}
