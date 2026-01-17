/// Modelo para dados do TMDB (The Movie Database)
/// Contém informações completas de filmes e séries

class TMDBMovie {
  final int id;
  final String? imdbId;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final int voteCount;
  final String? releaseDate;
  final List<String> genres;
  final int? runtime; // em minutos
  final String? tagline;
  final String? status;
  final int? budget;
  final int? revenue;
  final List<TMDBCastMember> cast;
  final List<TMDBCrewMember> crew;
  final List<TMDBVideo> videos;
  final String? homepage;
  final List<String> productionCompanies;
  final List<String> productionCountries;
  final String? originalLanguage;
  final double? popularity;
  final bool adult;

  const TMDBMovie({
    required this.id,
    this.imdbId,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0.0,
    this.voteCount = 0,
    this.releaseDate,
    this.genres = const [],
    this.runtime,
    this.tagline,
    this.status,
    this.budget,
    this.revenue,
    this.cast = const [],
    this.crew = const [],
    this.videos = const [],
    this.homepage,
    this.productionCompanies = const [],
    this.productionCountries = const [],
    this.originalLanguage,
    this.popularity,
    this.adult = false,
  });

  factory TMDBMovie.fromJson(Map<String, dynamic> json) {
    final genresList = (json['genres'] as List<dynamic>?)
            ?.map((g) => g['name'] as String)
            .toList() ??
        [];

    final companiesList = (json['production_companies'] as List<dynamic>?)
            ?.map((c) => c['name'] as String)
            .toList() ??
        [];

    final countriesList = (json['production_countries'] as List<dynamic>?)
            ?.map((c) => c['name'] as String)
            .toList() ??
        [];

    return TMDBMovie(
      id: json['id'] as int,
      imdbId: json['imdb_id'] as String?,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      originalTitle: json['original_title'] as String? ??
          json['original_name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      releaseDate:
          json['release_date'] as String? ?? json['first_air_date'] as String?,
      genres: genresList,
      runtime: json['runtime'] as int? ?? json['episode_run_time']?.first as int?,
      tagline: json['tagline'] as String?,
      status: json['status'] as String?,
      budget: json['budget'] as int?,
      revenue: json['revenue'] as int?,
      homepage: json['homepage'] as String?,
      productionCompanies: companiesList,
      productionCountries: countriesList,
      originalLanguage: json['original_language'] as String?,
      popularity: (json['popularity'] as num?)?.toDouble(),
      adult: json['adult'] as bool? ?? false,
    );
  }

  // URLs das imagens
  String get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w500$posterPath'
      : '';

  String get posterUrlHD => posterPath != null
      ? 'https://image.tmdb.org/t/p/w780$posterPath'
      : '';

  String get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w1280$backdropPath'
      : '';

  String get backdropUrlHD => backdropPath != null
      ? 'https://image.tmdb.org/t/p/original$backdropPath'
      : '';

  // Ano de lançamento
  String get releaseYear {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    return releaseDate!.split('-').first;
  }

  // Duração formatada
  String get formattedRuntime {
    if (runtime == null || runtime == 0) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }

  // Nota formatada
  String get formattedRating => voteAverage.toStringAsFixed(1);

  // Gêneros como string
  String get genresString => genres.take(3).join(' • ');

  // Diretor(es)
  List<String> get directors =>
      crew.where((c) => c.job == 'Director').map((c) => c.name).toList();

  // Roteirista(s)
  List<String> get writers => crew
      .where((c) => c.job == 'Writer' || c.job == 'Screenplay')
      .map((c) => c.name)
      .toList();

  // Trailer principal
  TMDBVideo? get mainTrailer {
    final trailers = videos.where((v) =>
        v.type == 'Trailer' && (v.site == 'YouTube' || v.site == 'Vimeo'));
    if (trailers.isNotEmpty) return trailers.first;
    return videos.isNotEmpty ? videos.first : null;
  }

  // URL do IMDB
  String? get imdbUrl =>
      imdbId != null ? 'https://www.imdb.com/title/$imdbId' : null;

  TMDBMovie copyWith({
    List<TMDBCastMember>? cast,
    List<TMDBCrewMember>? crew,
    List<TMDBVideo>? videos,
  }) {
    return TMDBMovie(
      id: id,
      imdbId: imdbId,
      title: title,
      originalTitle: originalTitle,
      overview: overview,
      posterPath: posterPath,
      backdropPath: backdropPath,
      voteAverage: voteAverage,
      voteCount: voteCount,
      releaseDate: releaseDate,
      genres: genres,
      runtime: runtime,
      tagline: tagline,
      status: status,
      budget: budget,
      revenue: revenue,
      cast: cast ?? this.cast,
      crew: crew ?? this.crew,
      videos: videos ?? this.videos,
      homepage: homepage,
      productionCompanies: productionCompanies,
      productionCountries: productionCountries,
      originalLanguage: originalLanguage,
      popularity: popularity,
      adult: adult,
    );
  }
}

/// Modelo para dados de série do TMDB
class TMDBSeries {
  final int id;
  final String name;
  final String? originalName;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final int voteCount;
  final String? firstAirDate;
  final String? lastAirDate;
  final List<String> genres;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? status;
  final List<String> networks;
  final List<TMDBSeason> seasons;
  final List<TMDBCastMember> cast;
  final List<TMDBCrewMember> crew;
  final List<TMDBVideo> videos;
  final List<String> createdBy;
  final String? type;
  final String? homepage;
  final double? popularity;
  final bool adult;
  final String? tagline;

  const TMDBSeries({
    required this.id,
    required this.name,
    this.originalName,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0.0,
    this.voteCount = 0,
    this.firstAirDate,
    this.lastAirDate,
    this.genres = const [],
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.status,
    this.networks = const [],
    this.seasons = const [],
    this.cast = const [],
    this.crew = const [],
    this.videos = const [],
    this.createdBy = const [],
    this.type,
    this.homepage,
    this.popularity,
    this.adult = false,
    this.tagline,
  });

  factory TMDBSeries.fromJson(Map<String, dynamic> json) {
    final genresList = (json['genres'] as List<dynamic>?)
            ?.map((g) => g['name'] as String)
            .toList() ??
        [];

    final networksList = (json['networks'] as List<dynamic>?)
            ?.map((n) => n['name'] as String)
            .toList() ??
        [];

    final creatorsList = (json['created_by'] as List<dynamic>?)
            ?.map((c) => c['name'] as String)
            .toList() ??
        [];

    final seasonsList = (json['seasons'] as List<dynamic>?)
            ?.map((s) => TMDBSeason.fromJson(s))
            .toList() ??
        [];

    return TMDBSeries(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      originalName: json['original_name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      firstAirDate: json['first_air_date'] as String?,
      lastAirDate: json['last_air_date'] as String?,
      genres: genresList,
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      status: json['status'] as String?,
      networks: networksList,
      seasons: seasonsList,
      createdBy: creatorsList,
      type: json['type'] as String?,
      homepage: json['homepage'] as String?,
      popularity: (json['popularity'] as num?)?.toDouble(),
      adult: json['adult'] as bool? ?? false,
      tagline: json['tagline'] as String?,
    );
  }

  String get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w500$posterPath'
      : '';

  String get posterUrlHD => posterPath != null
      ? 'https://image.tmdb.org/t/p/w780$posterPath'
      : '';

  String get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w1280$backdropPath'
      : '';

  String get firstAirYear {
    if (firstAirDate == null || firstAirDate!.isEmpty) return '';
    return firstAirDate!.split('-').first;
  }

  String get yearsRange {
    final start = firstAirYear;
    if (start.isEmpty) return '';
    
    if (status == 'Ended' || status == 'Canceled') {
      final end = lastAirDate?.split('-').first ?? '';
      if (end.isNotEmpty && end != start) {
        return '$start-$end';
      }
    }
    return '$start-';
  }

  String get formattedRating => voteAverage.toStringAsFixed(1);
  String get genresString => genres.take(3).join(' • ');

  TMDBVideo? get mainTrailer {
    final trailers = videos.where((v) =>
        v.type == 'Trailer' && (v.site == 'YouTube' || v.site == 'Vimeo'));
    if (trailers.isNotEmpty) return trailers.first;
    return videos.isNotEmpty ? videos.first : null;
  }

  TMDBSeries copyWith({
    List<TMDBCastMember>? cast,
    List<TMDBCrewMember>? crew,
    List<TMDBVideo>? videos,
    List<TMDBSeason>? seasons,
  }) {
    return TMDBSeries(
      id: id,
      name: name,
      originalName: originalName,
      overview: overview,
      posterPath: posterPath,
      backdropPath: backdropPath,
      voteAverage: voteAverage,
      voteCount: voteCount,
      firstAirDate: firstAirDate,
      lastAirDate: lastAirDate,
      genres: genres,
      numberOfSeasons: numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes,
      status: status,
      networks: networks,
      seasons: seasons ?? this.seasons,
      cast: cast ?? this.cast,
      crew: crew ?? this.crew,
      videos: videos ?? this.videos,
      createdBy: createdBy,
      type: type,
      homepage: homepage,
      popularity: popularity,
      adult: adult,
      tagline: tagline,
    );
  }
}

/// Temporada de uma série
class TMDBSeason {
  final int id;
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? posterPath;
  final String? airDate;
  final int? episodeCount;

  const TMDBSeason({
    required this.id,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterPath,
    this.airDate,
    this.episodeCount,
  });

  factory TMDBSeason.fromJson(Map<String, dynamic> json) {
    return TMDBSeason(
      id: json['id'] as int? ?? 0,
      seasonNumber: json['season_number'] as int? ?? 0,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      airDate: json['air_date'] as String?,
      episodeCount: json['episode_count'] as int?,
    );
  }

  String get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : '';
}

/// Membro do elenco
class TMDBCastMember {
  final int id;
  final String name;
  final String? character;
  final String? profilePath;
  final int? order;
  final String? knownForDepartment;
  final double? popularity;

  const TMDBCastMember({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
    this.order,
    this.knownForDepartment,
    this.popularity,
  });

  factory TMDBCastMember.fromJson(Map<String, dynamic> json) {
    return TMDBCastMember(
      id: json['id'] as int,
      name: json['name'] as String,
      character: json['character'] as String?,
      profilePath: json['profile_path'] as String?,
      order: json['order'] as int?,
      knownForDepartment: json['known_for_department'] as String?,
      popularity: (json['popularity'] as num?)?.toDouble(),
    );
  }

  String get profileUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : '';

  String get profileUrlHD => profilePath != null
      ? 'https://image.tmdb.org/t/p/w342$profilePath'
      : '';
}

/// Membro da equipe
class TMDBCrewMember {
  final int id;
  final String name;
  final String? job;
  final String? department;
  final String? profilePath;

  const TMDBCrewMember({
    required this.id,
    required this.name,
    this.job,
    this.department,
    this.profilePath,
  });

  factory TMDBCrewMember.fromJson(Map<String, dynamic> json) {
    return TMDBCrewMember(
      id: json['id'] as int,
      name: json['name'] as String,
      job: json['job'] as String?,
      department: json['department'] as String?,
      profilePath: json['profile_path'] as String?,
    );
  }

  String get profileUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : '';
}

/// Vídeo (trailer, teaser, etc.)
class TMDBVideo {
  final String id;
  final String key;
  final String name;
  final String site;
  final String type;
  final bool official;
  final String? publishedAt;

  const TMDBVideo({
    required this.id,
    required this.key,
    required this.name,
    required this.site,
    required this.type,
    this.official = false,
    this.publishedAt,
  });

  factory TMDBVideo.fromJson(Map<String, dynamic> json) {
    return TMDBVideo(
      id: json['id'] as String,
      key: json['key'] as String,
      name: json['name'] as String,
      site: json['site'] as String,
      type: json['type'] as String,
      official: json['official'] as bool? ?? false,
      publishedAt: json['published_at'] as String?,
    );
  }

  String get youtubeUrl => site == 'YouTube'
      ? 'https://www.youtube.com/watch?v=$key'
      : '';

  String get youtubeThumbnail => site == 'YouTube'
      ? 'https://img.youtube.com/vi/$key/hqdefault.jpg'
      : '';
}

/// Resultado de busca simplificado
class TMDBSearchResult {
  final int id;
  final String title;
  final String? posterPath;
  final String? releaseDate;
  final double voteAverage;
  final String mediaType; // 'movie' ou 'tv'

  const TMDBSearchResult({
    required this.id,
    required this.title,
    this.posterPath,
    this.releaseDate,
    this.voteAverage = 0.0,
    required this.mediaType,
  });

  factory TMDBSearchResult.fromJson(Map<String, dynamic> json, String type) {
    return TMDBSearchResult(
      id: json['id'] as int,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      releaseDate: json['release_date'] as String? ??
          json['first_air_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      mediaType: type,
    );
  }

  String get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : '';

  String get year {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    return releaseDate!.split('-').first;
  }
}
