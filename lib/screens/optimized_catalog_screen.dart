import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/lazy_movies_provider.dart';
import '../widgets/movie_detail_modal.dart';
import '../widgets/series_detail_modal.dart';
import '../widgets/search_modal.dart';
import '../widgets/advanced_filters_modal.dart';
import '../services/tmdb_image_service.dart';

/// Design System Ultra Moderno - Cores Premium
class StreamingColors {
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF141414);
  static const Color surfaceLight = Color(0xFF1F1F1F);
  static const Color surfaceElevated = Color(0xFF262626);
  static const Color accent = Color(0xFFE50914);
  static const Color accentLight = Color(0xFFFF2D2D);
  static const Color accentGold = Color(0xFFFFD700);
  static const Color accentBlue = Color(0xFF0077FF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF666666);
}

/// Tela de Catálogo Ultra Moderna - Design Premium de Streaming
class OptimizedCatalogScreen extends StatefulWidget {
  const OptimizedCatalogScreen({super.key});

  @override
  State<OptimizedCatalogScreen> createState() => _OptimizedCatalogScreenState();
}

class _OptimizedCatalogScreenState extends State<OptimizedCatalogScreen>
    with TickerProviderStateMixin {
  // === NAVEGAÇÃO D-PAD ===
  int _currentSection = 0; // 0=filtros, 1=conteúdo (categorias agora é modal)
  int _filterIndex = 0;
  int _contentRow = 0;
  int _contentCol = 0;
  
  // === MODAL DE CATEGORIAS ===
  bool _showCategoryModal = false;
  int _modalCategoryIndex = 0;
  final ScrollController _modalScrollController = ScrollController();
  
  // === CONTROLADORES ===
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _contentScrollController = ScrollController();
  late AnimationController _pulseController;
  
  // === LAYOUT DINÂMICO ===
  int _columnsPerRow = 6;
  double _cardWidth = 160.0;
  double _cardHeight = 240.0;
  double _horizontalPadding = 32.0;
  final double _topBarHeight = 100.0; // Estimativa header + filtros (categorias agora é modal)

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _initializeData();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
      _calculateLayout();
    });
  }

  /// Calcula layout baseado no tamanho da tela e densidade
  void _calculateLayout() {
    if (!mounted) return;
    
    final size = MediaQuery.of(context).size;
    
    setState(() {
      // Padding horizontal adaptativo
      _horizontalPadding = size.width * 0.025;
      
      // Calcula colunas baseado na largura disponível (30% mais colunas = cards 30% menores)
      final availableWidth = size.width - (_horizontalPadding * 2);
      
      if (size.width >= 1920) {
        _columnsPerRow = 9;  // Era 7
      } else if (size.width >= 1280) {
        _columnsPerRow = 8;  // Era 6
      } else if (size.width >= 960) {
        _columnsPerRow = 7;  // Era 5
      } else {
        _columnsPerRow = 5;  // Era 4
      }
      
      // Calcula tamanho dos cards (menores para caber mais)
      final spacing = 12.0 * (_columnsPerRow - 1);  // Spacing menor
      _cardWidth = (availableWidth - spacing) / _columnsPerRow;
      _cardHeight = _cardWidth * 1.5; // Aspect ratio 2:3
    });
  }

  Future<void> _initializeData() async {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    await provider.initialize();
    // SEMPRE força carregamento de "Todos" na inicialização
    await provider.selectCategory('Todos', forceReload: true);
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _contentScrollController.dispose();
    _modalScrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // === D-PAD NAVIGATION ===
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    final key = event.logicalKey;
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    // Se modal de categorias está aberto, trata navegação nele
    if (_showCategoryModal) {
      return _handleModalNavigation(key, provider);
    }
    
    if (key == LogicalKeyboardKey.arrowUp) {
      _navigateUp(provider);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _navigateDown(provider);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _navigateLeft(provider);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _navigateRight(provider);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || 
               key == LogicalKeyboardKey.enter) {
      _handleSelect(provider);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack ||
               key == LogicalKeyboardKey.escape) {
      // Se o modal de categorias está aberto, fecha ele primeiro
      if (_showCategoryModal) {
        setState(() => _showCategoryModal = false);
        return KeyEventResult.handled;
      }
      // Volta direto para tela de seleção (sem confirmação)
      Navigator.of(context).pushReplacementNamed('/selector');
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
  
  /// Mostra diálogo de confirmação para sair do aplicativo
  Future<void> _showExitConfirmation() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: StreamingColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: StreamingColors.surfaceLight),
        ),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: StreamingColors.accent, size: 28),
            SizedBox(width: 12),
            Text(
              'Sair do Catálogo',
              style: TextStyle(
                color: StreamingColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'Deseja voltar para a tela inicial?',
          style: TextStyle(
            color: StreamingColors.textSecondary,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: StreamingColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: StreamingColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Sair',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (shouldExit == true && mounted) {
      Navigator.of(context).pushReplacementNamed('/selector');
    }
  }
  
  // === NAVEGAÇÃO DO MODAL DE CATEGORIAS ===
  KeyEventResult _handleModalNavigation(LogicalKeyboardKey key, LazyMoviesProvider provider) {
    final categories = provider.availableCategories;
    
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_modalCategoryIndex > 0) {
          _modalCategoryIndex--;
          _scrollModalToIndex(_modalCategoryIndex);
        }
      });
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_modalCategoryIndex < categories.length - 1) {
          _modalCategoryIndex++;
          _scrollModalToIndex(_modalCategoryIndex);
        }
      });
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || 
               key == LogicalKeyboardKey.enter) {
      // Seleciona categoria e fecha modal
      if (_modalCategoryIndex < categories.length) {
        provider.selectCategory(categories[_modalCategoryIndex]);
        _contentRow = 0;
        _contentCol = 0;
        if (_contentScrollController.hasClients) {
          _contentScrollController.jumpTo(0);
        }
      }
      setState(() => _showCategoryModal = false);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack ||
               key == LogicalKeyboardKey.escape ||
               key == LogicalKeyboardKey.arrowRight) {
      setState(() => _showCategoryModal = false);
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
  
  void _scrollModalToIndex(int index) {
    if (!_modalScrollController.hasClients) return;
    
    const itemHeight = 56.0; // Altura de cada item do modal
    final screenHeight = MediaQuery.of(context).size.height;
    final viewportHeight = screenHeight - 200; // Desconta header do modal
    
    final itemTop = index * itemHeight;
    final itemBottom = itemTop + itemHeight;
    
    final currentScroll = _modalScrollController.offset;
    final viewportTop = currentScroll;
    final viewportBottom = currentScroll + viewportHeight;
    
    double targetOffset = currentScroll;
    
    if (itemBottom > viewportBottom) {
      targetOffset = itemBottom - viewportHeight + 20;
    } else if (itemTop < viewportTop) {
      targetOffset = itemTop - 20;
    }
    
    _modalScrollController.animateTo(
      targetOffset.clamp(0.0, _modalScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _navigateUp(LazyMoviesProvider provider) {
    setState(() {
      if (_currentSection == 1) {
        // No grid de conteúdo
        if (_contentRow > 0) {
          _contentRow--;
          _scrollToContentRow(_contentRow);
        } else {
          // Volta para filtros
          _currentSection = 0;
        }
      }
    });
  }

  void _navigateDown(LazyMoviesProvider provider) {
    setState(() {
      if (_currentSection == 0) {
        // Vai para conteúdo
        _currentSection = 1;
        _contentRow = 0;
        _contentCol = 0;
      } else if (_currentSection == 1) {
        // Navega pelas linhas do grid
        final items = provider.displayItems;
        final totalRows = (items.length / _columnsPerRow).ceil();
        if (_contentRow < totalRows - 1) {
          _contentRow++;
          _scrollToContentRow(_contentRow);
        }
      }
    });
  }

  void _navigateLeft(LazyMoviesProvider provider) {
    setState(() {
      switch (_currentSection) {
        case 0:
          if (_filterIndex > 0) {
            _filterIndex--;
          } else {
            // Se está no primeiro filtro, abre modal de categorias
            _openCategoryModal(provider);
          }
          break;
        case 1:
          if (_contentCol > 0) {
            _contentCol--;
          } else if (_contentRow > 0) {
            // Volta para linha anterior, última coluna
            _contentRow--;
            _contentCol = _columnsPerRow - 1;
            _scrollToContentRow(_contentRow);
          } else {
            // Se está na primeira coluna da primeira linha, abre modal
            _openCategoryModal(provider);
          }
          break;
      }
    });
  }
  
  void _openCategoryModal(LazyMoviesProvider provider) {
    final categories = provider.availableCategories;
    final currentCatIndex = categories.indexOf(provider.selectedCategoryName);
    setState(() {
      _showCategoryModal = true;
      _modalCategoryIndex = currentCatIndex >= 0 ? currentCatIndex : 0;
    });
    // Scroll para a categoria selecionada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollModalToIndex(_modalCategoryIndex);
    });
  }

  void _navigateRight(LazyMoviesProvider provider) {
    setState(() {
      switch (_currentSection) {
        case 0:
          if (_filterIndex < 5) _filterIndex++; // 0-5: categorias, todos, filmes, séries, filtros, pesquisa
          break;
        case 1:
          final items = provider.displayItems;
          final currentIndex = _contentRow * _columnsPerRow + _contentCol;
          if (currentIndex < items.length - 1) {
            if (_contentCol < _columnsPerRow - 1) {
              _contentCol++;
            } else {
              // Vai para próxima linha
              _contentRow++;
              _contentCol = 0;
              _scrollToContentRow(_contentRow);
            }
          }
          break;
      }
    });
  }

  void _scrollToContentRow(int row) {
    if (!_contentScrollController.hasClients) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final viewportHeight = screenHeight - _topBarHeight;
    final rowHeight = _cardHeight + 16; // card height + novo spacing
    
    // Calcula offset para centralizar a linha focada no viewport
    final rowCenter = (row * rowHeight) + (rowHeight / 2);
    final viewportCenter = viewportHeight / 2;
    final targetOffset = rowCenter - viewportCenter;
    
    _contentScrollController.animateTo(
      targetOffset.clamp(0.0, _contentScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _handleSelect(LazyMoviesProvider provider) {
    switch (_currentSection) {
      case 0:
        // Barra de filtros - primeiro item é botão de categorias
        if (_filterIndex == 0) {
          // Abre modal de categorias
          _openCategoryModal(provider);
        } else if (_filterIndex == 4) {
          // Abre modal de filtros avançados
          _openAdvancedFiltersModal(provider);
        } else if (_filterIndex == 5) {
          // Abre modal de pesquisa
          _openSearchModal();
        } else {
          // Filtros de tipo (1, 2, 3)
          MovieFilterType newFilter;
          if (_filterIndex == 1) {
            newFilter = MovieFilterType.all;
          } else if (_filterIndex == 2) {
            newFilter = MovieFilterType.movies;
          } else {
            newFilter = MovieFilterType.series;
          }
          
          if (provider.filterType != newFilter) {
            provider.setFilterType(newFilter);
            // Reseta navegação do conteúdo
            _contentRow = 0;
            _contentCol = 0;
            if (_contentScrollController.hasClients) {
              _contentScrollController.jumpTo(0);
            }
          }
        }
        break;
      case 1:
        // Conteúdo - abre detalhe do filme/série
        final items = provider.displayItems;
        final index = _contentRow * _columnsPerRow + _contentCol;
        if (index < items.length) {
          _showDetailModal(items[index]);
        }
        break;
    }
  }

  void _showDetailModal(CatalogDisplayItem item) {
    if (item.type == DisplayItemType.series && item.series != null) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (context) => SeriesDetailModal(series: item.series!),
      );
    } else if (item.movie != null) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (context) => MovieDetailModal(movie: item.movie!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Nunca permite sair diretamente
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // Se o modal de categorias está aberto, fecha ele primeiro
          if (_showCategoryModal) {
            setState(() => _showCategoryModal = false);
          } else {
            // Mostra confirmação antes de sair
            _showExitConfirmation();
          }
        }
      },
      child: Scaffold(
        backgroundColor: StreamingColors.background,
        body: Focus(
          focusNode: _mainFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: Consumer<LazyMoviesProvider>(
            builder: (context, provider, _) {
              if (provider.isLoadingIndex) {
                return _buildLoadingScreen();
              }
              
              return Stack(
                children: [
                  // Conteúdo principal
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(provider),
                      _buildFilters(provider),
                      const SizedBox(height: 16),
                      Expanded(child: _buildContentGrid(provider)),
                    ],
                  ),
                  // Modal de categorias (overlay lateral)
                  if (_showCategoryModal)
                    _buildCategoryModal(provider),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
  
  /// Modal lateral de categorias
  Widget _buildCategoryModal(LazyMoviesProvider provider) {
    final categories = provider.availableCategories;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Row(
      children: [
        // Painel lateral com categorias
        Container(
          width: 320,
          height: screenHeight,
          decoration: BoxDecoration(
            color: StreamingColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(5, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header do modal
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: StreamingColors.surfaceElevated,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StreamingColors.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.category_rounded,
                        color: StreamingColors.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Categorias',
                      style: TextStyle(
                        color: StreamingColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${categories.length}',
                      style: const TextStyle(
                        color: StreamingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // Lista de categorias
              Expanded(
                child: ListView.builder(
                  controller: _modalScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = provider.selectedCategoryName == category;
                    final isFocused = _modalCategoryIndex == index;
                    
                    return GestureDetector(
                      onTap: () {
                        provider.selectCategory(category);
                        setState(() => _showCategoryModal = false);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isFocused 
                              ? StreamingColors.accent.withOpacity(0.3)
                              : isSelected 
                                  ? StreamingColors.surfaceLight
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isFocused
                              ? Border.all(color: StreamingColors.accent, width: 2)
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Ícone da categoria
                            Icon(
                              _getCategoryIcon(category),
                              color: isFocused || isSelected
                                  ? StreamingColors.accent
                                  : StreamingColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            // Nome da categoria
                            Expanded(
                              child: Text(
                                category,
                                style: TextStyle(
                                  color: isFocused || isSelected
                                      ? StreamingColors.textPrimary
                                      : StreamingColors.textSecondary,
                                  fontSize: 15,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Indicador de selecionado
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: StreamingColors.accent,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Footer com dicas de navegação
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: StreamingColors.surfaceLight,
                  border: Border(
                    top: BorderSide(
                      color: StreamingColors.surfaceElevated,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildKeyHint('↑↓', 'Navegar'),
                    const SizedBox(width: 16),
                    _buildKeyHint('OK', 'Selecionar'),
                    const SizedBox(width: 16),
                    _buildKeyHint('←', 'Fechar'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Área clicável para fechar
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _showCategoryModal = false),
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildKeyHint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: StreamingColors.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: StreamingColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: StreamingColors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
  
  IconData _getCategoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower == 'todos') return Icons.apps_rounded;
    if (lower.contains('lançamento')) return Icons.new_releases_rounded;
    if (lower.contains('netflix')) return Icons.play_circle_filled_rounded;
    if (lower.contains('prime')) return Icons.shopping_bag_rounded;
    if (lower.contains('disney')) return Icons.castle_rounded;
    if (lower.contains('max') || lower.contains('hbo')) return Icons.movie_filter_rounded;
    if (lower.contains('paramount')) return Icons.star_purple500_rounded;
    if (lower.contains('apple')) return Icons.apple_rounded;
    if (lower.contains('globo')) return Icons.language_rounded;
    if (lower.contains('novela')) return Icons.favorite_rounded;
    if (lower.contains('dorama')) return Icons.self_improvement_rounded;
    if (lower.contains('anime') || lower.contains('crunchyroll') || lower.contains('funimation')) return Icons.animation_rounded;
    if (lower.contains('coleção') || lower.contains('colecao')) return Icons.collections_rounded;
    if (lower.contains('ação') || lower.contains('acao')) return Icons.local_fire_department_rounded;
    if (lower.contains('comédia') || lower.contains('comedia')) return Icons.sentiment_very_satisfied_rounded;
    if (lower.contains('terror') || lower.contains('horror')) return Icons.nights_stay_rounded;
    if (lower.contains('drama')) return Icons.theater_comedy_rounded;
    if (lower.contains('ficção') || lower.contains('ficcao') || lower.contains('sci-fi')) return Icons.rocket_launch_rounded;
    if (lower.contains('romance')) return Icons.favorite_border_rounded;
    if (lower.contains('documentário') || lower.contains('documentario')) return Icons.video_camera_back_rounded;
    if (lower.contains('infantil') || lower.contains('kids')) return Icons.child_care_rounded;
    if (lower.contains('marvel') || lower.contains('dc')) return Icons.shield_rounded;
    if (lower.contains('star wars')) return Icons.star_rounded;
    return Icons.folder_rounded;
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.1),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [StreamingColors.accent, StreamingColors.accentLight],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: StreamingColors.accent.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 50, color: Colors.white),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Carregando catálogo...',
            style: TextStyle(color: StreamingColors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(LazyMoviesProvider provider) {
    return Container(
      padding: EdgeInsets.fromLTRB(_horizontalPadding, 24, _horizontalPadding, 8),
      child: Row(
        children: [
          // Logo/Título
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [StreamingColors.accent, StreamingColors.accentLight],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Text(
                'Catálogo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Botão para ir aos Canais de TV
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pushReplacementNamed('/channels'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C853).withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Canais',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Contadores
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: StreamingColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.movie_outlined, color: StreamingColors.textMuted, size: 18),
                const SizedBox(width: 6),
                Text('${provider.totalMovies}', style: const TextStyle(color: StreamingColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                const Icon(Icons.tv_outlined, color: StreamingColors.textMuted, size: 18),
                const SizedBox(width: 6),
                Text('${provider.totalSeries}', style: const TextStyle(color: StreamingColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(LazyMoviesProvider provider) {
    // Filtros: primeiro é botão de categorias, depois os tipos, e por último pesquisa
    final filterTypes = [
      {'label': 'Todos', 'type': MovieFilterType.all, 'icon': Icons.apps_rounded},
      {'label': 'Filmes', 'type': MovieFilterType.movies, 'icon': Icons.movie_outlined},
      {'label': 'Séries', 'type': MovieFilterType.series, 'icon': Icons.tv_outlined},
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Row(
        children: [
          // Botão de categorias (primeiro item, index 0)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _openCategoryModal(provider),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [StreamingColors.accentBlue, Color(0xFF0099FF)],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  border: (_currentSection == 0 && _filterIndex == 0)
                      ? Border.all(color: StreamingColors.accentGold, width: 2)
                      : null,
                  boxShadow: (_currentSection == 0 && _filterIndex == 0)
                      ? [BoxShadow(color: StreamingColors.accentGold.withOpacity(0.4), blurRadius: 10)]
                      : null,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      provider.selectedCategoryName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
          // Separador visual
          Container(
            width: 1,
            height: 32,
            color: StreamingColors.surfaceElevated,
            margin: const EdgeInsets.only(right: 12),
          ),
          // Filtros de tipo (índices 1, 2, 3)
          ...filterTypes.asMap().entries.map((entry) {
            final index = entry.key + 1; // +1 porque 0 é o botão de categorias
            final filter = entry.value;
            final isSelected = provider.filterType == filter['type'];
            final isFocused = _currentSection == 0 && _filterIndex == index;
            
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => provider.setFilterType(filter['type'] as MovieFilterType),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: [StreamingColors.accent, StreamingColors.accentLight])
                        : null,
                    color: isSelected ? null : StreamingColors.surfaceLight,
                    borderRadius: BorderRadius.circular(25),
                    border: isFocused
                        ? Border.all(color: StreamingColors.accentGold, width: 2)
                        : null,
                    boxShadow: isFocused
                        ? [BoxShadow(color: StreamingColors.accentGold.withOpacity(0.4), blurRadius: 10)]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        filter['icon'] as IconData,
                        color: isSelected ? Colors.white : StreamingColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        filter['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : StreamingColors.textSecondary,
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // Separador visual antes da pesquisa
          Container(
            width: 1,
            height: 32,
            color: StreamingColors.surfaceElevated,
            margin: const EdgeInsets.only(right: 12),
          ),
          // Botão de filtros avançados (índice 4)
          GestureDetector(
            onTap: () => _openAdvancedFiltersModal(provider),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: provider.hasAdvancedFilters
                    ? const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFFF9500)])
                    : null,
                color: provider.hasAdvancedFilters ? null : StreamingColors.surfaceLight,
                borderRadius: BorderRadius.circular(25),
                border: (_currentSection == 0 && _filterIndex == 4)
                    ? Border.all(color: StreamingColors.accentGold, width: 2)
                    : null,
                boxShadow: (_currentSection == 0 && _filterIndex == 4)
                    ? [BoxShadow(color: StreamingColors.accentGold.withOpacity(0.4), blurRadius: 10)]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    color: provider.hasAdvancedFilters ? Colors.white : StreamingColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    provider.hasAdvancedFilters ? 'Filtros Ativos' : 'Filtros',
                    style: TextStyle(
                      color: provider.hasAdvancedFilters ? Colors.white : StreamingColors.textSecondary,
                      fontSize: 14,
                      fontWeight: provider.hasAdvancedFilters ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Botão de pesquisa (índice 5)
          GestureDetector(
            onTap: _openSearchModal,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
                ),
                borderRadius: BorderRadius.circular(25),
                border: (_currentSection == 0 && _filterIndex == 5)
                    ? Border.all(color: StreamingColors.accentGold, width: 2)
                    : null,
                boxShadow: (_currentSection == 0 && _filterIndex == 5)
                    ? [BoxShadow(color: StreamingColors.accentGold.withOpacity(0.4), blurRadius: 10)]
                    : null,
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Pesquisar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
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
  
  /// Abre o modal de filtros avançados
  void _openAdvancedFiltersModal(LazyMoviesProvider provider) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AdvancedFiltersModal(
        currentFilters: AdvancedFilters(
          genres: provider.filterGenres,
          yearFrom: provider.filterYearFrom,
          minRating: provider.filterMinRating,
          certification: provider.filterCertification,
          language: provider.filterLanguage,
          maxRuntime: provider.filterMaxRuntime,
          sortBy: _sortOptionFromString(provider.sortBy),
          sortDescending: provider.sortDescending,
        ),
        onApply: (filters) {
          provider.setAdvancedFilters(
            genres: filters.genres,
            yearFrom: filters.yearFrom,
            minRating: filters.minRating,
            certification: filters.certification,
            language: filters.language,
            maxRuntime: filters.maxRuntime,
            sortBy: _sortOptionToString(filters.sortBy),
            sortDescending: filters.sortDescending,
          );
          // Reseta navegação
          setState(() {
            _contentRow = 0;
            _contentCol = 0;
          });
          if (_contentScrollController.hasClients) {
            _contentScrollController.jumpTo(0);
          }
        },
      ),
    );
  }
  
  SortOption _sortOptionFromString(String sort) {
    switch (sort) {
      case 'year': return SortOption.year;
      case 'rating': return SortOption.rating;
      case 'popularity': return SortOption.popularity;
      case 'runtime': return SortOption.runtime;
      default: return SortOption.name;
    }
  }
  
  String _sortOptionToString(SortOption sort) {
    switch (sort) {
      case SortOption.year: return 'year';
      case SortOption.rating: return 'rating';
      case SortOption.popularity: return 'popularity';
      case SortOption.runtime: return 'runtime';
      default: return 'name';
    }
  }
  
  /// Abre o modal de pesquisa
  void _openSearchModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => const SearchModal(),
    );
  }

  Widget _buildContentGrid(LazyMoviesProvider provider) {
    final items = provider.displayItems;
    
    if (provider.isLoadingCategory) {
      return const Center(
        child: CircularProgressIndicator(color: StreamingColors.accent),
      );
    }
    
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_filter_outlined, size: 64, color: StreamingColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Nenhum conteúdo encontrado',
              style: TextStyle(color: StreamingColors.textSecondary, fontSize: 18),
            ),
          ],
        ),
      );
    }
    
    return GridView.builder(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(_horizontalPadding, 0, _horizontalPadding, 32),
      // Otimizações de performance para Fire TV Lite
      cacheExtent: 200, // Reduz cache de scroll para economizar memória
      addAutomaticKeepAlives: false, // Não mantém widgets fora da tela
      addRepaintBoundaries: true, // Isola repaint de cada item
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnsPerRow,
        childAspectRatio: _cardWidth / _cardHeight,
        crossAxisSpacing: 12,  // Menor spacing
        mainAxisSpacing: 16,   // Menor spacing
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final row = index ~/ _columnsPerRow;
        final col = index % _columnsPerRow;
        final isFocused = _currentSection == 1 && _contentRow == row && _contentCol == col;
        
        return _MovieCard(
          key: ValueKey(item.displayName), // Key para otimizar rebuild
          item: item,
          isFocused: isFocused,
          onTap: () => _showDetailModal(item),
        );
      },
    );
  }
}

/// Card de filme/série com nota e classificação do TMDB
class _MovieCard extends StatefulWidget {
  final CatalogDisplayItem item;
  final bool isFocused;
  final VoidCallback onTap;

  const _MovieCard({
    super.key,
    required this.item,
    required this.isFocused,
    required this.onTap,
  });

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;
  
  // Dados do TMDB
  double? _rating;
  String? _certification;
  bool _loadedTmdb = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOut),
    );
    _loadTmdbData();
  }

  Future<void> _loadTmdbData() async {
    if (_loadedTmdb) return;
    _loadedTmdb = true;
    
    final title = widget.item.displayName;
    final category = widget.item.type == DisplayItemType.movie 
        ? widget.item.movie?.category 
        : widget.item.series?.category;
    final isSeries = widget.item.type == DisplayItemType.series;
    
    try {
      // Busca rating e certificação em paralelo
      final results = await Future.wait([
        TMDBImageService.searchRating(title, type: isSeries ? 'tv' : 'movie', category: category),
        TMDBImageService.searchCertification(title, type: isSeries ? 'tv' : 'movie', category: category),
      ]);
      
      if (mounted) {
        setState(() {
          _rating = results[0] as double?;
          _certification = results[1] as String?;
        });
      }
    } catch (e) {
      // Ignora erros
    }
  }

  @override
  void didUpdateWidget(_MovieCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused && !_isHovered) {
      _hoverController.forward();
      _isHovered = true;
    } else if (!widget.isFocused && _isHovered) {
      _hoverController.reverse();
      _isHovered = false;
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  Color _getCertificationColor(String? cert) {
    if (cert == null) return StreamingColors.textMuted;
    switch (cert) {
      case 'L':
        return const Color(0xFF00A651); // Verde
      case '10':
        return const Color(0xFF00AEEF); // Azul claro
      case '12':
        return const Color(0xFFFFCB05); // Amarelo
      case '14':
        return const Color(0xFFF58220); // Laranja
      case '16':
        return const Color(0xFFED1C24); // Vermelho
      case '18':
        return const Color(0xFF1C1C1C); // Preto
      default:
        return StreamingColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => _hoverController.forward(),
          onExit: (_) => _hoverController.reverse(),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: widget.isFocused
                  ? [
                      BoxShadow(
                        color: StreamingColors.accent.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // Poster
                  Positioned.fill(
                    child: widget.item.logo != null
                        ? CachedNetworkImage(
                            imageUrl: widget.item.logo!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _buildPlaceholder(),
                            errorWidget: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                  
                  // Gradiente inferior
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withOpacity(0.8),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  
                  // Badge tipo (Filme/Série)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.item.type == DisplayItemType.series
                            ? StreamingColors.accentBlue
                            : StreamingColors.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.item.type == DisplayItemType.series ? 'SÉRIE' : 'FILME',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  
                  // Qualidade (4K, 1080p, etc)
                  if (widget.item.quality != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: StreamingColors.accentGold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.item.quality!,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  // Classificação indicativa (canto inferior direito)
                  if (_certification != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: _getCertificationColor(_certification),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          _certification!,
                          style: TextStyle(
                            color: _certification == '18' ? Colors.white : Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  // Info inferior (Nota + Nome)
                  Positioned(
                    left: 8,
                    right: _certification != null ? 50 : 8, // Espaço para classificação
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rating TMDB
                        if (_rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: StreamingColors.accentGold,
                                  size: 12,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        if (_rating != null) const SizedBox(height: 6),
                        
                        // Nome
                        Text(
                          widget.item.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Borda de foco
                  if (widget.isFocused)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: StreamingColors.accent,
                            width: 3,
                          ),
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
  }

  Widget _buildPlaceholder() {
    return Container(
      color: StreamingColors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.item.type == DisplayItemType.series ? Icons.tv : Icons.movie,
            color: StreamingColors.textMuted,
            size: 40,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              widget.item.displayName,
              style: const TextStyle(
                color: StreamingColors.textMuted,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
