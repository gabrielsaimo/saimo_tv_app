/// Categorias de canais na ordem de exibição
class ChannelCategory {
  static const String todos = 'Todos';
  static const String favoritos = 'Favoritos';
  static const String tvAberta = 'TV Aberta';
  static const String filmes = 'Filmes';
  static const String series = 'Series';
  static const String esportes = 'Esportes';
  static const String noticias = 'Noticias';
  static const String infantil = 'Infantil';
  static const String documentarios = 'Documentarios';
  static const String entretenimento = 'Entretenimento';
  static const String internacionais = 'Internacionais';
  static const String adulto = 'Adulto';
  static const String variedades = 'Variedades';
  static const String legendados = 'Legendados';
  static const String uhd = '4K UHD';
  static const String fhd = 'FHD';
  static const String hd = 'HD';
  static const String sd = 'SD';
  static const String channels24h = '24 Horas';

  /// Ordem das categorias para exibição
  static const List<String> order = [
    todos,
    favoritos,
    uhd, // High quality first
    fhd,
    hd,
    sd,
    tvAberta,
    variedades,
    filmes,
    series,
    legendados, // New category
    esportes,
    noticias,
    infantil,
    documentarios,
    entretenimento,
    internacionais,
    channels24h, // Special content
    adulto,
  ];

  /// Ícones das categorias
  static const Map<String, String> icons = {
    todos: '📡',
    favoritos: '⭐',
    tvAberta: '📺',
    filmes: '🎬',
    series: '📽️',
    esportes: '⚽',
    noticias: '📰',
    infantil: '🧒',
    documentarios: '🌍',
    entretenimento: '🎭',
    internacionais: '🌐',
    adulto: '🔞',
    variedades: '✨',
    legendados: '📝',
    uhd: '🌟',
    fhd: '💎',
    hd: 'ᴴᴰ',
    sd: '📺',
    channels24h: '🕒',
  };

  /// Cores das categorias
  static const Map<String, int> colors = {
    todos: 0xFF64748B,
    favoritos: 0xFFFBBF24,
    tvAberta: 0xFF22C55E,
    filmes: 0xFFEF4444,
    series: 0xFF8B5CF6,
    legendados: 0xFF10B981, // Emerald Green
    esportes: 0xFF06B6D4,
    noticias: 0xFF3B82F6,
    infantil: 0xFFF472B6,
    documentarios: 0xFF84CC16,
    entretenimento: 0xFFF97316,
    internacionais: 0xFF14B8A6,
    adulto: 0xFF9333EA,
    variedades: 0xFFD946EF,
    uhd: 0xFFFFD700, // Gold
    fhd: 0xFF00CED1, // Dark Turquoise
    hd: 0xFF1E90FF, // Dodger Blue
    sd: 0xFF808080, // Gray
    channels24h: 0xFFFF4500, // Orange Red
  };

  /// Retorna índice de ordenação para uma categoria
  static int getIndex(String category) {
    final index = order.indexOf(category);
    return index >= 0 ? index : order.length;
  }

  /// Retorna ícone da categoria
  static String getIcon(String category) {
    return icons[category] ?? '📺';
  }

  /// Retorna cor da categoria
  static int getColor(String category) {
    return colors[category] ?? 0xFF8B5CF6;
  }
}
