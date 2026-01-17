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
  bool _sidebarExpanded = true;
  bool _showMiniGuide = false;
  
  // Foco e navegação
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _channelsScrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();
  List<FocusNode> _channelFocusNodes = [];
  List<FocusNode> _categoryFocusNodes = [];
  bool _focusOnSidebar = false;
  bool _isDpadMode = false;
  
  // Animações
  late AnimationController _sidebarAnimController;
  late Animation<double> _sidebarAnimation;
  late AnimationController _fadeAnimController;
  late Animation<double> _fadeAnimation;
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
    
    // Animação da sidebar
    _sidebarAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _sidebarAnimation = Tween<double>(begin: 240, end: 80).animate(
      CurvedAnimation(parent: _sidebarAnimController, curve: Curves.easeInOutCubic),
    );
    
    // Animação de fade
    _fadeAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeAnimController,
      curve: Curves.easeOut,
    );
    
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
    
    // Inicializa focus nodes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFocusNodes();
      _initializeCategoryFocusNodes();
      _requestInitialFocus();
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

  void _initializeFocusNodes() {
    final channelsProvider = context.read<ChannelsProvider>();
    final channels = channelsProvider.filteredChannels;
    
    for (var node in _channelFocusNodes) {
      node.dispose();
    }
    
    _channelFocusNodes = List.generate(
      channels.length,
      (index) => FocusNode(debugLabel: 'channel_$index'),
    );
  }

  void _initializeCategoryFocusNodes() {
    final channelsProvider = context.read<ChannelsProvider>();
    final categories = channelsProvider.availableCategories;
    
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    
    _categoryFocusNodes = List.generate(
      categories.length,
      (index) => FocusNode(debugLabel: 'category_$index'),
    );
  }

  void _requestInitialFocus() {
    if (_channelFocusNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_channelFocusNodes.isNotEmpty && _channelFocusNodes[0].canRequestFocus) {
          _channelFocusNodes[0].requestFocus();
          setState(() => _isDpadMode = true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mainFocusNode.dispose();
    _channelsScrollController.dispose();
    _categoriesScrollController.dispose();
    _sidebarAnimController.dispose();
    _fadeAnimController.dispose();
    _pulseAnimController.dispose();
    _miniGuideTimer?.cancel();
    for (var node in _channelFocusNodes) {
      node.dispose();
    }
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLargeScreen = size.shortestSide > 600;
    final isLandscape = size.width > size.height;
    final isVeryLargeScreen = size.width >= 1280 || size.height >= 720;
    return (isLargeScreen && isLandscape) || (isVeryLargeScreen && isLandscape);
  }

  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide > 600;
  }

  int _getColumnCount(BuildContext context) {
    final isTV = _isTV(context) || _isDpadMode;
    if (isTV) return _sidebarExpanded ? 4 : 5;
    if (_isTablet(context)) return 4;
    final width = MediaQuery.of(context).size.width;
    return (width / 180).floor().clamp(2, 4);
  }

  void _onChannelSelected(Channel channel) {
    final playerProvider = context.read<PlayerProvider>();
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

  void _handleKeyEvent(KeyEvent event, int channelIndex) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    
    if (!_isDpadMode) setState(() => _isDpadMode = true);
    
    final channelsProvider = context.read<ChannelsProvider>();
    final channels = channelsProvider.filteredChannels;
    final columns = _getColumnCount(context);
    
    int newIndex = channelIndex;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        Navigator.of(context).maybePop();
        return;
      case LogicalKeyboardKey.keyS:
        Navigator.of(context).pushNamed('/search');
        return;
      case LogicalKeyboardKey.keyG:
        _toggleMiniGuide();
        return;
      case LogicalKeyboardKey.arrowUp:
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
    
    if (newIndex != channelIndex && newIndex >= 0 && newIndex < _channelFocusNodes.length) {
      setState(() => _selectedChannelIndex = newIndex);
      _channelFocusNodes[newIndex].requestFocus();
      _scrollToChannel(newIndex, columns);
    }
  }

  void _scrollToChannel(int index, int columns) {
    if (!_channelsScrollController.hasClients) return;
    
    final viewportHeight = _channelsScrollController.position.viewportDimension;
    final maxScroll = _channelsScrollController.position.maxScrollExtent;
    final channelsProvider = context.read<ChannelsProvider>();
    final totalRows = (channelsProvider.filteredChannels.length / columns).ceil();
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
            backgroundColor: const Color(0xFF0A0A0F),
            body: Stack(
              children: [
                // Background com gradiente sutil
                _buildBackground(),
                // Conteúdo principal
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: isTV ? _buildTVLayout() : _buildMobileLayout(),
                ),
                // Mini guia overlay
                if (_showMiniGuide) _buildMiniGuideOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0A0A0F),
            const Color(0xFF12121A),
            const Color(0xFF0F0F18),
          ],
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            const Text('Sair do App', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Deseja realmente sair do SAIMO TV?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SaimoTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==================== TV LAYOUT ====================
  Widget _buildTVLayout() {
    return Row(
      children: [
        // Sidebar premium
        _buildPremiumSidebar(),
        // Conteúdo principal
        Expanded(child: _buildMainContent()),
      ],
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
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white70, size: 22),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Consumer<ChannelsProvider>(
      builder: (context, provider, child) {
        final categories = provider.availableCategories;
        
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
                    _initializeFocusNodes();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==================== SIDEBAR PREMIUM ====================
  Widget _buildPremiumSidebar() {
    return AnimatedBuilder(
      animation: _sidebarAnimation,
      builder: (context, child) {
        final width = _sidebarExpanded ? 240.0 : 80.0;
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFF12121A),
            border: Border(
              right: BorderSide(
                color: Colors.white.withOpacity(0.05),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Logo e branding
              _buildSidebarHeader(),
              // Categorias
              Expanded(child: _buildCategoryList()),
              // Footer com ações
              _buildSidebarFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarHeader() {
    return GestureDetector(
      onTap: _onLogoTap,
      onDoubleTap: () {
        setState(() => _sidebarExpanded = !_sidebarExpanded);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.all(_sidebarExpanded ? 20 : 16),
        child: Row(
          children: [
            // Logo animado
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: SaimoTheme.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: SaimoTheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.live_tv, color: Colors.white, size: 26),
            ),
            if (_sidebarExpanded) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SAIMO TV',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
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
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return Consumer<ChannelsProvider>(
      builder: (context, provider, child) {
        final categories = provider.availableCategories;
        
        if (_categoryFocusNodes.length != categories.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeCategoryFocusNodes();
          });
        }

        return ListView.builder(
          controller: _categoriesScrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
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
            );
          },
        );
      },
    );
  }

  int _getCategoryCount(ChannelsProvider provider, String category) {
    if (category == ChannelCategory.todos) return provider.channels.length;
    if (category == ChannelCategory.favoritos) return 0; // Será calculado pelo FavoritesProvider
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
  }) {
    return Focus(
      focusNode: index < _categoryFocusNodes.length ? _categoryFocusNodes[index] : null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        
        final categories = provider.availableCategories;
        
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowUp:
            if (index > 0) _categoryFocusNodes[index - 1].requestFocus();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            if (index < categories.length - 1) _categoryFocusNodes[index + 1].requestFocus();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            _focusOnSidebar = false;
            if (_channelFocusNodes.isNotEmpty) {
              final targetIndex = _selectedChannelIndex.clamp(0, _channelFocusNodes.length - 1);
              _channelFocusNodes[targetIndex].requestFocus();
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            setState(() => _selectedCategoryIndex = index);
            provider.selectCategory(category);
            _focusOnSidebar = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _initializeFocusNodes();
              if (_channelFocusNodes.isNotEmpty) {
                _selectedChannelIndex = 0;
                _channelFocusNodes[0].requestFocus();
              }
            });
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _sidebarExpanded ? 12 : 8,
              vertical: 2,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  setState(() => _selectedCategoryIndex = index);
                  provider.selectCategory(category);
                  _initializeFocusNodes();
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: _sidebarExpanded ? 14 : 0,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isFocused
                        ? color.withOpacity(0.2)
                        : isSelected
                            ? color.withOpacity(0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFocused
                          ? color
                          : isSelected
                              ? color.withOpacity(0.5)
                              : Colors.transparent,
                      width: isFocused ? 2 : 1,
                    ),
                  ),
                  child: _sidebarExpanded
                      ? Row(
                          children: [
                            Text(icon, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                category,
                                style: TextStyle(
                                  color: isFocused || isSelected ? color : Colors.white70,
                                  fontSize: 14,
                                  fontWeight: isFocused || isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (count > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  count.toString(),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Center(
                          child: Tooltip(
                            message: category,
                            child: Text(icon, style: const TextStyle(fontSize: 24)),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebarFooter() {
    return Container(
      padding: EdgeInsets.all(_sidebarExpanded ? 16 : 12),
      child: Column(
        children: [
          // Divider estilizado
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Botões de ação
          if (_sidebarExpanded)
            Row(
              children: [
                Expanded(
                  child: _FooterButton(
                    icon: Icons.search,
                    label: 'Buscar',
                    onTap: () => Navigator.pushNamed(context, '/search'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FooterButton(
                    icon: Icons.settings,
                    label: 'Config',
                    onTap: () => Navigator.pushNamed(context, '/settings'),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _FooterIconButton(
                  icon: Icons.search,
                  onTap: () => Navigator.pushNamed(context, '/search'),
                ),
                const SizedBox(height: 8),
                _FooterIconButton(
                  icon: Icons.settings,
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
              ],
            ),
        ],
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

        final channels = channelsProvider.filteredChannels;
        final columns = _getColumnCount(context);
        final isTV = _isTV(context) || _isDpadMode;

        if (_channelFocusNodes.length != channels.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeFocusNodes();
          });
        }

        return Column(
          children: [
            // Header com info da categoria
            _buildContentHeader(channelsProvider),
            // Grid de canais
            Expanded(
              child: channels.isEmpty
                  ? _buildEmptyState()
                  : GridView.builder(
                      controller: _channelsScrollController,
                      padding: EdgeInsets.all(isTV ? 20 : 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: isTV ? 1.1 : 0.85,
                        crossAxisSpacing: isTV ? 16 : 10,
                        mainAxisSpacing: isTV ? 16 : 10,
                      ),
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        final isFavorite = favoritesProvider.isFavorite(channel.id);
                        final currentProgram = epgProvider.getCurrentProgram(channel.id);

                        return _buildChannelCard(
                          channel: channel,
                          index: index,
                          isFavorite: isFavorite,
                          currentProgram: currentProgram,
                          columns: columns,
                        );
                      },
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
        horizontal: isTV ? 24 : 16,
        vertical: isTV ? 16 : 12,
      ),
      child: Row(
        children: [
          // Info da categoria
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      ChannelCategory.getIcon(provider.selectedCategory),
                      style: TextStyle(fontSize: isTV ? 28 : 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      provider.selectedCategory,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTV ? 26 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${provider.filteredChannels.length} canais disponíveis',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: isTV ? 14 : 12,
                  ),
                ),
              ],
            ),
          ),
          // Relógio digital
          _buildDigitalClock(isTV),
        ],
      ),
    );
  }

  Widget _buildDigitalClock(bool isTV) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isTV ? 20 : 14,
            vertical: isTV ? 10 : 8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_rounded,
                color: SaimoTheme.primary,
                size: isTV ? 22 : 18,
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTV ? 24 : 18,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tv_off_rounded,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum canal encontrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CARD DE CANAL PREMIUM ====================
  Widget _buildChannelCard({
    required Channel channel,
    required int index,
    required bool isFavorite,
    required CurrentProgram? currentProgram,
    required int columns,
  }) {
    final focusNode = index < _channelFocusNodes.length
        ? _channelFocusNodes[index]
        : FocusNode();
    final isTV = _isTV(context) || _isDpadMode;

    return FocusableActionDetector(
      focusNode: focusNode,
      autofocus: isTV && index == 0,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          if (!_isDpadMode) setState(() => _isDpadMode = true);
          setState(() => _selectedChannelIndex = index);
          _scrollToChannel(index, columns);
        }
      },
      onShowHoverHighlight: (hovering) {
        setState(() => _hoveredChannelIndex = hovering ? index : -1);
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          final isHovered = _hoveredChannelIndex == index;
          final isSelected = isFocused || isHovered;

          return Focus(
            skipTraversal: true,
            onKeyEvent: (node, event) {
              _handleKeyEvent(event, index);
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if ([
                  LogicalKeyboardKey.arrowUp,
                  LogicalKeyboardKey.arrowDown,
                  LogicalKeyboardKey.arrowLeft,
                  LogicalKeyboardKey.arrowRight,
                  LogicalKeyboardKey.enter,
                  LogicalKeyboardKey.select,
                ].contains(event.logicalKey)) {
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: () => _onChannelSelected(channel),
              onLongPress: () => _onFavoriteToggle(channel.id),
              child: _PremiumChannelCard(
                channel: channel,
                isFavorite: isFavorite,
                isSelected: isSelected,
                currentProgram: currentProgram,
                isTV: isTV,
                onFavoriteToggle: () => _onFavoriteToggle(channel.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShortcutsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ShortcutHint(keys: '◀▶▲▼', label: 'Navegar'),
          const SizedBox(width: 32),
          _ShortcutHint(keys: 'OK', label: 'Assistir'),
          const SizedBox(width: 32),
          _ShortcutHint(keys: 'G', label: 'Mini Guia'),
          const SizedBox(width: 32),
          _ShortcutHint(keys: 'S', label: 'Buscar'),
        ],
      ),
    );
  }

  // ==================== MINI GUIA OVERLAY ====================
  Widget _buildMiniGuideOverlay() {
    return Consumer2<ChannelsProvider, EpgProvider>(
      builder: (context, channelsProvider, epgProvider, child) {
        final selectedChannel = _selectedChannelIndex < channelsProvider.filteredChannels.length
            ? channelsProvider.filteredChannels[_selectedChannelIndex]
            : null;

        if (selectedChannel == null) return const SizedBox();

        final programs = epgProvider.getUpcomingPrograms(selectedChannel.id, limit: 5);
        final currentProgram = epgProvider.getCurrentProgram(selectedChannel.id);

        return GestureDetector(
          onTap: () => setState(() => _showMiniGuide = false),
          child: Container(
            color: Colors.black.withOpacity(0.7),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: Container(
                  width: 500,
                  margin: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SaimoTheme.primary.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: SaimoTheme.primary.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
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
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Programação não disponível',
                            style: TextStyle(color: Colors.white54),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow, color: Colors.white),
                              const SizedBox(width: 8),
                              const Text(
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
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: channel.logo != null && channel.logo!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: channel.logo!,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => _buildChannelInitials(channel),
                    ),
                  )
                : _buildChannelInitials(channel),
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
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        channel.category,
                        style: const TextStyle(
                          color: Colors.white70,
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
                    color: Colors.white,
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
            icon: const Icon(Icons.close, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelInitials(Channel channel) {
    return Container(
      decoration: BoxDecoration(
        gradient: SaimoTheme.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          channel.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
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
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            program.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.1),
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
        color: isNow ? SaimoTheme.primary.withOpacity(0.1) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '${program.startTime.hour.toString().padLeft(2, '0')}:${program.startTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: isNow ? SaimoTheme.primary : Colors.white54,
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
                color: Colors.white.withOpacity(isNow ? 1 : 0.7),
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
            color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
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
                  color: isSelected ? color : Colors.white70,
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

/// Botão do footer da sidebar (expandido)
class _FooterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FooterButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white54, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão do footer da sidebar (colapsado)
class _FooterIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FooterIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white54, size: 22),
        ),
      ),
    );
  }
}

/// Hint de atalho de teclado
class _ShortcutHint extends StatelessWidget {
  final String keys;
  final String label;

  const _ShortcutHint({required this.keys, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Text(
            keys,
            style: TextStyle(
              color: SaimoTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

/// Card de canal premium
class _PremiumChannelCard extends StatelessWidget {
  final Channel channel;
  final bool isFavorite;
  final bool isSelected;
  final CurrentProgram? currentProgram;
  final bool isTV;
  final VoidCallback onFavoriteToggle;

  const _PremiumChannelCard({
    required this.channel,
    required this.isFavorite,
    required this.isSelected,
    required this.currentProgram,
    required this.isTV,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      transform: isSelected && isTV
          ? (Matrix4.identity()..scale(1.05))
          : Matrix4.identity(),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSelected
              ? [
                  SaimoTheme.primary.withOpacity(0.15),
                  const Color(0xFF1A1A25),
                ]
              : [
                  const Color(0xFF1A1A25),
                  const Color(0xFF15151F),
                ],
        ),
        borderRadius: BorderRadius.circular(isTV ? 16 : 12),
        border: Border.all(
          color: isSelected ? SaimoTheme.primary : Colors.white.withOpacity(0.05),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: SaimoTheme.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Área do logo
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Background com gradiente
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.03),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(isTV ? 15 : 11),
                    ),
                  ),
                ),
                // Logo
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: channel.logo != null && channel.logo!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logo!,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => _buildInitials(),
                            errorWidget: (_, __, ___) => _buildInitials(),
                          )
                        : _buildInitials(),
                  ),
                ),
                // Número do canal
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: isSelected ? SaimoTheme.primaryGradient : null,
                      color: isSelected ? null : Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      channel.channelNumber.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTV ? 13 : 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Favorito
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onFavoriteToggle,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isFavorite ? Colors.amber : Colors.white54,
                        size: isTV ? 20 : 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Área de informações
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(isTV ? 12 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Nome do canal
                  Text(
                    channel.name,
                    style: TextStyle(
                      color: isSelected ? SaimoTheme.primary : Colors.white,
                      fontSize: isTV ? 14 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Programa atual ou categoria
                  if (currentProgram?.current != null)
                    Text(
                      currentProgram!.current!.title,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: isTV ? 11 : 10,
                      ),
                      maxLines: isTV ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      channel.category,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: isTV ? 11 : 10,
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

  Widget _buildInitials() {
    return Container(
      decoration: BoxDecoration(
        gradient: SaimoTheme.primaryGradient,
        borderRadius: BorderRadius.circular(isTV ? 12 : 10),
      ),
      child: Center(
        child: Text(
          channel.initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: isTV ? 24 : 18,
            fontWeight: FontWeight.bold,
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
      backgroundColor: const Color(0xFF1A1A25),
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
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              Text(
                'Digite o código PIN',
                style: TextStyle(color: Colors.white54, fontSize: 13),
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
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 16,
            ),
            decoration: InputDecoration(
              hintText: '••••',
              hintStyle: TextStyle(
                color: Colors.white24,
                fontSize: 32,
                letterSpacing: 16,
              ),
              counterText: '',
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
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
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
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
