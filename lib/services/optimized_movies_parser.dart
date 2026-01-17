import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';

/// Resultado do parsing em isolate
class ParseResult {
  final List<Movie> movies;
  final Map<String, List<Movie>> byCategory;
  final List<GroupedSeries> groupedSeries;
  final int movieCount;
  final int seriesCount;
  final int adultCount;

  const ParseResult({
    required this.movies,
    required this.byCategory,
    required this.groupedSeries,
    required this.movieCount,
    required this.seriesCount,
    required this.adultCount,
  });
}

/// Dados de entrada para o isolate
class _ParseInput {
  final List<String> fileContents;
  final bool includeAdult;

  const _ParseInput({
    required this.fileContents,
    required this.includeAdult,
  });
}

/// Serviço otimizado de parse com isolates
class OptimizedMoviesParser {
  static final OptimizedMoviesParser _instance = OptimizedMoviesParser._internal();
  factory OptimizedMoviesParser() => _instance;
  OptimizedMoviesParser._internal();

  // Cache
  ParseResult? _cachedResult;
  bool _isLoading = false;
  
  /// Categorias ignoradas
  static const List<String> _ignoredCategories = [
    '⏺️ ABERTO', '⏺️ BAND', '⏺️ SBT', '⏺️ GLOBO', '⏺️ RECORD', '⏺️ HBO',
    '⏺️ TELECINE', '⏺️ DISCOVERY', '⏺️ CINE SKY', '⏺️ FILMES E SERIES',
    '⏺️ NOTICIA', '⏺️ NBA', '⏺️ RUNTIME', '⏺️ 4K',
    'GLOBO (CENTRO-OESTE)', 'GLOBO (NORDESTE)', 'GLOBO (NORTE)',
    'GLOBO (SUDESTE)', 'GLOBO (SUL)',
    '⚽APPLETV', '⚽DAZN', '⚽DISNEY', '⚽ESPORTE', '⚽HBO',
    '⚽PARAMOUNT', '⚽PREMIERE', '⚽PRIME', '⚽ COPINHA',
    'A FAZENDA', 'BBB 20', 'BBB 2026', 'ESTRELA DA CASA',
    'Área do cliente', 'JOGOS DE HOJE', 'RÁDIOS FM', 'CANAIS:',
  ];

  /// Keywords adulto
  static const List<String> _adultKeywords = [
    'ADULTOS', '[HOT]', 'XXX', '[Adulto]', 'ADULTO', '❌❤️',
  ];

  /// Keywords de série na categoria
  static const List<String> _seriesCategoryKeywords = [
    'series', 'série', 'novelas', 'doramas', 'programas', 'stand up', '24h',
  ];

  /// Patterns de episódio
  static final List<RegExp> _episodePatterns = [
    RegExp(r'S\d+\s*E\d+', caseSensitive: false),
    RegExp(r'T\d+\s*E\d+', caseSensitive: false),
    RegExp(r'\d+\s*x\s*\d+', caseSensitive: false),
    RegExp(r'Temporada\s*\d+', caseSensitive: false),
    RegExp(r'Temp\.?\s*\d+', caseSensitive: false),
    RegExp(r'Season\s*\d+', caseSensitive: false),
  ];

  /// Patterns de info de série
  static final List<RegExp> _seriesInfoPatterns = [
    RegExp(r'^(.+?)\s*S(\d+)\s*E(\d+)', caseSensitive: false),
    RegExp(r'^(.+?)\s*T(\d+)\s*E(\d+)', caseSensitive: false),
    RegExp(r'^(.+?)\s*(\d+)\s*x\s*(\d+)', caseSensitive: false),
  ];

  /// Carrega e parseia usando isolate para não travar a UI
  Future<ParseResult> loadAll({bool includeAdult = false}) async {
    // Retorna cache se disponível
    if (_cachedResult != null) {
      debugPrint('🎬 Usando cache: ${_cachedResult!.movies.length} itens');
      if (includeAdult) return _cachedResult!;
      return _filterAdult(_cachedResult!);
    }

    // Evita loading duplicado
    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_cachedResult != null) {
        if (includeAdult) return _cachedResult!;
        return _filterAdult(_cachedResult!);
      }
    }

    _isLoading = true;
    
    try {
      debugPrint('🎬 Carregando filmes em background...');
      final stopwatch = Stopwatch()..start();

      // Carrega arquivos
      final content1 = await rootBundle.loadString('assets/ListaBR01.m3u8');
      final content2 = await rootBundle.loadString('assets/ListaBR02.m3u8');

      // Parseia em isolate (background thread)
      final result = await compute(
        _parseInIsolate,
        _ParseInput(fileContents: [content1, content2], includeAdult: true),
      );

      stopwatch.stop();
      debugPrint('🎬 Carregamento completo em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   📽️ Filmes: ${result.movieCount}');
      debugPrint('   📺 Séries: ${result.seriesCount}');
      debugPrint('   🔞 Adulto: ${result.adultCount}');

      _cachedResult = result;
      _isLoading = false;

      if (includeAdult) return result;
      return _filterAdult(result);
    } catch (e, stack) {
      debugPrint('❌ Erro ao carregar: $e');
      debugPrint('Stack: $stack');
      _isLoading = false;
      rethrow;
    }
  }

  /// Filtra conteúdo adulto do resultado
  ParseResult _filterAdult(ParseResult result) {
    final movies = result.movies.where((m) => !m.isAdult).toList();
    final byCategory = <String, List<Movie>>{};
    
    for (final entry in result.byCategory.entries) {
      final filtered = entry.value.where((m) => !m.isAdult).toList();
      if (filtered.isNotEmpty) {
        byCategory[entry.key] = filtered;
      }
    }
    
    final series = result.groupedSeries.where((s) => !s.isAdult).toList();
    
    return ParseResult(
      movies: movies,
      byCategory: byCategory,
      groupedSeries: series,
      movieCount: movies.where((m) => m.type == MovieType.movie).length,
      seriesCount: movies.where((m) => m.type == MovieType.series).length,
      adultCount: 0,
    );
  }

  /// Função estática que roda no isolate
  static ParseResult _parseInIsolate(_ParseInput input) {
    final List<Movie> allMovies = [];
    
    for (final content in input.fileContents) {
      final movies = _parseContent(content);
      allMovies.addAll(movies);
    }

    // Remove duplicatas
    final seen = <String>{};
    final uniqueMovies = allMovies.where((movie) {
      if (seen.contains(movie.url)) return false;
      seen.add(movie.url);
      return true;
    }).toList();

    // Agrupa por categoria
    final Map<String, List<Movie>> byCategory = {};
    for (final movie in uniqueMovies) {
      byCategory.putIfAbsent(movie.category, () => []).add(movie);
    }

    // Agrupa séries
    final groupedSeries = _groupSeries(uniqueMovies);

    return ParseResult(
      movies: uniqueMovies,
      byCategory: byCategory,
      groupedSeries: groupedSeries,
      movieCount: uniqueMovies.where((m) => m.type == MovieType.movie).length,
      seriesCount: uniqueMovies.where((m) => m.type == MovieType.series).length,
      adultCount: uniqueMovies.where((m) => m.isAdult).length,
    );
  }

  static List<Movie> _parseContent(String content) {
    final List<Movie> movies = [];
    final lines = content.split('\n');
    
    String? currentName;
    String? currentCategory;
    String? currentLogo;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (line.startsWith('#EXTINF:')) {
        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        currentCategory = groupMatch?.group(1) ?? 'Outros';
        
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        currentLogo = logoMatch?.group(1);
        
        final nameMatch = RegExp(r',(.+)$').firstMatch(line);
        currentName = nameMatch?.group(1)?.trim();
      } else if (line.startsWith('http') && currentName != null) {
        final url = line;
        
        // Ignora .ts (streams ao vivo)
        if (url.toLowerCase().endsWith('.ts')) {
          currentName = null;
          currentCategory = null;
          currentLogo = null;
          continue;
        }
        
        final category = currentCategory ?? 'Outros';
        
        // Ignora categorias bloqueadas
        if (_shouldIgnoreCategory(category)) {
          currentName = null;
          currentCategory = null;
          currentLogo = null;
          continue;
        }
        
        final cleanedName = _cleanName(currentName);
        final isAdult = _isAdultContent(currentName, category);
        final isSeries = _isSeriesByCategory(category) || _isSeriesByName(currentName);
        final seriesInfo = _parseSeriesInfo(currentName);
        final type = (isSeries || seriesInfo != null) ? MovieType.series : MovieType.movie;
        final normalizedCategory = _normalizeCategory(category);
        
        movies.add(Movie(
          id: _generateId(cleanedName, url),
          name: cleanedName,
          url: url,
          logo: currentLogo,
          category: normalizedCategory,
          type: type,
          isAdult: isAdult,
          seriesName: seriesInfo?.baseName,
          season: seriesInfo?.season,
          episode: seriesInfo?.episode,
        ));
        
        currentName = null;
        currentCategory = null;
        currentLogo = null;
      }
    }
    
    return movies;
  }

  static List<GroupedSeries> _groupSeries(List<Movie> movies) {
    final Map<String, List<Movie>> seriesMap = {};
    
    for (final movie in movies) {
      if (movie.type == MovieType.series && movie.seriesName != null) {
        final key = '${movie.seriesName}_${movie.category}';
        seriesMap.putIfAbsent(key, () => []).add(movie);
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
        id: '${first.seriesName!.hashCode}_${first.category.hashCode}',
        name: first.seriesName!,
        logo: first.logo,
        category: first.category,
        seasons: Map.fromEntries(seasons),
        isAdult: first.isAdult,
      ));
    }
    
    grouped.sort((a, b) => a.name.compareTo(b.name));
    return grouped;
  }

  static bool _shouldIgnoreCategory(String category) {
    final upper = category.toUpperCase();
    return _ignoredCategories.any((ignored) {
      final upperIgnored = ignored.toUpperCase();
      return upper.startsWith(upperIgnored) || upper == upperIgnored || category == ignored;
    });
  }

  static bool _isSeriesByCategory(String category) {
    final lower = category.toLowerCase();
    return _seriesCategoryKeywords.any((keyword) => lower.contains(keyword));
  }

  static bool _isSeriesByName(String name) {
    return _episodePatterns.any((pattern) => pattern.hasMatch(name));
  }

  static bool _isAdultContent(String name, String category) {
    final combined = '$name $category';
    return _adultKeywords.any((keyword) => combined.contains(keyword));
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

  static String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'^\d+\s*[-–]\s*'), '')
        .replaceAll(RegExp(r'\s*\[L\]\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(DUB\)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(LEG\)\s*', caseSensitive: false), '')
        .trim();
  }

  static String _generateId(String name, String url) {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim().replaceAll(RegExp(r'\s+'), '-');
    final urlHash = url.hashCode.abs().toString();
    final hashPart = urlHash.length > 6 ? urlHash.substring(0, 6) : urlHash;
    return '$normalized-$hashPart';
  }

  static String _normalizeCategory(String category) {
    if (category.startsWith('OND /')) {
      var normalized = category.replaceFirst('OND /', '').trim();
      if (normalized.endsWith(' -')) {
        normalized = normalized.substring(0, normalized.length - 2).trim();
      }
      if (normalized.isNotEmpty) {
        normalized = normalized[0].toUpperCase() + normalized.substring(1);
      }
      return normalized.isEmpty ? 'Filmes' : normalized;
    }
    
    if (category.startsWith('Series |')) {
      final normalized = category.replaceFirst('Series |', '').trim();
      return normalized.isEmpty ? 'Séries' : normalized;
    }
    
    if (category.startsWith('COLETÂNEA:')) {
      return category.replaceFirst('COLETÂNEA:', '').trim();
    }
    
    final lower = category.toLowerCase();
    if (lower.contains('netflix')) return 'Netflix';
    if (lower.contains('prime video') || lower.contains('amazon prime')) return 'Prime Video';
    if (lower.contains('disney')) return 'Disney+';
    if (lower.contains('max') && !lower.contains('mad max')) return 'Max';
    if (lower.contains('hbo')) return 'Max';
    if (lower.contains('globoplay')) return 'Globoplay';
    if (lower.contains('paramount')) return 'Paramount+';
    if (lower.contains('apple')) return 'Apple TV+';
    if (lower.contains('novela')) return 'Novelas';
    if (lower.contains('dorama')) return 'Doramas';
    if (lower.contains('anime') || lower.contains('crunchyroll')) return 'Animes';
    if (lower.contains('programas de tv')) return 'Programas de TV';
    
    return category;
  }

  /// Limpa cache
  void clearCache() {
    _cachedResult = null;
    debugPrint('🧹 Cache limpo');
  }

  /// Busca (usa cache)
  Future<List<Movie>> search(String query, {bool includeAdult = false}) async {
    final result = await loadAll(includeAdult: includeAdult);
    final lower = query.toLowerCase();
    
    return result.movies.where((movie) {
      final searchable = '${movie.name} ${movie.seriesName ?? ''} ${movie.category}'.toLowerCase();
      return searchable.contains(lower);
    }).toList();
  }
}
