/// Modelo de Membro do Elenco (TMDB)
class CastMember {
  final int id;
  final String name;
  final String? character;
  final String? photo;

  const CastMember({
    required this.id,
    required this.name,
    this.character,
    this.photo,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      character: json['character'] as String?,
      photo: json['photo'] as String?,
    );
  }
}

/// Modelo de Recomendação (TMDB)
class Recommendation {
  final int id;
  final String title;
  final String? poster;
  final double? rating;

  const Recommendation({
    required this.id,
    required this.title,
    this.poster,
    this.rating,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      poster: json['poster'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }
}

/// Dados TMDB do conteúdo
class TMDBData {
  final int? id;
  final String? imdbId;
  final String? title;
  final String? originalTitle;
  final String? tagline;
  final String? overview;
  final String? status;
  final String? language;
  final String? releaseDate;
  final String? firstAirDate;
  final String? lastAirDate;
  final String? year;
  final int? runtime;
  final int? episodeRuntime;
  final double? rating;
  final int? voteCount;
  final double? popularity;
  final String? certification;
  final List<String>? genres;
  final String? poster;
  final String? posterHD;
  final String? backdrop;
  final String? backdropHD;
  final String? logo;
  final List<CastMember>? cast;
  final List<Recommendation>? recommendations;
  final List<String>? creators;
  final List<String>? keywords;

  const TMDBData({
    this.id,
    this.imdbId,
    this.title,
    this.originalTitle,
    this.tagline,
    this.overview,
    this.status,
    this.language,
    this.releaseDate,
    this.firstAirDate,
    this.lastAirDate,
    this.year,
    this.runtime,
    this.episodeRuntime,
    this.rating,
    this.voteCount,
    this.popularity,
    this.certification,
    this.genres,
    this.poster,
    this.posterHD,
    this.backdrop,
    this.backdropHD,
    this.logo,
    this.cast,
    this.recommendations,
    this.creators,
    this.keywords,
  });

  factory TMDBData.fromJson(Map<String, dynamic> json) {
    return TMDBData(
      id: json['id'] as int?,
      imdbId: json['imdbId'] as String?,
      title: json['title'] as String?,
      originalTitle: json['originalTitle'] as String?,
      tagline: json['tagline'] as String?,
      overview: json['overview'] as String?,
      status: json['status'] as String?,
      language: json['language'] as String?,
      releaseDate: json['releaseDate'] as String?,
      firstAirDate: json['firstAirDate'] as String?,
      lastAirDate: json['lastAirDate'] as String?,
      year: json['year'] as String?,
      runtime: json['runtime'] as int?,
      episodeRuntime: json['episodeRuntime'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      voteCount: json['voteCount'] as int?,
      popularity: (json['popularity'] as num?)?.toDouble(),
      certification: json['certification'] as String?,
      genres: (json['genres'] as List<dynamic>?)?.cast<String>(),
      poster: json['poster'] as String?,
      posterHD: json['posterHD'] as String?,
      backdrop: json['backdrop'] as String?,
      backdropHD: json['backdropHD'] as String?,
      logo: json['logo'] as String?,
      cast: (json['cast'] as List<dynamic>?)
          ?.map((c) => CastMember.fromJson(c as Map<String, dynamic>))
          .toList(),
      recommendations: (json['recommendations'] as List<dynamic>?)
          ?.map((r) => Recommendation.fromJson(r as Map<String, dynamic>))
          .toList(),
      creators: (json['creators'] as List<dynamic>?)?.cast<String>(),
      keywords: (json['keywords'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Duração formatada
  String get formattedRuntime {
    final mins = runtime ?? episodeRuntime;
    if (mins == null) return '';
    final hours = mins ~/ 60;
    final minutes = mins % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }

  /// Rating formatado (ex: "8.5")
  String get formattedRating => rating?.toStringAsFixed(1) ?? '';

  /// Gêneros como string
  String get genresText => genres?.join(', ') ?? '';
}

/// Modelo de Filme ou Episódio de Série
class Movie {
  final String id;
  final String name;
  final String url;
  final String? logo;
  final String category;
  final MovieType type;
  final bool isAdult;
  
  // Info de série (quando type == series)
  final String? seriesName;
  final int? season;
  final int? episode;
  
  // Episódios de série (para séries com estrutura de episódios)
  final Map<String, List<Episode>>? episodes;
  final int? totalEpisodes;
  final int? totalSeasons;
  
  // Dados TMDB
  final TMDBData? tmdb;

  const Movie({
    required this.id,
    required this.name,
    required this.url,
    this.logo,
    required this.category,
    this.type = MovieType.movie,
    this.isAdult = false,
    this.seriesName,
    this.season,
    this.episode,
    this.episodes,
    this.totalEpisodes,
    this.totalSeasons,
    this.tmdb,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    // Parse episodes se existir
    Map<String, List<Episode>>? episodesMap;
    if (json['episodes'] != null) {
      final rawEpisodes = json['episodes'] as Map<String, dynamic>;
      episodesMap = {};
      rawEpisodes.forEach((season, eps) {
        final epsList = (eps as List<dynamic>)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList();
        episodesMap![season] = epsList;
      });
    }
    
    // Parse TMDB data se existir
    TMDBData? tmdbData;
    if (json['tmdb'] != null) {
      tmdbData = TMDBData.fromJson(json['tmdb'] as Map<String, dynamic>);
    }
    
    // Determina URL - para séries, pode não ter URL direta
    String url = json['url'] as String? ?? '';
    if (url.isEmpty && episodesMap != null && episodesMap.isNotEmpty) {
      // Usa a URL do primeiro episódio como fallback
      final firstSeason = episodesMap.values.first;
      if (firstSeason.isNotEmpty) {
        url = firstSeason.first.url;
      }
    }
    
    // Para séries com episodes, o seriesName é o nome ou título TMDB
    final isSeriesType = (json['type'] as String? ?? 'movie').toLowerCase() == 'series';
    String? seriesName = json['seriesName'] as String?;
    if (seriesName == null && isSeriesType) {
      // Usa o título TMDB ou o nome
      seriesName = tmdbData?.title ?? json['name'] as String?;
    }
    
    // Conta episódios e temporadas se tiver episodes
    int? totalEpisodes = json['totalEpisodes'] as int?;
    int? totalSeasons = json['totalSeasons'] as int?;
    if (episodesMap != null && episodesMap.isNotEmpty) {
      totalSeasons ??= episodesMap.length;
      totalEpisodes ??= episodesMap.values.fold<int>(0, (sum, eps) => sum + eps.length);
    }
    
    return Movie(
      id: json['id'] as String,
      name: json['name'] as String,
      url: url,
      logo: json['logo'] as String?,
      category: json['category'] as String? ?? 'Outros',
      type: MovieType.fromString(json['type'] as String? ?? 'movie'),
      isAdult: json['isAdult'] as bool? ?? false,
      seriesName: seriesName,
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      episodes: episodesMap,
      totalEpisodes: totalEpisodes,
      totalSeasons: totalSeasons,
      tmdb: tmdbData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'logo': logo,
      'category': category,
      'type': type.name,
      'isAdult': isAdult,
      'seriesName': seriesName,
      'season': season,
      'episode': episode,
      'totalEpisodes': totalEpisodes,
      'totalSeasons': totalSeasons,
    };
  }

  /// Gera iniciais do nome para fallback de logo
  String get initials {
    final displayName = seriesName ?? name;
    return displayName
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  /// URL do poster TMDB ou logo com fallback
  String get posterUrl {
    // Prioriza poster TMDB
    if (tmdb?.poster != null && tmdb!.poster!.isNotEmpty) {
      return tmdb!.poster!;
    }
    // Fallback para logo existente
    if (logo != null && logo!.isNotEmpty) {
      return logo!;
    }
    // Avatar como último fallback
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(initials)}&background=ef4444&color=fff&size=256&bold=true&format=png';
  }
  
  /// URL do backdrop TMDB
  String? get backdropUrl => tmdb?.backdrop;
  
  /// URL do poster HD
  String? get posterHDUrl => tmdb?.posterHD;
  
  /// URL do backdrop HD  
  String? get backdropHDUrl => tmdb?.backdropHD;
  
  /// Rating (nota) do TMDB
  double? get rating => tmdb?.rating;
  
  /// Rating formatado
  String get ratingText => tmdb?.formattedRating ?? '';
  
  /// Ano de lançamento
  String? get year => tmdb?.year;
  
  /// Sinopse/Overview
  String? get overview => tmdb?.overview;
  
  /// Gêneros
  List<String>? get genres => tmdb?.genres;
  
  /// Gêneros como texto
  String get genresText => tmdb?.genresText ?? '';
  
  /// Duração formatada
  String get runtimeText => tmdb?.formattedRuntime ?? '';
  
  /// Elenco
  List<CastMember>? get cast => tmdb?.cast;
  
  /// Certificação (classificação indicativa)
  String? get certification => tmdb?.certification;
  
  /// Tagline
  String? get tagline => tmdb?.tagline;

  /// URL do logo com fallback (mantido para compatibilidade)
  String get logoUrl {
    if (logo != null && logo!.isNotEmpty) {
      return logo!;
    }
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(initials)}&background=ef4444&color=fff&size=256&bold=true&format=png';
  }

  /// Nome formatado do episódio (ex: "S01E05")
  String? get episodeTag {
    if (season != null && episode != null) {
      return 'S${season!.toString().padLeft(2, '0')}E${episode!.toString().padLeft(2, '0')}';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Movie && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Movie copyWith({
    String? id,
    String? name,
    String? url,
    String? logo,
    String? category,
    MovieType? type,
    bool? isAdult,
    String? seriesName,
    int? season,
    int? episode,
    Map<String, List<Episode>>? episodes,
    int? totalEpisodes,
    int? totalSeasons,
    TMDBData? tmdb,
  }) {
    return Movie(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo ?? this.logo,
      category: category ?? this.category,
      type: type ?? this.type,
      isAdult: isAdult ?? this.isAdult,
      seriesName: seriesName ?? this.seriesName,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      episodes: episodes ?? this.episodes,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      totalSeasons: totalSeasons ?? this.totalSeasons,
      tmdb: tmdb ?? this.tmdb,
    );
  }
}

/// Modelo de Episódio de Série
class Episode {
  final int episode;
  final String name;
  final String url;
  final String id;

  const Episode({
    required this.episode,
    required this.name,
    required this.url,
    required this.id,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      episode: json['episode'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      id: json['id'] as String? ?? '',
    );
  }
}

/// Tipo do conteúdo
enum MovieType {
  movie,
  series;

  static MovieType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'series':
        return MovieType.series;
      default:
        return MovieType.movie;
    }
  }
}

/// Série agrupada com temporadas
class GroupedSeries {
  final String id;
  final String name;
  final String? logo;
  final String category;
  final Map<int, List<Movie>> seasons;
  final bool isAdult;
  final TMDBData? tmdb;

  const GroupedSeries({
    required this.id,
    required this.name,
    this.logo,
    required this.category,
    required this.seasons,
    this.isAdult = false,
    this.tmdb,
  });

  /// Total de episódios (sem duplicados)
  int get episodeCount {
    int total = 0;
    for (final season in sortedSeasons) {
      total += getSeasonEpisodes(season).length;
    }
    return total;
  }

  /// Total de temporadas
  int get seasonCount => seasons.length;

  /// Iniciais para fallback de logo
  String get initials {
    return name
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  /// URL do poster TMDB ou logo
  String get posterUrl {
    if (tmdb?.poster != null && tmdb!.poster!.isNotEmpty) {
      return tmdb!.poster!;
    }
    if (logo != null && logo!.isNotEmpty) {
      return logo!;
    }
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(initials)}&background=8b5cf6&color=fff&size=256&bold=true&format=png';
  }

  /// URL do logo com fallback (mantido para compatibilidade)
  String get logoUrl => posterUrl;

  /// Lista ordenada de temporadas
  List<int> get sortedSeasons {
    final list = seasons.keys.toList();
    list.sort();
    return list;
  }

  /// Episódios de uma temporada ordenados e sem duplicados
  /// Remove episódios duplicados de forma inteligente:
  /// - Se existem dois episódios com mesmo número (ex: "Nome S01 E01" e "Nome (2016) S01 E01")
  /// - Prefere o que NÃO tem ano no nome
  /// - Se ambos têm ou ambos não têm ano, mantém o primeiro encontrado
  List<Movie> getSeasonEpisodes(int season) {
    final episodes = seasons[season] ?? [];
    if (episodes.isEmpty) return [];
    
    // Ordena primeiro por número do episódio
    episodes.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
    
    // Remove duplicados por número de episódio
    final deduped = <Movie>[];
    final seenEpisodes = <int, Movie>{};
    
    // Regex para detectar ano no nome: "(2016)", "(2024)", etc
    final yearPattern = RegExp(r'\(\d{4}\)');
    
    for (final ep in episodes) {
      final epNum = ep.episode ?? 0;
      
      if (!seenEpisodes.containsKey(epNum)) {
        // Primeiro episódio com este número
        seenEpisodes[epNum] = ep;
      } else {
        // Já existe um episódio com este número - decidir qual manter
        final existing = seenEpisodes[epNum]!;
        final existingHasYear = yearPattern.hasMatch(existing.name);
        final newHasYear = yearPattern.hasMatch(ep.name);
        
        // Prefere o que NÃO tem ano no nome
        if (existingHasYear && !newHasYear) {
          // O novo não tem ano, substitui o existente
          seenEpisodes[epNum] = ep;
        }
        // Se o existente não tem ano, mantém ele (não faz nada)
        // Se ambos têm ou não têm ano, mantém o primeiro (não faz nada)
      }
    }
    
    // Converte de volta para lista ordenada
    final sortedKeys = seenEpisodes.keys.toList()..sort();
    for (final key in sortedKeys) {
      deduped.add(seenEpisodes[key]!);
    }
    
    return deduped;
  }
}

/// Categorias de filmes/séries
class MovieCategory {
  static const String todos = 'Todos';
  static const String lancamentos = 'Lançamentos';
  static const String netflix = 'Netflix';
  static const String primeVideo = 'Prime Video';
  static const String disney = 'Disney+';
  static const String max = 'Max';
  static const String globoplay = 'Globoplay';
  static const String novelas = 'Novelas';
  static const String doramas = 'Doramas';
  static const String animes = 'Animes';
  static const String legendadas = 'Legendadas';
  static const String adulto = 'Adulto';

  /// Ícones das categorias de filmes
  static const Map<String, String> icons = {
    todos: '🎬',
    lancamentos: '🆕',
    netflix: '📺',
    primeVideo: '📦',
    disney: '🏰',
    max: '🎭',
    globoplay: '🌐',
    novelas: '💕',
    doramas: '🇰🇷',
    animes: '🎌',
    legendadas: '💬',
    adulto: '🔞',
  };

  /// Cores das categorias
  static const Map<String, int> colors = {
    todos: 0xFF64748B,
    lancamentos: 0xFFF59E0B,
    netflix: 0xFFE50914,
    primeVideo: 0xFF00A8E1,
    disney: 0xFF113CCF,
    max: 0xFF002BE7,
    globoplay: 0xFFFF6600,
    novelas: 0xFFEC4899,
    doramas: 0xFF10B981,
    animes: 0xFFF472B6,
    legendadas: 0xFF6366F1,
    adulto: 0xFF9333EA,
  };

  static String getIcon(String category) {
    return icons[category] ?? '🎬';
  }

  static int getColor(String category) {
    return colors[category] ?? 0xFF8B5CF6;
  }
}
