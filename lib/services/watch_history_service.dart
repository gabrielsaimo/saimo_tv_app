import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';

/// Serviço para gerenciar histórico de canais assistidos
/// Armazena o último canal e histórico recente para quick resume
class WatchHistoryService {
  static const String _lastChannelKey = 'last_channel_id';
  static const String _lastCategoryKey = 'last_category';
  static const String _watchHistoryKey = 'watch_history';
  static const String _watchTimeKey = 'watch_times';
  static const int _maxHistoryItems = 50;
  
  SharedPreferences? _prefs;
  
  /// Inicializa o serviço
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Salva o último canal assistido
  Future<void> saveLastChannel(Channel channel, String category) async {
    await init();
    await _prefs?.setString(_lastChannelKey, channel.id);
    await _prefs?.setString(_lastCategoryKey, category);
    await _addToHistory(channel);
  }
  
  /// Retorna o ID do último canal assistido
  Future<String?> getLastChannelId() async {
    await init();
    return _prefs?.getString(_lastChannelKey);
  }
  
  /// Retorna a última categoria selecionada
  Future<String?> getLastCategory() async {
    await init();
    return _prefs?.getString(_lastCategoryKey);
  }
  
  /// Adiciona canal ao histórico
  Future<void> _addToHistory(Channel channel) async {
    await init();
    
    final history = await getHistory();
    
    // Remove se já existe para adicionar no topo
    history.removeWhere((id) => id == channel.id);
    
    // Adiciona no início
    history.insert(0, channel.id);
    
    // Limita tamanho
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }
    
    await _prefs?.setStringList(_watchHistoryKey, history);
    
    // Atualiza tempo de visualização
    await _updateWatchTime(channel.id);
  }
  
  /// Retorna lista de IDs do histórico
  Future<List<String>> getHistory() async {
    await init();
    return _prefs?.getStringList(_watchHistoryKey) ?? [];
  }
  
  /// Atualiza tempo total assistido em um canal
  Future<void> _updateWatchTime(String channelId) async {
    await init();
    
    final watchTimesJson = _prefs?.getString(_watchTimeKey) ?? '{}';
    final Map<String, dynamic> watchTimes = json.decode(watchTimesJson);
    
    final currentTime = watchTimes[channelId] ?? 0;
    watchTimes[channelId] = currentTime + 1;
    
    await _prefs?.setString(_watchTimeKey, json.encode(watchTimes));
  }
  
  /// Retorna os canais mais assistidos (IDs)
  Future<List<String>> getMostWatched({int limit = 10}) async {
    await init();
    
    final watchTimesJson = _prefs?.getString(_watchTimeKey) ?? '{}';
    final Map<String, dynamic> watchTimes = json.decode(watchTimesJson);
    
    final sorted = watchTimes.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    
    return sorted.take(limit).map((e) => e.key).toList();
  }
  
  /// Limpa todo o histórico
  Future<void> clearHistory() async {
    await init();
    await _prefs?.remove(_watchHistoryKey);
    await _prefs?.remove(_watchTimeKey);
    await _prefs?.remove(_lastChannelKey);
    await _prefs?.remove(_lastCategoryKey);
  }
  
  /// Verifica se é primeira vez do usuário
  Future<bool> isFirstTime() async {
    await init();
    return _prefs?.getString(_lastChannelKey) == null;
  }
}
