import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../models/category.dart';
import '../data/channels_data.dart';
import '../services/channels_service.dart';
import '../services/storage_service.dart';

/// Provider de canais
class ChannelsProvider with ChangeNotifier {
  List<Channel> _channels = [];
  Map<String, List<Channel>> _channelsByCategory = {};
  bool _isLoading = false;
  String? _error;
  String _selectedCategory = ChannelCategory.todos;
  String _searchQuery = '';
  bool _showAdultChannels = false;

  // Getters
  List<Channel> get channels => _channels;
  Map<String, List<Channel>> get channelsByCategory => _channelsByCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get showAdultChannels => _showAdultChannels;

  /// Lista de categorias disponíveis
  List<String> get availableCategories {
    // Sempre incluir "Todos" e "Favoritos" no início
    final result = <String>[ChannelCategory.todos, ChannelCategory.favoritos];
    
    // Adicionar categorias existentes
    final categories = _channelsByCategory.keys.toList();
    categories.sort((a, b) {
      return ChannelCategory.getIndex(a).compareTo(ChannelCategory.getIndex(b));
    });
    
    for (final cat in categories) {
      if (!result.contains(cat)) {
        result.add(cat);
      }
    }
    return result;
  }

  /// Canais da categoria selecionada
  List<Channel> get currentCategoryChannels {
    if (_selectedCategory == ChannelCategory.todos) {
      return _channels; // Todos os canais
    }
    if (_selectedCategory == ChannelCategory.favoritos) {
      return []; // UI must filter from all channels using FavoritesProvider
    }
    return _channelsByCategory[_selectedCategory] ?? [];
  }

  /// Canais filtrados pela busca
  List<Channel> get filteredChannels {
    if (_searchQuery.isEmpty) {
      return currentCategoryChannels;
    }

    final query = _searchQuery.toLowerCase();
    return _channels.where((channel) {
      return channel.name.toLowerCase().contains(query) ||
          channel.category.toLowerCase().contains(query);
    }).toList();
  }



  /// Seleciona uma categoria
  void selectCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  /// Define a query de busca
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Limpa a busca
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  /// Busca um canal pelo ID
  Channel? getChannelById(String id) {
    try {
      return _channels.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Busca um canal pelo número
  Channel? getChannelByNumber(int number) {
    try {
      return _channels.firstWhere((c) => c.channelNumber == number);
    } catch (_) {
      return null;
    }
  }

  /// Obtém o próximo canal
  Channel? getNextChannel(String currentId) {
    final currentIndex = _channels.indexWhere((c) => c.id == currentId);
    if (currentIndex < 0 || currentIndex >= _channels.length - 1) {
      return _channels.isNotEmpty ? _channels.first : null;
    }
    return _channels[currentIndex + 1];
  }

  /// Obtém o canal anterior
  Channel? getPreviousChannel(String currentId) {
    final currentIndex = _channels.indexWhere((c) => c.id == currentId);
    if (currentIndex <= 0) {
      return _channels.isNotEmpty ? _channels.last : null;
    }
    return _channels[currentIndex - 1];
  }

  /// Ativa/desativa modo adulto
  Future<void> setAdultMode(bool enabled) async {
    _showAdultChannels = enabled;
    
    // Salva a preferência
    final storage = StorageService();
    await storage.setAdultModeUnlocked(enabled);
    
    // Recarrega canais
    await loadChannels();
  }
  
  /// Toggle modo adulto (para uso com clique secreto na logo)
  Future<void> toggleAdultChannels() async {
    _showAdultChannels = !_showAdultChannels;
    
    // Salva a preferência
    final storage = StorageService();
    await storage.setAdultModeUnlocked(_showAdultChannels);
    
    // Recarrega canais
    await loadChannels();
  }

  // ===== Modo Lite/Pro =====
  
  bool _isProMode = false;
  bool get isProMode => _isProMode;
  
  List<Channel> _liteChannels = [];
  List<Channel> _proChannels = [];
  
  /// Alterna entre modo Lite e Pro
  Future<void> toggleChannelMode() async {
    _isProMode = !_isProMode;
    
    // Salva preferência
    final storage = StorageService();
    await storage.setProModeEnabled(_isProMode);
    
    await loadChannels();
  }

  /// Carrega os canais
  Future<void> loadChannels() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final storage = StorageService();
      
      // Verifica se modo adulto está desbloqueado
      _showAdultChannels = await storage.isAdultModeUnlocked();
      
      // Carrega modo Pro salvo
      if (!_isProMode) { 
         _isProMode = await storage.isProModeEnabled();
      }
      
      final service = ChannelsService();
      
      // 1. CARREGAMENTO (Mantendo lógica original de fetch)
      if (_isProMode) {
        if (_proChannels.isEmpty) {
            _proChannels = await service.fetchProChannels();
        }
        // Clona para lista principal (SEM FILTRAR AINDA)
        _channels = List.from(_proChannels);
      } else {
        if (_liteChannels.isEmpty) {
            try {
                final remoteChannels = await service.fetchChannels();
                _liteChannels = ChannelsData.mergeChannels(remoteChannels, includeAdult: true);
            } catch (e) {
                debugPrint('Erro ao carregar canais remotos: $e');
                _liteChannels = ChannelsData.getAllChannels(includeAdult: true);
            }
        }
        // Clona para lista principal
        _channels = List.from(_liteChannels);
      }
      
      // 2. FILTRO DE SEGURANÇA (CRÍTICO)
      // Remove canais adultos da lista PRINCIPAL se o modo estiver bloqueado
      if (!_showAdultChannels) {
          _channels = _channels.where((c) => !c.isAdult).toList();
      }

      // 3. CATEGORIZAÇÃO (Multi-Categoria)
      // Um mesmo canal pode aparecer em "Esportes" e "FHD" ao mesmo tempo
      _channelsByCategory = {};
      
      for (final channel in _channels) {
        // A. Categoria Original
        _channelsByCategory.putIfAbsent(channel.category, () => []).add(channel);
        
        // 24H Exclusivity: If it's a 24h channel, do NOT add to other virtual lists
        final nameUpper = channel.name.toUpperCase();
        final is24h = channel.category == ChannelCategory.channels24h || nameUpper.contains('24H');
        
        if (is24h) {
             _channelsByCategory.putIfAbsent('24h', () => []).add(channel);
             continue; // EXCLUSIVITY: Skip adding to other virtual categories
        }
        
        // B. Categorias Virtuais (Baseadas no nome)
        if (nameUpper.contains('4K') || nameUpper.contains('UHD')) {
             _channelsByCategory.putIfAbsent('4K UHD', () => []).add(channel);
        }
        
        if (nameUpper.contains('FHD')) {
             _channelsByCategory.putIfAbsent('FHD', () => []).add(channel);
        } else if (nameUpper.contains('HD')) {
             _channelsByCategory.putIfAbsent('HD', () => []).add(channel);
        } else if (nameUpper.contains('SD')) {
             _channelsByCategory.putIfAbsent('SD', () => []).add(channel);
        }
      }
      
      // Reseta categoria selecionada se ela não existir mais na nova lista
      if (_selectedCategory != ChannelCategory.todos && 
          _selectedCategory != ChannelCategory.favoritos &&
          !_channelsByCategory.containsKey(_selectedCategory)) {
        _selectedCategory = ChannelCategory.todos;
      }

      _error = null;
    } catch (e) {
      _error = 'Erro ao carregar canais: $e';
    } finally {
      _isLoading = false;
      if (_channels.isNotEmpty) {
          debugPrint('[ChannelsProvider] Loaded ${_channels.length} channels. First 5 IDs: ${_channels.take(5).map((c) => c.id).toList()}');
      } else {
          debugPrint('[ChannelsProvider] Loaded 0 channels.');
      }
      notifyListeners();
    }
  }

  // ===== Persistência de Scroll =====
  
  int _lastSelectedIndex = 0;
  int get lastSelectedIndex => _lastSelectedIndex;
  
  void setLastSelectedIndex(int index) {
    _lastSelectedIndex = index;
    // Não notificamos listeners aqui para evitar rebuilds desnecessários de toda a tela
    // A tela apenas lê isso ao inicializar ou retornar
  }


}
