/// Modelo de Canal de TV
class Channel {
  final String id;
  final String name;
  final String url;
  final String? logo;
  final String category;
  final int channelNumber;
  final bool isAdult;
  final bool isMpegTs;

  const Channel({
    required this.id,
    required this.name,
    required this.url,
    this.logo,
    this.category = 'Outros',
    this.channelNumber = 0,
    this.isAdult = false,
    this.isMpegTs = false,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      logo: json['logo'] as String?,
      category: json['category'] as String? ?? 'Outros',
      channelNumber: json['channelNumber'] as int? ?? 0,
      isAdult: json['isAdult'] as bool? ?? false,
      isMpegTs: json['isMpegTs'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'logo': logo,
      'category': category,
      'channelNumber': channelNumber,
      'isAdult': isAdult,
      'isMpegTs': isMpegTs,
    };
  }

  /// Gera iniciais do nome para fallback de logo
  String get initials {
    return name
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  /// Verifica se o logo é um asset local
  bool get isLocalAsset {
    return logo != null && logo!.startsWith('asset:');
  }

  /// Retorna o path do asset (sem o prefixo 'asset:')
  String get assetPath {
    if (isLocalAsset) {
      return logo!.substring(6); // Remove 'asset:'
    }
    return '';
  }

  /// URL do logo com fallback
  String get logoUrl {
    if (logo != null && logo!.isNotEmpty) {
      // Se for asset local, retorna o path do fallback
      if (isLocalAsset) {
        return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(initials)}&background=8b5cf6&color=fff&size=128&bold=true&format=png';
      }
      return logo!;
    }
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(initials)}&background=8b5cf6&color=fff&size=128&bold=true&format=png';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Channel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Channel copyWith({
    String? id,
    String? name,
    String? url,
    String? logo,
    String? category,
    int? channelNumber,
    bool? isAdult,
    bool? isMpegTs,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo ?? this.logo,
      category: category ?? this.category,
      channelNumber: channelNumber ?? this.channelNumber,
      isAdult: isAdult ?? this.isAdult,
      isMpegTs: isMpegTs ?? this.isMpegTs,
    );
  }
}
