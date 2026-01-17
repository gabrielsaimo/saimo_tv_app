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

  /// Ordem das categorias para exibição
  static const List<String> order = [
    todos,
    favoritos,
    tvAberta,
    filmes,
    series,
    esportes,
    noticias,
    infantil,
    documentarios,
    entretenimento,
    internacionais,
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
  };

  /// Cores das categorias
  static const Map<String, int> colors = {
    todos: 0xFF64748B,
    favoritos: 0xFFFBBF24,
    tvAberta: 0xFF22C55E,
    filmes: 0xFFEF4444,
    series: 0xFF8B5CF6,
    esportes: 0xFF06B6D4,
    noticias: 0xFF3B82F6,
    infantil: 0xFFF472B6,
    documentarios: 0xFF84CC16,
    entretenimento: 0xFFF97316,
    internacionais: 0xFF14B8A6,
    adulto: 0xFF9333EA,
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
