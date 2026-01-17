import 'package:flutter/material.dart';
import '../models/program.dart';
import '../services/epg_service.dart';
import '../data/epg_mappings.dart';

/// Provider de EPG (Guia de Programação)
class EpgProvider with ChangeNotifier {
  final EpgService _epgService = EpgService();

  final Map<String, ChannelEPG> _epgData = {};
  final Map<String, bool> _loadingChannels = {};
  final Map<String, String?> _errors = {};
  bool _initialized = false;

  // Getters
  Map<String, ChannelEPG> get epgData => _epgData;
  bool get isInitialized => _initialized;

  EpgProvider() {
    // Registra listener para atualizações automáticas
    _epgService.addListener(_onEpgUpdate);
  }

  @override
  void dispose() {
    _epgService.removeListener(_onEpgUpdate);
    super.dispose();
  }

  /// Callback quando EPG é atualizado
  void _onEpgUpdate(String channelId, List<Program> programs) {
    _epgData[channelId] = ChannelEPG(
      channelId: channelId,
      programs: programs,
      lastUpdated: DateTime.now(),
    );
    _loadingChannels[channelId] = false;
    notifyListeners();
  }

  /// Verifica se está carregando EPG de um canal
  bool isLoading(String channelId) => _loadingChannels[channelId] ?? false;

  /// Obtém erro de um canal
  String? getError(String channelId) => _errors[channelId];

  /// Obtém EPG de um canal
  ChannelEPG? getEPG(String channelId) => _epgData[channelId];

  /// Obtém programa atual de um canal
  CurrentProgram? getCurrentProgram(String channelId) {
    return _epgData[channelId]?.currentProgram;
  }

  /// Verifica se canal suporta EPG
  bool hasEpgSupport(String channelId) {
    return EpgMappings.hasEpg(channelId);
  }

  /// Carrega EPG de um canal
  Future<void> loadChannelEPG(String channelId) async {
    if (_loadingChannels[channelId] == true) return;

    _loadingChannels[channelId] = true;
    _errors[channelId] = null;
    notifyListeners();

    try {
      final epg = await _epgService.getChannelEPG(channelId);
      _epgData[channelId] = epg;
      _errors[channelId] = null;
    } catch (e) {
      _errors[channelId] = 'Erro ao carregar programação';
    } finally {
      _loadingChannels[channelId] = false;
      notifyListeners();
    }
  }

  /// Carrega EPG de múltiplos canais
  Future<void> loadMultipleEPG(List<String> channelIds) async {
    await _epgService.preloadEPG(channelIds);
    
    for (final id in channelIds) {
      final epg = await _epgService.getChannelEPG(id);
      _epgData[id] = epg;
    }
    
    notifyListeners();
  }

  /// Inicializa carregando dados do cache local imediatamente
  /// Depois dispara atualização em background
  Future<void> initializeFromCache() async {
    // Permite recarregar se já foi inicializado mas não tem dados
    if (_initialized && _epgData.isNotEmpty) {
      print('[EPGProvider] Já inicializado com ${_epgData.length} canais');
      return;
    }
    
    print('[EPGProvider] Inicializando a partir do cache...');
    
    // Carrega o cache do SharedPreferences imediatamente
    final cachedData = await _epgService.loadAndGetCache();
    
    // Popula o provider com os dados do cache
    cachedData.forEach((channelId, programs) {
      _epgData[channelId] = ChannelEPG(
        channelId: channelId,
        programs: programs,
        lastUpdated: DateTime.now(),
      );
    });
    
    _initialized = true;
    
    print('[EPGProvider] Cache carregado: ${_epgData.length} canais com EPG');
    
    // Notifica a UI imediatamente para mostrar o que temos
    notifyListeners();
    
    // Inicia atualização em background (não bloqueia)
    _updateInBackground();
  }
  
  /// Atualiza EPGs que precisam em background
  Future<void> _updateInBackground() async {
    // Inicializa o serviço (que vai verificar o que precisa atualizar)
    await _epgService.initialize();
    
    // Atualiza dados que foram atualizados em background
    final updatedCache = _epgService.getAllCachedPrograms();
    updatedCache.forEach((channelId, programs) {
      _epgData[channelId] = ChannelEPG(
        channelId: channelId,
        programs: programs,
        lastUpdated: DateTime.now(),
      );
    });
    
    notifyListeners();
  }

  /// Atualiza EPG de um canal (força refresh)
  Future<void> refreshChannelEPG(String channelId) async {
    _epgService.clearChannelCache(channelId);
    await loadChannelEPG(channelId);
  }

  /// Limpa cache de EPG
  void clearCache() {
    _epgData.clear();
    _errors.clear();
    _epgService.clearCache();
    notifyListeners();
  }

  /// Obtém lista de programas futuros de um canal
  List<Program> getUpcomingPrograms(String channelId, {int limit = 10}) {
    final epg = _epgData[channelId];
    if (epg == null) return [];

    final now = DateTime.now();
    return epg.programs
        .where((p) => p.endTime.isAfter(now))
        .take(limit)
        .toList();
  }

  /// Obtém todos os programas do dia de um canal
  List<Program> getDayPrograms(String channelId, DateTime date) {
    final epg = _epgData[channelId];
    if (epg == null) return [];

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return epg.programs.where((p) {
      return p.startTime.isAfter(startOfDay) && p.startTime.isBefore(endOfDay);
    }).toList();
  }

  /// Estatísticas do EPG
  Map<String, dynamic> get stats => _epgService.getStats();
  
  /// Progresso de carregamento
  double get loadProgress => _epgService.progress;
  int get loadedChannels => _epgService.loadedCount;
  int get totalChannels => _epgService.totalCount;
  bool get isBackgroundLoading => _epgService.isLoading;

  /// Lista todos os canais com EPG
  List<String> get channelsWithEpg => EpgMappings.allChannelsWithEpg;
}
