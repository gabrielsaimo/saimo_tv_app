import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serviço de busca de imagens, rating e classificação do TMDB
/// Usa sistema de pontuação (score) para encontrar resultado mais preciso
class TMDBImageService {
  static final TMDBImageService _instance = TMDBImageService._internal();
  factory TMDBImageService() => _instance;
  TMDBImageService._internal();

  static const String _apiKey = '15d2ea6d0dc1d476efbca3eba2b9bbfb';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p';

  // Caches
  final Map<String, String?> _imageCache = {};
  final Map<String, double?> _ratingCache = {};
  final Map<String, String?> _certificationCache = {};
  final Map<String, Map<String, dynamic>?> _detailsCache = {};

  // Categorias que indicam anime
  static const List<String> _animeCategories = [
    'crunchyroll',
    'funimation',
    'anime',
    'animes',
    'animação',
    'animacao',
  ];

  /// Busca imagem/poster do filme ou série
  static Future<String?> searchImage(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final instance = TMDBImageService();
    return instance._searchImage(title, type: type, category: category);
  }

  /// Busca nota/rating (0-10) do TMDB
  static Future<double?> searchRating(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final instance = TMDBImageService();
    return instance._searchRating(title, type: type, category: category);
  }

  /// Busca classificação indicativa (L, 10, 12, 14, 16, 18)
  static Future<String?> searchCertification(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final instance = TMDBImageService();
    return instance._searchCertification(title, type: type, category: category);
  }

  /// Busca todos os detalhes do filme/série
  static Future<Map<String, dynamic>?> searchMovieDetails(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final instance = TMDBImageService();
    return instance._searchMovieDetails(title, type: type, category: category);
  }

  // === Implementações internas ===

  Future<String?> _searchImage(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final cacheKey = _buildCacheKey(title, type, category);
    if (_imageCache.containsKey(cacheKey)) {
      return _imageCache[cacheKey];
    }

    final result = await _searchWithScore(title, type: type, category: category);
    final posterPath = result?['poster_path'];
    final imageUrl = posterPath != null ? '$_imageBase/w500$posterPath' : null;
    
    _imageCache[cacheKey] = imageUrl;
    return imageUrl;
  }

  Future<double?> _searchRating(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final cacheKey = _buildCacheKey(title, type, category);
    if (_ratingCache.containsKey(cacheKey)) {
      return _ratingCache[cacheKey];
    }

    final result = await _searchWithScore(title, type: type, category: category);
    final rating = result?['vote_average']?.toDouble();
    
    _ratingCache[cacheKey] = rating;
    return rating;
  }

  Future<String?> _searchCertification(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final cacheKey = _buildCacheKey(title, type, category);
    if (_certificationCache.containsKey(cacheKey)) {
      return _certificationCache[cacheKey];
    }

    final result = await _searchWithScore(title, type: type, category: category);
    if (result == null) {
      _certificationCache[cacheKey] = null;
      return null;
    }

    final id = result['id'];
    final mediaType = result['media_type'] ?? (type == 'movie' ? 'movie' : 'tv');
    
    String? certification;
    
    if (mediaType == 'movie') {
      certification = await _getMovieCertification(id);
    } else {
      certification = await _getSeriesCertification(id);
    }
    
    _certificationCache[cacheKey] = certification;
    return certification;
  }

  Future<Map<String, dynamic>?> _searchMovieDetails(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final cacheKey = _buildCacheKey(title, type, category);
    if (_detailsCache.containsKey(cacheKey)) {
      return _detailsCache[cacheKey];
    }

    final result = await _searchWithScore(title, type: type, category: category);
    if (result == null) {
      _detailsCache[cacheKey] = null;
      return null;
    }

    final id = result['id'];
    final mediaType = result['media_type'] ?? (type == 'movie' ? 'movie' : 'tv');
    
    Map<String, dynamic>? details;
    
    if (mediaType == 'movie') {
      details = await _getMovieFullDetails(id);
    } else {
      details = await _getSeriesFullDetails(id);
    }
    
    _detailsCache[cacheKey] = details;
    return details;
  }

  /// Busca com sistema de pontuação (score)
  Future<Map<String, dynamic>?> _searchWithScore(
    String title, {
    String type = 'multi',
    String? category,
  }) async {
    final cleanedTitle = _cleanTitle(title);
    final targetYear = _extractYear(title);
    final expectAnime = _isAnimeCategory(category);

    try {
      // Determina endpoint baseado no tipo
      String endpoint;
      if (type == 'movie') {
        endpoint = '/search/movie';
      } else if (type == 'series' || type == 'tv') {
        endpoint = '/search/tv';
      } else {
        endpoint = '/search/multi';
      }

      final params = <String, String>{
        'query': cleanedTitle,
        'language': 'pt-BR',
        'include_adult': 'false',
      };

      // Adiciona ano para filmes se disponível
      if (targetYear != null && type == 'movie') {
        params['year'] = targetYear.toString();
      }

      final response = await _makeRequest(endpoint, params);
      
      if (response == null || response['results'] == null) {
        return null;
      }

      final results = response['results'] as List;
      if (results.isEmpty) return null;

      // Calcula score para cada resultado
      final scoredResults = <Map<String, dynamic>>[];
      
      for (final result in results) {
        final score = _calculateMatchScore(
          result,
          cleanedTitle,
          targetYear,
          expectAnime,
          category,
        );
        scoredResults.add({
          'result': result,
          'score': score,
        });
      }

      // Ordena por score (maior primeiro)
      scoredResults.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      // Retorna o melhor match
      if (scoredResults.isNotEmpty) {
        return scoredResults.first['result'] as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Erro na busca TMDB: $e');
    }

    return null;
  }

  /// Calcula pontuação de match para um resultado
  int _calculateMatchScore(
    Map<String, dynamic> result,
    String searchTitle,
    int? targetYear,
    bool expectAnime,
    String? category,
  ) {
    int score = 0;
    
    // === Score por título ===
    final resultTitle = (result['title'] ?? result['name'] ?? '').toString();
    final normalizedSearch = _normalizeForComparison(searchTitle);
    final normalizedResult = _normalizeForComparison(resultTitle);
    
    if (normalizedResult == normalizedSearch) {
      score += 50; // Título exato
    } else if (normalizedResult.contains(normalizedSearch) || 
               normalizedSearch.contains(normalizedResult)) {
      score += 30; // Título parcial
    }

    // === Score por ano ===
    final releaseDate = result['release_date'] ?? result['first_air_date'] ?? '';
    final resultYear = _extractYearFromDate(releaseDate);
    
    if (targetYear != null && resultYear != null) {
      final yearDiff = (targetYear - resultYear).abs();
      
      if (yearDiff == 0) {
        score += 40; // Ano exato
      } else if (yearDiff <= 1) {
        score += 20; // Ano próximo (±1)
      } else if (yearDiff <= 3) {
        score += 5; // Ano próximo (±3)
      } else {
        score -= yearDiff * 3; // Penaliza anos muito diferentes
      }
    }

    // === Score por tipo (anime/live-action) ===
    final genreIds = result['genre_ids'] as List? ?? [];
    final originCountry = result['origin_country'] as List? ?? [];
    final originalLanguage = result['original_language'] ?? '';
    
    // Detecta se é anime (animação japonesa)
    final isLikelyAnime = genreIds.contains(16) && // 16 = Animation
                          (originalLanguage == 'ja' || 
                           originCountry.contains('JP'));
    
    final isAnimation = genreIds.contains(16);
    
    if (expectAnime) {
      if (isLikelyAnime) {
        score += 35; // É anime esperado
      } else if (isAnimation) {
        score += 15; // É animação
      }
    } else {
      if (isLikelyAnime) {
        score -= 20; // Anime não esperado
      }
    }

    // === Score por plataforma ===
    if (category != null) {
      final normalizedCategory = category.toLowerCase();
      
      // Bonus para Netflix
      if (normalizedCategory.contains('netflix')) {
        if (!isLikelyAnime && originCountry.contains('US')) {
          score += 10;
        }
      }
      
      // Bonus para Disney+
      if (normalizedCategory.contains('disney')) {
        if (isAnimation && !isLikelyAnime) {
          score += 10;
        }
      }
      
      // Bonus para Prime Video
      if (normalizedCategory.contains('prime') || normalizedCategory.contains('amazon')) {
        if (!isLikelyAnime) {
          score += 5;
        }
      }
    }

    // === Score por popularidade ===
    final voteCount = result['vote_count'] ?? 0;
    if (voteCount > 100) {
      score += 5; // Resultado confiável (muitos votos)
    }

    // === Bonus para poster disponível ===
    if (result['poster_path'] != null) {
      score += 10;
    }

    return score;
  }

  /// Obtém classificação indicativa de filme
  Future<String?> _getMovieCertification(int movieId) async {
    try {
      final response = await _makeRequest(
        '/movie/$movieId/release_dates',
        {},
      );
      
      if (response == null) return null;
      
      final results = response['results'] as List? ?? [];
      
      // Prioridade: Brasil, EUA, genérico
      for (final country in ['BR', 'US']) {
        final countryData = results.firstWhere(
          (r) => r['iso_3166_1'] == country,
          orElse: () => null,
        );
        
        if (countryData != null) {
          final releases = countryData['release_dates'] as List? ?? [];
          for (final release in releases) {
            final cert = release['certification'];
            if (cert != null && cert.toString().isNotEmpty) {
              return _normalizeCertification(cert.toString());
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao obter certificação do filme: $e');
    }
    
    return null;
  }

  /// Obtém classificação indicativa de série
  Future<String?> _getSeriesCertification(int seriesId) async {
    try {
      final response = await _makeRequest(
        '/tv/$seriesId/content_ratings',
        {},
      );
      
      if (response == null) return null;
      
      final results = response['results'] as List? ?? [];
      
      // Prioridade: Brasil, EUA
      for (final country in ['BR', 'US']) {
        final countryData = results.firstWhere(
          (r) => r['iso_3166_1'] == country,
          orElse: () => null,
        );
        
        if (countryData != null) {
          final rating = countryData['rating'];
          if (rating != null && rating.toString().isNotEmpty) {
            return _normalizeCertification(rating.toString());
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao obter certificação da série: $e');
    }
    
    return null;
  }

  /// Obtém detalhes completos do filme
  Future<Map<String, dynamic>?> _getMovieFullDetails(int movieId) async {
    try {
      final response = await _makeRequest(
        '/movie/$movieId',
        {
          'language': 'pt-BR',
          'append_to_response': 'credits,release_dates',
        },
      );
      
      if (response == null) return null;
      
      // Extrai certificação
      String? certification;
      if (response['release_dates'] != null) {
        final results = response['release_dates']['results'] as List? ?? [];
        for (final country in ['BR', 'US']) {
          final countryData = results.firstWhere(
            (r) => r['iso_3166_1'] == country,
            orElse: () => null,
          );
          if (countryData != null) {
            final releases = countryData['release_dates'] as List? ?? [];
            for (final release in releases) {
              final cert = release['certification'];
              if (cert != null && cert.toString().isNotEmpty) {
                certification = _normalizeCertification(cert.toString());
                break;
              }
            }
          }
          if (certification != null) break;
        }
      }
      
      // Extrai diretor e elenco
      String? director;
      List<String> cast = [];
      if (response['credits'] != null) {
        final crew = response['credits']['crew'] as List? ?? [];
        for (final member in crew) {
          if (member['job'] == 'Director') {
            director = member['name'];
            break;
          }
        }
        
        final castList = response['credits']['cast'] as List? ?? [];
        cast = castList.take(5).map((c) => c['name'].toString()).toList();
      }
      
      return {
        'id': response['id'],
        'title': response['title'],
        'originalTitle': response['original_title'],
        'overview': response['overview'],
        'releaseDate': response['release_date'],
        'year': _extractYearFromDate(response['release_date'] ?? ''),
        'runtime': response['runtime'],
        'genres': (response['genres'] as List? ?? []).map((g) => g['name'].toString()).toList(),
        'rating': response['vote_average']?.toDouble(),
        'voteCount': response['vote_count'],
        'certification': certification,
        'posterPath': response['poster_path'] != null 
            ? '$_imageBase/w500${response['poster_path']}' 
            : null,
        'backdropPath': response['backdrop_path'] != null 
            ? '$_imageBase/w1280${response['backdrop_path']}' 
            : null,
        'director': director,
        'cast': cast,
        'tagline': response['tagline'],
      };
    } catch (e) {
      debugPrint('Erro ao obter detalhes do filme: $e');
    }
    
    return null;
  }

  /// Obtém detalhes completos da série
  Future<Map<String, dynamic>?> _getSeriesFullDetails(int seriesId) async {
    try {
      final response = await _makeRequest(
        '/tv/$seriesId',
        {
          'language': 'pt-BR',
          'append_to_response': 'credits,content_ratings',
        },
      );
      
      if (response == null) return null;
      
      // Extrai certificação
      String? certification;
      if (response['content_ratings'] != null) {
        final results = response['content_ratings']['results'] as List? ?? [];
        for (final country in ['BR', 'US']) {
          final countryData = results.firstWhere(
            (r) => r['iso_3166_1'] == country,
            orElse: () => null,
          );
          if (countryData != null) {
            final rating = countryData['rating'];
            if (rating != null && rating.toString().isNotEmpty) {
              certification = _normalizeCertification(rating.toString());
              break;
            }
          }
        }
      }
      
      // Extrai elenco
      List<String> cast = [];
      if (response['credits'] != null) {
        final castList = response['credits']['cast'] as List? ?? [];
        cast = castList.take(5).map((c) => c['name'].toString()).toList();
      }
      
      return {
        'id': response['id'],
        'title': response['name'],
        'originalTitle': response['original_name'],
        'overview': response['overview'],
        'releaseDate': response['first_air_date'],
        'year': _extractYearFromDate(response['first_air_date'] ?? ''),
        'seasons': response['number_of_seasons'],
        'episodes': response['number_of_episodes'],
        'genres': (response['genres'] as List? ?? []).map((g) => g['name'].toString()).toList(),
        'rating': response['vote_average']?.toDouble(),
        'voteCount': response['vote_count'],
        'certification': certification,
        'posterPath': response['poster_path'] != null 
            ? '$_imageBase/w500${response['poster_path']}' 
            : null,
        'backdropPath': response['backdrop_path'] != null 
            ? '$_imageBase/w1280${response['backdrop_path']}' 
            : null,
        'cast': cast,
        'tagline': response['tagline'],
      };
    } catch (e) {
      debugPrint('Erro ao obter detalhes da série: $e');
    }
    
    return null;
  }

  // === Métodos utilitários ===

  Future<Map<String, dynamic>?> _makeRequest(
    String endpoint,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse('$_baseUrl$endpoint').replace(
      queryParameters: {'api_key': _apiKey, ...params},
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 429) {
        await Future.delayed(const Duration(milliseconds: 500));
        return _makeRequest(endpoint, params);
      }
    } catch (e) {
      debugPrint('Erro na requisição: $e');
    }

    return null;
  }

  String _buildCacheKey(String title, String type, String? category) {
    final cleanedTitle = _cleanTitle(title);
    final year = _extractYear(title);
    return '${type}_${cleanedTitle}_${year ?? ''}_${category ?? ''}';
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*\(\d{4}\)\s*'), ' ')
        .replaceAll(RegExp(r'\s*S\d+E\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*EP?\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*Episódio\s*\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*Temporada\s*\d+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*(4K|1080p|720p|480p|CAM|HDTS|TS|HD|SD|DVD|BLURAY|WEBRIP|WEB-DL|WEBDL)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*(LEGENDADO|DUBLADO|DUAL|DUB|LEG|NACIONAL)', caseSensitive: false), '')
        .replaceAll(RegExp(r'[™®©]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int? _extractYear(String name) {
    final match = RegExp(r'\((\d{4})\)').firstMatch(name);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  int? _extractYearFromDate(String date) {
    if (date.isEmpty) return null;
    final parts = date.split('-');
    if (parts.isNotEmpty) {
      return int.tryParse(parts[0]);
    }
    return null;
  }

  bool _isAnimeCategory(String? category) {
    if (category == null) return false;
    final normalizedCategory = category.toLowerCase();
    return _animeCategories.any((anime) => normalizedCategory.contains(anime));
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

  /// Normaliza classificação para padrão brasileiro
  String _normalizeCertification(String cert) {
    final upper = cert.toUpperCase();
    
    // Já está no padrão brasileiro
    if (['L', '10', '12', '14', '16', '18'].contains(upper)) {
      return upper;
    }
    
    // Converte do padrão americano
    switch (upper) {
      case 'G':
      case 'TV-G':
      case 'TV-Y':
      case 'TV-Y7':
        return 'L';
      case 'PG':
      case 'TV-PG':
        return '10';
      case 'PG-13':
      case 'TV-14':
        return '14';
      case 'R':
      case 'TV-MA':
        return '16';
      case 'NC-17':
        return '18';
      default:
        // Tenta extrair número
        final numMatch = RegExp(r'(\d+)').firstMatch(upper);
        if (numMatch != null) {
          return numMatch.group(1)!;
        }
        return cert;
    }
  }

  /// Limpa todos os caches
  void clearAllCaches() {
    _imageCache.clear();
    _ratingCache.clear();
    _certificationCache.clear();
    _detailsCache.clear();
  }
}
