import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../services/json_lazy_service.dart';
import '../services/storage_service.dart';
import '../services/trending_service.dart';

/// Provider otimizado com LAZY LOADING por categoria
/// 
/// Otimizações para dispositivos com 1GB RAM:
/// - Carrega apenas índice inicialmente (~5KB)
/// - Carrega cada categoria sob demanda
/// - Mantém máximo de 8 categorias em memória (LRU)
/// - Libera memória automaticamente
/// - Parsing em isolate (não trava UI)
/// 
/// Agora usa catálogo JSON da pasta json/
class LazyMoviesProvider with ChangeNotifier {
  final JsonLazyService _service = JsonLazyService();
  
  // === Estado do índice ===
  bool _isLoadingIndex = false;
  List<JsonCategoryIndex> _categories = [];
  String? _indexError;
  
  // === Estado da categoria atual ===
  String? _selectedCategoryId;
  String _selectedCategoryName = 'Todos';
  bool _isLoadingCategory = false;
  JsonCategoryData? _currentCategoryData;
  List<Movie> _loadedMovies = [];      // Todos os filmes carregados da categoria
  List<Movie> _loadedSeries = [];      // Todas as séries carregadas da categoria
  int _currentCategoryPage = 1;        // Página atual da categoria
  bool _isLoadingMorePages = false;    // Carregando mais páginas
  String? _categoryError;
  
  // === Filtros ===
  String _searchQuery = '';
  MovieFilterType _filterType = MovieFilterType.all;
  bool _showAdultContent = false;
  
  // === Filtros Avançados ===
  Set<String> _filterGenres = {};
  int? _filterYearFrom;
  double? _filterMinRating;
  String? _filterCertification;
  String? _filterLanguage;
  int? _filterMaxRuntime;
  String _sortBy = 'name'; // name, year, rating, popularity, runtime
  bool _sortDescending = false;
  
  // === Busca Global ===
  bool _isSearchingGlobal = false;
  List<Movie> _globalSearchResults = [];
  List<Movie> _globalSearchSeries = [];
  bool _hasGlobalResults = false;
  
  // === Paginação ===
  static const int _pageSize = 30;
  int _currentPage = 0;

  // === Getters básicos ===
  bool get isLoadingIndex => _isLoadingIndex;
  bool get isLoadingCategory => _isLoadingCategory;
  bool get isLoadingMorePages => _isLoadingMorePages;
  bool get isLoading => _isLoadingIndex || _isLoadingCategory;
  bool get isSearchingGlobal => _isSearchingGlobal;
  bool get hasGlobalResults => _hasGlobalResults;
  String? get error => _indexError ?? _categoryError;
  String get selectedCategoryName => _selectedCategoryName;
  String? get selectedCategoryId => _selectedCategoryId;
  String get searchQuery => _searchQuery;
  MovieFilterType get filterType => _filterType;
  bool get showAdultContent => _showAdultContent;
  int get pageSize => _pageSize;
  int get currentCategoryPage => _currentCategoryPage;
  
  // === Getters Filtros Avançados ===
  Set<String> get filterGenres => _filterGenres;
  int? get filterYearFrom => _filterYearFrom;
  double? get filterMinRating => _filterMinRating;
  String? get filterCertification => _filterCertification;
  String? get filterLanguage => _filterLanguage;
  int? get filterMaxRuntime => _filterMaxRuntime;
  String get sortBy => _sortBy;
  bool get sortDescending => _sortDescending;
  bool get hasAdvancedFilters => _filterGenres.isNotEmpty || 
      _filterYearFrom != null || 
      _filterMinRating != null || 
      _filterCertification != null ||
      _filterLanguage != null ||
      _filterMaxRuntime != null;

  // === Getters do serviço ===
  int get totalMovies => _service.totalMovies;
  int get totalSeries => _service.totalSeries;
  int get cachedCategoriesCount => _service.cachedCategoriesCount;

  // === Cache de conteúdo por categoria (para filtrar categorias vazias) ===
  final Map<String, Set<String>> _categoryContentTypes = {}; // 'movies', 'series'

  /// Ordem preferencial das categorias
  static const List<String> _categoryOrder = [
    '🌟 Primeiras',
    'Lançamentos 2026',
    'Lançamentos 2025',
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
  ];

  /// Lista de categorias disponíveis (ordenadas e filtradas pelo tipo selecionado)
  /// NOTA: Coleções são removidas da lista lateral e só aparecem no "Todos"
  List<String> get availableCategories {
    // Filtra categorias adultas se não liberado e remove coleções
    var filteredCategories = _categories.where((c) {
      final nameLower = c.name.toLowerCase();
      
      // Remove coleções da lista lateral (só aparecem no "Todos")
      if (nameLower.contains('coleção') || nameLower.contains('colecao')) {
        return false;
      }
      
      if (!_showAdultContent) {
        // Remove categorias que contêm palavras adultas
        if (nameLower.contains('adulto') ||
            nameLower.contains('adult') ||
            nameLower.contains('+18') ||
            nameLower.contains('xxx') ||
            nameLower.contains('porno') ||
            nameLower.contains('porn') ||
            nameLower.contains('erotic') ||
            nameLower.contains('erótic')) {
          return false;
        }
      }
      
      // Filtra por tipo de conteúdo se temos cache
      if (_categoryContentTypes.containsKey(c.name)) {
        final types = _categoryContentTypes[c.name]!;
        if (_filterType == MovieFilterType.movies && !types.contains('movies')) {
          return false;
        }
        if (_filterType == MovieFilterType.series && !types.contains('series')) {
          return false;
        }
      } else {
        // Se não temos cache, usa heurística pelo nome da categoria
        final nameLower = c.name.toLowerCase();
        final isSeries = nameLower.contains('novela') ||
                         nameLower.contains('dorama') ||
                         nameLower.contains('anime') ||
                         nameLower.contains('série') ||
                         nameLower.contains('series') ||
                         nameLower.contains('📺');
        final isMovies = nameLower.contains('filme') ||
                         nameLower.contains('movie') ||
                         nameLower.contains('lançamento') ||
                         nameLower.contains('🎬');
        
        // Se filtro é filmes e parece ser só séries, esconde
        if (_filterType == MovieFilterType.movies && isSeries && !isMovies) {
          return false;
        }
        // Se filtro é séries e parece ser só filmes, esconde
        if (_filterType == MovieFilterType.series && isMovies && !isSeries) {
          return false;
        }
      }
      
      return true;
    }).toList();
    
    var names = filteredCategories.map((c) => c.name).toList();
    
    // Ordena categorias: ordem preferencial > alfabética
    names.sort((a, b) {
      // Ordem preferencial
      final indexA = _categoryOrder.indexOf(a);
      final indexB = _categoryOrder.indexOf(b);
      
      if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;
      
      // Alfabética
      return a.compareTo(b);
    });
    
    return ['Todos', '🌟 Primeiras', '📊 Tendências', ...names];
  }

  /// Informações das categorias com contagem
  List<JsonCategoryIndex> get categoriesInfo => _categories;

  /// Filmes da categoria atual (filtrados e paginados)
  List<Movie> get currentMovies {
    var movies = <Movie>[];
    
    // Usa dados carregados acumulados
    switch (_filterType) {
      case MovieFilterType.all:
        movies = [..._loadedMovies, ..._loadedSeries];
        break;
      case MovieFilterType.movies:
        movies = _loadedMovies;
        break;
      case MovieFilterType.series:
        movies = _loadedSeries;
        break;
    }
    
    // Aplica busca
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      movies = movies.where((m) {
        final searchable = '${m.name} ${m.seriesName ?? ''}'.toLowerCase();
        return searchable.contains(query);
      }).toList();
    }
    
    // Filtra adulto
    if (!_showAdultContent) {
      movies = movies.where((m) => !m.isAdult).toList();
    }
    
    return movies;
  }

  /// Itens para exibição na grade: filmes individuais + séries agrupadas
  /// Séries são representadas por um Movie "virtual" que abre o modal
  /// IMPORTANTE: Remove duplicados por nome normalizado (ignorando ano, qualidade, etc)
  List<CatalogDisplayItem> get displayItems {
    final items = <CatalogDisplayItem>[];
    final seenNames = <String>{}; // Nomes normalizados já vistos
    
    // Se temos resultados de busca global, usa eles
    List<Movie> moviesToShow;
    List<Movie> seriesToShow;
    
    if (_hasGlobalResults && _searchQuery.isNotEmpty) {
      moviesToShow = _globalSearchResults;
      seriesToShow = _globalSearchSeries;
    } else {
      moviesToShow = _loadedMovies;
      seriesToShow = _loadedSeries;
    }
    
    // Adiciona filmes (apenas se filtro não for só séries)
    if (_filterType != MovieFilterType.series) {
      var movies = List<Movie>.from(moviesToShow);
      
      // Aplica busca local se não tiver busca global
      if (_searchQuery.isNotEmpty && !_hasGlobalResults) {
        final query = _searchQuery.toLowerCase();
        movies = movies.where((m) => 
          m.name.toLowerCase().contains(query) ||
          (m.seriesName?.toLowerCase().contains(query) ?? false)
        ).toList();
      }
      
      // Filtra adulto
      if (!_showAdultContent) {
        movies = movies.where((m) => !m.isAdult).toList();
      }
      
      // Aplica filtros avançados
      if (hasAdvancedFilters) {
        movies = movies.where((m) => _passesAdvancedFilters(m, m.tmdb)).toList();
      }
      
      // Remove duplicados por NOME NORMALIZADO (ignora ano, qualidade, etc)
      for (final movie in movies) {
        final normalizedName = _normalizeNameForDedup(movie.name);
        if (!seenNames.contains(normalizedName)) {
          seenNames.add(normalizedName);
          items.add(CatalogDisplayItem(
            type: DisplayItemType.movie,
            movie: movie,
          ));
        }
      }
    }
    
    // Adiciona séries agrupadas (apenas se filtro não for só filmes)
    if (_filterType != MovieFilterType.movies) {
      // Se busca global, agrupa as séries dos resultados
      List<GroupedSeries> grouped;
      if (_hasGlobalResults && _searchQuery.isNotEmpty) {
        grouped = _groupSeriesFromList(seriesToShow);
      } else {
        grouped = currentGroupedSeries;
      }
      
      // Aplica filtros avançados nas séries
      if (hasAdvancedFilters) {
        grouped = grouped.where((s) => _passesAdvancedFilters(null, s.tmdb)).toList();
      }
      
      // Remove séries duplicadas pelo nome normalizado
      for (final series in grouped) {
        final normalizedName = _normalizeNameForDedup(series.name);
        if (!seenNames.contains(normalizedName)) {
          seenNames.add(normalizedName);
          items.add(CatalogDisplayItem(
            type: DisplayItemType.series,
            series: series,
          ));
        }
      }
    }
    
    // Ordena conforme configuração
    items.sort((a, b) {
      int result = 0;
      final tmdbA = a.movie?.tmdb ?? a.series?.tmdb;
      final tmdbB = b.movie?.tmdb ?? b.series?.tmdb;
      
      switch (_sortBy) {
        case 'year':
          final yearA = int.tryParse(tmdbA?.year ?? '0') ?? 0;
          final yearB = int.tryParse(tmdbB?.year ?? '0') ?? 0;
          result = yearA.compareTo(yearB);
          break;
        case 'rating':
          final ratingA = tmdbA?.rating ?? 0.0;
          final ratingB = tmdbB?.rating ?? 0.0;
          result = ratingA.compareTo(ratingB);
          break;
        case 'popularity':
          final popA = tmdbA?.popularity ?? 0.0;
          final popB = tmdbB?.popularity ?? 0.0;
          result = popA.compareTo(popB);
          break;
        case 'runtime':
          final rtA = tmdbA?.runtime ?? tmdbA?.episodeRuntime ?? 0;
          final rtB = tmdbB?.runtime ?? tmdbB?.episodeRuntime ?? 0;
          result = rtA.compareTo(rtB);
          break;
        case 'name':
        default:
          result = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
          break;
      }
      
      return _sortDescending ? -result : result;
    });
    
    return items;
  }
  
  /// Normaliza nome para deduplicação - remove ano, qualidade, caracteres especiais
  String _normalizeNameForDedup(String name) {
    return name
        .toLowerCase()
        // Remove ano entre parênteses: "Filme (2024)" -> "Filme"
        .replaceAll(RegExp(r'\s*\(\d{4}\)\s*'), ' ')
        // Remove qualidade: "4K", "1080p", "720p", "CAM", "HDTS", etc
        .replaceAll(RegExp(r'\b(4k|2160p|1080p|720p|480p|cam|hdts|ts|hd|sd|dvd|bluray|webrip|webdl|web-dl)\b', caseSensitive: false), '')
        // Remove legendado/dublado
        .replaceAll(RegExp(r'\b(legendado|dublado|dual|dub|leg|nacional)\b', caseSensitive: false), '')
        // Remove caracteres especiais
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        // Remove espaços múltiplos
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  
  /// Agrupa séries de uma lista (para busca global)
  /// Lida com dois formatos:
  /// 1. Formato novo: série com episodes embutidos (converte diretamente para GroupedSeries)
  /// 2. Formato antigo: episódios individuais com seriesName (agrupa por seriesName)
  List<GroupedSeries> _groupSeriesFromList(List<Movie> seriesItems) {
    final grouped = <GroupedSeries>[];
    final seenSeriesNames = <String>{};
    
    // Formato antigo: episódios individuais para agrupar
    final episodesToGroup = <Movie>[];
    
    for (final item in seriesItems) {
      // Formato novo: série com episodes embutidos
      if (item.episodes != null && item.episodes!.isNotEmpty) {
        final seriesName = item.tmdb?.title ?? item.seriesName ?? item.name;
        final normalizedName = seriesName.toLowerCase().trim();
        
        if (seenSeriesNames.contains(normalizedName)) continue;
        seenSeriesNames.add(normalizedName);
        
        // Converte episodes (Map<String, List<Episode>>) para seasons (Map<int, List<Movie>>)
        final Map<int, List<Movie>> seasons = {};
        for (final entry in item.episodes!.entries) {
          final seasonNum = int.tryParse(entry.key) ?? 1;
          seasons[seasonNum] = entry.value.map((ep) => Movie(
            id: ep.id,
            name: ep.name,
            url: ep.url,
            category: item.category,
            type: MovieType.series,
            seriesName: seriesName,
            season: seasonNum,
            episode: ep.episode,
          )).toList();
        }
        
        grouped.add(GroupedSeries(
          id: '${seriesName.hashCode}_search',
          name: seriesName,
          logo: item.tmdb?.poster ?? item.logo,
          category: item.category.isNotEmpty ? item.category : 'Busca',
          seasons: seasons,
          isAdult: item.isAdult,
          tmdb: item.tmdb,
        ));
      } 
      // Formato antigo: episódio individual com seriesName
      else if (item.seriesName != null && item.seriesName!.isNotEmpty) {
        episodesToGroup.add(item);
      }
    }
    
    // Agrupa episódios do formato antigo
    if (episodesToGroup.isNotEmpty) {
      final Map<String, List<Movie>> seriesMap = {};
      final Map<String, String> seriesOriginalName = {};
      
      for (final episode in episodesToGroup) {
        final key = episode.seriesName!.toLowerCase().trim();
        if (seenSeriesNames.contains(key)) continue;
        
        seriesMap.putIfAbsent(key, () => []).add(episode);
        seriesOriginalName.putIfAbsent(key, () => episode.seriesName!);
      }
      
      for (final entry in seriesMap.entries) {
        final eps = entry.value;
        if (eps.isEmpty) continue;
        
        seenSeriesNames.add(entry.key);
        final first = eps.first;
        final originalName = seriesOriginalName[entry.key] ?? first.seriesName!;
        
        final Map<int, List<Movie>> seasonMap = {};
        for (final ep in eps) {
          final season = ep.season ?? 1;
          seasonMap.putIfAbsent(season, () => []).add(ep);
        }
        
        final seasons = seasonMap.entries.map((e) {
          final episodeList = e.value..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
          return MapEntry(e.key, episodeList);
        }).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        
        grouped.add(GroupedSeries(
          id: '${originalName.hashCode}_search',
          name: originalName,
          logo: first.tmdb?.poster ?? first.logo,
          category: first.category.isNotEmpty ? first.category : 'Busca',
          seasons: Map.fromEntries(seasons),
          isAdult: first.isAdult,
          tmdb: first.tmdb,
        ));
      }
    }
    
    grouped.sort((a, b) => a.name.compareTo(b.name));
    return grouped;
  }

  /// Total de itens para exibição
  int get displayItemsCount => displayItems.length;

  /// Verifica se a categoria atual tem mais páginas para carregar
  bool get hasMoreCategoryPages {
    // JSONs não são paginados, retorna false
    return false;
  }

  /// Filmes paginados para exibição
  List<Movie> get paginatedMovies {
    final all = currentMovies;
    final limit = (_currentPage + 1) * _pageSize;
    return all.take(limit).toList();
  }

  /// Séries agrupadas da categoria atual
  List<GroupedSeries> get currentGroupedSeries {
    if (_loadedSeries.isEmpty) return [];
    
    final grouped = <GroupedSeries>[];
    final seenIds = <String>{};
    
    for (final series in _loadedSeries) {
      // Se a série já tem episodes embutidos (formato novo), cria GroupedSeries direto
      if (series.episodes != null && series.episodes!.isNotEmpty) {
        final seriesId = series.id;
        if (seenIds.contains(seriesId)) continue;
        seenIds.add(seriesId);
        
        // Converte episodes para Map<int, List<Movie>>
        final Map<int, List<Movie>> seasonMap = {};
        series.episodes!.forEach((seasonStr, eps) {
          final seasonNum = int.tryParse(seasonStr) ?? 1;
          final epMovies = eps.map((ep) => Movie(
            id: ep.id,
            name: ep.name,
            url: ep.url,
            logo: series.posterUrl,
            category: series.category,
            type: MovieType.series,
            isAdult: series.isAdult,
            seriesName: series.seriesName ?? series.tmdb?.title ?? series.name,
            season: seasonNum,
            episode: ep.episode,
            tmdb: series.tmdb,
          )).toList();
          epMovies.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
          seasonMap[seasonNum] = epMovies;
        });
        
        grouped.add(GroupedSeries(
          id: seriesId,
          name: series.seriesName ?? series.tmdb?.title ?? series.name,
          logo: series.posterUrl,
          category: series.category,
          seasons: seasonMap,
          isAdult: series.isAdult,
          tmdb: series.tmdb,
        ));
      } else if (series.seriesName != null && series.seriesName!.isNotEmpty) {
        // Formato antigo: episódios separados que precisam ser agrupados
        // Isso será tratado abaixo
      }
    }
    
    // Para séries do formato antigo (episódios separados), agrupa por seriesName
    final Map<String, List<Movie>> seriesMap = {};
    final Map<String, String> seriesOriginalName = {};
    
    for (final episode in _loadedSeries) {
      // Pula séries que já foram processadas (têm episodes embutido)
      if (episode.episodes != null && episode.episodes!.isNotEmpty) continue;
      
      if (episode.seriesName != null && episode.seriesName!.isNotEmpty) {
        final key = episode.seriesName!.toLowerCase().trim();
        seriesMap.putIfAbsent(key, () => []).add(episode);
        seriesOriginalName.putIfAbsent(key, () => episode.seriesName!);
      }
    }
    
    for (final entry in seriesMap.entries) {
      final episodes = entry.value;
      if (episodes.isEmpty) continue;
      
      final seriesId = 'grouped_${entry.key.hashCode}';
      if (seenIds.contains(seriesId)) continue;
      seenIds.add(seriesId);
      
      final first = episodes.first;
      final originalName = seriesOriginalName[entry.key] ?? first.seriesName!;
      
      // Agrupa por temporada
      final Map<int, List<Movie>> seasonMap = {};
      for (final ep in episodes) {
        final season = ep.season ?? 1;
        seasonMap.putIfAbsent(season, () => []).add(ep);
      }
      
      // Ordena episódios
      final seasons = seasonMap.entries.map((e) {
        final eps = e.value..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
        return MapEntry(e.key, eps);
      }).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      
      grouped.add(GroupedSeries(
        id: seriesId,
        name: originalName,
        logo: first.logo,
        category: first.category.isNotEmpty ? first.category : _selectedCategoryName,
        seasons: Map.fromEntries(seasons),
        isAdult: first.isAdult,
        tmdb: first.tmdb,
      ));
    }
    
    // Aplica filtros
    var result = grouped;
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((s) => s.name.toLowerCase().contains(query)).toList();
    }
    
    if (!_showAdultContent) {
      result = result.where((s) => !s.isAdult).toList();
    }
    
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// Tem mais itens para carregar?
  bool get hasMoreItems {
    return paginatedMovies.length < currentMovies.length;
  }

  // === Inicialização ===

  /// Carrega o índice de categorias (leve e rápido)
  Future<void> initialize() async {
    if (_categories.isNotEmpty) return;
    
    _isLoadingIndex = true;
    _indexError = null;
    notifyListeners();

    try {
      // Carrega preferência de conteúdo adulto
      final storage = StorageService();
      _showAdultContent = await storage.isAdultModeUnlocked();
      
      // Carrega índice (apenas ~5KB)
      debugPrint('🚀 Iniciando carregamento do índice de categorias...');
      _categories = await _service.loadCategoryIndex();
      
      debugPrint('📂 Índice carregado: ${_categories.length} categorias');
      if (_categories.isNotEmpty) {
        debugPrint('📂 Primeira categoria: ${_categories.first.name} (${_categories.first.id})');
        debugPrint('📂 Última categoria: ${_categories.last.name} (${_categories.last.id})');
      } else {
        debugPrint('⚠️ ALERTA: Nenhuma categoria foi carregada!');
      }
    } catch (e) {
      _indexError = 'Erro ao carregar catálogo: $e';
      debugPrint('❌ $_indexError');
    } finally {
      _isLoadingIndex = false;
      notifyListeners();
    }
  }

  // === Seleção de categoria ===

  /// Seleciona uma categoria pelo nome
  /// Se [forceReload] for true, recarrega mesmo se já estiver selecionada
  Future<void> selectCategory(String categoryName, {bool forceReload = false}) async {
    // Para 'Todos', verifica se já tem dados carregados
    if (!forceReload && categoryName == _selectedCategoryName) {
      if (categoryName == 'Todos' && _loadedMovies.isNotEmpty) {
        return;
      } else if (categoryName == '🌟 Primeiras' && _loadedMovies.isNotEmpty) {
        return;
      } else if (categoryName == '📊 Tendências' && _loadedMovies.isNotEmpty) {
        return;
      } else if (categoryName != 'Todos' && categoryName != '🌟 Primeiras' && categoryName != '📊 Tendências' && _currentCategoryData != null) {
        return;
      }
    }

    _selectedCategoryName = categoryName;
    _currentPage = 0;
    _loadedMovies = [];
    _loadedSeries = [];
    
    if (categoryName == 'Todos') {
      _selectedCategoryId = null;
      _currentCategoryData = null;
      await _loadAllCategoriesSample();
      return;
    }
    
    if (categoryName == '🌟 Primeiras') {
      _selectedCategoryId = 'primeiras';
      _currentCategoryData = null;
      await _loadPrimeirasCategory();
      return;
    }
    
    if (categoryName == '📊 Tendências') {
      _selectedCategoryId = 'trending';
      _currentCategoryData = null;
      await _loadTrendingCategory();
      return;
    }

    // Encontra a categoria pelo nome (case insensitive)
    final categoryInfo = _categories.firstWhere(
      (c) => c.name.toLowerCase() == categoryName.toLowerCase(),
      orElse: () {
        debugPrint('⚠️ Categoria "$categoryName" não encontrada no índice');
        // Tenta encontrar por ID
        return _categories.firstWhere(
          (c) => c.id.toLowerCase() == categoryName.toLowerCase(),
          orElse: () => JsonCategoryIndex(
            id: categoryName.toLowerCase().replaceAll(' ', '_'),
            name: categoryName,
            file: '${categoryName.toLowerCase().replaceAll(' ', '-')}.json',
            count: 0,
            isAdult: false,
          ),
        );
      },
    );

    await _loadCategory(categoryInfo.id);
  }

  /// IDs de categorias de streaming para mostrar em "Todos"
  static const List<String> _streamingCategoryIds = [
    'netflix',
    'prime-video', 
    'disney',
    'max',
    'globoplay',
    'paramount',
    'apple-tv',
    'star',
    'crunchyroll',
    'funimation',
    'discovery',
    'amc-plus',
    'plutotv',
    'claro-video',
    'play-plus',
    'directv',
    'lionsgate',
  ];

  /// Carrega amostra das categorias de STREAMING para "Todos"
  /// Carrega 5 filmes/séries de cada categoria de streaming
  Future<void> _loadAllCategoriesSample() async {
    _isLoadingCategory = true;
    _categoryError = null;
    notifyListeners();

    try {
      // Filtra APENAS categorias de streaming (não adultas)
      final streamingCategories = _categories
          .where((c) => _streamingCategoryIds.contains(c.id))
          .where((c) => !c.isAdult) // NUNCA mostra categorias adultas em Todos
          .toList();
      
      // Ordena por ordem preferencial
      streamingCategories.sort((a, b) {
        final indexA = _streamingCategoryIds.indexOf(a.id);
        final indexB = _streamingCategoryIds.indexOf(b.id);
        if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
        if (indexA != -1) return -1;
        if (indexB != -1) return 1;
        return a.name.compareTo(b.name);
      });
      
      // Carrega 5 itens de cada categoria de streaming
      for (final cat in streamingCategories) {
        try {
          final data = await _service.loadCategory(cat.id);
          if (data != null) {
            // Pega até 5 filmes de cada categoria (FILTRA ADULTO)
            final movies = data.movies
                .where((m) => !m.isAdult) // NUNCA mostra conteúdo adulto em Todos
                .take(5)
                .toList();
            // Pega até 5 séries (episódios) de cada categoria (FILTRA ADULTO)
            final series = data.series
                .where((s) => !s.isAdult) // NUNCA mostra conteúdo adulto em Todos  
                .take(5)
                .toList();
            
            // Marca a categoria correta em cada item
            for (final movie in movies) {
              _loadedMovies.add(movie.copyWith(category: cat.name));
            }
            for (final episode in series) {
              _loadedSeries.add(episode.copyWith(category: cat.name));
            }
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao carregar amostra de ${cat.name}: $e');
        }
      }
      
      debugPrint('📂 Todos (Streaming): ${_loadedMovies.length} filmes, ${_loadedSeries.length} séries de ${streamingCategories.length} categorias');
    } catch (e) {
      _categoryError = 'Erro ao carregar: $e';
    } finally {
      _isLoadingCategory = false;
      notifyListeners();
    }
  }

  /// Carrega a categoria especial "🌟 Primeiras" com os primeiros filmes/séries de cada categoria
  Future<void> _loadPrimeirasCategory() async {
    _isLoadingCategory = true;
    _categoryError = null;
    notifyListeners();

    try {
      // Carrega um item de cada categoria
      for (final cat in _categories) {
        if (cat.isAdult && !_showAdultContent) continue; // Pula categorias adultas
        
        try {
          final data = await _service.loadCategory(cat.id);
          if (data != null) {
            // Pega o primeiro filme
            if (data.movies.isNotEmpty && !data.movies[0].isAdult) {
              _loadedMovies.add(data.movies[0].copyWith(category: cat.name));
            }
            // Pega a primeira série (episódio)
            if (data.series.isNotEmpty && !data.series[0].isAdult) {
              _loadedSeries.add(data.series[0].copyWith(category: cat.name));
            }
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao carregar primeira de ${cat.name}: $e');
        }
      }
      
      // Limita a 20 itens total
      if (_loadedMovies.length + _loadedSeries.length > 20) {
        final total = _loadedMovies.length + _loadedSeries.length;
        final ratio = 20 / total;
        _loadedMovies = (_loadedMovies.take((_loadedMovies.length * ratio).toInt()).toList());
        _loadedSeries = (_loadedSeries.take((_loadedSeries.length * ratio).toInt()).toList());
      }
      
      debugPrint('⭐ Primeiras: ${_loadedMovies.length} filmes, ${_loadedSeries.length} séries');
    } catch (e) {
      _categoryError = 'Erro ao carregar: $e';
    } finally {
      _isLoadingCategory = false;
      notifyListeners();
    }
  }

  /// Carrega a categoria de Tendências combinando hoje e semana
  Future<void> _loadTrendingCategory() async {
    _isLoadingCategory = true;
    _categoryError = null;
    notifyListeners();

    try {
      // Carrega tendências de hoje
      try {
        final results = await TrendingService.getAllTrending(_service);
        
        // Adiciona tendências de hoje
        for (final item in results.today) {
          try {
            _loadedMovies.add(item.localMovie.copyWith(category: '🔥 Tendências'));
          } catch (e) {
            debugPrint('⚠️ Erro ao processar trending item: $e');
          }
        }
        
        // Adiciona tendências da semana
        for (final item in results.week) {
          try {
            _loadedMovies.add(item.localMovie.copyWith(category: '📅 Tendências'));
          } catch (e) {
            debugPrint('⚠️ Erro ao processar trending item: $e');
          }
        }
        
        debugPrint('📊 Tendências: ${_loadedMovies.length} itens carregados');
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar tendências: $e');
      }
    } catch (e) {
      _categoryError = 'Erro ao carregar tendências: $e';
      debugPrint('❌ Erro ao carregar tendências: $e');
    } finally {
      _isLoadingCategory = false;
      notifyListeners();
    }
  }

  /// Seleciona uma categoria pelo ID
  Future<void> selectCategoryById(String categoryId) async {
    if (categoryId == _selectedCategoryId && _currentCategoryData != null) {
      return;
    }

    final categoryInfo = _categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => throw Exception('Categoria não encontrada'),
    );

    _selectedCategoryName = categoryInfo.name;
    _currentPage = 0;
    
    await _loadCategory(categoryId);
  }

  /// Carrega dados de uma categoria (arquivo único)
  Future<void> _loadCategory(String categoryId) async {
    _isLoadingCategory = true;
    _categoryError = null;
    _selectedCategoryId = categoryId;
    _currentCategoryPage = 1;
    _loadedMovies = [];
    _loadedSeries = [];
    notifyListeners();

    try {
      // Carrega categoria do JSON
      _currentCategoryData = await _service.loadCategory(categoryId);
      
      if (_currentCategoryData == null) {
        _categoryError = 'Categoria não encontrada';
      } else {
        _loadedMovies = List.from(_currentCategoryData!.movies);
        _loadedSeries = List.from(_currentCategoryData!.series);
        
        // Atualiza cache de tipos de conteúdo da categoria
        _updateCategoryContentTypes(_selectedCategoryName);
      }
    } catch (e) {
      _categoryError = 'Erro ao carregar: $e';
      debugPrint('❌ $_categoryError');
    } finally {
      _isLoadingCategory = false;
      notifyListeners();
    }
  }

  /// Atualiza o cache de tipos de conteúdo para uma categoria
  void _updateCategoryContentTypes(String categoryName) {
    final types = <String>{};
    if (_loadedMovies.isNotEmpty) types.add('movies');
    if (_loadedSeries.isNotEmpty) types.add('series');
    _categoryContentTypes[categoryName] = types;
  }

  /// Carrega mais páginas da categoria atual (não utilizado com JSONs únicos)
  Future<void> loadMoreCategoryPages() async {
    // JSONs não são paginados, não faz nada
    return;
  }

  // === Paginação ===

  /// Carrega mais itens (scroll infinito)
  void loadMore() {
    if (hasMoreItems) {
      _currentPage++;
      notifyListeners();
    }
  }

  /// Reseta paginação
  void resetPagination() {
    _currentPage = 0;
    notifyListeners();
  }

  // === Filtros ===

  /// Define o tipo de filtro
  void setFilterType(MovieFilterType type) {
    if (_filterType != type) {
      _filterType = type;
      _currentPage = 0;
      
      // Verifica se a categoria atual está disponível no novo filtro
      // Se não estiver, volta para "Todos"
      final availableCats = availableCategories;
      if (!availableCats.contains(_selectedCategoryName)) {
        _selectedCategoryName = 'Todos';
        _selectedCategoryId = null;
        _currentCategoryData = null;
        // Recarrega "Todos" para o novo filtro
        _loadAllCategoriesSample();
      }
      
      notifyListeners();
    }
  }
  
  /// Define filtros avançados
  void setAdvancedFilters({
    Set<String>? genres,
    int? yearFrom,
    double? minRating,
    String? certification,
    String? language,
    int? maxRuntime,
    String? sortBy,
    bool? sortDescending,
  }) {
    _filterGenres = genres ?? {};
    _filterYearFrom = yearFrom;
    _filterMinRating = minRating;
    _filterCertification = certification;
    _filterLanguage = language;
    _filterMaxRuntime = maxRuntime;
    _sortBy = sortBy ?? 'name';
    _sortDescending = sortDescending ?? false;
    _currentPage = 0;
    notifyListeners();
  }
  
  /// Limpa filtros avançados
  void clearAdvancedFilters() {
    _filterGenres = {};
    _filterYearFrom = null;
    _filterMinRating = null;
    _filterCertification = null;
    _filterLanguage = null;
    _filterMaxRuntime = null;
    _sortBy = 'name';
    _sortDescending = false;
    _currentPage = 0;
    notifyListeners();
  }
  
  /// Verifica se um item passa nos filtros avançados
  bool _passesAdvancedFilters(Movie? movie, TMDBData? tmdb) {
    if (tmdb == null && movie == null) return true;
    
    final data = tmdb ?? movie?.tmdb;
    if (data == null && !hasAdvancedFilters) return true;
    if (data == null && hasAdvancedFilters) return false;
    
    // Filtro de gêneros
    if (_filterGenres.isNotEmpty) {
      if (data!.genres == null || data.genres!.isEmpty) return false;
      if (!_filterGenres.any((g) => data.genres!.contains(g))) return false;
    }
    
    // Filtro de ano
    if (_filterYearFrom != null) {
      final year = int.tryParse(data!.year ?? '');
      if (year == null || year < _filterYearFrom!) return false;
    }
    
    // Filtro de nota
    if (_filterMinRating != null) {
      if (data!.rating == null || data.rating! < _filterMinRating!) return false;
    }
    
    // Filtro de classificação
    if (_filterCertification != null) {
      if (data!.certification != _filterCertification) return false;
    }
    
    // Filtro de idioma
    if (_filterLanguage != null) {
      if (data!.language != _filterLanguage) return false;
    }
    
    // Filtro de duração
    if (_filterMaxRuntime != null) {
      final runtime = data!.runtime ?? data.episodeRuntime;
      if (runtime == null || runtime > _filterMaxRuntime!) return false;
    }
    
    return true;
  }

  /// Define a query de busca
  void setSearchQuery(String query) {
    _searchQuery = query;
    _currentPage = 0;
    _hasGlobalResults = false;
    notifyListeners();
  }

  /// Limpa a busca
  void clearSearch() {
    _searchQuery = '';
    _currentPage = 0;
    _globalSearchResults = [];
    _globalSearchSeries = [];
    _hasGlobalResults = false;
    notifyListeners();
  }

  // === Busca ===

  /// Busca global em todas as categorias
  Future<void> performGlobalSearch(String query) async {
    if (query.trim().isEmpty) {
      clearSearch();
      return;
    }
    
    _searchQuery = query;
    _isSearchingGlobal = true;
    _hasGlobalResults = false;
    notifyListeners();
    
    try {
      debugPrint('🔍 Iniciando busca global por: "$query"');
      debugPrint('🔍 Total de categorias disponíveis: ${_categories.length}');
      
      final lower = query.toLowerCase();
      final foundMovies = <Movie>[];
      final foundSeries = <Movie>[];
      final seenIds = <String>{};
      int categoriesSearched = 0;
      
      // Busca em todas as categorias
      for (final cat in _categories) {
        // Pula adultos se não habilitado
        if (cat.isAdult && !_showAdultContent) continue;
        
        try {
          // Carrega categoria
          debugPrint('🔍 Buscando em: ${cat.name} (${cat.id})');
          final data = await _service.loadCategory(cat.id);
          if (data == null) {
            debugPrint('⚠️ Categoria ${cat.id} retornou null');
            continue;
          }
          
          categoriesSearched++;
          debugPrint('📂 ${cat.name}: ${data.movies.length} filmes, ${data.series.length} séries');
          
          // Busca em filmes
          for (final movie in data.movies) {
            if (seenIds.contains(movie.id)) continue;
            // Busca em nome, seriesName e título TMDB
            final searchable = '${movie.name} ${movie.seriesName ?? ''} ${movie.tmdb?.title ?? ''} ${movie.tmdb?.originalTitle ?? ''}'.toLowerCase();
            if (searchable.contains(lower)) {
              seenIds.add(movie.id);
              foundMovies.add(movie.copyWith(category: cat.name));
            }
          }
          
          // Busca em séries
          for (final series in data.series) {
            if (seenIds.contains(series.id)) continue;
            // Busca em nome, seriesName e título TMDB
            final searchable = '${series.name} ${series.seriesName ?? ''} ${series.tmdb?.title ?? ''} ${series.tmdb?.originalTitle ?? ''}'.toLowerCase();
            if (searchable.contains(lower)) {
              seenIds.add(series.id);
              foundSeries.add(series.copyWith(category: cat.name));
            }
          }
          
          // Se encontrou mais de 100 resultados, para para não sobrecarregar
          if (foundMovies.length + foundSeries.length > 100) {
            debugPrint('🔍 Encontrou muitos resultados, parando busca');
            break;
          }
          
        } catch (e) {
          debugPrint('⚠️ Erro ao buscar em ${cat.name}: $e');
        }
      }
      
      _globalSearchResults = foundMovies;
      _globalSearchSeries = foundSeries;
      _hasGlobalResults = true;
      
      debugPrint('✅ Busca concluída: ${foundMovies.length} filmes, ${foundSeries.length} séries');
      
    } catch (e) {
      debugPrint('❌ Erro na busca global: $e');
    } finally {
      _isSearchingGlobal = false;
      notifyListeners();
    }
  }

  /// Busca rápida no cache
  List<Movie> searchInCache(String query) {
    return _service.searchInCache(query);
  }

  /// Busca global (carrega categorias necessárias)
  Future<List<Movie>> searchAll(String query, {int limit = 50}) async {
    return await _service.searchAll(query, limit: limit);
  }

  // === Utilitários ===

  /// Busca um filme pelo ID (busca no cache primeiro)
  Movie? getMovieById(String id) {
    if (_currentCategoryData != null) {
      try {
        return _currentCategoryData!.movies.firstWhere((m) => m.id == id);
      } catch (_) {}
      try {
        return _currentCategoryData!.series.firstWhere((m) => m.id == id);
      } catch (_) {}
    }
    return null;
  }

  /// Busca uma série agrupada pelo ID
  GroupedSeries? getSeriesById(String id) {
    try {
      return currentGroupedSeries.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Busca filmes/séries por ID do ator (em todas as categorias)
  Future<List<Movie>> findByActorId(int actorId) async {
    return await _service.findByActorId(actorId, includeAdult: _showAdultContent);
  }

  /// Busca filmes/séries por nome do ator (em todas as categorias)
  Future<List<Movie>> findByActorName(String actorName) async {
    return await _service.findByActorName(actorName, includeAdult: _showAdultContent);
  }

  /// Busca filme/série por TMDB ID
  Future<Movie?> findByTmdbId(int tmdbId) async {
    return await _service.findByTmdbId(tmdbId, includeAdult: _showAdultContent);
  }

  /// Busca GroupedSeries pelo Movie (episódio)
  Future<GroupedSeries?> findGroupedSeriesByMovie(Movie movie) async {
    // Se o filme não é série, retorna null
    if (movie.type != MovieType.series) return null;
    
    final seriesName = movie.seriesName ?? movie.name;
    final tmdbId = movie.tmdb?.id;
    
    // Busca nas séries agrupadas da categoria atual
    for (final series in currentGroupedSeries) {
      if (series.name == seriesName) {
        return series;
      }
      if (tmdbId != null && series.tmdb?.id == tmdbId) {
        return series;
      }
    }
    
    // Se não encontrou na categoria atual, tenta buscar em todas as categorias
    final index = await _service.loadCategoryIndex();
    for (final cat in index) {
      if (!_showAdultContent && cat.isAdult) continue;
      
      final data = await _service.loadCategory(cat.id);
      if (data == null) continue;
      
      // Usa a extensão que já existe para agrupar séries
      final grouped = data.groupedSeries;
      for (final series in grouped) {
        if (series.name == seriesName) {
          return series;
        }
        if (tmdbId != null && series.tmdb?.id == tmdbId) {
          return series;
        }
      }
    }
    
    return null;
  }

  /// Ativa/desativa modo adulto
  Future<void> setAdultMode(bool enabled) async {
    if (_showAdultContent != enabled) {
      _showAdultContent = enabled;
      notifyListeners();
    }
  }

  /// Limpa cache e força recarregamento
  Future<void> refresh() async {
    _service.clearCache();
    _currentCategoryData = null;
    _loadedMovies = [];
    _loadedSeries = [];
    _currentCategoryPage = 1;
    
    if (_selectedCategoryId != null) {
      await _loadCategory(_selectedCategoryId!);
    } else {
      notifyListeners();
    }
  }

  /// Limpa tudo (índice + cache)
  Future<void> clearAll() async {
    _service.clearAll();
    _categories = [];
    _currentCategoryData = null;
    _loadedMovies = [];
    _loadedSeries = [];
    _selectedCategoryId = null;
    _selectedCategoryName = 'Todos';
    _currentCategoryPage = 1;
    notifyListeners();
  }

  /// Obtém estatísticas de memória
  Map<String, dynamic> get memoryStats => _service.getMemoryStats();

  /// Estatísticas gerais
  Map<String, dynamic> get statistics {
    return {
      'categories': _categories.length,
      'totalMovies': _service.totalMovies,
      'totalSeries': _service.totalSeries,
      'cachedCategories': _service.cachedCategoriesCount,
      'currentCategory': _selectedCategoryName,
      'currentMovies': currentMovies.length,
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

/// Tipo de item no catálogo
enum DisplayItemType {
  movie,
  series,
}

/// Item de exibição no catálogo (pode ser filme ou série)
class CatalogDisplayItem {
  final DisplayItemType type;
  final Movie? movie;
  final GroupedSeries? series;

  const CatalogDisplayItem({
    required this.type,
    this.movie,
    this.series,
  });

  /// Nome para exibição
  String get displayName {
    if (type == DisplayItemType.movie) {
      return movie?.name ?? '';
    }
    return series?.name ?? '';
  }

  /// URL do logo/poster
  String? get logo {
    if (type == DisplayItemType.movie) {
      return movie?.logo;
    }
    return series?.logo;
  }

  /// Iniciais para fallback
  String get initials {
    final name = displayName;
    return name
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  /// É conteúdo adulto?
  bool get isAdult {
    if (type == DisplayItemType.movie) {
      return movie?.isAdult ?? false;
    }
    return series?.isAdult ?? false;
  }

  /// Info adicional (temporadas para séries)
  String? get subtitle {
    if (type == DisplayItemType.series && series != null) {
      final seasonCount = series!.seasons.length;
      final episodeCount = series!.episodeCount;
      return '$seasonCount temp. • $episodeCount ep.';
    }
    return null;
  }
  
  /// Extrai ano do nome
  String? get year {
    final name = displayName;
    // Procura padrão (NNNN) no nome
    final yearRegex = RegExp(r'\((\d{4})\)');
    final match = yearRegex.firstMatch(name);
    if (match != null) {
      return match.group(1);
    }
    // Procura padrão NNNN no final ou com espaço
    final yearRegex2 = RegExp(r'[\s\[](\d{4})[\s\]]');
    final match2 = yearRegex2.firstMatch(name);
    if (match2 != null) {
      return match2.group(1);
    }
    return null;
  }
  
  /// Extrai qualidade do nome
  String? get quality {
    final name = displayName.toUpperCase();
    // Verifica qualidades comuns
    if (name.contains('4K') || name.contains('2160P')) return '4K';
    if (name.contains('1080P') || name.contains('FHD')) return '1080p';
    if (name.contains('720P') || name.contains('HD')) return '720p';
    if (name.contains('480P') || name.contains('SD')) return '480p';
    if (name.contains('CAM')) return 'CAM';
    if (name.contains('TS') || name.contains('TELESYNC')) return 'TS';
    if (name.contains('HDCAM')) return 'HDCAM';
    if (name.contains('WEB-DL') || name.contains('WEBDL')) return 'WEB';
    if (name.contains('BLURAY') || name.contains('BLU-RAY')) return 'BD';
    return null;
  }
}
