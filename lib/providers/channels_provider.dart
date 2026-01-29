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
      return _channels; // Será filtrado pelo FavoritesProvider
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
    
    // Salva preferência (opcional, por enquanto em memória para sessão atual ou pro futuro)
    // final storage = StorageService();
    // await storage.setChannelMode(_isProMode ? 'pro' : 'lite');
    
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
      
      final service = ChannelsService();
      
      if (_isProMode) {
        // MODO PRO: Carrega lista M3U local (assets/pro_list.m3u)
        if (_proChannels.isEmpty) {
            _proChannels = await service.fetchProChannels();
        }
        
        // Aplica filtro de adulto se necessário
        if (!_showAdultChannels) {
            _channels = _proChannels.where((c) => !c.isAdult).toList();
        } else {
            _channels = List.from(_proChannels);
        }
      } else {
        // MODO LITE: Web + Overrides (Original)
        if (_liteChannels.isEmpty) {
            try {
                final remoteChannels = await service.fetchChannels();
                _liteChannels = ChannelsData.mergeChannels(remoteChannels, includeAdult: true); // Merge raw list
            } catch (e) {
                print('Erro ao carregar canais remotos: $e');
                _liteChannels = ChannelsData.getAllChannels(includeAdult: true);
            }
        }
        
        // Aplica filtro de adulto e overrides locais
        if (!_showAdultChannels) {
            _channels = _liteChannels.where((c) => !c.isAdult).toList();
        } else {
            _channels = List.from(_liteChannels);
        }
      }
        
      // Atualiza mapa de categorias
      _channelsByCategory = {};
      for (final channel in _channels) {
        _channelsByCategory.putIfAbsent(channel.category, () => []).add(channel);
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
