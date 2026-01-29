import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import 'json_lazy_service.dart';
import 'storage_service.dart';

/// Serviço para buscar tendências do TMDB
/// Retorna apenas conteúdos que existem no catálogo local
class TrendingService {
  static const String _apiKey = '15d2ea6d0dc1d476efbca3eba2b9bbfb';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const Duration _cacheDuration = Duration(minutes: 30);
  
  // Cache Memória
  static List<TrendingItem>? _todayCache;
  static DateTime? _todayCacheTime;
  static List<TrendingItem>? _weekCache;
  static DateTime? _weekCacheTime;
  
  // Cache Keys
  static const String _todayCacheKey = 'saimo_tv_trending_today';
  static const String _weekCacheKey = 'saimo_tv_trending_week';
  
  /// Busca tendências de hoje filtradas pelo catálogo local
  static Future<List<TrendingItem>> getTrendingToday(JsonLazyService service) async {
    // 1. Tenta memória
    if (_todayCache != null && _todayCacheTime != null) {
      if (DateTime.now().difference(_todayCacheTime!) < _cacheDuration) {
        return _todayCache!;
      }
    }
    
    final storage = StorageService();
    
    // 2. Tenta disco (se memória falhou/vazia)
    if (_todayCache == null) {
      final cachedJson = await storage.getString(_todayCacheKey);
      if (cachedJson != null) {
        try {
          final List<dynamic> list = jsonDecode(cachedJson);
          // O cache local não guarda o objeto Movie completo, então precisamos re-hidratar
          // Mas como isso seria lento, melhor apenas guardar os IDs e buscar do serviço
          // Por simplicidade e eficiência, vamos confiar na busca do TMDB + Filtro Local que já é rápida
          // A otimização principal será carregar o TMDB em paralelo
        } catch (e) {
          debugPrint('Erro ao ler cache disco hoje: $e');
        }
      }
    }
    
    debugPrint('🔥 Buscando tendências de hoje no TMDB (Paralelo)...');
    final items = await _fetchTrending('day');
    final filtered = await _filterByLocalCatalog(items, service);
    
    _todayCache = filtered;
    _todayCacheTime = DateTime.now();
    
    // Salva cache em disco (opcional, por enquanto mantemos apenas em memória para não complicar a serialização/deserialização do Movie)
    
    debugPrint('✅ Encontrados ${filtered.length} itens de tendências de hoje no catálogo');
    return filtered;
  }
  
  /// Busca tendências da semana filtradas pelo catálogo local
  static Future<List<TrendingItem>> getTrendingWeek(JsonLazyService service) async {
    // Verifica cache memória
    if (_weekCache != null && _weekCacheTime != null) {
      if (DateTime.now().difference(_weekCacheTime!) < _cacheDuration) {
        return _weekCache!;
      }
    }
    
    debugPrint('📅 Buscando tendências da semana no TMDB (Paralelo)...');
    final items = await _fetchTrending('week');
    final filtered = await _filterByLocalCatalog(items, service);
    
    _weekCache = filtered;
    _weekCacheTime = DateTime.now();
    
    debugPrint('✅ Encontrados ${filtered.length} itens de tendências da semana no catálogo');
    return filtered;
  }
  
  /// Busca ambas as listas em paralelo
  static Future<({List<TrendingItem> today, List<TrendingItem> week})> getAllTrending(JsonLazyService service) async {
    final results = await Future.wait([
      getTrendingToday(service),
      getTrendingWeek(service),
    ]);
    return (today: results[0], week: results[1]);
  }
  
  /// Limpa o cache
  static void clearCache() {
    _todayCache = null;
    _weekCache = null;
    _todayCacheTime = null;
    _weekCacheTime = null;
  }
  
  /// Busca tendências da API TMDB
  static Future<List<_TMDBTrendingResult>> _fetchTrending(String timeWindow) async {
    final List<_TMDBTrendingResult> allResults = [];
    
    try {
      // Busca 3 páginas EM PARALELO para performance máxima
      final futures = <Future<http.Response>>[];
      for (int page = 1; page <= 3; page++) {
        final url = '$_baseUrl/trending/all/$timeWindow?api_key=$_apiKey&language=pt-BR&page=$page';
        futures.add(http.get(Uri.parse(url)).timeout(const Duration(seconds: 10)));
      }
      
      final responses = await Future.wait(futures);
      
      for (final response in responses) {
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final results = (data['results'] as List?) ?? [];
          
          for (final item in results) {
            allResults.add(_TMDBTrendingResult.fromJson(item));
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar tendências TMDB: $e');
    }
    
    return allResults;
  }
  
  /// Filtra os itens do TMDB para mostrar apenas os que existem no catálogo local
  /// OTIMIZADO: Usa busca em lote (single pass)
  static Future<List<TrendingItem>> _filterByLocalCatalog(
    List<_TMDBTrendingResult> tmdbItems,
    JsonLazyService service,
  ) async {
    // Coleta todos os IDs para buscar de uma vez
    final tmdbIds = tmdbItems.map((e) => e.id).toList();
    
    // Busca em lote (muito mais rápido)
    final foundItems = await service.findBatchByTmdbIds(tmdbIds);
    
    final List<TrendingItem> filtered = [];
    
    for (final tmdbItem in tmdbItems) {
      final localItem = foundItems[tmdbItem.id];
      
      if (localItem != null) {
        filtered.add(TrendingItem(
          tmdbId: tmdbItem.id,
          title: tmdbItem.title ?? tmdbItem.name ?? localItem.name,
          posterPath: tmdbItem.posterPath,
          backdropPath: tmdbItem.backdropPath,
          mediaType: tmdbItem.mediaType,
          voteAverage: tmdbItem.voteAverage,
          localMovie: localItem,
        ));
      }
      
      // Limita a 20 itens
      if (filtered.length >= 20) break;
    }
    
    return filtered;
  }
}

/// Item de tendência com referência ao item local
class TrendingItem {
  final int tmdbId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType;
  final double? voteAverage;
  final Movie localMovie;
  
  const TrendingItem({
    required this.tmdbId,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.mediaType,
    this.voteAverage,
    required this.localMovie,
  });
  
  String? get posterUrl {
    if (posterPath != null && posterPath!.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w342$posterPath';
    }
    final localPoster = localMovie.posterUrl;
    return localPoster.isNotEmpty ? localPoster : null;
  }
  
  String get backdropUrl {
    if (backdropPath != null && backdropPath!.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w780$backdropPath';
    }
    return localMovie.backdropUrl ?? '';
  }
  
  double get rating => voteAverage ?? 0.0;
  
  bool get isSeries => mediaType == 'tv' || localMovie.type == MovieType.series;
}

/// Resultado da API TMDB
class _TMDBTrendingResult {
  final int id;
  final String? title;
  final String? name;
  final String mediaType;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  
  const _TMDBTrendingResult({
    required this.id,
    this.title,
    this.name,
    required this.mediaType,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
  });
  
  factory _TMDBTrendingResult.fromJson(Map<String, dynamic> json) {
    return _TMDBTrendingResult(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String?,
      name: json['name'] as String?,
      mediaType: json['media_type'] as String? ?? 'movie',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );
  }
}
