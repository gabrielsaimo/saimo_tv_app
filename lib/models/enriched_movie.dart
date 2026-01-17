/// Modelos para filmes e séries enriched com dados do TMDB

/// Informação de elenco
class EnrichedCastMember {
  final int id;
  final String name;
  final String character;
  final String? photo;

  const EnrichedCastMember({
    required this.id,
    required this.name,
    required this.character,
    this.photo,
  });

  factory EnrichedCastMember.fromJson(Map<String, dynamic> json) {
    return EnrichedCastMember(
      id: json['id'] as int,
      name: json['name'] as String,
      character: json['character'] as String? ?? '',
      photo: json['photo'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'character': character,
      'photo': photo,
    };
  }
}

/// Recomendação de filme/série
class EnrichedRecommendation {
  final int id;
  final String title;
  final String? poster;

  const EnrichedRecommendation({
    required this.id,
    required this.title,
    this.poster,
  });

  factory EnrichedRecommendation.fromJson(Map<String, dynamic> json) {
    return EnrichedRecommendation(
      id: json['id'] as int,
      title: json['title'] as String,
      poster: json['poster'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'poster': poster,
    };
  }
}

/// Dados TMDB do filme/série
class EnrichedTMDB {
  final int id;
  final String? imdbId;
  final String title;
  final String? originalTitle;
  final String? tagline;
  final String? overview;
  final String status;
  final String language;
  final String? releaseDate;
  final String year;
  final int? runtime;
  final double rating;
  final int voteCount;
  final double popularity;
  final String? certification;
  final List<String> genres;
  final String? poster;
  final String? posterHD;
  final String? backdrop;
  final String? backdropHD;
  final String? logo;
  final List<EnrichedCastMember> cast;
  final List<String> companies;
  final List<String> countries;
  final List<String> keywords;
  final List<EnrichedRecommendation> recommendations;

  const EnrichedTMDB({
    required this.id,
    this.imdbId,
    required this.title,
    this.originalTitle,
    this.tagline,
    this.overview,
    required this.status,
    required this.language,
    this.releaseDate,
    required this.year,
    this.runtime,
    required this.rating,
    required this.voteCount,
    required this.popularity,
    this.certification,
    required this.genres,
    this.poster,
    this.posterHD,
    this.backdrop,
    this.backdropHD,
    this.logo,
    required this.cast,
    required this.companies,
    required this.countries,
    required this.keywords,
    required this.recommendations,
  });

  factory EnrichedTMDB.fromJson(Map<String, dynamic> json) {
    return EnrichedTMDB(
      id: json['id'] as int,
      imdbId: json['imdbId'] as String?,
      title: json['title'] as String,
      originalTitle: json['originalTitle'] as String?,
      tagline: json['tagline'] as String?,
      overview: json['overview'] as String?,
      status: json['status'] as String? ?? 'Unknown',
      language: json['language'] as String? ?? 'en',
      releaseDate: json['releaseDate'] as String?,
      year: json['year'] as String? ?? '',
      runtime: json['runtime'] as int?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['voteCount'] as int? ?? 0,
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0.0,
      certification: json['certification'] as String?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      poster: json['poster'] as String?,
      posterHD: json['posterHD'] as String?,
      backdrop: json['backdrop'] as String?,
      backdropHD: json['backdropHD'] as String?,
      logo: json['logo'] as String?,
      cast: (json['cast'] as List<dynamic>?)
              ?.map((e) => EnrichedCastMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      companies: (json['companies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      countries: (json['countries'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      keywords: (json['keywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((e) => EnrichedRecommendation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imdbId': imdbId,
      'title': title,
      'originalTitle': originalTitle,
      'tagline': tagline,
      'overview': overview,
      'status': status,
      'language': language,
      'releaseDate': releaseDate,
      'year': year,
      'runtime': runtime,
      'rating': rating,
      'voteCount': voteCount,
      'popularity': popularity,
      'certification': certification,
      'genres': genres,
      'poster': poster,
      'posterHD': posterHD,
      'backdrop': backdrop,
      'backdropHD': backdropHD,
      'logo': logo,
      'cast': cast.map((e) => e.toJson()).toList(),
      'companies': companies,
      'countries': countries,
      'keywords': keywords,
      'recommendations': recommendations.map((e) => e.toJson()).toList(),
    };
  }
}

/// Episódio de uma série
class EnrichedEpisode {
  final int episode;
  final String name;
  final String url;
  final String id;

  const EnrichedEpisode({
    required this.episode,
    required this.name,
    required this.url,
    required this.id,
  });

  factory EnrichedEpisode.fromJson(Map<String, dynamic> json) {
    return EnrichedEpisode(
      episode: json['episode'] as int,
      name: json['name'] as String,
      url: json['url'] as String,
      id: json['id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'episode': episode,
      'name': name,
      'url': url,
      'id': id,
    };
  }
}

/// Filme enriched com dados TMDB
class EnrichedMovie {
  final String id;
  final String name;
  final String category;
  final String type; // 'movie' ou 'series'
  final bool isAdult;
  final String? url; // Para filmes
  final EnrichedTMDB? tmdb;

  const EnrichedMovie({
    required this.id,
    required this.name,
    required this.category,
    required this.type,
    required this.isAdult,
    this.url,
    this.tmdb,
  });

  factory EnrichedMovie.fromJson(Map<String, dynamic> json) {
    return EnrichedMovie(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? 'Outros',
      type: json['type'] as String? ?? 'movie',
      isAdult: json['isAdult'] as bool? ?? false,
      url: json['url'] as String?,
      tmdb: json['tmdb'] != null
          ? EnrichedTMDB.fromJson(json['tmdb'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'type': type,
      'isAdult': isAdult,
      'url': url,
      'tmdb': tmdb?.toJson(),
    };
  }

  bool get isMovie => type == 'movie';
  bool get isSeries => type == 'series';
  
  String get displayTitle => tmdb?.title ?? name;
  String? get posterUrl => tmdb?.poster;
  String? get backdropUrl => tmdb?.backdrop;
  double get rating => tmdb?.rating ?? 0.0;
  String get yearString => tmdb?.year ?? '';
  List<String> get genresList => tmdb?.genres ?? [];
}

/// Série enriched com episódios
class EnrichedSeries extends EnrichedMovie {
  final Map<String, List<EnrichedEpisode>> episodes;
  final int totalSeasons;
  final int totalEpisodes;

  const EnrichedSeries({
    required super.id,
    required super.name,
    required super.category,
    required super.isAdult,
    super.tmdb,
    required this.episodes,
    required this.totalSeasons,
    required this.totalEpisodes,
  }) : super(type: 'series');

  factory EnrichedSeries.fromJson(Map<String, dynamic> json) {
    // Parse episodes por temporada
    final episodesMap = <String, List<EnrichedEpisode>>{};
    int totalEps = 0;

    if (json['episodes'] != null) {
      final eps = json['episodes'] as Map<String, dynamic>;
      eps.forEach((season, episodesList) {
        final seasonEpisodes = (episodesList as List<dynamic>)
            .map((e) => EnrichedEpisode.fromJson(e as Map<String, dynamic>))
            .toList();
        episodesMap[season] = seasonEpisodes;
        totalEps += seasonEpisodes.length;
      });
    }

    return EnrichedSeries(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? 'Outros',
      isAdult: json['isAdult'] as bool? ?? false,
      tmdb: json['tmdb'] != null
          ? EnrichedTMDB.fromJson(json['tmdb'] as Map<String, dynamic>)
          : null,
      episodes: episodesMap,
      totalSeasons: episodesMap.length,
      totalEpisodes: totalEps,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'episodes': episodes.map(
        (season, eps) => MapEntry(
          season,
          eps.map((e) => e.toJson()).toList(),
        ),
      ),
      'totalSeasons': totalSeasons,
      'totalEpisodes': totalEpisodes,
    };
  }

  /// Retorna lista ordenada de temporadas
  List<String> get seasonsList {
    return episodes.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  }

  /// Retorna episódios de uma temporada específica
  List<EnrichedEpisode> getEpisodes(String season) {
    return episodes[season] ?? [];
  }
}

/// Informações de categoria
class EnrichedCategoryInfo {
  final String name;
  final String file;
  final int count;
  final bool isAdult;

  const EnrichedCategoryInfo({
    required this.name,
    required this.file,
    this.count = 0,
    this.isAdult = false,
  });

  String get id => file.replaceAll('.json', '');
}

/// Opções de filtro
class FilterOptions {
  final String type; // 'all', 'movie', 'series'
  final List<String> genres;
  final List<String> years;
  final List<String> certifications;
  final List<String> ratings;
  final String sortBy; // 'popularity', 'rating', 'year', 'name'
  final String sortOrder; // 'asc', 'desc'

  const FilterOptions({
    this.type = 'all',
    this.genres = const [],
    this.years = const [],
    this.certifications = const [],
    this.ratings = const [],
    this.sortBy = 'popularity',
    this.sortOrder = 'desc',
  });

  FilterOptions copyWith({
    String? type,
    List<String>? genres,
    List<String>? years,
    List<String>? certifications,
    List<String>? ratings,
    String? sortBy,
    String? sortOrder,
  }) {
    return FilterOptions(
      type: type ?? this.type,
      genres: genres ?? this.genres,
      years: years ?? this.years,
      certifications: certifications ?? this.certifications,
      ratings: ratings ?? this.ratings,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  bool get hasActiveFilters =>
      type != 'all' ||
      genres.isNotEmpty ||
      years.isNotEmpty ||
      certifications.isNotEmpty ||
      ratings.isNotEmpty;
}

/// Filmografia de um ator
class ActorFilmography {
  final EnrichedCastMember actor;
  final List<EnrichedMovie> movies;
  final List<EnrichedSeries> series;

  const ActorFilmography({
    required this.actor,
    required this.movies,
    required this.series,
  });

  int get totalWorks => movies.length + series.length;
}
