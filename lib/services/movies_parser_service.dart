import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';

/// Serviço para parsear arquivos M3U8 e extrair filmes/séries
class MoviesParserService {
  static final MoviesParserService _instance = MoviesParserService._internal();
  factory MoviesParserService() => _instance;
  MoviesParserService._internal();

  List<Movie>? _cachedMovies;
  Map<String, List<Movie>>? _cachedByCategory;
  
  /// Categorias que devem ser IGNORADAS (TV ao vivo, esportes, etc.)
  static const List<String> _ignoredCategories = [
    // TV ao vivo - Canais com emoji ⏺️
    '⏺️ ABERTO',
    '⏺️ BAND',
    '⏺️ SBT',
    '⏺️ GLOBO',
    '⏺️ RECORD',
    '⏺️ HBO',
    '⏺️ TELECINE',
    '⏺️ DISCOVERY',
    '⏺️ CINE SKY',
    '⏺️ FILMES E SERIES',
    '⏺️ NOTICIA',
    '⏺️ NBA',
    '⏺️ RUNTIME',
    '⏺️ 4K',
    // Globo regionais
    'GLOBO (CENTRO-OESTE)',
    'GLOBO (NORDESTE)',
    'GLOBO (NORTE)',
    'GLOBO (SUDESTE)',
    'GLOBO (SUL)',
    // Esportes ao vivo
    '⚽APPLETV',
    '⚽DAZN',
    '⚽DISNEY',
    '⚽ESPORTE',
    '⚽HBO',
    '⚽PARAMOUNT',
    '⚽PREMIERE',
    '⚽PRIME',
    '⚽ COPINHA',
    // Reality shows e outros
    'A FAZENDA',
    'BBB 20',
    'BBB 2026',
    'ESTRELA DA CASA',
    'Área do cliente',
    'JOGOS DE HOJE',
    'RÁDIOS FM',
    // Canais ListaBR01
    'CANAIS:',
  ];

  /// Keywords de conteúdo adulto
  static const List<String> _adultKeywords = [
    'ADULTOS',
    '[HOT]',
    'XXX',
    '[Adulto]',
    'ADULTO',
    '❌❤️',
  ];

  /// Keywords que indicam séries na categoria
  static const List<String> _seriesCategoryKeywords = [
    'series',
    'série',
    'novelas',
    'doramas',
    'programas',
    'stand up',
    '24h',
  ];

  /// Padrões regex para detectar episódios no NOME
  static final List<RegExp> _episodePatterns = [
    RegExp(r'S\d+\s*E\d+', caseSensitive: false),           // S01E05, S01 E05
    RegExp(r'T\d+\s*E\d+', caseSensitive: false),           // T01E05, T01 E05
    RegExp(r'\d+\s*x\s*\d+', caseSensitive: false),         // 1x05
    RegExp(r'Temporada\s*\d+', caseSensitive: false),       // Temporada 1
    RegExp(r'Temp\.?\s*\d+', caseSensitive: false),         // Temp 1, Temp. 1
    RegExp(r'Season\s*\d+', caseSensitive: false),          // Season 1
  ];

  /// Padrão para extrair info de série (nome base, temporada, episódio)
  static final List<RegExp> _seriesInfoPatterns = [
    RegExp(r'^(.+?)\s*S(\d+)\s*E(\d+)', caseSensitive: false),
    RegExp(r'^(.+?)\s*T(\d+)\s*E(\d+)', caseSensitive: false),
    RegExp(r'^(.+?)\s*(\d+)\s*x\s*(\d+)', caseSensitive: false),
  ];

  /// Verifica se a categoria deve ser ignorada
  bool _shouldIgnoreCategory(String category) {
    final upperCategory = category.toUpperCase();
    return _ignoredCategories.any((ignored) {
      final upperIgnored = ignored.toUpperCase();
      // Verifica se começa com ou é igual
      return upperCategory.startsWith(upperIgnored) || 
             upperCategory == upperIgnored ||
             category == ignored;
    });
  }

  /// Verifica se é série pela categoria
  bool _isSeriesByCategory(String category) {
    final lowerCat = category.toLowerCase();
    return _seriesCategoryKeywords.any((keyword) => lowerCat.contains(keyword));
  }

  /// Verifica se é série pelo nome (padrões S01E01, etc.)
  bool _isSeriesByName(String name) {
    return _episodePatterns.any((pattern) => pattern.hasMatch(name));
  }

  bool _isAdultContent(String name, String category) {
    final combined = '$name $category';
    return _adultKeywords.any((keyword) => combined.contains(keyword));
  }

  /// Extrai informações de série do nome
  ({String baseName, int season, int episode})? _parseSeriesInfo(String name) {
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

  /// Limpa o nome removendo prefixos e sufixos
  String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'^\d+\s*[-–]\s*'), '') // Remove número no início
        .replaceAll(RegExp(r'\s*\[L\]\s*$', caseSensitive: false), '') // Remove [L]
        .replaceAll(RegExp(r'\s*\(DUB\)\s*', caseSensitive: false), '') // Remove (DUB)
        .replaceAll(RegExp(r'\s*\(LEG\)\s*', caseSensitive: false), '') // Remove (LEG)
        .trim();
  }

  String _generateId(String name, String url) {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim().replaceAll(RegExp(r'\s+'), '-');
    final urlHash = url.hashCode.abs().toString();
    final hashPart = urlHash.length > 6 ? urlHash.substring(0, 6) : urlHash;
    return '$normalized-$hashPart';
  }

  String _normalizeCategory(String category) {
    var normalized = category;
    
    if (category.startsWith('OND /')) {
      normalized = category.replaceFirst('OND /', '').trim();
      if (normalized.endsWith(' -')) {
        normalized = normalized.substring(0, normalized.length - 2).trim();
      }
      if (normalized.isNotEmpty) {
        normalized = normalized[0].toUpperCase() + normalized.substring(1);
      }
      return normalized.isEmpty ? 'Filmes' : normalized;
    }
    
    if (category.startsWith('Series |')) {
      normalized = category.replaceFirst('Series |', '').trim();
      return normalized.isEmpty ? 'Séries' : normalized;
    }
    
    if (category.startsWith('COLETÂNEA:')) {
      return category.replaceFirst('COLETÂNEA:', '').trim();
    }
    
    final lowerCat = category.toLowerCase();
    if (lowerCat.contains('netflix')) return 'Netflix';
    if (lowerCat.contains('prime video') || lowerCat.contains('amazon prime')) return 'Prime Video';
    if (lowerCat.contains('disney')) return 'Disney+';
    if (lowerCat.contains('max') && !lowerCat.contains('mad max')) return 'Max';
    if (lowerCat.contains('hbo')) return 'Max';
    if (lowerCat.contains('globoplay')) return 'Globoplay';
    if (lowerCat.contains('paramount')) return 'Paramount+';
    if (lowerCat.contains('apple')) return 'Apple TV+';
    if (lowerCat.contains('novela')) return 'Novelas';
    if (lowerCat.contains('dorama')) return 'Doramas';
    if (lowerCat.contains('anime') || lowerCat.contains('crunchyroll')) return 'Animes';
    if (lowerCat.contains('programas de tv')) return 'Programas de TV';
    
    return category;
  }

  Future<List<Movie>> _parseM3u8File(String assetPath) async {
    final List<Movie> movies = [];
    
    try {
      debugPrint('Carregando arquivo: $assetPath');
      final content = await rootBundle.loadString(assetPath);
      final lines = content.split('\n');
      debugPrint('Total de linhas: ${lines.length}');
      
      String? currentName;
      String? currentCategory;
      String? currentLogo;
      int parsedCount = 0;
      int skippedTvCount = 0;
      
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
          
          // IGNORA URLs .ts (streams ao vivo)
          if (url.toLowerCase().endsWith('.ts')) {
            skippedTvCount++;
            currentName = null;
            currentCategory = null;
            currentLogo = null;
            continue;
          }
          
          // Se não tem categoria, usa "Outros"
          final category = currentCategory ?? 'Outros';
          
          // IGNORA apenas categorias na lista de ignoradas
          if (_shouldIgnoreCategory(category)) {
            skippedTvCount++;
            currentName = null;
            currentCategory = null;
            currentLogo = null;
            continue;
          }
          
          // Limpa o nome
          final cleanedName = _cleanName(currentName);
          
          // Verifica se é conteúdo adulto
          final isAdult = _isAdultContent(currentName, category);
          
          // Detecta se é série pela categoria OU pelo nome
          final isSeries = _isSeriesByCategory(category) || _isSeriesByName(currentName);
          final seriesInfo = _parseSeriesInfo(currentName);
          
          final MovieType type = (isSeries || seriesInfo != null) ? MovieType.series : MovieType.movie;
          
          // Normaliza categoria para exibição
          final normalizedCategory = _normalizeCategory(category);
          
          final movie = Movie(
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
          );
          
          movies.add(movie);
          parsedCount++;
          
          currentName = null;
          currentCategory = null;
          currentLogo = null;
        }
      }
      
      debugPrint('Parseados: $parsedCount | Ignorados: $skippedTvCount');
    } catch (e, stack) {
      debugPrint('Erro ao parsear $assetPath: $e');
      debugPrint('Stack: $stack');
    }
    
    return movies;
  }

  Future<List<Movie>> loadAllMovies({bool includeAdult = false}) async {
    if (_cachedMovies != null) {
      debugPrint('Usando cache: ${_cachedMovies!.length} itens');
      return includeAdult ? _cachedMovies! : _cachedMovies!.where((m) => !m.isAdult).toList();
    }

    debugPrint('Carregando filmes e series...');
    final List<Movie> allMovies = [];
    
    final movies1 = await _parseM3u8File('assets/ListaBR01.m3u8');
    final movies2 = await _parseM3u8File('assets/ListaBR02.m3u8');
    
    allMovies.addAll(movies1);
    allMovies.addAll(movies2);
    
    debugPrint('Total bruto: ${allMovies.length}');
    
    final seen = <String>{};
    final uniqueMovies = allMovies.where((movie) {
      if (seen.contains(movie.url)) return false;
      seen.add(movie.url);
      return true;
    }).toList();
    
    _cachedMovies = uniqueMovies;
    
    final movieCount = uniqueMovies.where((m) => m.type == MovieType.movie).length;
    final seriesCount = uniqueMovies.where((m) => m.type == MovieType.series).length;
    final adultCount = uniqueMovies.where((m) => m.isAdult).length;
    
    debugPrint('===================================');
    debugPrint('RESULTADO FINAL DO PARSING:');
    debugPrint('===================================');
    debugPrint('Filmes: $movieCount');
    debugPrint('Series/Episodios: $seriesCount');
    debugPrint('Adulto: $adultCount');
    debugPrint('Total unico: ${uniqueMovies.length}');
    debugPrint('===================================');
    
    return includeAdult ? uniqueMovies : uniqueMovies.where((m) => !m.isAdult).toList();
  }

  Future<Map<String, List<Movie>>> getMoviesByCategory({bool includeAdult = false}) async {
    if (_cachedByCategory != null) {
      if (includeAdult) return _cachedByCategory!;
      
      final filtered = <String, List<Movie>>{};
      for (final entry in _cachedByCategory!.entries) {
        final movies = entry.value.where((m) => !m.isAdult).toList();
        if (movies.isNotEmpty) {
          filtered[entry.key] = movies;
        }
      }
      return filtered;
    }

    final movies = await loadAllMovies(includeAdult: true);
    final Map<String, List<Movie>> grouped = {};

    for (final movie in movies) {
      grouped.putIfAbsent(movie.category, () => []).add(movie);
    }

    _cachedByCategory = grouped;

    debugPrint('Categorias encontradas: ${grouped.keys.length}');
    for (final entry in grouped.entries) {
      debugPrint('  - ${entry.key}: ${entry.value.length} itens');
    }
    
    return includeAdult 
        ? grouped 
        : Map.fromEntries(
            grouped.entries
                .map((e) => MapEntry(e.key, e.value.where((m) => !m.isAdult).toList()))
                .where((e) => e.value.isNotEmpty)
          );
  }

  Future<List<String>> getAvailableCategories({bool includeAdult = false}) async {
    final byCategory = await getMoviesByCategory(includeAdult: includeAdult);
    
    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    
    return sorted.map((e) => e.key).toList();
  }

  Future<List<GroupedSeries>> groupSeries(List<Movie> movies) async {
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
    
    debugPrint('Series agrupadas: ${grouped.length}');
    
    return grouped;
  }

  void clearCache() {
    _cachedMovies = null;
    _cachedByCategory = null;
    debugPrint('Cache limpo');
  }

  Future<List<Movie>> search(String query, {bool includeAdult = false}) async {
    final movies = await loadAllMovies(includeAdult: includeAdult);
    final lowerQuery = query.toLowerCase();
    
    return movies.where((movie) {
      final searchable = '${movie.name} ${movie.seriesName ?? ''} ${movie.category}'.toLowerCase();
      return searchable.contains(lowerQuery);
    }).toList();
  }
}
