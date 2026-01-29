import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../models/category.dart';
import '../models/program.dart';
import '../providers/channels_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/epg_provider.dart';
import '../providers/player_provider.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';
import '../widgets/options_modal.dart';
import '../services/casting_service.dart';

/// Tela de Canais Premium - Design moderno para provedores de TV
/// Otimizada para TV, Tablet e Mobile com navegação D-Pad fluida
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Estados de navegação
  int _selectedCategoryIndex = 0;
  int _selectedChannelIndex = 0;
  int _hoveredChannelIndex = -1;
  bool _showMiniGuide = false;
  
  // Focus nodes para navegação D-pad
  final FocusNode _mainFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search_button');
  final FocusNode _settingsFocusNode = FocusNode(debugLabel: 'settings_button');
  final FocusNode _guiaFocusNode = FocusNode(debugLabel: 'guia_button');
  final FocusNode _switchFocusNode = FocusNode(debugLabel: 'mode_switch');
  final FocusScopeNode _gridFocusScopeNode = FocusScopeNode(debugLabel: 'grid_scope');
  final ScrollController _channelsScrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();
  List<FocusNode> _categoryFocusNodes = [];
  bool _focusOnSidebar = false;
  bool _focusOnHeader = false;
  int _headerFocusIndex = 0; // 0=guia, 1=buscar, 2=config
  bool _isDpadMode = false;
  
  // Animações
  late AnimationController _pulseAnimController;
  late Animation<double> _pulseAnimation;
  
  // Timer para esconder mini guia
  Timer? _miniGuideTimer;
  
  // Desbloqueio adulto
  int _logoClickCount = 0;
  DateTime? _lastLogoClick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Animação de pulso (para indicador ao vivo)
    _pulseAnimController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseAnimController, curve: Curves.easeInOut),
    );
    
    // Carrega EPG
    _loadEPG();
    
    // Inicializa focus nodes das categorias
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCategoryFocusNodes();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadEPG();
    }
  }

  Future<void> _loadEPG() async {
    final epgProvider = context.read<EpgProvider>();
    await epgProvider.initializeFromCache();
    if (mounted) setState(() {});
  }

  // Helper method to filter categories (hiding Favorites if empty)
  List<String> _getFilteredCategories(ChannelsProvider channelsProvider, FavoritesProvider favoritesProvider) {
    var categories = channelsProvider.availableCategories;
    if (favoritesProvider.favorites.isEmpty) {
      categories = categories.where((c) => c != ChannelCategory.favoritos).toList();
    }
    return categories;
  }

  // Helper method to get correct channels based on category and favorites
  List<Channel> _getDisplayChannels(ChannelsProvider channelsProvider) {
    if (channelsProvider.selectedCategory == ChannelCategory.favoritos) {
      final favoritesProvider = context.read<FavoritesProvider>();
      // Filter channels that are in favorites list
      return channelsProvider.channels
          .where((c) => favoritesProvider.isFavorite(c.id))
          .toList();
    }
    return channelsProvider.filteredChannels;
  }

  void _initializeCategoryFocusNodes() {
    final channelsProvider = context.read<ChannelsProvider>();
    final favoritesProvider = context.read<FavoritesProvider>();
    final categories = _getFilteredCategories(channelsProvider, favoritesProvider);
    
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    
    _categoryFocusNodes = List.generate(
      categories.length,
      (index) => FocusNode(debugLabel: 'category_$index'),
    );
  }

  /// Foca no grid de canais
  void _focusOnGrid() {
    setState(() {
      _focusOnSidebar = false;
      _focusOnHeader = false;
      
      // Recupera último índice selecionado
      final channelsProvider = context.read<ChannelsProvider>();
      // Ensure index is valid for current list
      final channels = _getDisplayChannels(channelsProvider);
      
      int targetIndex = channelsProvider.lastSelectedIndex;
      if (channels.isEmpty) {
        targetIndex = 0;
      } else if (targetIndex >= channels.length) {
        targetIndex = channels.length - 1;
      }
      
      _selectedChannelIndex = targetIndex;
    });
    
    // Usa o FocusScopeNode para pedir foco no primeiro filho
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _gridFocusScopeNode.requestFocus();
        // Garante que o canal correto receba foco
        // Vamos apenas rolar para o item para garantir visibilidade
        final columns = _getColumnCount(context);
        _scrollToChannel(_selectedChannelIndex, columns);
        
        // Preload EPG
        _preloadEpg();
      }
    });
  }
  
  void _preloadEpg() {
    final channelsProvider = context.read<ChannelsProvider>();
    final epgProvider = context.read<EpgProvider>();
    final channels = _getDisplayChannels(channelsProvider);
    epgProvider.preloadFuzzyMatches(channels);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mainFocusNode.dispose();
    _searchFocusNode.dispose();
    _settingsFocusNode.dispose();
    _guiaFocusNode.dispose();
    _switchFocusNode.dispose();
    _gridFocusScopeNode.dispose();
    _channelsScrollController.dispose();
    _categoriesScrollController.dispose();
    _pulseAnimController.dispose();
    _miniGuideTimer?.cancel();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  bool _isTV(BuildContext context) {
    // Usa a detecção centralizada de TVConstants ou modo dpad ativo
    return TVConstants.isTV(context) || _isDpadMode;
  }

  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide > 600;
  }

  int _getColumnCount(BuildContext context) {
    final isTV = _isTV(context);
    if (isTV) return 5;
    if (_isTablet(context)) return 4;
    final width = MediaQuery.of(context).size.width;
    return (width / 180).floor().clamp(2, 4);
  }

  void _onChannelSelected(Channel channel) {
    // Salva o índice atual para persistência
    final playerProvider = context.read<PlayerProvider>();
    final channelsProvider = context.read<ChannelsProvider>();
    
    // Encontra o index deste canal na lista atual para salvar
    // Fix: Use correct list (filtered/display channels)
    final channels = _getDisplayChannels(channelsProvider);
    final currentIndex = channels.indexOf(channel);
    if (currentIndex >= 0) {
      channelsProvider.setLastSelectedIndex(currentIndex);
    }

    playerProvider.setChannel(channel);
    Navigator.of(context).pushNamed('/player');
  }

  void _onFavoriteToggle(String channelId) {
    final favoritesProvider = context.read<FavoritesProvider>();
    favoritesProvider.toggleFavorite(channelId);
  }

  void _onLogoTap() {
    final now = DateTime.now();
    if (_lastLogoClick != null && now.difference(_lastLogoClick!).inSeconds > 3) {
      _logoClickCount = 0;
    }
    
    _lastLogoClick = now;
    _logoClickCount++;
    
    if (_logoClickCount >= 5) {
      _logoClickCount = 0;
      _showPinDialog();
    } else if (_logoClickCount >= 3) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${5 - _logoClickCount} cliques restantes...'),
          backgroundColor: SaimoTheme.surfaceLight,
          duration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  void _showPinDialog() {
    final pinController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _PinDialog(
        controller: pinController,
        onConfirm: (pin) => _validatePin(pin, context),
      ),
    );
  }

  void _validatePin(String pin, BuildContext dialogContext) {
    if (pin == '1234') {
      Navigator.pop(dialogContext);
      
      final channelsProvider = context.read<ChannelsProvider>();
      final newState = !channelsProvider.showAdultChannels;
      channelsProvider.toggleAdultChannels();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(newState ? Icons.lock_open : Icons.lock, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                newState ? '🔞 Canais adultos desbloqueados!' : '🔒 Canais adultos bloqueados!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: newState ? SaimoTheme.success : SaimoTheme.error,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text('Código incorreto!'),
          backgroundColor: SaimoTheme.error,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleMiniGuide() {
    setState(() => _showMiniGuide = !_showMiniGuide);
    if (_showMiniGuide) {
      _miniGuideTimer?.cancel();
      _miniGuideTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _showMiniGuide = false);
      });
    }
  }

  void _showChannelOptions(Channel channel) {
    final favoritesProvider = context.read<FavoritesProvider>();
    final isFavorite = favoritesProvider.isFavorite(channel.id);
    
    showDialog(
      context: context,
      builder: (context) => OptionsModal(
        title: channel.name,
        isFavorite: isFavorite,
        onToggleFavorite: () {
          favoritesProvider.toggleFavorite(channel.id);
          // Force rebuild to show updated status if modal stays open or just for background
          setState(() {}); 
        },
        onPlay: () {
          // Close modal and play
          _onChannelSelected(channel);
        },
        onCastSelected: (device) {
          final castingService = CastingService();
          try {
             castingService.castMedia(
               device: device,
               url: channel.url,
               title: channel.name,
               imageUrl: channel.logoUrl,
             );
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text('Transmitindo para ${device.name}...'),
                 backgroundColor: SaimoTheme.primary,
               ),
             );
          } catch (e) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text('Erro ao transmitir: $e'),
                 backgroundColor: SaimoTheme.error,
               ),
             );
          }
        },
      ),
    ).then((_) {
      // Return focus to grid when modal closes
      _focusOnGrid();
    });
  }

  void _scrollCategoryIntoView(int index) {
    if (!_categoriesScrollController.hasClients) return;
    
    // Estima altura de cada item (aproximadamente 48 pixels)
    const itemHeight = 48.0;
    final viewportHeight = _categoriesScrollController.position.viewportDimension;
    final maxScroll = _categoriesScrollController.position.maxScrollExtent;
    
    final itemOffset = index * itemHeight;
    final centeredOffset = itemOffset - (viewportHeight / 2) + (itemHeight / 2);
    final targetOffset = centeredOffset.clamp(0.0, maxScroll);
    
    _categoriesScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleKeyEvent(KeyEvent event, int channelIndex) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    
    if (!_isDpadMode) setState(() => _isDpadMode = true);
    
    final channelsProvider = context.read<ChannelsProvider>();
    final channels = _getDisplayChannels(channelsProvider);
    final columns = _getColumnCount(context);
    
    int newIndex = channelIndex;

    switch (event.logicalKey) {
      // NOTA: goBack e escape são tratados pelo PopScope para evitar duplicação
      case LogicalKeyboardKey.keyS:
        Navigator.of(context).pushNamed('/search');
        return;
      case LogicalKeyboardKey.keyG:
        _toggleMiniGuide();
        return;
      case LogicalKeyboardKey.arrowUp:
        // Se está na primeira linha, vai para o header
        if (channelIndex < columns) {
          setState(() {
            _focusOnHeader = true;
            _headerFocusIndex = 0;
          });
          _guiaFocusNode.requestFocus();
          return;
        }
        newIndex = (channelIndex - columns).clamp(0, channels.length - 1);
        break;
      case LogicalKeyboardKey.arrowDown:
        newIndex = (channelIndex + columns).clamp(0, channels.length - 1);
        break;
      case LogicalKeyboardKey.arrowLeft:
        if (channelIndex % columns == 0 && (_isTV(context) || _isDpadMode)) {
          _focusOnSidebar = true;
          if (_categoryFocusNodes.isNotEmpty && _selectedCategoryIndex < _categoryFocusNodes.length) {
            _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
            _scrollCategoryIntoView(_selectedCategoryIndex);
          }
          return;
        } else if (channelIndex > 0) {
          newIndex = channelIndex - 1;
        }
        break;
      case LogicalKeyboardKey.arrowRight:
        if (channelIndex < channels.length - 1) {
          newIndex = channelIndex + 1;
        }
        break;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
      case LogicalKeyboardKey.numpadEnter:
        if (channels.isNotEmpty && channelIndex < channels.length) {
          _onChannelSelected(channels[channelIndex]);
        }
        return;
      default:
        return;
    }
    
    // A navegação dentro do grid agora é feita pelo FocusTraversalGroup
    // Este método só é chamado para teclas especiais
  }

  void _scrollToChannel(int index, int columns) {
    if (!_channelsScrollController.hasClients) return;
    
    final viewportHeight = _channelsScrollController.position.viewportDimension;
    final maxScroll = _channelsScrollController.position.maxScrollExtent;
    final channelsProvider = context.read<ChannelsProvider>();
    final channels = _getDisplayChannels(channelsProvider);
    final totalRows = (channels.length / columns).ceil();
    final estimatedRowHeight = totalRows > 0 ? (maxScroll + viewportHeight) / totalRows : 200.0;
    
    final rowIndex = index ~/ columns;
    final itemOffset = rowIndex * estimatedRowHeight;
    final centeredOffset = itemOffset - (viewportHeight / 2) + (estimatedRowHeight / 2);
    final targetOffset = centeredOffset.clamp(0.0, maxScroll);
    
    _channelsScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context) || _isDpadMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showMiniGuide) {
          setState(() => _showMiniGuide = false);
          return;
        }
        _showExitConfirmation();
      },
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        },
        child: Focus(
          focusNode: _mainFocusNode,
          autofocus: !isTV,
          skipTraversal: true,
          child: Scaffold(
            backgroundColor: SaimoTheme.background,
            body: Stack(
              children: [
                // Conteúdo principal
                isTV ? _buildTVLayout() : _buildMobileLayout(),
                // Mini guia overlay
                if (_showMiniGuide) _buildMiniGuideOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SaimoTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: SaimoTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.exit_to_app, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Sair do App', style: TextStyle(color: SaimoTheme.textPrimary)),
          ],
        ),
        content: const Text(
          'Deseja realmente sair do SAIMO TV?',
          style: TextStyle(color: SaimoTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: SaimoTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SaimoTheme.primary),
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==================== TV LAYOUT ====================
  Widget _buildTVLayout() {
    return Column(
      children: [
        // Header com logo, buscar e configurações
        _buildTVHeader(),
        // Conteúdo: Sidebar + Grid
        Expanded(
          child: Row(
            children: [
              // Sidebar com categorias
              _buildSidebar(),
              // Grid de canais
              Expanded(child: _buildMainContent()),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== HEADER TV (estilo compacto e moderno) ====================
  Widget _buildTVHeader() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Botão Voltar
          _buildHeaderNavButton(
            focusNode: _guiaFocusNode,
            icon: Icons.arrow_back_rounded,
            label: 'Voltar',
            index: 0,
            onTap: () => Navigator.of(context).pushReplacementNamed('/selector'),
          ),
          const SizedBox(width: 12),
          
          // Botão Filmes
          _buildHeaderNavButton(
            focusNode: _searchFocusNode,
            icon: Icons.movie_rounded,
            label: 'Filmes',
            index: 1,
            onTap: () => Navigator.of(context).pushReplacementNamed('/movies'),
          ),
          
          const SizedBox(width: 16),
          
          // Logo
          GestureDetector(
            onTap: _onLogoTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: SaimoTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 6),
                const Text(
                  'SAIMO',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'TV',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: SaimoTheme.primary,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Indicador AO VIVO
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: SaimoTheme.live.withOpacity(_pulseAnimation.value),
                      shape: BoxShape.circle,
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              Text(
                'AO VIVO',
                style: TextStyle(
                  color: SaimoTheme.live.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          
          const SizedBox(width: 16),
          
          // Switch Lite/Pro
          Consumer<ChannelsProvider>(
            builder: (context, provider, _) {
              final isPro = provider.isProMode;
              return Focus(
                focusNode: _switchFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                  switch (event.logicalKey) {
                    case LogicalKeyboardKey.arrowLeft:
                      setState(() => _headerFocusIndex = 1);
                      _searchFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.arrowRight:
                      setState(() => _headerFocusIndex = 3);
                      _settingsFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.arrowDown:
                      setState(() => _focusOnHeader = false);
                      _focusOnGrid();
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.enter:
                    case LogicalKeyboardKey.select:
                      provider.toggleChannelMode();
                      return KeyEventResult.handled;
                    default:
                      return KeyEventResult.ignored;
                  }
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () => provider.toggleChannelMode(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isFocused ? SaimoTheme.primary.withOpacity(0.3) : Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isFocused ? SaimoTheme.primary : Colors.white24,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'LITE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: !isPro ? FontWeight.w900 : FontWeight.normal,
                                color: !isPro ? SaimoTheme.primary : Colors.white54,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                                width: 32,
                                height: 16,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: isPro ? SaimoTheme.primary.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
                                ),
                                child: Stack(
                                    children: [
                                        AnimatedAlign(
                                            duration: const Duration(milliseconds: 200),
                                            alignment: isPro ? Alignment.centerRight : Alignment.centerLeft,
                                            child: Container(
                                                margin: const EdgeInsets.all(2),
                                                width: 12,
                                                height: 12,
                                                decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white,
                                                ),
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'PRO',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isPro ? FontWeight.w900 : FontWeight.normal,
                                color: isPro ? SaimoTheme.primary : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                ),
              );
            },
          ),
          
          // Botão de configurações
          _buildHeaderNavButton(
            focusNode: _settingsFocusNode,
            icon: Icons.settings_rounded,
            label: 'Config',
            index: 3,
            onTap: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactClock() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        return Text(
          time,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }

  Widget _buildHeaderNavButton({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required int index,
    required VoidCallback onTap,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            if (index > 0) {
              setState(() => _headerFocusIndex = index - 1);
              if (index == 1) _guiaFocusNode.requestFocus();
              if (index == 2) _searchFocusNode.requestFocus();
              if (index == 3) _switchFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            if (index < 3) {
              setState(() => _headerFocusIndex = index + 1);
              if (index == 0) _searchFocusNode.requestFocus(); // 0 -> 1
              if (index == 1) _switchFocusNode.requestFocus(); // 1 -> 2
              if (index == 2) _settingsFocusNode.requestFocus(); // 2 -> 3
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            setState(() {
              _focusOnHeader = false;
            });
            _focusOnGrid();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            onTap();
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isFocused 
                    ? SaimoTheme.primary.withOpacity(0.3) 
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused ? SaimoTheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isFocused ? SaimoTheme.primary : Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isFocused ? SaimoTheme.primary : Colors.white70,
                      fontSize: 12,
                      fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== MOBILE LAYOUT ====================
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildMobileHeader(),
        _buildCategoryChips(),
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _onLogoTap,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: SaimoTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.live_tv, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'SAIMO TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _buildIconButton(Icons.search, () => Navigator.pushNamed(context, '/search')),
          const SizedBox(width: 8),
          _buildIconButton(Icons.settings, () => Navigator.pushNamed(context, '/settings')),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: SaimoTheme.surfaceLight,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: SaimoTheme.textSecondary, size: 22),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Consumer2<ChannelsProvider, FavoritesProvider>(
      builder: (context, provider, favoritesProvider, child) {
        final categories = _getFilteredCategories(provider, favoritesProvider);
        
        return Container(
          height: 48,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = index == _selectedCategoryIndex;
              final icon = ChannelCategory.getIcon(category);
              final color = Color(ChannelCategory.getColor(category));
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CategoryChip(
                  label: category,
                  icon: icon,
                  color: color,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() => _selectedCategoryIndex = index);
                    provider.selectCategory(category);
                    _focusOnGrid();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==================== SIDEBAR ====================
  Widget _buildSidebar() {
    return Consumer2<ChannelsProvider, FavoritesProvider>(
      builder: (context, provider, favoritesProvider, child) {
        final categories = _getFilteredCategories(provider, favoritesProvider);
        
        if (_categoryFocusNodes.length != categories.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeCategoryFocusNodes();
          });
        }

        return Container(
          width: 220,
          decoration: BoxDecoration(
            color: SaimoTheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20),
            ],
          ),
          child: Column(
            children: [
              // Título da sidebar
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.category, color: SaimoTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'CATEGORIAS',
                      style: TextStyle(
                        color: SaimoTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Lista de categorias
              Expanded(
                child: ListView.builder(
                  controller: _categoriesScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = index == _selectedCategoryIndex;
                    final icon = ChannelCategory.getIcon(category);
                    final color = Color(ChannelCategory.getColor(category));
                    final count = _getCategoryCount(provider, category);

                    return _buildCategoryItem(
                      index: index,
                      category: category,
                      icon: icon,
                      color: color,
                      count: count,
                      isSelected: isSelected,
                      provider: provider,
                      totalCategories: categories.length,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _getCategoryCount(ChannelsProvider provider, String category) {
    if (category == ChannelCategory.todos) return provider.channels.length;
    if (category == ChannelCategory.favoritos) return 0;
    return provider.channelsByCategory[category]?.length ?? 0;
  }

  Widget _buildCategoryItem({
    required int index,
    required String category,
    required String icon,
    required Color color,
    required int count,
    required bool isSelected,
    required ChannelsProvider provider,
    required int totalCategories,
  }) {
    return Focus(
      focusNode: index < _categoryFocusNodes.length ? _categoryFocusNodes[index] : null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowUp:
            if (index > 0) {
              _categoryFocusNodes[index - 1].requestFocus();
              _scrollCategoryIntoView(index - 1);
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            if (index < totalCategories - 1) {
              _categoryFocusNodes[index + 1].requestFocus();
              _scrollCategoryIntoView(index + 1);
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            // Sai da sidebar e vai para o grid
            _focusOnGrid();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.gameButtonA:
          case LogicalKeyboardKey.numpadEnter:
            // Seleciona a categoria e vai para o grid
            provider.selectCategory(category);
            setState(() {
              _selectedCategoryIndex = index;
            });
            _focusOnGrid();
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: GestureDetector(
              onTap: () {
                provider.selectCategory(category);
                setState(() {
                  _selectedCategoryIndex = index;
                });
                _focusOnGrid();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isFocused 
                      ? color.withOpacity(0.3)
                      : isSelected 
                          ? color.withOpacity(0.2) 
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isFocused ? color : (isSelected ? color.withOpacity(0.5) : Colors.transparent),
                    width: isFocused ? 2 : (isSelected ? 1 : 0),
                  ),
                ),
                child: Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isFocused || isSelected ? color : SaimoTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: isFocused || isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          count.toString(),
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== CONTEÚDO PRINCIPAL ====================
  Widget _buildMainContent() {
    return Consumer3<ChannelsProvider, FavoritesProvider, EpgProvider>(
      builder: (context, channelsProvider, favoritesProvider, epgProvider, child) {
        if (channelsProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: SaimoTheme.primary),
          );
        }

        final channels = _getDisplayChannels(channelsProvider);
        final columns = _getColumnCount(context);
        final isTV = _isTV(context) || _isDpadMode;

        return Column(
          children: [
            // Header com info da categoria
            _buildContentHeader(channelsProvider),
            // Grid de canais envolto em FocusScope para navegação D-pad
            Expanded(
              child: channels.isEmpty
                  ? _buildEmptyState()
                  : FocusScope(
                      node: _gridFocusScopeNode,
                      child: FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: GridView.builder(
                          controller: _channelsScrollController,
                          padding: EdgeInsets.all(isTV ? 16 : 12),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            childAspectRatio: isTV ? 0.85 : 0.75,
                            crossAxisSpacing: isTV ? 14 : 10,
                            mainAxisSpacing: isTV ? 14 : 10,
                          ),
                          itemCount: channels.length,
                          itemBuilder: (context, index) {
                            final channel = channels[index];
                            final isFavorite = favoritesProvider.isFavorite(channel.id);
                            final currentProgram = epgProvider.getProgramForChannel(channel);

                            return _buildChannelCard(
                              channel: channel,
                              index: index,
                              isFavorite: isFavorite,
                              currentProgram: currentProgram,
                              columns: columns,
                              totalChannels: channels.length,
                            );
                          },
                        ),
                      ),
                    ),
            ),
            // Barra de atalhos (TV)
            if (isTV) _buildShortcutsBar(),
          ],
        );
      },
    );
  }

  Widget _buildContentHeader(ChannelsProvider provider) {
    final isTV = _isTV(context) || _isDpadMode;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTV ? 20 : 16,
        vertical: isTV ? 12 : 10,
      ),
      child: Row(
        children: [
          // Info da categoria
          Text(
            ChannelCategory.getIcon(provider.selectedCategory),
            style: TextStyle(fontSize: isTV ? 24 : 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.selectedCategory,
                style: TextStyle(
                  color: SaimoTheme.textPrimary,
                  fontSize: isTV ? 22 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${provider.filteredChannels.length} canais',
                style: TextStyle(
                  color: SaimoTheme.textTertiary,
                  fontSize: isTV ? 13 : 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tv_off_rounded, size: 64, color: SaimoTheme.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Nenhum canal encontrado',
            style: TextStyle(color: SaimoTheme.textSecondary, fontSize: 18),
          ),
        ],
      ),
    );
  }

  // ==================== CARD DE CANAL ====================
  Widget _buildChannelCard({
    required Channel channel,
    required int index,
    required bool isFavorite,
    required CurrentProgram? currentProgram,
    required int columns,
    required int totalChannels,
  }) {
    final isTV = _isTV(context) || _isDpadMode;

    return Focus(
      autofocus: index == _selectedChannelIndex,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          if (!_isDpadMode) setState(() => _isDpadMode = true);
          setState(() {
            _selectedChannelIndex = index;
            _focusOnHeader = false;
            _focusOnSidebar = false;
          });
          _scrollToChannel(index, columns);
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        
        final key = event.logicalKey;
        
        // Enter/Select - abre o canal
        if (key == LogicalKeyboardKey.enter || 
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.numpadEnter) {
          _onChannelSelected(channel);
          return KeyEventResult.handled;
        }
        
        // NOTA: Escape/Back são tratados pelo PopScope para evitar duplicação
        
        // Navegação seta esquerda - vai para sidebar na primeira coluna
        if (key == LogicalKeyboardKey.arrowLeft && index % columns == 0) {
          _focusOnSidebar = true;
          if (_categoryFocusNodes.isNotEmpty && _selectedCategoryIndex < _categoryFocusNodes.length) {
            _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
            _scrollCategoryIntoView(_selectedCategoryIndex);
          }
          return KeyEventResult.handled;
        }
        
        // Navegação seta cima - vai para header na primeira linha
        if (key == LogicalKeyboardKey.arrowUp && index < columns) {
          setState(() {
            _focusOnHeader = true;
            _headerFocusIndex = 0;
          });
          _guiaFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        
        // TODAS as outras teclas de navegação são ignoradas para permitir o FocusTraversalGroup funcionar
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          final isHovered = _hoveredChannelIndex == index;
          final isSelected = isFocused || isHovered;
          
          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredChannelIndex = index),
            onExit: (_) => setState(() => _hoveredChannelIndex = -1),
            child: GestureDetector(
              onTap: () => _onChannelSelected(channel),
              onLongPress: () => _showChannelOptions(channel),
              child: _buildChannelCardContent(
                channel: channel,
                isFavorite: isFavorite,
                isTV: isTV,
                isSelected: isSelected,
                currentProgram: currentProgram,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelCardContent({
    required Channel channel,
    required bool isFavorite,
    required bool isTV,
    required bool isSelected,
    required CurrentProgram? currentProgram,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: SaimoTheme.surface,
        borderRadius: BorderRadius.circular(isTV ? 14 : 12),
        border: Border.all(
          color: isSelected ? SaimoTheme.primary : SaimoTheme.surfaceLight,
          width: isSelected ? 3 : 1,
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: SaimoTheme.primary.withOpacity(0.4),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ] : null,
      ),
      transform: isSelected && isTV ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
      transformAlignment: Alignment.center,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo do canal
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: isSelected 
                    ? SaimoTheme.primary.withOpacity(0.1)
                    : SaimoTheme.surfaceLight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(isTV ? 13 : 11)),
              ),
              child: Stack(
                children: [
                  // Logo
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: channel.logo != null && channel.logo!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: channel.logo!,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => _buildChannelInitials(channel, isTV),
                              errorWidget: (_, __, ___) => _buildChannelInitials(channel, isTV),
                            )
                          : _buildChannelInitials(channel, isTV),
                    ),
                  ),
                  // Número do canal
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? SaimoTheme.primary : SaimoTheme.primary.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        channel.channelNumber.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTV ? 12 : 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Favorito
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => _onFavoriteToggle(channel.id),
                      child: Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        color: isFavorite ? Colors.amber : SaimoTheme.textTertiary,
                        size: isTV ? 22 : 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Info do canal com EPG
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(isTV ? 10 : 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Nome do canal
                  Text(
                    channel.name,
                    style: TextStyle(
                      color: isSelected ? SaimoTheme.primary : SaimoTheme.textPrimary,
                      fontSize: isTV ? 13 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Programa atual (EPG) ou categoria
                  if (currentProgram?.current != null)
                    Expanded(
                      child: Text(
                        '▶ ${currentProgram!.current!.title}',
                        style: TextStyle(
                          color: SaimoTheme.accent,
                          fontSize: isTV ? 11 : 9,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        channel.category,
                        style: TextStyle(
                          color: SaimoTheme.textTertiary,
                          fontSize: isTV ? 11 : 9,
                        ),
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelInitials(Channel channel, bool isTV) {
    return Container(
      width: isTV ? 60 : 40,
      height: isTV ? 60 : 40,
      decoration: BoxDecoration(
        gradient: SaimoTheme.primaryGradient,
        borderRadius: BorderRadius.circular(isTV ? 10 : 8),
      ),
      child: Center(
        child: Text(
          channel.initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: isTV ? 20 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: SaimoTheme.surface,
        border: Border(top: BorderSide(color: SaimoTheme.surfaceLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildKeyHint('◀▶▲▼', 'Navegar'),
          const SizedBox(width: 24),
          _buildKeyHint('OK', 'Assistir'),
          const SizedBox(width: 24),
          _buildKeyHint('G', 'Mini Guia'),
          const SizedBox(width: 24),
          _buildKeyHint('S', 'Buscar'),
        ],
      ),
    );
  }

  Widget _buildKeyHint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SaimoTheme.surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: SaimoTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: SaimoTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  // ==================== MINI GUIA OVERLAY ====================
  Widget _buildMiniGuideOverlay() {
    return Consumer2<ChannelsProvider, EpgProvider>(
      builder: (context, channelsProvider, epgProvider, child) {
        // Fix: Use filtered display channels
        final channels = _getDisplayChannels(channelsProvider);
        final selectedChannel = _selectedChannelIndex < channels.length
            ? channels[_selectedChannelIndex]
            : null;

        if (selectedChannel == null) return const SizedBox();

        final programs = epgProvider.getUpcomingPrograms(selectedChannel.id, limit: 5);
        final currentProgram = epgProvider.getCurrentProgram(selectedChannel.id);

        return GestureDetector(
          onTap: () => setState(() => _showMiniGuide = false),
          child: Container(
            color: Colors.black.withOpacity(0.8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: Container(
                  width: 500,
                  margin: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: SaimoTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SaimoTheme.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header do canal
                      _buildMiniGuideHeader(selectedChannel),
                      // Programa atual
                      if (currentProgram?.current != null)
                        _buildCurrentProgramCard(currentProgram!.current!),
                      // Lista de programas
                      if (programs.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: programs.length,
                            itemBuilder: (context, index) {
                              return _buildProgramListItem(programs[index]);
                            },
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Programação não disponível',
                            style: TextStyle(color: SaimoTheme.textSecondary),
                          ),
                        ),
                      // Botão assistir
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _showMiniGuide = false);
                            _onChannelSelected(selectedChannel);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SaimoTheme.primary,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_arrow, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'ASSISTIR AGORA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniGuideHeader(Channel channel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SaimoTheme.primary.withOpacity(0.2),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: SaimoTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: channel.logo != null && channel.logo!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: channel.logo!,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => _buildChannelInitials(channel, true),
                    ),
                  )
                : _buildChannelInitials(channel, true),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: SaimoTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'CH ${channel.channelNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SaimoTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        channel.category,
                        style: const TextStyle(
                          color: SaimoTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  channel.name,
                  style: const TextStyle(
                    color: SaimoTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Fechar
          IconButton(
            onPressed: () => setState(() => _showMiniGuide = false),
            icon: const Icon(Icons.close, color: SaimoTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentProgramCard(Program program) {
    final now = DateTime.now();
    final totalDuration = program.endTime.difference(program.startTime).inMinutes;
    final elapsed = now.difference(program.startTime).inMinutes;
    final progress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SaimoTheme.live.withOpacity(0.15),
            SaimoTheme.live.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SaimoTheme.live.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: SaimoTheme.live.withOpacity(_pulseAnimation.value * 0.8 + 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'AO VIVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(
                '${program.startTime.hour.toString().padLeft(2, '0')}:${program.startTime.minute.toString().padLeft(2, '0')} - ${program.endTime.hour.toString().padLeft(2, '0')}:${program.endTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: SaimoTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            program.title,
            style: const TextStyle(
              color: SaimoTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: SaimoTheme.surfaceLight,
              valueColor: const AlwaysStoppedAnimation<Color>(SaimoTheme.live),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramListItem(Program program) {
    final isNow = program.isCurrentlyAiring;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isNow ? SaimoTheme.primary.withOpacity(0.1) : SaimoTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '${program.startTime.hour.toString().padLeft(2, '0')}:${program.startTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: isNow ? SaimoTheme.primary : SaimoTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              program.title,
              style: TextStyle(
                color: SaimoTheme.textPrimary.withOpacity(isNow ? 1 : 0.7),
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== WIDGETS AUXILIARES ====================

/// Chip de categoria para mobile
class _CategoryChip extends StatelessWidget {
  final String label;
  final String icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : SaimoTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : SaimoTheme.surfaceLight,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : SaimoTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo de PIN
class _PinDialog extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onConfirm;

  const _PinDialog({
    required this.controller,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SaimoTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: SaimoTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Acesso Restrito',
                style: TextStyle(color: SaimoTheme.textPrimary, fontSize: 18),
              ),
              Text(
                'Digite o código PIN',
                style: TextStyle(color: SaimoTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            style: const TextStyle(
              color: SaimoTheme.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 16,
            ),
            decoration: InputDecoration(
              hintText: '••••',
              hintStyle: TextStyle(
                color: SaimoTheme.textTertiary,
                fontSize: 32,
                letterSpacing: 16,
              ),
              counterText: '',
              filled: true,
              fillColor: SaimoTheme.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: SaimoTheme.primary, width: 2),
              ),
            ),
            onSubmitted: (value) => onConfirm(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: SaimoTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => onConfirm(controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: SaimoTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

/// Builder animado auxiliar
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
