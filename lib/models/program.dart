/// Modelo de Programa de TV (EPG)
class Program {
  final String id;
  final String channelId;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final String? category;
  final String? rating;
  final String? thumbnail;
  final bool isLive;
  final EpisodeInfo? episodeInfo;

  const Program({
    required this.id,
    required this.channelId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.category,
    this.rating,
    this.thumbnail,
    this.isLive = false,
    this.episodeInfo,
  });

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: json['id'] as String,
      channelId: json['channelId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      category: json['category'] as String?,
      rating: json['rating'] as String?,
      thumbnail: json['thumbnail'] as String?,
      isLive: json['isLive'] as bool? ?? false,
      episodeInfo: json['episodeInfo'] != null
          ? EpisodeInfo.fromJson(json['episodeInfo'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channelId': channelId,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'category': category,
      'rating': rating,
      'thumbnail': thumbnail,
      'isLive': isLive,
      'episodeInfo': episodeInfo?.toJson(),
    };
  }

  /// Calcula o progresso do programa (0-100)
  double get progress {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0;
    if (now.isAfter(endTime)) return 100;

    final total = endTime.difference(startTime).inSeconds;
    final elapsed = now.difference(startTime).inSeconds;
    return (elapsed / total) * 100;
  }

  /// Verifica se o programa está em exibição
  bool get isCurrentlyAiring {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  /// Duração em minutos
  int get durationMinutes {
    return endTime.difference(startTime).inMinutes;
  }

  /// Tempo restante em minutos
  int get remainingMinutes {
    final now = DateTime.now();
    if (now.isAfter(endTime)) return 0;
    if (now.isBefore(startTime)) return durationMinutes;
    return endTime.difference(now).inMinutes;
  }

  /// Formata horário de início
  String get formattedStartTime {
    return '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
  }

  /// Formata horário de término
  String get formattedEndTime {
    return '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  }

  /// Formata período completo
  String get formattedPeriod {
    return '$formattedStartTime - $formattedEndTime';
  }
}

/// Informações de episódio para séries
class EpisodeInfo {
  final int? season;
  final int? episode;
  final String? episodeTitle;

  const EpisodeInfo({
    this.season,
    this.episode,
    this.episodeTitle,
  });

  factory EpisodeInfo.fromJson(Map<String, dynamic> json) {
    return EpisodeInfo(
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      episodeTitle: json['episodeTitle'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'season': season,
      'episode': episode,
      'episodeTitle': episodeTitle,
    };
  }

  String get formatted {
    final parts = <String>[];
    if (season != null) parts.add('T$season');
    if (episode != null) parts.add('E$episode');
    if (episodeTitle != null && episodeTitle!.isNotEmpty) {
      parts.add(episodeTitle!);
    }
    return parts.join(' - ');
  }
}

/// Programa atual com contexto
class CurrentProgram {
  final Program? current;
  final Program? next;
  final double progress;

  const CurrentProgram({
    this.current,
    this.next,
    this.progress = 0,
  });

  factory CurrentProgram.fromPrograms(List<Program> programs) {
    final now = DateTime.now();
    
    Program? current;
    Program? next;

    for (int i = 0; i < programs.length; i++) {
      final program = programs[i];
      if (program.isCurrentlyAiring) {
        current = program;
        if (i + 1 < programs.length) {
          next = programs[i + 1];
        }
        break;
      } else if (program.startTime.isAfter(now)) {
        next = program;
        break;
      }
    }

    return CurrentProgram(
      current: current,
      next: next,
      progress: current?.progress ?? 0,
    );
  }
}

/// EPG completo de um canal
class ChannelEPG {
  final String channelId;
  final List<Program> programs;
  final DateTime lastUpdated;

  const ChannelEPG({
    required this.channelId,
    required this.programs,
    required this.lastUpdated,
  });

  CurrentProgram get currentProgram => CurrentProgram.fromPrograms(programs);

  bool get isStale {
    return DateTime.now().difference(lastUpdated).inMinutes > 30;
  }
}
