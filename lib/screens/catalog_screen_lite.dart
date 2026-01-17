import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/lazy_movies_provider.dart';
import '../widgets/movie_detail_modal.dart';
import '../widgets/series_modal_optimized.dart';
import '../widgets/advanced_filters_modal.dart';
import '../services/tmdb_image_service.dart';

/// Tela de Catálogo Ultra Otimizada para Fire TV Lite
/// - Menos widgets = menos memória
/// - Scroll virtualizado
/// - Imagens com cache otimizado
/// - Navegação D-PAD simplificada
class CatalogScreenLite extends StatefulWidget {
  const CatalogScreenLite({super.key});

  @override
  State<CatalogScreenLite> createState() => _CatalogScreenLiteState();
}

class _CatalogScreenLiteState extends State<CatalogScreenLite> {
  // === NAVEGAÇÃO ===
  // Seções: 0=header, 1=filtros, 2=conteúdo
  int _section = 1;
  int _headerIndex = 0; // 0=voltar, 1=tv ao vivo, 2=config
  int _filterIndex = 0; // 0=categorias, 1=todos, 2=filmes, 3=séries, 4=avançado, 5=buscar
  int _contentRow = 0;
  int _contentCol = 0;
  
  // === MODAL CATEGORIAS ===
  bool _showCategoryModal = false;
  int _modalIndex = 0;
  final ScrollController _modalScroll = ScrollController();
  
  // === BUSCA ===
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  static const int _minSearchChars = 3;
  
  // === CONTROLADORES ===
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  // === LAYOUT ===
  int _columns = 6;
  double _cardWidth = 140;
  double _cardHeight = 210;

  @override
  void initState() {
    super.initState();
    _initData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _calculateLayout();
    });
  }

  Future<void> _initData() async {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    await provider.initialize();
    // Inicia com "Todos" selecionado
    if (provider.selectedCategoryName != 'Todos') {
      await provider.selectCategory('Todos');
    }
  }

  void _calculateLayout() {
    if (!mounted) return;
    final width = MediaQuery.of(context).size.width;
    
    setState(() {
      if (width >= 1920) {
        _columns = 8;
      } else if (width >= 1280) {
        _columns = 7;
      } else {
        _columns = 5;
      }
      
      final padding = width * 0.02;
      final spacing = 10.0 * (_columns - 1);
      _cardWidth = (width - (padding * 2) - spacing) / _columns;
      _cardHeight = _cardWidth * 1.5;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _modalScroll.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // === NAVEGAÇÃO D-PAD ===
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    
    // Se está no modo de busca com campo focado
    if (_isSearchMode && _searchFocusNode.hasFocus) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchFocusNode.unfocus();
        setState(() => _section = 2);
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      // Deixa o TextField processar outras teclas
      return KeyEventResult.ignored;
    }
    
    // Modal de categorias aberto
    if (_showCategoryModal) {
      return _handleModalKey(key);
    }
    
    // Botão de Options/Menu do Fire TV - abre modal de categorias
    if (key == LogicalKeyboardKey.contextMenu || 
        key == LogicalKeyboardKey.info ||
        key == LogicalKeyboardKey.gameButtonSelect) {
      final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
      _openCategoryModal(provider);
      return KeyEventResult.handled;
    }
    
    if (key == LogicalKeyboardKey.arrowUp) {
      _onUp();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _onDown();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _onLeft();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _onRight();
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _onSelect();
    } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      if (_isSearchMode) {
        _closeSearch();
      } else {
        Navigator.of(context).pushReplacementNamed('/selector');
      }
    } else {
      return KeyEventResult.ignored;
    }
    
    return KeyEventResult.handled;
  }
  
  KeyEventResult _handleModalKey(LogicalKeyboardKey key) {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final cats = provider.availableCategories;
    
    if (key == LogicalKeyboardKey.arrowUp && _modalIndex > 0) {
      setState(() => _modalIndex--);
      _scrollModal();
    } else if (key == LogicalKeyboardKey.arrowDown && _modalIndex < cats.length - 1) {
      setState(() => _modalIndex++);
      _scrollModal();
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      provider.selectCategory(cats[_modalIndex]);
      setState(() {
        _showCategoryModal = false;
        _contentRow = 0;
        _contentCol = 0;
      });
      _scrollController.jumpTo(0);
    } else if (key == LogicalKeyboardKey.goBack || 
               key == LogicalKeyboardKey.escape ||
               key == LogicalKeyboardKey.arrowRight) {
      setState(() => _showCategoryModal = false);
    } else {
      return KeyEventResult.ignored;
    }
    
    return KeyEventResult.handled;
  }
  
  void _scrollModal() {
    if (!_modalScroll.hasClients) return;
    const h = 48.0;
    final offset = (_modalIndex * h) - 150;
    _modalScroll.animateTo(
      offset.clamp(0.0, _modalScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _onUp() {
    setState(() {
      if (_section == 2) {
        if (_contentRow > 0) {
          _contentRow--;
          _scrollToRow();
        } else {
          _section = 1;
        }
      } else if (_section == 1) {
        _section = 0;
      }
    });
  }

  void _onDown() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final itemCount = provider.selectedCategoryName == 'Todos' 
        ? provider.availableCategories.length - 1 // Exclui "Todos"
        : provider.displayItems.length;
    final rows = (itemCount / _columns).ceil();
    
    setState(() {
      if (_section == 0) {
        _section = 1;
      } else if (_section == 1) {
        _section = 2;
        _contentRow = 0;
        _contentCol = 0;
      } else if (_contentRow < rows - 1) {
        _contentRow++;
        _scrollToRow();
      }
    });
  }

  void _onLeft() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    setState(() {
      if (_section == 0) {
        if (_headerIndex > 0) _headerIndex--;
      } else if (_section == 1) {
        if (_filterIndex > 0) {
          _filterIndex--;
        } else {
          _openCategoryModal(provider);
        }
      } else if (_section == 2) {
        if (_contentCol > 0) {
          _contentCol--;
        } else if (_contentRow > 0) {
          _contentRow--;
          _contentCol = _columns - 1;
          _scrollToRow();
        } else {
          _openCategoryModal(provider);
        }
      }
    });
  }

  void _onRight() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final itemCount = provider.selectedCategoryName == 'Todos' 
        ? provider.availableCategories.length - 1
        : provider.displayItems.length;
    
    setState(() {
      if (_section == 0) {
        if (_headerIndex < 2) _headerIndex++;
      } else if (_section == 1) {
        if (_filterIndex < 5) _filterIndex++; // Agora vai até 5 (buscar)
      } else if (_section == 2) {
        final idx = _contentRow * _columns + _contentCol;
        if (idx < itemCount - 1) {
          if (_contentCol < _columns - 1) {
            _contentCol++;
          } else {
            _contentRow++;
            _contentCol = 0;
            _scrollToRow();
          }
        }
      }
    });
  }

  void _onSelect() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    if (_section == 0) {
      if (_headerIndex == 0) {
        Navigator.of(context).pushReplacementNamed('/selector');
      } else if (_headerIndex == 1) {
        Navigator.of(context).pushReplacementNamed('/channels');
      } else {
        Navigator.of(context).pushNamed('/settings');
      }
    } else if (_section == 1) {
      if (_filterIndex == 0) {
        _openCategoryModal(provider);
      } else if (_filterIndex == 4) {
        // Botão Filtros Avançados
        _openAdvancedFilters(provider);
      } else if (_filterIndex == 5) {
        // Botão Buscar
        _openSearch();
      } else {
        final filters = [MovieFilterType.all, MovieFilterType.movies, MovieFilterType.series];
        final newFilter = filters[_filterIndex - 1];
        if (provider.filterType != newFilter) {
          provider.setFilterType(newFilter);
          _contentRow = 0;
          _contentCol = 0;
          _scrollController.jumpTo(0);
        }
      }
    } else if (_section == 2) {
      if (provider.selectedCategoryName == 'Todos' && !_isSearchMode) {
        // Seleciona categoria
        final cats = provider.availableCategories.where((c) => c != 'Todos').toList();
        final idx = _contentRow * _columns + _contentCol;
        if (idx < cats.length) {
          provider.selectCategory(cats[idx]);
          _contentRow = 0;
          _contentCol = 0;
          _scrollController.jumpTo(0);
        }
      } else {
        // Abre detalhe
        final items = provider.displayItems;
        final idx = _contentRow * _columns + _contentCol;
        if (idx < items.length) {
          _showDetail(items[idx]);
        }
      }
    }
  }
  
  // === FUNÇÕES DE BUSCA ===
  void _openSearch() {
    setState(() {
      _isSearchMode = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }
  
  void _closeSearch() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    provider.clearSearch();
    _searchController.clear();
    setState(() {
      _isSearchMode = false;
      _contentRow = 0;
      _contentCol = 0;
    });
    _focusNode.requestFocus();
  }
  
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    
    // Atualiza o estado visual
    setState(() {});
    
    // Se menos de 3 caracteres, limpa busca e não busca ainda
    if (query.isEmpty) {
      final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
      provider.clearSearch();
      return;
    }
    
    if (query.length < _minSearchChars) {
      return;
    }
    
    // Debounce de 500ms para busca global (mais pesada)
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }
  
  Future<void> _performSearch(String query) async {
    if (query.length < _minSearchChars) return;
    
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    // Usa performGlobalSearch para buscar em TODAS as categorias
    await provider.performGlobalSearch(query);
    
    if (mounted) {
      setState(() {
        _contentRow = 0;
        _contentCol = 0;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }
  
  void _submitSearch() {
    _searchDebounce?.cancel();
    final query = _searchController.text;
    if (query.length >= _minSearchChars) {
      _performSearch(query);
    }
  }
  
  void _openCategoryModal(LazyMoviesProvider provider) {
    final cats = provider.availableCategories;
    final idx = cats.indexOf(provider.selectedCategoryName);
    setState(() {
      _showCategoryModal = true;
      _modalIndex = idx >= 0 ? idx : 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollModal());
  }

  void _openAdvancedFilters(LazyMoviesProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AdvancedFiltersModal(
        currentFilters: AdvancedFilters.empty,
        onApply: (filters) {
          // Aplica os filtros avançados
          provider.setAdvancedFilters(
            genres: filters.genres.isNotEmpty ? filters.genres : null,
            yearFrom: filters.yearFrom,
            minRating: filters.minRating,
            certification: filters.certification,
            language: filters.language,
            maxRuntime: filters.maxRuntime,
            sortBy: filters.sortBy.name,
            sortDescending: filters.sortDescending,
          );
          
          _contentRow = 0;
          _contentCol = 0;
          _scrollController.jumpTo(0);
        },
      ),
    );
  }

  void _scrollToRow() {
    if (!_scrollController.hasClients) return;
    
    final screenH = MediaQuery.of(context).size.height;
    final headerH = 56.0 + 48.0; // header + filtros
    final contentH = screenH - headerH;
    final padding = MediaQuery.of(context).size.width * 0.02;
    
    // Calcula altura correta do card baseado se é "Todos" (16:9) ou conteúdo (poster)
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final isTodos = provider.selectedCategoryName == 'Todos';
    final aspectRatio = isTodos ? 16 / 9 : _cardWidth / _cardHeight;
    final cardH = isTodos ? (_cardWidth / (16 / 9)) : _cardHeight;
    final rowH = cardH + 10; // altura do card + spacing
    
    // Calcula posição do item focado
    final focusedItemTop = padding + (_contentRow * rowH);
    final focusedItemBottom = focusedItemTop + cardH;
    
    // Visão atual do scroll
    final currentScrollTop = _scrollController.offset;
    final currentScrollBottom = currentScrollTop + contentH;
    
    // Margem de segurança para garantir que o item está bem visível
    const safeMargin = 20.0;
    
    double targetOffset = currentScrollTop;
    
    // Se o item está acima da área visível
    if (focusedItemTop < currentScrollTop + safeMargin) {
      targetOffset = focusedItemTop - safeMargin;
    }
    // Se o item está abaixo da área visível
    else if (focusedItemBottom > currentScrollBottom - safeMargin) {
      targetOffset = focusedItemBottom - contentH + safeMargin;
    }
    
    // Aplica o scroll se necessário
    if (targetOffset != currentScrollTop) {
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _showDetail(CatalogDisplayItem item) {
    if (item.type == DisplayItemType.series && item.series != null) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => SeriesModalOptimized(series: item.series!),
      );
    } else if (item.movie != null) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => MovieDetailModal(movie: item.movie!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: Consumer<LazyMoviesProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingIndex) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              );
            }
            
            return Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(provider),
                    _buildFilters(provider),
                    Expanded(child: _buildContent(provider)),
                  ],
                ),
                if (_showCategoryModal) _buildCategoryModal(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(LazyMoviesProvider provider) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Botão Voltar
          _HeaderButton(
            icon: Icons.arrow_back_rounded,
            label: 'Voltar',
            isFocused: _section == 0 && _headerIndex == 0,
            onTap: () => Navigator.of(context).pushReplacementNamed('/selector'),
          ),
          const SizedBox(width: 12),
          
          // Botão TV ao Vivo
          _HeaderButton(
            icon: Icons.live_tv_rounded,
            label: 'TV ao Vivo',
            isFocused: _section == 0 && _headerIndex == 1,
            onTap: () => Navigator.of(context).pushReplacementNamed('/channels'),
          ),
          
          const Spacer(),
          
          // Título
          const Text(
            'Catálogo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const Spacer(),
          
          // Stats
          Text(
            '${provider.totalMovies} filmes • ${provider.totalSeries} séries',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          
          const SizedBox(width: 12),
          
          // Botão Configurações
          _HeaderButton(
            icon: Icons.settings_rounded,
            label: 'Config',
            isFocused: _section == 0 && _headerIndex == 2,
            onTap: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(LazyMoviesProvider provider) {
    // Se está no modo busca, mostra o campo de busca
    if (_isSearchMode) {
      return _buildSearchBar(provider);
    }
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Botão de categoria
          _FilterButton(
            icon: Icons.category_rounded,
            label: provider.selectedCategoryName,
            isSelected: true,
            isFocused: _section == 1 && _filterIndex == 0,
            isBlue: true,
            onTap: () => _openCategoryModal(provider),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.white10),
          const SizedBox(width: 8),
          
          // Filtros de tipo
          _FilterButton(
            icon: Icons.apps_rounded,
            label: 'Todos',
            isSelected: provider.filterType == MovieFilterType.all,
            isFocused: _section == 1 && _filterIndex == 1,
            onTap: () => provider.setFilterType(MovieFilterType.all),
          ),
          const SizedBox(width: 8),
          _FilterButton(
            icon: Icons.movie_rounded,
            label: 'Filmes',
            isSelected: provider.filterType == MovieFilterType.movies,
            isFocused: _section == 1 && _filterIndex == 2,
            onTap: () => provider.setFilterType(MovieFilterType.movies),
          ),
          const SizedBox(width: 8),
          _FilterButton(
            icon: Icons.tv_rounded,
            label: 'Séries',
            isSelected: provider.filterType == MovieFilterType.series,
            isFocused: _section == 1 && _filterIndex == 3,
            onTap: () => provider.setFilterType(MovieFilterType.series),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.white10),
          const SizedBox(width: 8),
          
          // Botão FILTROS AVANÇADOS
          _FilterButton(
            icon: Icons.tune_rounded,
            label: 'Avançado',
            isSelected: false,
            isFocused: _section == 1 && _filterIndex == 4,
            isOrange: true,
            onTap: () => _openAdvancedFilters(provider),
          ),
          const SizedBox(width: 8),
          
          // Botão BUSCAR
          _FilterButton(
            icon: Icons.search_rounded,
            label: 'Buscar',
            isSelected: false,
            isFocused: _section == 1 && _filterIndex == 5,
            isGreen: true,
            onTap: _openSearch,
          ),
        ],
      ),
    );
  }
  
  /// Barra de busca quando está no modo de busca
  Widget _buildSearchBar(LazyMoviesProvider provider) {
    final queryLength = _searchController.text.length;
    final hasMinChars = queryLength >= _minSearchChars;
    final resultCount = provider.displayItems.length;
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Botão fechar
          GestureDetector(
            onTap: _closeSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Fechar', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Campo de busca
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _searchFocusNode.hasFocus 
                      ? const Color(0xFF10B981) 
                      : Colors.white24,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.search_rounded,
                    color: _searchFocusNode.hasFocus 
                        ? const Color(0xFF10B981) 
                        : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar filmes e séries... (mín. $_minSearchChars letras)',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _submitSearch(),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  // Loading indicator durante a busca
                  if (provider.isSearchingGlobal)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  // Indicador de progresso (caracteres)
                  if (!provider.isSearchingGlobal && queryLength > 0 && !hasMinChars)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$queryLength/$_minSearchChars',
                        style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  // Contador de resultados
                  if (!provider.isSearchingGlobal && hasMinChars && provider.searchQuery.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$resultCount encontrados',
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  // Botão limpar
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        provider.clearSearch();
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.clear_rounded, color: Colors.white54, size: 14),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Botão buscar
          GestureDetector(
            onTap: _submitSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: hasMinChars ? const Color(0xFF10B981) : Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: hasMinChars ? Colors.white : Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Buscar',
                    style: TextStyle(
                      color: hasMinChars ? Colors.white : Colors.white38,
                      fontSize: 12,
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

  Widget _buildContent(LazyMoviesProvider provider) {
    if (provider.isLoadingCategory) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      );
    }
    
    // Se está no modo de busca, mostra resultados
    if (_isSearchMode) {
      return _buildSearchResults(provider);
    }
    
    // Se categoria é "Todos", mostra cards de categorias
    if (provider.selectedCategoryName == 'Todos') {
      return _buildCategoryCards(provider);
    }
    
    // Senão, mostra grid de filmes/séries
    return _buildContentGrid(provider);
  }
  
  /// Resultados da busca
  Widget _buildSearchResults(LazyMoviesProvider provider) {
    // Mostra loading durante a busca
    if (provider.isSearchingGlobal) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF10B981)),
            const SizedBox(height: 16),
            Text(
              'Buscando "${provider.searchQuery}"...',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Procurando em todas as categorias',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    final items = provider.displayItems;
    
    // Se não tem query, mostra dica
    if (provider.searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Digite para buscar',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Mínimo de $_minSearchChars letras',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    // Se não tem resultados
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              'Nenhum resultado para "${provider.searchQuery}"',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tente outros termos de busca',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    // Grid de resultados
    return Column(
      children: [
        // Header de resultados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF10B981), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Resultados para "${provider.searchQuery}"',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${items.length} ${items.length == 1 ? 'resultado' : 'resultados'}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        // Grid
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final row = index ~/ _columns;
              final col = index % _columns;
              final isFocused = _section == 2 && _contentRow == row && _contentCol == col;
              
              return _ContentCard(
                item: items[index],
                isFocused: isFocused,
                onTap: () => _showDetail(items[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCards(LazyMoviesProvider provider) {
    final categories = provider.availableCategories.where((c) => c != 'Todos').toList();
    
    if (categories.isEmpty) {
      return const Center(
        child: Text('Nenhuma categoria', style: TextStyle(color: Colors.white38)),
      );
    }
    
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final row = index ~/ _columns;
        final col = index % _columns;
        final isFocused = _section == 2 && _contentRow == row && _contentCol == col;
        
        return _CategoryCard(
          name: category,
          isFocused: isFocused,
          onTap: () {
            provider.selectCategory(category);
            setState(() {
              _contentRow = 0;
              _contentCol = 0;
            });
            _scrollController.jumpTo(0);
          },
        );
      },
    );
  }

  Widget _buildContentGrid(LazyMoviesProvider provider) {
    final items = provider.displayItems;
    
    if (items.isEmpty) {
      return const Center(
        child: Text('Nenhum conteúdo', style: TextStyle(color: Colors.white38)),
      );
    }
    
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: _cardWidth / _cardHeight,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final row = index ~/ _columns;
        final col = index % _columns;
        final isFocused = _section == 2 && _contentRow == row && _contentCol == col;
        
        return _ContentCard(
          item: item,
          isFocused: isFocused,
          onTap: () => _showDetail(item),
        );
      },
    );
  }

  Widget _buildCategoryModal(LazyMoviesProvider provider) {
    final categories = provider.availableCategories;
    
    return Row(
      children: [
        // Painel
        Container(
          width: 280,
          color: const Color(0xFF111111),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category_rounded, color: Color(0xFFE50914), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Categorias',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text('${categories.length}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
              
              // Lista
              Expanded(
                child: ListView.builder(
                  controller: _modalScroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = provider.selectedCategoryName == cat;
                    final isFocused = _modalIndex == index;
                    
                    return GestureDetector(
                      onTap: () {
                        provider.selectCategory(cat);
                        setState(() {
                          _showCategoryModal = false;
                          _contentRow = 0;
                          _contentCol = 0;
                        });
                        _scrollController.jumpTo(0);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isFocused ? const Color(0xFFE50914) : (isSelected ? Colors.white10 : Colors.transparent),
                          borderRadius: BorderRadius.circular(6),
                          border: isFocused ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getCategoryIcon(cat),
                              color: isFocused ? Colors.white : (isSelected ? const Color(0xFFE50914) : Colors.white54),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                cat,
                                style: TextStyle(
                                  color: isFocused || isSelected ? Colors.white : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_rounded, color: Color(0xFFE50914), size: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // Footer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A0A),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('↑↓ Navegar  •  OK Selecionar  •  → Fechar', 
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Overlay
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _showCategoryModal = false),
            child: Container(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  IconData _getCategoryIcon(String cat) {
    final l = cat.toLowerCase();
    if (l == 'todos') return Icons.apps_rounded;
    if (l.contains('lançamento')) return Icons.new_releases_rounded;
    if (l.contains('netflix')) return Icons.play_circle_rounded;
    if (l.contains('prime')) return Icons.shopping_bag_rounded;
    if (l.contains('disney')) return Icons.castle_rounded;
    if (l.contains('max') || l.contains('hbo')) return Icons.movie_rounded;
    if (l.contains('novela')) return Icons.favorite_rounded;
    if (l.contains('anime')) return Icons.animation_rounded;
    if (l.contains('coleção') || l.contains('colecao')) return Icons.collections_rounded;
    return Icons.folder_rounded;
  }
}

// === WIDGETS LEVES ===

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isFocused;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFFE50914) : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: isFocused ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isFocused;
  final bool isBlue;
  final bool isGreen;
  final bool isOrange;
  final VoidCallback onTap;

  const _FilterButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isFocused,
    this.isBlue = false,
    this.isGreen = false,
    this.isOrange = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Define as cores baseado no tipo
    List<Color>? gradientColors;
    if (isSelected) {
      if (isBlue) {
        gradientColors = [const Color(0xFF0077FF), const Color(0xFF00AAFF)];
      } else if (isGreen) {
        gradientColors = [const Color(0xFF10B981), const Color(0xFF34D399)];
      } else if (isOrange) {
        gradientColors = [const Color(0xFFFF8C00), const Color(0xFFFFAA33)];
      } else {
        gradientColors = [const Color(0xFFE50914), const Color(0xFFFF2020)];
      }
    } else if (isGreen && isFocused) {
      gradientColors = [const Color(0xFF10B981), const Color(0xFF34D399)];
    } else if (isOrange && isFocused) {
      gradientColors = [const Color(0xFFFF8C00), const Color(0xFFFFAA33)];
    }
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: gradientColors != null ? LinearGradient(colors: gradientColors) : null,
          color: gradientColors == null ? Colors.white10 : null,
          borderRadius: BorderRadius.circular(20),
          border: isFocused ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
          boxShadow: (isGreen && isFocused) || (isOrange && isFocused) ? [
            BoxShadow(color: isOrange ? const Color(0xFFFF8C00).withOpacity(0.5) : const Color(0xFF10B981).withOpacity(0.5), blurRadius: 8),
          ] : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: isSelected || (isGreen && isFocused) || (isOrange && isFocused) ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isBlue) ...[
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final bool isFocused;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _getCategoryColor(name),
              _getCategoryColor(name).withAlpha(150),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: isFocused ? Border.all(color: const Color(0xFFFFD700), width: 3) : null,
          boxShadow: isFocused
              ? [BoxShadow(color: const Color(0xFFFFD700).withAlpha(100), blurRadius: 12)]
              : null,
        ),
        child: Stack(
          children: [
            // Ícone de fundo
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                _getCategoryIcon(name),
                size: 80,
                color: Colors.white10,
              ),
            ),
            // Conteúdo
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(_getCategoryIcon(name), color: Colors.white, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String cat) {
    final l = cat.toLowerCase();
    if (l.contains('netflix')) return const Color(0xFFE50914);
    if (l.contains('prime')) return const Color(0xFF00A8E1);
    if (l.contains('disney')) return const Color(0xFF113CCF);
    if (l.contains('max') || l.contains('hbo')) return const Color(0xFF8B5CF6);
    if (l.contains('paramount')) return const Color(0xFF0066FF);
    if (l.contains('apple')) return const Color(0xFF555555);
    if (l.contains('globo')) return const Color(0xFFFF6B00);
    if (l.contains('novela')) return const Color(0xFFEC4899);
    if (l.contains('anime') || l.contains('crunchyroll')) return const Color(0xFFF97316);
    if (l.contains('lançamento')) return const Color(0xFF10B981);
    if (l.contains('coleção') || l.contains('colecao')) return const Color(0xFF8B5CF6);
    if (l.contains('ação') || l.contains('acao')) return const Color(0xFFDC2626);
    if (l.contains('comédia') || l.contains('comedia')) return const Color(0xFFFBBF24);
    if (l.contains('terror')) return const Color(0xFF1F2937);
    if (l.contains('drama')) return const Color(0xFF6366F1);
    if (l.contains('ficção') || l.contains('sci-fi')) return const Color(0xFF06B6D4);
    if (l.contains('romance')) return const Color(0xFFF472B6);
    if (l.contains('documentário') || l.contains('documentario')) return const Color(0xFF84CC16);
    if (l.contains('infantil')) return const Color(0xFFA855F7);
    return const Color(0xFF374151);
  }

  IconData _getCategoryIcon(String cat) {
    final l = cat.toLowerCase();
    if (l.contains('netflix')) return Icons.play_circle_rounded;
    if (l.contains('prime')) return Icons.shopping_bag_rounded;
    if (l.contains('disney')) return Icons.castle_rounded;
    if (l.contains('max') || l.contains('hbo')) return Icons.movie_rounded;
    if (l.contains('novela')) return Icons.favorite_rounded;
    if (l.contains('anime')) return Icons.animation_rounded;
    if (l.contains('lançamento')) return Icons.new_releases_rounded;
    if (l.contains('coleção') || l.contains('colecao')) return Icons.collections_rounded;
    if (l.contains('ação') || l.contains('acao')) return Icons.local_fire_department_rounded;
    if (l.contains('comédia') || l.contains('comedia')) return Icons.sentiment_very_satisfied_rounded;
    if (l.contains('terror')) return Icons.nights_stay_rounded;
    if (l.contains('drama')) return Icons.theater_comedy_rounded;
    if (l.contains('ficção') || l.contains('sci-fi')) return Icons.rocket_launch_rounded;
    if (l.contains('romance')) return Icons.favorite_border_rounded;
    if (l.contains('documentário') || l.contains('documentario')) return Icons.video_camera_back_rounded;
    if (l.contains('infantil')) return Icons.child_care_rounded;
    return Icons.folder_rounded;
  }
}

class _ContentCard extends StatefulWidget {
  final CatalogDisplayItem item;
  final bool isFocused;
  final VoidCallback onTap;

  const _ContentCard({
    required this.item,
    required this.isFocused,
    required this.onTap,
  });

  @override
  State<_ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<_ContentCard> {
  // Cache de dados TMDB
  String? _tmdbPoster;
  double? _tmdbRating;
  String? _tmdbCertification;
  bool _loadedTmdb = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Carrega TMDB de forma lazy
    _loadTMDBData();
  }

  @override
  void didUpdateWidget(covariant _ContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se o item mudou, recarrega TMDB
    if (oldWidget.item.displayName != widget.item.displayName) {
      _loadedTmdb = false;
      _tmdbPoster = null;
      _tmdbRating = null;
      _tmdbCertification = null;
      _loadTMDBData();
    }
  }

  Future<void> _loadTMDBData() async {
    if (_loadedTmdb || _isLoading) return;
    _isLoading = true;
    
    try {
      final type = widget.item.type == DisplayItemType.series ? 'tv' : 'movie';
      final name = widget.item.displayName;
      final category = widget.item.movie?.category ?? widget.item.series?.category;
      
      // Busca poster
      final poster = await TMDBImageService.searchImage(
        name, 
        type: type, 
        category: category,
      );
      
      if (mounted && poster != null && poster.isNotEmpty) {
        setState(() => _tmdbPoster = poster);
      }
      
      // Busca rating
      final rating = await TMDBImageService.searchRating(
        name, 
        type: type, 
        category: category,
      );
      
      if (mounted && rating != null && rating > 0) {
        setState(() => _tmdbRating = rating);
      }
      
      // Busca classificação indicativa
      final certification = await TMDBImageService.searchCertification(
        name, 
        type: type, 
        category: category,
      );
      
      if (mounted && certification != null && certification.isNotEmpty) {
        setState(() => _tmdbCertification = certification);
      }
      
      _loadedTmdb = true;
    } catch (_) {
      // Ignora erros - usa imagem original
    } finally {
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usa poster do TMDB se disponível, senão usa o logo original
    final imageUrl = _tmdbPoster ?? widget.item.logo;
    
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: widget.isFocused ? Border.all(color: const Color(0xFFFFD700), width: 3) : null,
          boxShadow: widget.isFocused
              ? [BoxShadow(color: const Color(0xFFE50914).withAlpha(150), blurRadius: 12)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster (TMDB ou original)
              imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
              
              // Gradiente
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withAlpha(220)],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),
              
              // Badge tipo (SÉRIE/FILME) - canto superior esquerdo
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.item.type == DisplayItemType.series
                        ? const Color(0xFF0077FF)
                        : const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.item.type == DisplayItemType.series ? 'SÉRIE' : 'FILME',
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              // Rating e Classificação - canto superior direito
              Positioned(
                top: 6,
                right: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Rating (nota do TMDB)
                    if (_tmdbRating != null && _tmdbRating! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getRatingColor(_tmdbRating!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.white, size: 10),
                            const SizedBox(width: 2),
                            Text(
                              _tmdbRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white, 
                                fontSize: 9, 
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Classificação indicativa
                    if (_tmdbCertification != null && _tmdbCertification!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getCertificationColor(_tmdbCertification!),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white24, width: 0.5),
                        ),
                        child: Text(
                          _tmdbCertification!,
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 8, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              // Nome
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Info adicional de série (temporadas/episódios)
                    if (widget.item.type == DisplayItemType.series && widget.item.series != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${widget.item.series!.seasonCount}T • ${widget.item.series!.episodeCount}E',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFE50914),
                ),
              )
            : Icon(
                widget.item.type == DisplayItemType.series ? Icons.tv : Icons.movie,
                color: Colors.white24,
                size: 32,
              ),
      ),
    );
  }

  /// Retorna cor baseada na nota
  Color _getRatingColor(double rating) {
    if (rating >= 7.5) return const Color(0xFF22C55E); // Verde
    if (rating >= 6.0) return const Color(0xFFF59E0B); // Amarelo
    if (rating >= 4.0) return const Color(0xFFF97316); // Laranja
    return const Color(0xFFEF4444); // Vermelho
  }

  /// Retorna cor baseada na classificação
  Color _getCertificationColor(String cert) {
    final c = cert.toUpperCase();
    if (c == 'L' || c == 'G' || c == 'TV-G' || c == 'TV-Y') {
      return const Color(0xFF22C55E); // Verde - Livre
    }
    if (c == '10' || c == 'PG' || c == 'TV-PG' || c == 'TV-Y7') {
      return const Color(0xFF3B82F6); // Azul - 10 anos
    }
    if (c == '12' || c == 'PG-13' || c == 'TV-14') {
      return const Color(0xFFF59E0B); // Amarelo - 12 anos
    }
    if (c == '14') {
      return const Color(0xFFF97316); // Laranja - 14 anos
    }
    if (c == '16' || c == 'R' || c == 'TV-MA') {
      return const Color(0xFFEF4444); // Vermelho - 16 anos
    }
    if (c == '18' || c == 'NC-17' || c == 'NR') {
      return const Color(0xFF000000); // Preto - 18 anos
    }
    return const Color(0xFF6B7280); // Cinza - Desconhecido
  }
}
