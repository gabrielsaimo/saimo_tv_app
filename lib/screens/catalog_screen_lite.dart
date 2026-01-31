import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../providers/lazy_movies_provider.dart';
import '../providers/movie_favorites_provider.dart';
import '../widgets/movie_detail_modal.dart';
import '../widgets/series_modal_optimized.dart';
import '../widgets/advanced_filters_modal.dart';
import '../services/trending_service.dart';
import '../services/json_lazy_service.dart';
import 'dart:ui' as ui;
import '../utils/tv_constants.dart';
import '../utils/key_debouncer.dart';

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
  // Seções: 0=header, 1=filtros, 2=tendências hoje, 3=tendências semana, 4=categorias
  int _section = 1;
  int _headerIndex = 0; // 0=voltar, 1=tv ao vivo, 2=config
  int _filterIndex = 0; // 0=categorias, 1=favoritos, 2=todos, 3=filmes, 4=séries, 5=avançado, 6=buscar
  int _contentRow = 0;
  int _contentCol = 0;
  
  // === TENDÊNCIAS ===
  List<TrendingItem> _trendingToday = [];
  List<TrendingItem> _trendingWeek = [];
  bool _loadingTrending = true;
  int _trendingTodayIndex = 0;
  int _trendingWeekIndex = 0;
  final ScrollController _trendingTodayScroll = ScrollController();
  final ScrollController _trendingWeekScroll = ScrollController();
  
  // === MODO FAVORITOS ===
  bool _showingFavorites = false;
  
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
  final KeyDebouncer _debouncer = KeyDebouncer();
  
  // === LAYOUT ===
  int _columns = 6;
  double _cardWidth = 140;
  double _cardHeight = 210;
  
  // === APPLE TV LAYOUT ===
  int _heroIndex = 0;
  final ScrollController _heroScrollController = ScrollController();
  final Map<String, ScrollController> _rowControllers = {};
  
  ScrollController _getRowController(String key) {
    if (!_rowControllers.containsKey(key)) {
      _rowControllers[key] = ScrollController();
    }
    return _rowControllers[key]!;
  }
  
  List<CatalogDisplayItem> _getCategoryItems(LazyMoviesProvider provider, String category) {
    // Para 'Todos', não listamos itens aqui (seria redundante).
    // Mas se precisarmos, podemos filtrar.
    if (category == 'Todos') return [];
    
    // Filtra itens da categoria
    return provider.displayItems
        .where((item) => 
            (item.movie?.category == category) || 
            (item.series?.category == category)
        )
        .take(10) // Limita a 10 items
        .toList();
  }

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
    // Inicia com a categoria já selecionada no provider (persistência)
    // Inicia com a categoria já selecionada no provider (persistência)
    if (provider.selectedCategoryName == 'Todos') {
       // FIX: Se for 'Todos' mas não tiver nada carregado (ou só tiver carregado lixo),
       // força o carregamento das categorias de novo.
       if (provider.displayItems.isEmpty) {
          await provider.selectCategory('Todos', forceReload: true);
       }
    }
    
    // Carrega tendências do TMDB em paralelo
    _loadTrending();
  }
  
  Future<void> _loadTrending() async {
    if (!mounted) return;
    
    setState(() => _loadingTrending = true);
    
    try {
      final service = JsonLazyService();
      final results = await TrendingService.getAllTrending(service);
      
      if (mounted) {
        setState(() {
          _trendingToday = results.today;
          _trendingWeek = results.week;
          _loadingTrending = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar tendências: $e');
      if (mounted) {
        setState(() => _loadingTrending = false);
      }
    }
  }

  void _calculateLayout() {
    if (!mounted) return;
    final width = MediaQuery.of(context).size.width;
    
    setState(() {
      // Usa TVConstants para determinar número de colunas por largura
      _columns = TVConstants.getColumnsForWidth(width);
      
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
    _trendingTodayScroll.dispose();
    _trendingWeekScroll.dispose();
    _heroScrollController.dispose();
    for (final c in _rowControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // === NAVEGAÇÃO D-PAD ===
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    
    // Se está no modo de busca com campo focado
    if (_isSearchMode && _searchFocusNode.hasFocus) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
        if (_debouncer.shouldProcessBack()) {
          _closeSearch();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchFocusNode.unfocus();
        setState(() => _section = 4);
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      
      // FIX: Permite sair do input com setas laterais
      if (key == LogicalKeyboardKey.arrowRight) {
        _searchFocusNode.unfocus();
        setState(() => _filterIndex = 2); // Search Button
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _searchFocusNode.unfocus();
        setState(() => _filterIndex = 0); // Close Button
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
      if (_debouncer.shouldProcessBack()) {
        if (_isSearchMode) {
          _closeSearch();
        } else {
          Navigator.of(context).pushReplacementNamed('/selector');
        }
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
        _showingFavorites = false; // Sai do modo favoritos ao selecionar categoria
        _contentRow = 0;
        _contentCol = 0;
      });
      _scrollController.jumpTo(0);
    } else if (key == LogicalKeyboardKey.goBack || 
               key == LogicalKeyboardKey.escape ||
               key == LogicalKeyboardKey.arrowRight) {
      if (_debouncer.shouldProcessBack()) {
        setState(() => _showCategoryModal = false);
      }
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
      if (_section == 4) {
        // Grid (Favoritos / Busca / Categoria Simples)
        if (_contentRow > 0) {
          _contentRow--;
          _scrollToVerticalRow();
        } else {
          // Sobe para Filtros
          _section = 1;
          _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      } else if (_section == 3) {
        // Nas linhas de categoria
        if (_contentRow > 0) {
          _contentRow--;
          _scrollToVerticalRow();
        } else {
          // Sobe para o Hero Banner
          if (_trendingToday.isNotEmpty) {
            _section = 2;
            _scrollToMainSection(2);
          } else {
            _section = 1;
            _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        }
      } else if (_section == 2) {
        // No Hero Banner, sobe para Filtros
        _section = 1;
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else if (_section == 1) {
        _section = 0;
      }
    });
  }

  void _onDown() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final totalRows = _getTotalRows(provider);
    
    setState(() {
      if (_section == 0) {
        _section = 1;
      } else if (_section == 1) {
        // De filtros para:
        // - Grid (se for categoria simples / busca / favoritos)
        final isGrid = _isSearchMode || _showingFavorites || !['Todos', '📊 Tendências'].contains(provider.selectedCategoryName);
        
        if (isGrid) {
           _section = 4;
           _contentRow = 0;
           _contentCol = 0;
           return;
        }

        // - Hero ou Rows (se for Todos/Tendências)
        if (_trendingToday.isNotEmpty) {
          _section = 2;
          _heroIndex = 0;
          _scrollToMainSection(2);
        } else if (totalRows > 0) {
          _section = 3;
          _contentRow = 0;
          _contentCol = 0;
          _scrollToMainSection(3);
        }
      } else if (_section == 2) {
        // De Hero para Rows
        if (totalRows > 0) {
          _section = 3;
          _contentRow = 0;
          _contentCol = 0;
          _scrollToMainSection(3);
        }
      } else if (_section == 3) {
        // Navega entre linhas
        if (_contentRow < totalRows - 1) {
          _contentRow++;
          _contentCol = 0; // Reset col ao mudar de linha
          _scrollToVerticalRow();
        }
      } else if (_section == 4) {
        // Grid Navigation
        final items = provider.displayItems;
        final totalGridRows = (items.length / _columns).ceil();
        if (_contentRow < totalGridRows - 1) {
          _contentRow++;
          _scrollToVerticalRow();
        }
      }
    });
  }
  
  void _onLeft() {
    setState(() {
      if (_section == 0) {
        if (_headerIndex > 0) _headerIndex--;
      } else if (_section == 1) {
        if (_isSearchMode) {
          // 0: Close, 1: TextField, 2: Search Button
          if (_filterIndex > 0) _filterIndex--;
          
          // Manage Focus
          if (_filterIndex == 1) {
            _searchFocusNode.requestFocus();
          } else {
            _searchFocusNode.unfocus();
          }
        } else {
          if (_filterIndex > 0) {
             _filterIndex--;
          } else {
             _openCategoryModal(Provider.of<LazyMoviesProvider>(context, listen: false));
          }
        }
      } else if (_section == 2) {
        // Hero Banner
        if (_heroIndex > 0) {
          _heroIndex--;
          _scrollTrendingToday(); // Usa método corrigido com width 85%
        } else {
          _openCategoryModal(Provider.of<LazyMoviesProvider>(context, listen: false));
        }
      } else if (_section == 3) {
        // Category Rows
        if (_contentCol > 0) {
          _contentCol--;
          _scrollCurrentRowHorizontal();
        } else {
          _openCategoryModal(Provider.of<LazyMoviesProvider>(context, listen: false));
        }
      } else if (_section == 4) {
        // Grid
        if (_contentCol > 0) {
          _contentCol--;
        } else {
          _openCategoryModal(Provider.of<LazyMoviesProvider>(context, listen: false));
        }
      }
    });
  }

  void _onRight() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    setState(() {
      if (_section == 0) {
        if (_headerIndex < 2) _headerIndex++;
      } else if (_section == 1) {
        if (_isSearchMode) {
           // 0: Close, 1: TextField, 2: Search Button
           if (_filterIndex < 2) _filterIndex++;
           
           // Manage Focus
           if (_filterIndex == 1) {
             _searchFocusNode.requestFocus();
           } else {
             _searchFocusNode.unfocus();
           }
        } else {
          if (_filterIndex < 6) _filterIndex++;
        }
      } else if (_section == 2) {
        // Hero Banner
        // Need to filter trending today for boundary check
        final filteredToday = _trendingToday.where((t) {
            if (provider.filterType == MovieFilterType.movies) return !t.isSeries;
            if (provider.filterType == MovieFilterType.series) return t.isSeries;
            return true;
        }).toList();
        
        if (_heroIndex < filteredToday.length - 1) {
          _heroIndex++;
          _scrollTrendingToday(); 
        }
      } else if (_section == 3) {
        // Category Rows
        final items = _getCurrentRowItems(provider);
        if (_contentCol < items.length - 1) {
          _contentCol++;
          _scrollCurrentRowHorizontal();
        }
      } else if (_section == 4) {
        // Grid
        final items = provider.displayItems;
        // Check if next item exists
        final nextIndex = (_contentRow * _columns) + _contentCol + 1;
        if (_contentCol < _columns - 1 && nextIndex < items.length) {
          _contentCol++;
        }
      }
    });
  }
  
  void _scrollToMainSection(int section) {
    double offset = 0;
    if (section == 2) {
       offset = 0;
    } else if (section == 3) {
       // Hero height + spacing
       final screenH = MediaQuery.of(context).size.height;
       offset = (screenH * 0.45) + 20;
    }
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic
    );
  }
  
  void _scrollToVerticalRow() {
    if (!_scrollController.hasClients) return;

    final screenH = MediaQuery.of(context).size.height;
    final screenCenter = screenH / 2;
    const headerH = 56.0;
    const filterH = 48.0;
    
    double contentAreaTop = headerH + filterH;
    double rowOffset = 0;

    if (_section == 3) {
      // Home (Rows)
      final heroH = screenH * 0.45;
      const rowHeight = 315.0; 
      const centerInsideRow = 185.0; // 55 (title area) + 130 (half card)
      
      rowOffset = (heroH + 20.0) + (_contentRow * rowHeight) + centerInsideRow;
    } else if (_section == 4) {
      // Grid (Categories / Search / Favorites)
      final rowHeight = _cardHeight + 12.0;
      final centerInsideRow = _cardHeight / 2;
      
      // Se estiver em modo busca, tem um header extra de ~40px
      if (_isSearchMode) {
        contentAreaTop += 40.0;
      }
      
      rowOffset = 10.0 + (_contentRow * rowHeight) + centerInsideRow;
    }

    // A mágica: alvo do scroll = posição do item - (ponto de centro da tela - início da área de conteúdo)
    // Isso garante que o item fique no centro da tela física, não apenas da viewport.
    final targetOffset = rowOffset - (screenCenter - contentAreaTop);

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }
  
  void _scrollCurrentRowHorizontal() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final controller = _getCurrentRowController(provider);
    if (controller != null) {
      // largura do card 130 + margin horizontal 15+15 = 30
      _scrollToHorizontalIndex(controller, _contentCol, 130.0, 30.0); 
    }
  }


  
  void _scrollTrendingToday() {
    if (!_heroScrollController.hasClients) return;
    
    // Calcula a largura do item do Hero Banner (85% da tela)
    final width = MediaQuery.of(context).size.width;
    final itemWidth = (width * 0.85); // Item width (85%)
    
    // The items are laid out with paddingLeft = (width - itemWidth) / 2.
    // Item 0 is at padded start.
    // Item N starts at paddingLeft + N * (itemWidth + 20).
    // The +20 comes from symmetric margin(10) on each item.
    
    final scrollOffset = _heroIndex * (itemWidth + 20);
    
    _heroScrollController.animateTo(
      scrollOffset.clamp(0.0, _heroScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
  
  void _scrollTrendingWeek() {
    if (!_trendingWeekScroll.hasClients) return;
    final offset = _trendingWeekIndex * (_cardWidth + 12);
    _trendingWeekScroll.animateTo(
      offset.clamp(0.0, _trendingWeekScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
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
      if (_isSearchMode) {
        // Navegação especial para Search Bar
        // 0: Close, 1: TextField, 2: Search Button
        if (_filterIndex == 0) {
          _closeSearch();
        } else if (_filterIndex == 2) {
          _submitSearch();
        }
      } else {
        if (_filterIndex == 0) {
          _openCategoryModal(provider);
        } else if (_filterIndex == 1) {
          // Botão Favoritos
          setState(() {
            _showingFavorites = !_showingFavorites;
            _contentRow = 0;
            _contentCol = 0;
          });
          _scrollController.jumpTo(0);
        } else if (_filterIndex == 5) {
          // Botão Filtros Avançados
          _openAdvancedFilters(provider);
        } else if (_filterIndex == 6) {
          // Botão Buscar
          _openSearch();
        } else {
          // Filtros de tipo (2=todos, 3=filmes, 4=séries)
          final filters = [MovieFilterType.all, MovieFilterType.movies, MovieFilterType.series];
          final newFilter = filters[_filterIndex - 2];
          if (provider.filterType != newFilter) {
            provider.setFilterType(newFilter);
            _contentRow = 0;
            _contentCol = 0;
            _scrollController.jumpTo(0);
          }
        }
      }
    } else if (_section == 2) {
      // Tendências de hoje (Hero Banner)
      final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
      final filteredToday = _trendingToday.where((t) {
        if (provider.filterType == MovieFilterType.movies) return !t.isSeries;
        if (provider.filterType == MovieFilterType.series) return t.isSeries;
        return true;
      }).toList();
      
      if (_heroIndex < filteredToday.length) {
        _showDetail(CatalogDisplayItem(
          type: filteredToday[_heroIndex].isSeries ? DisplayItemType.series : DisplayItemType.movie,
          movie: filteredToday[_heroIndex].localMovie,
        ));
      }
      } else if (_section == 3) {
        // Category Rows selection
        final items = _getCurrentRowItems(provider);
        if (_contentCol < items.length) {
          _showDetail(items[_contentCol]);
        }
      } else if (_section == 4) {
        // Grid selection
        if (_showingFavorites) {
          final favProvider = context.read<MovieFavoritesProvider>();
          final favorites = favProvider.favorites;
          final idx = _contentRow * _columns + _contentCol;
          if (idx < favorites.length) {
            final movie = favorites[idx];
            if (movie.type == MovieType.series && movie.episodes != null && movie.episodes!.isNotEmpty) {
              final groupedSeries = _createGroupedSeriesFromMovie(movie);
              showDialog(
                context: context,
                barrierColor: Colors.black87,
                builder: (_) => SeriesModalOptimized(series: groupedSeries),
              );
            } else {
              showDialog(
                context: context,
                barrierColor: Colors.black87,
                builder: (_) => MovieDetailModal(movie: movie),
              );
            }
          }
        } else {
          // Normal category grid
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
    
    // Apenas atualiza o estado visual, NÃO busca automaticamente
    // A busca é disparada apenas pelo botão buscar ou enter (_submitSearch)
    setState(() {});
  }
  
  Future<void> _performSearch(String query) async {
    if (query.length < _minSearchChars) return;
    
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    // Usa performGlobalSearch para buscar em TODAS as categorias
    await provider.performGlobalSearch(query);
    
    if (mounted) {
      _resetNavigation();
    }
  }

  void _resetNavigation() {
    if (mounted) {
      setState(() {
        _contentRow = 0;
        _contentCol = 0;
        _heroIndex = 0;
        _headerIndex = 0;
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

  // === HELPER METHODS ===
  Color _getRatingColor(double rating) {
    if (rating >= 8.0) return const Color(0xFF4CAF50); // Green
    if (rating >= 6.0) return const Color(0xFFFFC107); // Amber
    return const Color(0xFFF44336); // Red
  }

  Color _getCertificationColor(String cert) {
    final c = cert.toUpperCase();
    if (c == 'L' || c == '0' || c == '10') return const Color(0xFF4CAF50);
    if (c == '12' || c == '14') return const Color(0xFFFFC107);
    if (c == '16' || c == '18') return const Color(0xFFF44336);
    return Colors.grey;
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



  // Consolidado em _scrollToVerticalRow


  void _showDetail(CatalogDisplayItem item) {
    // Se é série com GroupedSeries já disponível
    if (item.type == DisplayItemType.series && item.series != null) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => SeriesModalOptimized(series: item.series!),
      );
    } 
    // Se é série mas sem GroupedSeries (ex: favoritos com episodes no movie)
    else if (item.type == DisplayItemType.series && item.movie != null && 
             item.movie!.episodes != null && item.movie!.episodes!.isNotEmpty) {
      final groupedSeries = _createGroupedSeriesFromMovie(item.movie!);
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => SeriesModalOptimized(series: groupedSeries),
      );
    }
    // Filme normal
    else if (item.movie != null) {
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => MovieDetailModal(movie: item.movie!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showCategoryModal) {
          setState(() => _showCategoryModal = false);
          return;
        }
        if (_isSearchMode) {
          _closeSearch();
          return;
        }
        // Navega de volta para o seletor
        Navigator.of(context).pushReplacementNamed('/selector');
      },
      child: Scaffold(
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

              // Responsive layout calculation
              final width = MediaQuery.of(context).size.width;
              if (width < 900) {
                _columns = 4;
              } else if (width < 1400) {
                _columns = 6;
              } else if (width < 2000) {
                _columns = 7;
              } else {
                _columns = 9;
              }
              
              // Base spacing and margins
              final horizontalPadding = width * 0.04;
              const gridSpacing = 12.0;
              
              // Calculate optimal card width
              _cardWidth = (width - (horizontalPadding * 2) - ((_columns - 1) * gridSpacing)) / _columns;
              _cardHeight = _cardWidth * 1.5;
              
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
      ),
    );
  }

  Widget _buildHeader(LazyMoviesProvider provider) {
    return SafeArea(
      bottom: false,
      child: Container(
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
    ),
  );
}

  Widget _buildFilters(LazyMoviesProvider provider) {
    // Se está no modo busca, mostra o campo de busca
    if (_isSearchMode) {
      return _buildSearchBar(provider);
    }
    
    final favProvider = context.watch<MovieFavoritesProvider>();
    final favCount = favProvider.count;
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Botão de categoria
          _FilterButton(
            icon: Icons.category_rounded,
            label: provider.selectedCategoryName,
            isSelected: !_showingFavorites,
            isFocused: _section == 1 && _filterIndex == 0,
            isBlue: true,
            onTap: () => _openCategoryModal(provider),
          ),
          const SizedBox(width: 8),
          
          // Botão Favoritos
          _FilterButton(
            icon: _showingFavorites ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            label: 'Favoritos${favCount > 0 ? " ($favCount)" : ""}',
            isSelected: _showingFavorites,
            isFocused: _section == 1 && _filterIndex == 1,
            isPink: true,
            onTap: () {
              _resetNavigation();
              setState(() {
                _showingFavorites = !_showingFavorites;
              });
            },
          ),
          const SizedBox(width: 8),
          
          Container(width: 1, height: 24, color: Colors.white10),
          const SizedBox(width: 8),
          
          // Filtros de tipo
          _FilterButton(
            icon: Icons.apps_rounded,
            label: 'Todos',
            isSelected: provider.filterType == MovieFilterType.all && !_showingFavorites,
            isFocused: _section == 1 && _filterIndex == 2,
            onTap: () {
              _resetNavigation();
              setState(() => _showingFavorites = false);
              provider.setFilterType(MovieFilterType.all);
            },
          ),
          const SizedBox(width: 8),
          _FilterButton(
            icon: Icons.movie_rounded,
            label: 'Filmes',
            isSelected: provider.filterType == MovieFilterType.movies && !_showingFavorites,
            isFocused: _section == 1 && _filterIndex == 3,
            onTap: () {
              _resetNavigation();
              setState(() => _showingFavorites = false);
              provider.setFilterType(MovieFilterType.movies);
            },
          ),
          const SizedBox(width: 8),
          _FilterButton(
            icon: Icons.tv_rounded,
            label: 'Séries',
            isSelected: provider.filterType == MovieFilterType.series && !_showingFavorites,
            isFocused: _section == 1 && _filterIndex == 4,
            onTap: () {
              _resetNavigation();
              setState(() => _showingFavorites = false);
              provider.setFilterType(MovieFilterType.series);
            },
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.white10),
          const SizedBox(width: 8),
          
          // Botão FILTROS AVANÇADOS
          _FilterButton(
            icon: Icons.tune_rounded,
            label: 'Avançado',
            isSelected: false,
            isFocused: _section == 1 && _filterIndex == 5,
            isOrange: true,
            onTap: () => _openAdvancedFilters(provider),
          ),
          const SizedBox(width: 8),
          
          // Botão BUSCAR
          _FilterButton(
            icon: Icons.search_rounded,
            label: 'Buscar',
            isSelected: false,
            isFocused: _section == 1 && _filterIndex == 6,
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
                border: (_section == 1 && _filterIndex == 0) 
                    ? Border.all(color: Colors.white, width: 2) 
                    : null,
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
                border: (_section == 1 && _filterIndex == 2) 
                    ? Border.all(color: const Color(0xFFFFD700), width: 2) 
                    : null,
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
    
    // Se está mostrando favoritos
    if (_showingFavorites) {
      return _buildFavoritesGrid();
    }
    
    // Se categoria é "Todos" ou "Tendências", mostra layout novo (Hero + Rows)
    if (provider.selectedCategoryName == 'Todos' || provider.selectedCategoryName == '📊 Tendências') {
      return _buildCategoryCards(provider);
    }
    
    // Senão, mostra grid de filmes/séries para categorias normais
    return _buildCategoryGrid(provider);
  }
  
  /// Grid de categorias normais (não-agrupadas)
  Widget _buildCategoryGrid(LazyMoviesProvider provider) {
    // Grid logic is handled in navigation/key handler mainly
    
    final items = provider.displayItems;
    
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_filter_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Nenhum item nesta categoria',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
         Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(_getCategoryIcon(provider.selectedCategoryName), color: const Color(0xFFE50914), size: 20),
              const SizedBox(width: 8),
              Text(
                provider.selectedCategoryName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text('${items.length} itens', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.04,
              vertical: 10,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final row = index ~/ _columns;
              final col = index % _columns;
              final isFocused = _section == 4 && _contentRow == row && _contentCol == col;
              
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
  
  /// Conteúdo especial para categoria Tendências com seções Hoje e Semana

  
  /// Grid de favoritos
  Widget _buildFavoritesGrid() {
    final favProvider = context.watch<MovieFavoritesProvider>();
    final favorites = favProvider.favorites;
    
    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Nenhum favorito ainda',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Adicione filmes e séries aos seus favoritos',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Color(0xFFE91E63), size: 20),
              const SizedBox(width: 8),
              Text(
                'Meus Favoritos (${favorites.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // Grid
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.04,
              vertical: 10,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final movie = favorites[index];
              final row = index ~/ _columns;
              final col = index % _columns;
              final isFocused = _section == 4 && _contentRow == row && _contentCol == col;
              
              // Converte Movie para CatalogDisplayItem
              final displayItem = CatalogDisplayItem(
                type: movie.type == MovieType.series ? DisplayItemType.series : DisplayItemType.movie,
                movie: movie,
              );
              
              return _ContentCard(
                item: displayItem,
                isFocused: isFocused,
                onTap: () => _showDetail(displayItem),
              );
            },
          ),
        ),
      ],
    );
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
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.04,
              vertical: 10,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final row = index ~/ _columns;
              final col = index % _columns;
              final isFocused = _section == 4 && _contentRow == row && _contentCol == col;
              
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
    
    // Lista de rows a serem renderizadas
    final widgetList = <Widget>[];
    
    // 1. Hero Banner (Always shown if available)
    widgetList.add(_buildHeroBanner(provider));
    widgetList.add(const SizedBox(height: 20));
    
    // 2. Rows
    // Lógica de índices:
    // A navegação usa _contentRow para saber em qual linha estamos na seção 3.
    // Precisamos garantir que a ordem de renderização bata com a ordem lógica.
    
    int rowIndex = 0;
    
    // Row Optional: Tendências da Semana (FILTRADA)
    final filteredTrendingWeek = _trendingWeek.where((t) {
      if (provider.filterType == MovieFilterType.movies) return !t.isSeries;
      if (provider.filterType == MovieFilterType.series) return t.isSeries;
      return true;
    }).toList();

    if (filteredTrendingWeek.isNotEmpty) {
      widgetList.add(
        _buildCategoryRow(
          '📅 Tendências da Semana',
          filteredTrendingWeek.take(10).map((t) => CatalogDisplayItem(
            type: t.isSeries ? DisplayItemType.series : DisplayItemType.movie,
            movie: t.localMovie,
          )).toList(),
          rowIndex
        )
      );
      rowIndex++;
    }
    
    // Rows: Categories
    for (final cat in categories) {
      final items = _getCategoryItems(provider, cat);
      if (items.isNotEmpty) {
        widgetList.add(_buildCategoryRow(cat, items, rowIndex));
        rowIndex++;
      }
    }
    
    widgetList.add(const SizedBox(height: 100)); // Padding final

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      cacheExtent: 1000, // Pre-cache rows to avoid jank
      children: widgetList,
    );
  }




  // Método auxiliar para contar total de linhas disponíveis (usado na navegação)
  int _getTotalRows(LazyMoviesProvider provider) {
    int count = 0;
    
    // Check Tendências Semana (using same filter as UI)
    final filteredTrendingWeek = _trendingWeek.where((t) {
      if (provider.filterType == MovieFilterType.movies) return !t.isSeries;
      if (provider.filterType == MovieFilterType.series) return t.isSeries;
      return true;
    }).toList();
    if (filteredTrendingWeek.isNotEmpty) count++;
    
    // Check Categories
    final categories = provider.availableCategories.where((c) => c != 'Todos');
    for (final cat in categories) {
       if (_getCategoryItems(provider, cat).isNotEmpty) count++;
    }
    return count;
  }
  
  // Método auxiliar para obter controller da linha atual (usado na navegação)
  ScrollController? _getCurrentRowController(LazyMoviesProvider provider) {
    int currentIndex = 0;
    
    // Checa Tendências Semana
    if (_trendingWeek.isNotEmpty) {
      if (_contentRow == currentIndex) return _getRowController('📅 Tendências da Semana');
      currentIndex++;
    }
    
    // Checa Categorias
    final categories = provider.availableCategories.where((c) => c != 'Todos');
    for (final cat in categories) {
       if (_getCategoryItems(provider, cat).isNotEmpty) {
         if (_contentRow == currentIndex) return _getRowController(cat);
         currentIndex++;
       }
    }
    return null;
  }
  
  // Método auxiliar para obter items da linha atual (usado na navegação)
  List<CatalogDisplayItem> _getCurrentRowItems(LazyMoviesProvider provider) {
    int currentIndex = 0;
    
    if (_trendingWeek.isNotEmpty) {
      if (_contentRow == currentIndex) {
        return _trendingWeek.take(10).map((t) => CatalogDisplayItem(
          type: t.isSeries ? DisplayItemType.series : DisplayItemType.movie,
          movie: t.localMovie,
        )).toList();
      }
      currentIndex++;
    }
    
    final categories = provider.availableCategories.where((c) => c != 'Todos');
    for (final cat in categories) {
       final items = _getCategoryItems(provider, cat);
       if (items.isNotEmpty) {
         if (_contentRow == currentIndex) return items;
         currentIndex++;
       }
    }
    return [];
  }

  /// Converte um Movie (com episodes) para GroupedSeries
  GroupedSeries _createGroupedSeriesFromMovie(Movie movie) {
    final Map<int, List<Movie>> seasonMap = {};
    
    if (movie.episodes != null && movie.episodes!.isNotEmpty) {
      for (final entry in movie.episodes!.entries) {
        final seasonNum = int.tryParse(entry.key) ?? 1;
        final epMovies = entry.value.map((ep) => Movie(
          id: ep.id,
          name: ep.name,
          url: ep.url,
          logo: movie.posterUrl,
          category: movie.category,
          type: MovieType.series,
          isAdult: movie.isAdult,
          seriesName: movie.seriesName ?? movie.tmdb?.title ?? movie.name,
          season: seasonNum,
          episode: ep.episode,
          tmdb: movie.tmdb,
        )).toList();
        epMovies.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
        seasonMap[seasonNum] = epMovies;
      }
    }
    
    return GroupedSeries(
      id: movie.id,
      name: movie.seriesName ?? movie.tmdb?.title ?? movie.name,
      logo: movie.posterUrl,
      category: movie.category,
      seasons: seasonMap,
      isAdult: movie.isAdult,
      tmdb: movie.tmdb,
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
                          _resetNavigation();
                          provider.selectCategory(cat);
                          setState(() {
                            _showCategoryModal = false;
                            _showingFavorites = false; 
                            _section = 1; 
                          });
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

  // === WIDGETS APPLE TV STYLE ===
  
  Widget _buildHeroBanner(LazyMoviesProvider provider) {
    if (_trendingToday.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.of(context).size.width;
    final itemWidth = width * 0.85; // Banner principal ocupa 85% da tela
    
    // Filtra itens uma única vez fora do builder para performance
    final filteredToday = _trendingToday.where((t) {
      if (provider.filterType == MovieFilterType.movies) return !t.isSeries;
      if (provider.filterType == MovieFilterType.series) return t.isSeries;
      return true;
    }).toList();

    if (filteredToday.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: ListView.builder(
            controller: _heroScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: filteredToday.length,
            // Importante: padding para centralizar visualmente o primeiro item (opcional)
            padding: EdgeInsets.symmetric(horizontal: (width - itemWidth) / 2),
            physics: const ClampingScrollPhysics(), 
            itemBuilder: (context, index) {
               final item = filteredToday[index];
               final isFocused = _section == 2 && _heroIndex == index;
               
               // Scale animation logic based on focus
               final scale = isFocused ? 1.0 : 0.95;
               
               return AnimatedContainer(
                 duration: const Duration(milliseconds: 300),
                 curve: Curves.easeOutCubic,
                 width: itemWidth,
                 margin: const EdgeInsets.symmetric(horizontal: 10),
                 transform: Matrix4.identity()..scale(scale),
                 child: Stack(
                   fit: StackFit.expand,
                   children: [
                     // Backdrop Image
                     Container(
                       decoration: BoxDecoration(
                         borderRadius: BorderRadius.circular(16),
                         boxShadow: isFocused ? [
                           BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))
                         ] : [],
                       ),
                       clipBehavior: Clip.antiAlias,
                       child: CachedNetworkImage(
                         imageUrl: item.localMovie.backdropUrl ?? item.localMovie.posterUrl,
                         fit: BoxFit.cover,
                         placeholder: (_, __) => Container(color: Colors.grey[900]),
                         errorWidget: (_, __, ___) => Container(color: Colors.grey[900], child: const Icon(Icons.error)),
                       ),
                     ),
                     
                     // Gradient Overlay
                     Container(
                       decoration: BoxDecoration(
                         borderRadius: BorderRadius.circular(16),
                         gradient: const LinearGradient(
                           begin: Alignment.topCenter,
                           end: Alignment.bottomCenter,
                           colors: [Colors.transparent, Colors.black87],
                           stops: [0.3, 1.0],
                         ),
                       ),
                     ),
                     
                     // Info
                     Positioned(
                       bottom: 20,
                       left: 20,
                       right: 20,
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                            // Card (Poster)
                            if (item.localMovie.posterUrl != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                width: 100,
                                height: 150,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    )
                                  ],
                                  border: Border.all(color: Colors.white24, width: 1.5),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CachedNetworkImage(
                                  imageUrl: item.localMovie.posterUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: Colors.white10),
                                  errorWidget: (_, __, ___) => Container(
                                    color: Colors.white10,
                                    child: const Icon(Icons.movie, color: Colors.white24, size: 40),
                                  ),
                                ),
                              ),
                              
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            
                            // Metadata (Rating & Certification)
                            Row(
                              children: [
                                if (item.localMovie.tmdb?.rating != null && item.localMovie.tmdb!.rating! > 0) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getRatingColor(item.localMovie.tmdb!.rating!),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.white, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          item.localMovie.tmdb!.rating!.toStringAsFixed(1),
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                
                                if (item.localMovie.tmdb?.certification != null && item.localMovie.tmdb!.certification!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getCertificationColor(item.localMovie.tmdb!.certification!),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.localMovie.tmdb!.certification!,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  
                                if (item.localMovie.tmdb?.overview != null) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      item.localMovie.overview!,
                                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                         ],
                       ),
                     ),
                     
                     // Border Focus
                     if (isFocused)
                       Container(
                         decoration: BoxDecoration(
                           borderRadius: BorderRadius.circular(16),
                           border: Border.all(color: Colors.white, width: 3),
                         ),
                       ),
                   ],
                 ),
               );
            },
          ),
        ),
        // Indicators removed as requested
      ],
    );
  }

  Widget _buildCategoryRow(String title, List<CatalogDisplayItem> items, int rowIndex) {
    if (items.isEmpty) return const SizedBox.shrink();
    
    final isRowFocused = _section == 3 && _contentRow == rowIndex;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(50, 20, 0, 10),
          child: Text(
            title,
            style: TextStyle(
              color: isRowFocused ? Colors.white : Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 260, // Aumentado de 240 para 260 para acomodar scale e metadata sem cortar
          child: ListView.builder(
            controller: _getRowController(title),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            clipBehavior: Clip.none, // IMPORTANTE: Permite card crescer sem cortar
            itemBuilder: (context, index) {
               final item = items[index];
               final isItemFocused = isRowFocused && _contentCol == index;
               
               // Scale effect
               final scale = isItemFocused ? 1.05 : 1.0;
               
               return AnimatedContainer(
                 duration: const Duration(milliseconds: 200),
                 curve: Curves.easeOut,
                 transform: Matrix4.identity()..scale(scale),
                 margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), // Espaço para crescer
                 width: 130, // Largura fixa do card
                 child: _ContentCard(
                   item: item,
                   isFocused: isItemFocused,
                   onTap: () => _showDetail(item),
                 ),
               );
            },
          ),
        ),
      ],
    );
  }
  
  void _scrollToHorizontalIndex(ScrollController controller, int index, double itemWidth, double spacing) {
    if (!controller.hasClients) return;
    
    final screenW = MediaQuery.of(context).size.width;
    final itemFullWidth = itemWidth + spacing;
    
    // Alvo: (posição do item + metade do item) - metade da tela
    // Isso coloca o CENTRO do item no CENTRO da tela.
    final targetOffset = (index * itemFullWidth) + (itemFullWidth / 2) - (screenW / 2);
    
    controller.animateTo(
      targetOffset.clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
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
  final bool isPink;
  final VoidCallback onTap;

  const _FilterButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isFocused,
    this.isBlue = false,
    this.isGreen = false,
    this.isOrange = false,
    this.isPink = false,
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
      } else if (isPink) {
        gradientColors = [const Color(0xFFE91E63), const Color(0xFFFF4081)];
      } else {
        gradientColors = [const Color(0xFFE50914), const Color(0xFFFF2020)];
      }
    } else if (isGreen && isFocused) {
      gradientColors = [const Color(0xFF10B981), const Color(0xFF34D399)];
    } else if (isOrange && isFocused) {
      gradientColors = [const Color(0xFFFF8C00), const Color(0xFFFFAA33)];
    } else if (isPink && isFocused) {
      gradientColors = [const Color(0xFFE91E63), const Color(0xFFFF4081)];
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
          boxShadow: (isGreen && isFocused) || (isOrange && isFocused) || (isPink && isFocused) ? [
            BoxShadow(color: isPink 
                ? const Color(0xFFE91E63).withOpacity(0.5)
                : isOrange 
                    ? const Color(0xFFFF8C00).withOpacity(0.5) 
                    : const Color(0xFF10B981).withOpacity(0.5), blurRadius: 8),
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
                fontWeight: isSelected || (isGreen && isFocused) || (isOrange && isFocused) || (isPink && isFocused) ? FontWeight.bold : FontWeight.normal,
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




/// OTIMIZADO: Convertido para StatelessWidget, usa dados TMDB pré-carregados
  // === WIDGETS APPLE TV STYLE ===
  






class _ContentCard extends StatelessWidget {
  final CatalogDisplayItem item;
  final bool isFocused;
  final VoidCallback onTap;

  const _ContentCard({
    required this.item,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Usa dados TMDB já pré-carregados do JSON (sem chamadas async)
    final imageUrl = item.movie?.posterUrl ?? item.series?.logoUrl ?? item.logo;
    final rating = item.movie?.tmdb?.rating ?? item.series?.tmdb?.rating;
    final certification = item.movie?.tmdb?.certification ?? item.series?.tmdb?.certification;
    
    return GestureDetector(
      onTap: onTap,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: isFocused 
                ? Border.all(color: const Color(0xFFFFD700), width: 3) 
                : null,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.6),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
          ),
          child: Transform.scale(
            scale: isFocused ? 1.06 : 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster (pré-carregado)
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
                  
                  // Indicador de foco
                  if (isFocused)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFD700),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.black, size: 16),
                      ),
                    ),
                  
                  // Badge tipo (SÉRIE/FILME)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.type == DisplayItemType.series
                            ? const Color(0xFF0077FF)
                            : const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.type == DisplayItemType.series ? 'SÉRIE' : 'FILME',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  
                  // Rating e Classificação
                  if (rating != null && rating > 0 || certification != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (rating != null && rating > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getRatingColor(rating),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.white, size: 10),
                                  const SizedBox(width: 2),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          if (certification != null && certification.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getCertificationColor(certification),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                certification,
                                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
                          item.movie?.name ?? item.series?.name ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.type == DisplayItemType.series && item.series != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${item.series!.seasonCount}T • ${item.series!.episodeCount}E',
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9),
                            ),
                          ),
                      ],
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

  Widget _placeholder() {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Icon(Icons.movie_rounded, color: Colors.white24),
      ),
    );
  }

  Color _getRatingColor(double rating) {
    if (rating >= 8.0) return const Color(0xFF4CAF50); // Green
    if (rating >= 6.0) return const Color(0xFFFFC107); // Amber
    return const Color(0xFFF44336); // Red
  }

  Color _getCertificationColor(String cert) {
    final c = cert.toUpperCase();
    if (c == 'L' || c == '0' || c == '10') return const Color(0xFF4CAF50);
    if (c == '12' || c == '14') return const Color(0xFFFFC107);
    if (c == '16' || c == '18') return const Color(0xFFF44336);
    return Colors.grey;
  }
}

