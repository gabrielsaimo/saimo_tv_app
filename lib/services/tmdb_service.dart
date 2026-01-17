import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tmdb_model.dart';

/// Serviço para buscar dados do TMDB (The Movie Database)
/// Inclui informações detalhadas de filmes e séries, elenco, trailers, etc.
class TMDBService {
  static final TMDBService _instance = TMDBService._internal();
  factory TMDBService() => _instance;
  TMDBService._internal();

  static const String _apiKey = '15d2ea6d0dc1d476efbca3eba2b9bbfb';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p';

  // Cache de resultados
  final Map<String, dynamic> _cache = {};
  static const Duration _cacheExpiration = Duration(hours: 24);
  final Map<String, DateTime> _cacheTimestamps = {};

  // Rate limiting
  final _requestQueue = <_QueuedRequest>[];
  bool _isProcessingQueue = false;
  static const int _maxRequestsPerSecond = 40;
  DateTime _lastRequestTime = DateTime.now();
  int _requestsThisSecond = 0;

  /// Busca filme por nome
  Future<List<TMDBSearchResult>> searchMovies(String query) async {
    if (query.isEmpty) return [];

    final cacheKey = 'search_movie_$query';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/search/movie',
        {'query': query, 'language': 'pt-BR'},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .map((r) => TMDBSearchResult.fromJson(r, 'movie'))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao buscar filmes: $e');
    }

    return [];
  }

  /// Busca série por nome
  Future<List<TMDBSearchResult>> searchSeries(String query) async {
    if (query.isEmpty) return [];

    final cacheKey = 'search_tv_$query';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/search/tv',
        {'query': query, 'language': 'pt-BR'},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .map((r) => TMDBSearchResult.fromJson(r, 'tv'))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao buscar séries: $e');
    }

    return [];
  }

  /// Busca multi (filmes e séries)
  Future<List<TMDBSearchResult>> searchMulti(String query) async {
    if (query.isEmpty) return [];

    final cacheKey = 'search_multi_$query';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/search/multi',
        {'query': query, 'language': 'pt-BR'},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .where((r) => r['media_type'] == 'movie' || r['media_type'] == 'tv')
            .map((r) => TMDBSearchResult.fromJson(r, r['media_type']))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao buscar: $e');
    }

    return [];
  }

  /// Obtém detalhes completos de um filme
  Future<TMDBMovie?> getMovieDetails(int movieId) async {
    final cacheKey = 'movie_$movieId';
    if (_isCacheValid(cacheKey)) {
      return _cache[cacheKey] as TMDBMovie;
    }

    try {
      // Busca detalhes + créditos + vídeos em uma única chamada
      final response = await _makeRequest(
        '/movie/$movieId',
        {
          'language': 'pt-BR',
          'append_to_response': 'credits,videos,external_ids',
        },
      );

      if (response != null) {
        var movie = TMDBMovie.fromJson(response);

        // Parse créditos
        if (response['credits'] != null) {
          final cast = (response['credits']['cast'] as List?)
                  ?.take(20)
                  .map((c) => TMDBCastMember.fromJson(c))
                  .toList() ??
              [];
          final crew = (response['credits']['crew'] as List?)
                  ?.where((c) =>
                      c['job'] == 'Director' ||
                      c['job'] == 'Writer' ||
                      c['job'] == 'Screenplay' ||
                      c['job'] == 'Producer')
                  .map((c) => TMDBCrewMember.fromJson(c))
                  .toList() ??
              [];
          movie = movie.copyWith(cast: cast, crew: crew);
        }

        // Parse vídeos
        if (response['videos'] != null && response['videos']['results'] != null) {
          final videos = (response['videos']['results'] as List)
              .map((v) => TMDBVideo.fromJson(v))
              .where((v) => v.site == 'YouTube')
              .toList();
          movie = movie.copyWith(videos: videos);
        }

        _setCache(cacheKey, movie);
        return movie;
      }
    } catch (e) {
      print('Erro ao obter detalhes do filme: $e');
    }

    return null;
  }

  /// Obtém detalhes completos de uma série
  Future<TMDBSeries?> getSeriesDetails(int seriesId) async {
    final cacheKey = 'series_$seriesId';
    if (_isCacheValid(cacheKey)) {
      return _cache[cacheKey] as TMDBSeries;
    }

    try {
      final response = await _makeRequest(
        '/tv/$seriesId',
        {
          'language': 'pt-BR',
          'append_to_response': 'credits,videos,external_ids',
        },
      );

      if (response != null) {
        var series = TMDBSeries.fromJson(response);

        // Parse créditos
        if (response['credits'] != null) {
          final cast = (response['credits']['cast'] as List?)
                  ?.take(20)
                  .map((c) => TMDBCastMember.fromJson(c))
                  .toList() ??
              [];
          final crew = (response['credits']['crew'] as List?)
                  ?.where((c) =>
                      c['job'] == 'Director' ||
                      c['job'] == 'Writer' ||
                      c['job'] == 'Executive Producer')
                  .map((c) => TMDBCrewMember.fromJson(c))
                  .toList() ??
              [];
          series = series.copyWith(cast: cast, crew: crew);
        }

        // Parse vídeos
        if (response['videos'] != null && response['videos']['results'] != null) {
          final videos = (response['videos']['results'] as List)
              .map((v) => TMDBVideo.fromJson(v))
              .where((v) => v.site == 'YouTube')
              .toList();
          series = series.copyWith(videos: videos);
        }

        _setCache(cacheKey, series);
        return series;
      }
    } catch (e) {
      print('Erro ao obter detalhes da série: $e');
    }

    return null;
  }

  /// Busca filme/série por título e retorna detalhes completos
  Future<dynamic> getDetailsByTitle(String title, {bool isSeries = false}) async {
    final cleanedTitle = _cleanTitle(title);
    final year = _extractYear(title);

    final cacheKey = 'details_${cleanedTitle}_${isSeries ? 'tv' : 'movie'}';
    if (_isCacheValid(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      // Busca pelo título
      final searchType = isSeries ? 'tv' : 'movie';
      final yearParam = year != null && !isSeries ? {'year': year.toString()} : <String, String>{};
      
      final response = await _makeRequest(
        '/search/$searchType',
        {'query': cleanedTitle, 'language': 'pt-BR', ...yearParam},
      );

      if (response != null && response['results'] != null && response['results'].isNotEmpty) {
        final bestMatch = _findBestMatch(response['results'], cleanedTitle, year);
        if (bestMatch != null) {
          final id = bestMatch['id'] as int;
          final details = isSeries
              ? await getSeriesDetails(id)
              : await getMovieDetails(id);
          
          if (details != null) {
            _setCache(cacheKey, details);
            return details;
          }
        }
      }

      // Se não encontrou, tenta o tipo oposto
      final altType = isSeries ? 'movie' : 'tv';
      final altResponse = await _makeRequest(
        '/search/$altType',
        {'query': cleanedTitle, 'language': 'pt-BR'},
      );

      if (altResponse != null && altResponse['results'] != null && altResponse['results'].isNotEmpty) {
        final bestMatch = _findBestMatch(altResponse['results'], cleanedTitle, year);
        if (bestMatch != null) {
          final id = bestMatch['id'] as int;
          final details = !isSeries
              ? await getSeriesDetails(id)
              : await getMovieDetails(id);
          
          if (details != null) {
            _setCache(cacheKey, details);
            return details;
          }
        }
      }
    } catch (e) {
      print('Erro ao buscar detalhes por título: $e');
    }

    return null;
  }

  /// Obtém filmes populares
  Future<List<TMDBSearchResult>> getPopularMovies({int page = 1}) async {
    final cacheKey = 'popular_movies_$page';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/movie/popular',
        {'language': 'pt-BR', 'page': page.toString()},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .map((r) => TMDBSearchResult.fromJson(r, 'movie'))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao obter filmes populares: $e');
    }

    return [];
  }

  /// Obtém séries populares
  Future<List<TMDBSearchResult>> getPopularSeries({int page = 1}) async {
    final cacheKey = 'popular_series_$page';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/tv/popular',
        {'language': 'pt-BR', 'page': page.toString()},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .map((r) => TMDBSearchResult.fromJson(r, 'tv'))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao obter séries populares: $e');
    }

    return [];
  }

  /// Obtém filmes em lançamento
  Future<List<TMDBSearchResult>> getNowPlayingMovies({int page = 1}) async {
    final cacheKey = 'now_playing_$page';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/movie/now_playing',
        {'language': 'pt-BR', 'page': page.toString(), 'region': 'BR'},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .map((r) => TMDBSearchResult.fromJson(r, 'movie'))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao obter lançamentos: $e');
    }

    return [];
  }

  /// Obtém filmes mais bem avaliados
  Future<List<TMDBSearchResult>> getTopRatedMovies({int page = 1}) async {
    final cacheKey = 'top_rated_movies_$page';
    if (_isCacheValid(cacheKey)) {
      return (_cache[cacheKey] as List).cast<TMDBSearchResult>();
    }

    try {
      final response = await _makeRequest(
        '/movie/top_rated',
        {'language': 'pt-BR', 'page': page.toString()},
      );

      if (response != null && response['results'] != null) {
        final results = (response['results'] as List)
            .map((r) => TMDBSearchResult.fromJson(r, 'movie'))
            .toList();
        _setCache(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Erro ao obter top rated: $e');
    }

    return [];
  }

  // === Métodos auxiliares ===

  Future<Map<String, dynamic>?> _makeRequest(
    String endpoint,
    Map<String, String> params,
  ) async {
    // Rate limiting
    final now = DateTime.now();
    if (now.difference(_lastRequestTime).inSeconds >= 1) {
      _requestsThisSecond = 0;
      _lastRequestTime = now;
    }

    if (_requestsThisSecond >= _maxRequestsPerSecond) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    _requestsThisSecond++;

    final uri = Uri.parse('$_baseUrl$endpoint').replace(
      queryParameters: {'api_key': _apiKey, ...params},
    );

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 429) {
        // Rate limited - espera e tenta novamente
        await Future.delayed(const Duration(seconds: 1));
        return _makeRequest(endpoint, params);
      }
    } catch (e) {
      print('Erro na requisição TMDB: $e');
    }

    return null;
  }

  bool _isCacheValid(String key) {
    if (!_cache.containsKey(key)) return false;
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheExpiration;
  }

  void _setCache(String key, dynamic value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '')
        .replaceAll(RegExp(r'\s*S\d+E\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*EP?\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*Episódio\s*\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*Temporada\s*\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[™®©]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int? _extractYear(String name) {
    final match = RegExp(r'\((\d{4})\)').firstMatch(name);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  String _normalizeForComparison(String str) {
    return str
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Map<String, dynamic>? _findBestMatch(
    List<dynamic> results,
    String originalTitle,
    int? year,
  ) {
    if (results.isEmpty) return null;

    final normalizedOriginal = _normalizeForComparison(originalTitle);

    // Busca correspondência exata com ano
    for (final result in results) {
      final tmdbTitle = result['title'] ?? result['name'] ?? '';
      final normalizedTmdb = _normalizeForComparison(tmdbTitle);
      final tmdbYear = result['release_date']?.split('-')[0] ??
          result['first_air_date']?.split('-')[0];

      if (normalizedTmdb == normalizedOriginal &&
          (year == null || tmdbYear == year.toString())) {
        return result;
      }
    }

    // Busca correspondência exata sem ano
    for (final result in results) {
      final tmdbTitle = result['title'] ?? result['name'] ?? '';
      if (_normalizeForComparison(tmdbTitle) == normalizedOriginal) {
        return result;
      }
    }

    // Retorna primeiro com poster
    for (final result in results) {
      if (result['poster_path'] != null) {
        return result;
      }
    }

    return results.first;
  }

  /// Limpa o cache
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  /// Método estático simplificado para obter detalhes formatados para UI
  static Future<Map<String, dynamic>?> getDetailsForUI(
    String title, {
    bool isMovie = true,
  }) async {
    final instance = TMDBService();
    
    try {
      final details = await instance.getDetailsByTitle(title, isSeries: !isMovie);
      
      if (details == null) return null;
      
      if (details is TMDBMovie) {
        return {
          'id': details.id,
          'title': details.title,
          'overview': details.overview,
          'poster': details.posterPath != null ? getPosterUrl(details.posterPath) : null,
          'backdrop': details.backdropPath != null ? getBackdropUrl(details.backdropPath) : null,
          'year': details.releaseDate?.split('-').firstOrNull,
          'rating': details.voteAverage,
          'runtime': details.runtime,
          'genres': details.genres.join(', '),
          'director': details.crew.where((c) => c.job == 'Director').map((c) => c.name).join(', '),
          'cast': details.cast.take(5).map((c) => c.name).join(', '),
        };
      } else if (details is TMDBSeries) {
        return {
          'id': details.id,
          'title': details.name,
          'overview': details.overview,
          'poster': details.posterPath != null ? getPosterUrl(details.posterPath) : null,
          'backdrop': details.backdropPath != null ? getBackdropUrl(details.backdropPath) : null,
          'year': details.firstAirDate?.split('-').firstOrNull,
          'rating': details.voteAverage,
          'seasons': details.numberOfSeasons,
          'episodes': details.numberOfEpisodes,
          'genres': details.genres.join(', '),
          'cast': details.cast.take(5).map((c) => c.name).join(', '),
        };
      }
    } catch (e) {
      print('Erro ao obter detalhes: $e');
    }
    
    return null;
  }

  /// URLs de imagens
  static String getPosterUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/$size$path';
  }

  static String getBackdropUrl(String? path, {String size = 'w1280'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/$size$path';
  }

  static String getProfileUrl(String? path, {String size = 'w185'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/$size$path';
  }
}

class _QueuedRequest {
  final String endpoint;
  final Map<String, String> params;
  final Completer<Map<String, dynamic>?> completer;

  _QueuedRequest(this.endpoint, this.params, this.completer);
}
