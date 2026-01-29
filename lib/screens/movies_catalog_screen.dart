import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../providers/movies_provider.dart';
import '../utils/theme.dart';
import '../widgets/series_modal.dart';
import '../widgets/options_modal.dart';
import '../services/casting_service.dart';
import '../providers/favorites_provider.dart';
import '../providers/movie_favorites_provider.dart';

/// Tela principal do catálogo de filmes e séries
/// Otimizada com lazy loading, cache de imagens e virtualização
class MoviesCatalogScreen extends StatefulWidget {
  const MoviesCatalogScreen({super.key});

  @override
  State<MoviesCatalogScreen> createState() => _MoviesCatalogScreenState();
}

class _MoviesCatalogScreenState extends State<MoviesCatalogScreen>
    with TickerProviderStateMixin {
  // === NAVEGAÇÃO ===
  int _currentSection = 0; // 0=header, 1=filtros, 2=categorias, 3=conteúdo
  int _headerIndex = 0; // 0=voltar, 1=busca, 2=config
  int _filterIndex = 0;
  int _categoryIndex = 0;
  
  // Para navegação no modo "Todos" (seções por categoria)
  int _sectionIndex = 0;
  int _itemIndex = 0;
  
  // Para navegação no modo categoria específica (grid)
  int _contentRowIndex = 0;
  int _contentColIndex = 0;

  // === CONTROLADORES ===
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _categoriesScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<int, ScrollController> _sectionScrollControllers = {};
  late AnimationController _pulseController;
  Timer? _clockTimer;
  String _currentTime = '';

  // === ESTADO ===
  bool _isSearching = false;
  bool _showGroupedSeries = true;
  
  // === BUSCA INTELIGENTE ===
  Timer? _searchDebounce;
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  static const int _minSearchChars = 3;
  
  // === PAGINAÇÃO EM CATEGORIAS ESPECÍFICAS ===
  final Map<String, int> _categoryItemsLoaded = {};
  static const int _itemsPerPage = 50;
  bool _isLoadingMore = false;

  // Constantes de tamanho (compactas para 4 rows x 7 cols)
  static const double _cardWidth = 100.0;
  static const double _cardHeight = 140.0;
  static const double _sectionHeight = 190.0;
  static const double _categoryChipHeight = 32.0;

  // Long press detection
  Timer? _longPressTimer;
  bool _isLongPress = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _updateTime();
    _startClockTimer();
    _loadMovies();
    
    // Listener para paginação em categorias específicas
    _contentScrollController.addListener(_onGridScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mainFocusNode.dispose();
    _categoriesScrollController.dispose();
    _contentScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    for (var controller in _sectionScrollControllers.values) {
      controller.dispose();
    }
    _clockTimer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    });
  }

  void _startClockTimer() {
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
  }
  
  void _onGridScroll() {
    if (!_contentScrollController.hasClients || _isLoadingMore) return;
    
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    // Só pagina em categorias específicas, não em "Todos"
    if (provider.selectedCategory == 'Todos') return;
    
    final position = _contentScrollController.position;
    // Se chegou em 80% do final, carrega mais
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      _loadMoreItems();
    }
  }
  
  void _loadMoreItems() {
    if (_isLoadingMore) return;
    
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    final category = provider.selectedCategory;
    final allItems = _getAllItemsForCategory(provider, category);
    final currentLoaded = _getLoadedItemsCount(category);
    
    // Se já carregou tudo, retorna
    if (currentLoaded >= allItems.length) return;
    
    setState(() {
      _isLoadingMore = true;
      _categoryItemsLoaded[category] = currentLoaded + _itemsPerPage;
    });
    
    // Simula delay mínimo para evitar múltiplas chamadas
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    });
  }
  
  int _getLoadedItemsCount(String category) {
    return _categoryItemsLoaded[category] ?? _itemsPerPage;
  }
  
  List<dynamic> _getAllItemsForCategory(MoviesProvider provider, String category) {
    if (_showGroupedSeries && provider.filterType != MovieFilterType.movies) {
      final series = provider.getSeriesForCategory(category);
      final movies = provider.getMoviesForCategory(category)
          .where((m) => m.type == MovieType.movie || m.seriesName == null)
          .toList();
      return [...series, ...movies];
    }
    return provider.getMoviesForCategory(category);
  }
  
  void _goToCategory(String category) {
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    provider.selectCategory(category);
    
    // Reseta contador de paginação
    _categoryItemsLoaded[category] = _itemsPerPage;
    
    // Encontra o índice da categoria
    final categories = provider.availableCategories;
    final categoryIdx = categories.indexOf(category);
    
    setState(() {
      _categoryIndex = categoryIdx;
      _currentSection = 3;
      _contentRowIndex = 0;
      _contentColIndex = 0;
    });
    
    if (categoryIdx >= 0) {
      _scrollToCategoryCenter(categoryIdx, categories.length);
    }
    
    HapticFeedback.mediumImpact();
  }

  Future<void> _loadMovies() async {
    final provider = context.read<MoviesProvider>();
    await provider.loadMovies();
  }

  ScrollController _getOrCreateSectionController(int sectionIdx) {
    if (!_sectionScrollControllers.containsKey(sectionIdx)) {
      _sectionScrollControllers[sectionIdx] = ScrollController();
    }
    return _sectionScrollControllers[sectionIdx]!;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    // Se o campo de busca está focado, deixa o TextField lidar com os eventos
    if (_isSearching && _searchFocusNode.hasFocus) {
      // Apenas intercepta ESC para fechar a busca
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.browserBack) {
        _toggleSearch();
        return;
      }
      // Seta para baixo sai do campo de busca para navegar nos resultados
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchFocusNode.unfocus();
        setState(() => _currentSection = 1);
        _mainFocusNode.requestFocus();
        HapticFeedback.selectionClick();
        return;
      }
      // Deixa o TextField processar outras teclas
      return;
    }

    // Handle Long Press for Select/Enter
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.numpadEnter) {
      
      if (event is KeyDownEvent) {
         if (_longPressTimer == null || !_longPressTimer!.isActive) {
           _isLongPress = false;
           _longPressTimer = Timer(const Duration(milliseconds: 600), () {
             _isLongPress = true;
             HapticFeedback.heavyImpact();
             _handleLongPress();
           });
         }
         return; // Wait for Up or Timer
      } else if (event is KeyUpEvent) {
         _longPressTimer?.cancel();
         if (!_isLongPress) {
           // Normal click
           _handleNormalSelect();
         }
         _isLongPress = false;
         return;
      }
    }

    // Voltar
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_isSearching) {
        _toggleSearch();
      } else {
        Navigator.pushReplacementNamed(context, '/selector');
      }
      return;
    }

    switch (_currentSection) {
      case 0:
        _handleHeaderNavigation(key);
        break;
      case 1:
        _handleFilterNavigation(key);
        break;
      case 2:
        _handleCategoryNavigation(key);
        break;
      case 3:
        final provider = context.read<MoviesProvider>();
        if (provider.selectedCategory == 'Todos' && provider.searchQuery.isEmpty) {
          _handleSectionNavigation(key);
        } else {
          _handleContentNavigation(key);
        }
        break;
    }
  }

  void _handleHeaderNavigation(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_headerIndex > 0) {
        setState(() => _headerIndex--);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_headerIndex < 2) {
        setState(() => _headerIndex++);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _currentSection = 1);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _executeHeaderAction();
    }
  }

  void _executeHeaderAction() {
    switch (_headerIndex) {
      case 0:
        Navigator.pushReplacementNamed(context, '/selector');
        break;
      case 1:
        _toggleSearch();
        break;
      case 2:
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
  
  /// Alterna o modo de busca
  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        // Foca no campo de busca
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      } else {
        // Limpa a busca ao fechar
        _clearSearch();
        _mainFocusNode.requestFocus();
      }
    });
  }
  
  /// Executa a busca com debounce inteligente
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    
    setState(() {
      _searchQuery = query;
    });
    
    // Se menos de 3 caracteres e não vazio, não busca ainda
    if (query.isNotEmpty && query.length < _minSearchChars) {
      return;
    }
    
    // Debounce de 300ms para performance
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }
  
  /// Executa a busca imediatamente (botão buscar)
  void _performSearch(String query) {
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    provider.setSearchQuery(query);
    
    // Reseta navegação ao buscar
    setState(() {
      _contentRowIndex = 0;
      _contentColIndex = 0;
      _sectionIndex = 0;
      _itemIndex = 0;
    });
  }
  
  /// Limpa a busca
  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    provider.clearSearch();
  }
  
  /// Força a busca imediatamente
  void _submitSearch() {
    _searchDebounce?.cancel();
    _performSearch(_searchQuery);
  }

  void _handleFilterNavigation(LogicalKeyboardKey key) {
    // Total de itens: filtros + botão busca
    final maxFilterIndex = MovieFilterType.values.length; // último índice é o botão buscar
    
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_filterIndex > 0) {
        setState(() => _filterIndex--);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_filterIndex < maxFilterIndex) {
        setState(() => _filterIndex++);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _currentSection = 0);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _currentSection = 2);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      // Se está no botão buscar
      if (_filterIndex == maxFilterIndex) {
        _toggleSearch();
        HapticFeedback.mediumImpact();
      } else {
        // Está num filtro normal
        final provider = context.read<MoviesProvider>();
        provider.setFilterType(MovieFilterType.values[_filterIndex]);
        setState(() {
          _categoryIndex = 0;
        });
        provider.selectCategory('Todos');
        HapticFeedback.mediumImpact();
      }
    }
  }

  void _handleCategoryNavigation(LogicalKeyboardKey key) {
    final provider = context.read<MoviesProvider>();
    final categories = provider.availableCategories;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_categoryIndex > 0) {
        setState(() => _categoryIndex--);
        provider.selectCategory(categories[_categoryIndex]);
        _scrollToCategoryCenter(_categoryIndex, categories.length);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_categoryIndex < categories.length - 1) {
        setState(() => _categoryIndex++);
        provider.selectCategory(categories[_categoryIndex]);
        _scrollToCategoryCenter(_categoryIndex, categories.length);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _currentSection = 1);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _currentSection = 3;
        _contentRowIndex = 0;
        _contentColIndex = 0;
        _sectionIndex = 0;
        _itemIndex = 0;
      });
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      setState(() {
        _currentSection = 3;
        _contentRowIndex = 0;
        _contentColIndex = 0;
        _sectionIndex = 0;
        _itemIndex = 0;
      });
    }
  }

  void _handleSectionNavigation(LogicalKeyboardKey key) {
    final provider = context.read<MoviesProvider>();
    final categories = provider.availableCategories.where((c) => c != 'Todos').toList();
    
    if (categories.isEmpty) return;
    
    final currentCategory = categories[_sectionIndex.clamp(0, categories.length - 1)];

    // Se a categoria ainda não carregou, não temos itens para navegar nela
    if (!provider.isCategoryLoaded(currentCategory)) {
      // Pode tentar carregar
      provider.loadCategory(currentCategory);
      // Mas a navegação deve ser interrompida ou limitada
      if (key == LogicalKeyboardKey.arrowUp && _sectionIndex > 0) {
         setState(() {
          _sectionIndex--;
          _itemIndex = 0;
        });
        _scrollToSection(_sectionIndex);
      } else if (key == LogicalKeyboardKey.arrowDown && _sectionIndex < categories.length - 1) {
         setState(() {
          _sectionIndex++;
          _itemIndex = 0;
        });
        _scrollToSection(_sectionIndex);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        // Sai para cima
         setState(() => _currentSection = 2);
      }
      return;
    }

    final items = _getItemsForCategory(provider, currentCategory);
    
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_itemIndex > 0) {
        setState(() => _itemIndex--);
        _scrollToItemInSection(_sectionIndex, _itemIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final maxItems = items.length.clamp(0, 30) - 1;
      if (_itemIndex < maxItems) {
        setState(() => _itemIndex++);
        _scrollToItemInSection(_sectionIndex, _itemIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_sectionIndex > 0) {
        setState(() {
          _sectionIndex--;
          _itemIndex = 0;
        });
        _scrollToSection(_sectionIndex);
        HapticFeedback.selectionClick();
      } else {
        setState(() => _currentSection = 2);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_sectionIndex < categories.length - 1) {
        setState(() {
          _sectionIndex++;
          _itemIndex = 0;
        });
        _scrollToSection(_sectionIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _selectSectionItem(items);
    }
  }

  void _handleContentNavigation(LogicalKeyboardKey key) {
    final provider = context.read<MoviesProvider>();
    
    // Se tem busca ativa, usa os itens da busca
    final List<dynamic> items;
    if (provider.searchQuery.isNotEmpty) {
      final movies = provider.filteredMovies;
      final series = provider.filteredGroupedSeries;
      items = [...series, ...movies];
    } else {
      items = _getDisplayItems(provider);
    }
    
    final itemsPerRow = _getItemsPerRow();
    final totalRows = (items.length / itemsPerRow).ceil();

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_contentColIndex > 0) {
        setState(() => _contentColIndex--);
        // Mantém o item centralizado verticalmente
        _scrollToRow(_contentRowIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final maxCol = _getMaxColInRow(_contentRowIndex, items.length, itemsPerRow);
      if (_contentColIndex < maxCol) {
        setState(() => _contentColIndex++);
        // Mantém o item centralizado verticalmente
        _scrollToRow(_contentRowIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_contentRowIndex > 0) {
        setState(() => _contentRowIndex--);
        _scrollToRow(_contentRowIndex);
        HapticFeedback.selectionClick();
      } else {
        setState(() => _currentSection = 2);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_contentRowIndex < totalRows - 1) {
        setState(() => _contentRowIndex++);
        final maxCol = _getMaxColInRow(_contentRowIndex, items.length, itemsPerRow);
        if (_contentColIndex > maxCol) {
          _contentColIndex = maxCol;
        }
        _scrollToRow(_contentRowIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _selectItem(items);
    }
  }

  List<dynamic> _getItemsForCategory(MoviesProvider provider, String category) {
    if (_showGroupedSeries && provider.filterType != MovieFilterType.movies) {
      final series = provider.getSeriesForCategory(category);
      final movies = provider.getMoviesForCategory(category)
          .where((m) => m.type == MovieType.movie || m.seriesName == null)
          .toList();
      return [...series, ...movies];
    }
    return provider.getMoviesForCategory(category);
  }

  List<dynamic> _getDisplayItems(MoviesProvider provider) {
    // Modo "Todos" - sem paginação (são apenas 10 itens por seção)
    if (provider.selectedCategory == 'Todos') {
      if (_showGroupedSeries && provider.filterType != MovieFilterType.movies) {
        final series = provider.filteredGroupedSeries;
        final movies = provider.filteredMovies
            .where((m) => m.type == MovieType.movie || m.seriesName == null)
            .toList();
        return [...series, ...movies];
      }
      return provider.filteredMovies;
    }
    
    // Categoria específica - COM PAGINAÇÃO
    final category = provider.selectedCategory;
    final allItems = _getAllItemsForCategory(provider, category);
    final loadedCount = _getLoadedItemsCount(category);
    
    // Retorna apenas os itens carregados até agora
    return allItems.take(loadedCount).toList();
  }

  int _getItemsPerRow() {
    final width = MediaQuery.of(context).size.width;
    return (width / (_cardWidth + 12)).floor().clamp(5, 12);
  }

  int _getMaxColInRow(int row, int totalItems, int itemsPerRow) {
    final startIndex = row * itemsPerRow;
    final itemsInRow = (totalItems - startIndex).clamp(0, itemsPerRow);
    return (itemsInRow - 1).clamp(0, itemsPerRow - 1);
  }

  void _scrollToCategoryCenter(int index, int totalCategories) {
    if (!_categoriesScrollController.hasClients) return;
    
    final screenWidth = MediaQuery.of(context).size.width;
    const chipWidth = 110.0;
    const chipSpacing = 8.0;
    
    final itemOffset = index * (chipWidth + chipSpacing);
    final centerOffset = itemOffset - (screenWidth / 2) + (chipWidth / 2) + 24;
    
    _categoriesScrollController.animateTo(
      centerOffset.clamp(0.0, _categoriesScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToSection(int sectionIndex) {
    if (!_contentScrollController.hasClients) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    // Altura fixa do item (igual ao itemExtent do ListView)
    const itemExtent = _sectionHeight + 8;
    // Calcula offset da seção
    final itemOffset = sectionIndex * itemExtent;
    // Área visível (desconta header ~100px)
    final visibleHeight = screenHeight - 100;
    // Centraliza: coloca o item no meio da área visível
    final centerOffset = itemOffset - (visibleHeight / 2) + (itemExtent / 2);
    
    _contentScrollController.animateTo(
      centerOffset.clamp(0.0, _contentScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToItemInSection(int sectionIdx, int itemIndex) {
    final controller = _getOrCreateSectionController(sectionIdx);
    if (!controller.hasClients) return;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final offset = itemIndex * (_cardWidth + 10) - (screenWidth / 2) + (_cardWidth / 2) + 20;
    
    controller.animateTo(
      offset.clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
    
    // Também centraliza a seção verticalmente
    _scrollToSection(sectionIdx);
  }

  void _scrollToRow(int row) {
    if (!_contentScrollController.hasClients) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    // Considera header ~120px (header, filtros, categorias)
    final headerOffset = 120.0;
    final availableHeight = screenHeight - headerOffset;
    const itemHeight = _cardHeight + 16;
    final itemOffset = row * itemHeight;
    // Centraliza o item na área visível
    final centerOffset = itemOffset - (availableHeight / 2) + (itemHeight / 2);
    
    _contentScrollController.animateTo(
      centerOffset.clamp(0.0, _contentScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectSectionItem(List<dynamic> items) {
    if (_itemIndex >= items.length) return;
    
    final item = items[_itemIndex];
    HapticFeedback.mediumImpact();

    if (item is GroupedSeries) {
      showDialog(
        context: context,
        builder: (context) => SeriesModal(
          series: item,
          onSelectEpisode: (episode) => _playMovie(episode),
        ),
      );
    } else if (item is Movie) {
      _playMovie(item);
    }
  }

  void _selectItem(List<dynamic> items) {
    final itemsPerRow = _getItemsPerRow();
    final index = (_contentRowIndex * itemsPerRow) + _contentColIndex;
    if (index >= items.length) return;

    final item = items[index];
    HapticFeedback.mediumImpact();

    if (item is GroupedSeries) {
      showDialog(
        context: context,
        builder: (context) => SeriesModal(
          series: item,
          onSelectEpisode: (episode) => _playMovie(episode),
        ),
      );
    } else if (item is Movie) {
      _playMovie(item);
    }
  }

  void _playMovie(Movie movie) {
    Navigator.pushNamed(
      context,
      '/movie-player',
      arguments: movie,
    );
  }

  @override
  void _handleNormalSelect() {
    switch (_currentSection) {
      case 0:
        _executeHeaderAction();
        break;
      case 1:
        if (_filterIndex == MovieFilterType.values.length) {
          _toggleSearch();
        } else {
          final provider = context.read<MoviesProvider>();
          provider.setFilterType(MovieFilterType.values[_filterIndex]);
          setState(() {
            _categoryIndex = 0;
          });
          provider.selectCategory('Todos');
        }
        break;
      case 2:
        setState(() {
          _currentSection = 3;
          _contentRowIndex = 0;
          _contentColIndex = 0;
          _sectionIndex = 0;
          _itemIndex = 0;
        });
        break;
      case 3:
        final provider = context.read<MoviesProvider>();
        if (provider.selectedCategory == 'Todos' && provider.searchQuery.isEmpty) {
           final categoriesWithCount = provider.categoriesWithCount;
           final categories = categoriesWithCount.keys.toList();
           if (categories.isNotEmpty) {
             final currentCategory = categories[_sectionIndex.clamp(0, categories.length - 1)];
             final items = _getItemsForCategory(provider, currentCategory);
             _selectSectionItem(items);
           }
        } else {
           // Se tem busca ativa, usa os itens da busca
           final List<dynamic> items;
           if (provider.searchQuery.isNotEmpty) {
             final movies = provider.filteredMovies;
             final series = provider.filteredGroupedSeries;
             items = [...series, ...movies];
           } else {
             items = _getDisplayItems(provider);
           }
           _selectItem(items);
        }
        break;
    }
  }

  void _handleLongPress() {
    if (_currentSection == 3) {
        final provider = context.read<MoviesProvider>();
        final List<dynamic> items;
        int index = 0;

        if (provider.selectedCategory == 'Todos' && provider.searchQuery.isEmpty) {
           final categories = provider.availableCategories.where((c) => c != 'Todos').toList();
           if (categories.isEmpty) return;
           final currentCategory = categories[_sectionIndex.clamp(0, categories.length - 1)];
           if (!provider.isCategoryLoaded(currentCategory)) return;
           items = _getItemsForCategory(provider, currentCategory);
           index = _itemIndex;
        } else {
           if (provider.searchQuery.isNotEmpty) {
             final movies = provider.filteredMovies;
             final series = provider.filteredGroupedSeries;
             items = [...series, ...movies];
           } else {
             items = _getDisplayItems(provider);
           }
           final itemsPerRow = _getItemsPerRow();
           index = (_contentRowIndex * itemsPerRow) + _contentColIndex;
        }

        if (index >= 0 && index < items.length) {
           final item = items[index];
           _showMovieOptions(item);
        }
    }
  }

  void _showMovieOptions(dynamic item) {
    if (item is GroupedSeries || item is Movie) {
      final isSeries = item is GroupedSeries;
      final movie = isSeries ? null : (item as Movie);
      final series = isSeries ? (item as GroupedSeries) : null;
      
      final title = isSeries ? series!.name : movie!.name;
      
      final favProvider = context.read<MovieFavoritesProvider>();
      final id = isSeries ? series!.name : movie!.id; 
      
      bool isFav = false;
      try {
         isFav = favProvider.isFavorite(id);
      } catch (e) {
         // Fallback
      }

      showDialog(
        context: context,
        builder: (context) => OptionsModal(
          title: title,
          isFavorite: isFav,
          onToggleFavorite: () {
            if (isSeries) {
               // Logic for series favorite
               // If provider supports it: favProvider.toggleSeriesFavorite(series)
               // For now, let's assume we toggle the first movie or generic ID
               final firstSeason = series!.sortedSeasons.first;
               final firstEpisode = series!.getSeasonEpisodes(firstSeason).first;
               favProvider.toggleFavorite(firstEpisode); 
            } else {
               favProvider.toggleFavorite(movie!);
            }
            setState(() {});
          },
          onPlay: () {
             Navigator.pop(context); // Close modal
             if (isSeries) {
                 showDialog(
                  context: context,
                  builder: (context) => SeriesModal(
                    series: series!,
                    onSelectEpisode: (episode) => _playMovie(episode),
                  ),
                );
             } else {
                _playMovie(movie!);
             }
          },
          onCastSelected: (device) {
             final castingService = CastingService();
             try {
                String castUrl = '';
                String castTitle = title;
                String castImage = '';
                
                if (isSeries) {
                   // Cast first available episode for testing or allow open modal
                   final firstSeason = series!.sortedSeasons.first;
                   final firstEpisode = series!.getSeasonEpisodes(firstSeason).first;
                   castUrl = firstEpisode.url;
                   castImage = firstEpisode.posterUrl;
                } else {
                   castUrl = movie!.url;
                   castImage = movie.posterUrl;
                }

                castingService.castMedia(
                  device: device,
                  url: castUrl,
                  title: castTitle,
                  imageUrl: castImage,
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
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaimoTheme.background,
      body: KeyboardListener(
        focusNode: _mainFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SaimoTheme.background,
                const Color(0xFF1a1a2e),
              ],
            ),
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildFilters(),
              _buildCategories(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _buildHeaderButton(
            index: 0,
            icon: Icons.arrow_back_rounded,
            label: 'Voltar',
          ),
          const SizedBox(width: 12),

          // Mostra título ou campo de busca
          if (_isSearching)
            Expanded(child: _buildSearchField())
          else ...[
            Row(
              children: [
                Icon(
                  Icons.movie_rounded,
                  color: const Color(0xFFEF4444),
                  size: 24,
                ),
                const SizedBox(width: 6),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  ).createShader(bounds),
                  child: const Text(
                    'Filmes & Séries',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),
          ],

          _buildHeaderButton(
            index: 1,
            icon: _isSearching ? Icons.close_rounded : Icons.search_rounded,
            label: _isSearching ? 'Fechar' : 'Buscar',
          ),
          const SizedBox(width: 10),

          _buildHeaderButton(
            index: 2,
            icon: Icons.settings_rounded,
            label: 'Config',
          ),
          const SizedBox(width: 12),

          Text(
            _currentTime,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Campo de busca integrado no header
  Widget _buildSearchField() {
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    final hasResults = provider.searchQuery.isNotEmpty;
    
    return Container(
      height: 40,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: SaimoTheme.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _searchFocusNode.hasFocus 
              ? SaimoTheme.primary 
              : Colors.white.withOpacity(0.2),
          width: 2,
        ),
        boxShadow: _searchFocusNode.hasFocus ? [
          BoxShadow(
            color: SaimoTheme.primary.withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ] : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.search_rounded,
            color: _searchFocusNode.hasFocus 
                ? SaimoTheme.primary 
                : SaimoTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Pesquisar filmes e séries... (mín. $_minSearchChars letras)',
                hintStyle: TextStyle(
                  color: SaimoTheme.textTertiary,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _submitSearch(),
              textInputAction: TextInputAction.search,
            ),
          ),
          // Indicador de status da busca
          if (_searchQuery.isNotEmpty && _searchQuery.length < _minSearchChars)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_searchQuery.length}/$_minSearchChars',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (hasResults)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: SaimoTheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Consumer<MoviesProvider>(
                builder: (context, provider, _) {
                  final count = provider.filteredMovies.length + 
                                provider.filteredGroupedSeries.length;
                  return Text(
                    '$count encontrados',
                    style: const TextStyle(
                      color: SaimoTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
          // Botão limpar
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _clearSearch();
                _searchFocusNode.requestFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.clear_rounded,
                  color: SaimoTheme.textSecondary,
                  size: 14,
                ),
              ),
            ),
          // Botão buscar
          GestureDetector(
            onTap: _submitSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _searchQuery.length >= _minSearchChars
                    ? SaimoTheme.primary
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: _searchQuery.length >= _minSearchChars
                        ? Colors.white
                        : Colors.white54,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Buscar',
                    style: TextStyle(
                      color: _searchQuery.length >= _minSearchChars
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 11,
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

  Widget _buildHeaderButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isFocused = _currentSection == 0 && _headerIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentSection = 0;
          _headerIndex = index;
        });
        _executeHeaderAction();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isFocused
              ? SaimoTheme.primary
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
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
              color: isFocused ? Colors.white : Colors.white70,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isFocused ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Consumer<MoviesProvider>(
      builder: (context, provider, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              Text(
                'Filtrar:',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 10),
              ...MovieFilterType.values.asMap().entries.map((entry) {
                final index = entry.key;
                final type = entry.value;
                final isSelected = provider.filterType == type;
                final isFocused = _currentSection == 1 && _filterIndex == index;

                return GestureDetector(
                  onTap: () {
                    provider.setFilterType(type);
                    setState(() {
                      _filterIndex = index;
                      _currentSection = 1;
                      _categoryIndex = 0;
                    });
                    provider.selectCategory('Todos');
                    HapticFeedback.mediumImpact();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SaimoTheme.primary
                            : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isFocused
                              ? Colors.white
                              : isSelected
                                  ? SaimoTheme.primary
                                  : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(type.icon, style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Text(
                            type.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 8),
              // Botão de Busca ao lado dos filtros
              _buildSearchButton(),
              const Spacer(),
              Consumer<MoviesProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) return const SizedBox.shrink();
                  final stats = provider.statistics;
                  return Text(
                    '${stats['total']} itens',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// Botão de busca destacado
  Widget _buildSearchButton() {
    final isFocused = _currentSection == 1 && _filterIndex == MovieFilterType.values.length;
    final isActive = _isSearching || Provider.of<MoviesProvider>(context, listen: false).searchQuery.isNotEmpty;
    
    return GestureDetector(
      onTap: _toggleSearch,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF10B981) // Verde quando ativo
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFocused
                ? Colors.white
                : isActive
                    ? const Color(0xFF10B981)
                    : Colors.transparent,
            width: 2,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: const Color(0xFF10B981).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
              color: isActive || isFocused ? Colors.white : Colors.white70,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              _isSearching ? 'Fechar' : 'Buscar',
              style: TextStyle(
                color: isActive || isFocused ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isActive || isFocused ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return Consumer<MoviesProvider>(
      builder: (context, provider, _) {
        final categories = provider.availableCategories;

        return Container(
          height: _categoryChipHeight + 8,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListView.builder(
            controller: _categoriesScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = provider.selectedCategory == category;
              final isFocused = _currentSection == 2 && _categoryIndex == index;

              return GestureDetector(
                onTap: () {
                  provider.selectCategory(category);
                  setState(() {
                    _categoryIndex = index;
                    _currentSection = 2;
                    _sectionIndex = 0;
                    _itemIndex = 0;
                  });
                  _scrollToCategoryCenter(index, categories.length);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  height: _categoryChipHeight,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Color(MovieCategory.getColor(category))
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isFocused
                          ? Colors.white
                          : isSelected
                              ? Color(MovieCategory.getColor(category))
                              : Colors.transparent,
                      width: isFocused ? 2 : 1,
                    ),
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: Color(MovieCategory.getColor(category)).withOpacity(0.5),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MovieCategory.getIcon(category),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        category,
                        style: TextStyle(
                          color: isSelected || isFocused ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight:
                              isSelected || isFocused ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    return Consumer<MoviesProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return _buildLoadingState();
        }

        if (provider.error != null) {
          return _buildErrorState(provider.error!);
        }
        
        // Se tem busca ativa, mostra resultados em grid
        if (provider.searchQuery.isNotEmpty) {
          return _buildSearchResults(provider);
        }

        if (provider.selectedCategory == 'Todos') {
          return _buildCategorySections(provider);
        }

        final items = _getDisplayItems(provider);

        if (items.isEmpty) {
          return _buildEmptyState();
        }

        return _buildGrid(items);
      },
    );
  }
  
  /// Constrói a visualização dos resultados da busca
  Widget _buildSearchResults(MoviesProvider provider) {
    // Combina filmes e séries agrupadas
    final movies = provider.filteredMovies;
    final series = provider.filteredGroupedSeries;
    final List<dynamic> items = [...series, ...movies];
    
    if (items.isEmpty) {
      return _buildSearchEmptyState(provider.searchQuery);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header dos resultados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: SaimoTheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: SaimoTheme.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Resultados para "${provider.searchQuery}"',
                      style: const TextStyle(
                        color: SaimoTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${items.length} ${items.length == 1 ? 'resultado' : 'resultados'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              // Dica de navegação
              Row(
                children: [
                  Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white.withOpacity(0.3),
                    size: 16,
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white.withOpacity(0.3),
                    size: 16,
                  ),
                  Icon(
                    Icons.keyboard_arrow_left,
                    color: Colors.white.withOpacity(0.3),
                    size: 16,
                  ),
                  Icon(
                    Icons.keyboard_arrow_right,
                    color: Colors.white.withOpacity(0.3),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Navegar',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Grid de resultados
        Expanded(child: _buildGrid(items)),
      ],
    );
  }
  
  /// Estado vazio específico para busca
  Widget _buildSearchEmptyState(String query) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            color: Colors.white.withOpacity(0.3),
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum resultado para "$query"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tente usar outros termos de busca',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              _clearSearch();
              if (_isSearching) {
                _searchFocusNode.requestFocus();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: SaimoTheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: SaimoTheme.primary.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    color: SaimoTheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Limpar busca',
                    style: TextStyle(
                      color: SaimoTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

  Widget _buildCategorySections(MoviesProvider provider) {
    // Usa availableCategories (exceto Todos) em vez de categoriesWithCount
    final categories = provider.availableCategories.where((c) => c != 'Todos').toList();
    
    if (categories.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _contentScrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      // IMPORTANTE: Define altura fixa para cálculo preciso do scroll
      itemExtent: _sectionHeight + 8, // altura + margin
      itemBuilder: (context, sectionIdx) {
        final category = categories[sectionIdx];
        
        // Lazy Load Check
        if (!provider.isCategoryLoaded(category)) {
          // Trigger load
          provider.loadCategory(category);
          // Show placeholder
          return _buildLoadingSection(category);
        }

        final items = _getItemsForCategory(provider, category);
        final isSectionFocused = _currentSection == 3 && _sectionIndex == sectionIdx;
        
        // Mesmo carregado, pode estar vazio (filtro etc)
        if (items.isEmpty) return const SizedBox.shrink();
        
        return _buildCategorySection(
          category: category,
          items: items,
          sectionIdx: sectionIdx,
          isSectionFocused: isSectionFocused,
          count: items.length,
        );
      },
    );
  }

  Widget _buildLoadingSection(String category) {
    return SizedBox(
      height: _sectionHeight + 8,
      child: Container(
        height: _sectionHeight,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Placeholder
            Row(
              children: [
                Container(
                  width: 100,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  category,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
             const SizedBox(height: 10),
             // Cards Placeholder
             Expanded(
               child: ListView.builder(
                 scrollDirection: Axis.horizontal,
                 physics: const NeverScrollableScrollPhysics(), // Placeholder estático
                 itemCount: 6,
                 itemBuilder: (context, index) {
                   return Container(
                     width: _cardWidth,
                     height: _cardHeight,
                     margin: const EdgeInsets.only(right: 10),
                     decoration: BoxDecoration(
                       color: Colors.white.withOpacity(0.05),
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: Center(
                       child: SizedBox(
                         width: 16, 
                         height: 16,
                         child: CircularProgressIndicator(
                           strokeWidth: 2, 
                           valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.1)),
                         )
                       ),
                     ),
                   );
                 },
               ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection({
    required String category,
    required List<dynamic> items,
    required int sectionIdx,
    required bool isSectionFocused,
    required int count,
  }) {
    final sectionScrollController = _getOrCreateSectionController(sectionIdx);
    
    // LIMITA a 10 itens no modo "Todos"
    const maxItemsInTodos = 10;
    final limitedItems = items.take(maxItemsInTodos).toList();
    final hasMore = items.length > maxItemsInTodos;
    // +1 se tiver botão "Ver mais"
    final totalItemsToShow = limitedItems.length + (hasMore ? 1 : 0);
    
    // Container com altura fixa para corresponder ao itemExtent
    return SizedBox(
      height: _sectionHeight + 8, // Deve corresponder ao itemExtent
      child: Container(
        height: _sectionHeight,
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header da seção
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(MovieCategory.getColor(category)).withOpacity(
                        isSectionFocused ? 1.0 : 0.7,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          MovieCategory.getIcon(category),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          category,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: isSectionFocused ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count itens',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  if (isSectionFocused)
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_back_ios,
                          color: Colors.white.withOpacity(0.3),
                          size: 10,
                        ),
                        Text(
                          ' Navegar ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 9,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white.withOpacity(0.3),
                          size: 10,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          
          // Lista horizontal de itens (10 itens + botão Ver mais)
          Expanded(
            child: ListView.builder(
              controller: sectionScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: totalItemsToShow,
              cacheExtent: _cardWidth * 2,
              itemBuilder: (context, itemIdx) {
                // Botão "Ver mais" no final
                if (hasMore && itemIdx == limitedItems.length) {
                  final isFocused = isSectionFocused && _itemIndex == itemIdx;
                  return _buildSeeMoreButton(
                    category: category,
                    isFocused: isFocused,
                    totalCount: count,
                    onTap: () {
                      setState(() {
                        _currentSection = 3;
                        _sectionIndex = sectionIdx;
                        _itemIndex = itemIdx;
                      });
                      _goToCategory(category);
                    },
                  );
                }
                
                final isFocused = isSectionFocused && _itemIndex == itemIdx;
                final item = limitedItems[itemIdx];

                if (item is GroupedSeries) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SmallSeriesCard(
                      series: item,
                      isFocused: isFocused,
                      width: _cardWidth,
                      height: _cardHeight,
                      onTap: () {
                        setState(() {
                          _currentSection = 3;
                          _sectionIndex = sectionIdx;
                          _itemIndex = itemIdx;
                        });
                        _selectSectionItem(items);
                      },
                    ),
                  );
                } else if (item is Movie) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SmallMovieCard(
                      movie: item,
                      isFocused: isFocused,
                      width: _cardWidth,
                      height: _cardHeight,
                      onTap: () {
                        setState(() {
                          _currentSection = 3;
                          _sectionIndex = sectionIdx;
                          _itemIndex = itemIdx;
                        });
                        _selectSectionItem(items);
                      },
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSeeMoreButton({
    required String category,
    required bool isFocused,
    required int totalCount,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _cardWidth,
          height: _cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFocused ? Colors.white : Colors.white.withOpacity(0.2),
              width: isFocused ? 3 : 1.5,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(MovieCategory.getColor(category)).withOpacity(0.3),
                Color(MovieCategory.getColor(category)).withOpacity(0.1),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withOpacity(isFocused ? 1.0 : 0.7),
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                'Ver mais',
                style: TextStyle(
                  color: Colors.white.withOpacity(isFocused ? 1.0 : 0.7),
                  fontSize: 11,
                  fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '+${totalCount - 10}',
                style: TextStyle(
                  color: Colors.white.withOpacity(isFocused ? 0.8 : 0.5),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SaimoTheme.primary.withOpacity(
                        0.2 + (_pulseController.value * 0.2),
                      ),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    SaimoTheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Carregando catálogo...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Isso pode demorar alguns segundos',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red.withOpacity(0.7),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Erro ao carregar',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_filter_rounded,
            color: Colors.white.withOpacity(0.3),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum conteúdo encontrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tente mudar os filtros ou categoria',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<dynamic> items) {
    final itemsPerRow = _getItemsPerRow();
    final provider = Provider.of<MoviesProvider>(context, listen: false);
    final category = provider.selectedCategory;
    final allItems = category != 'Todos' ? _getAllItemsForCategory(provider, category) : items;
    final hasMore = items.length < allItems.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              controller: _contentScrollController,
              // Cache mínimo: apenas 2 linhas fora da tela
              cacheExtent: _cardHeight * 2,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: itemsPerRow,
                childAspectRatio: _cardWidth / _cardHeight,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              // Mostra apenas itens paginados
              itemCount: items.length,
              itemBuilder: (context, index) {
          final row = index ~/ itemsPerRow;
          final col = index % itemsPerRow;
          final isFocused = _currentSection == 3 &&
              _contentRowIndex == row &&
              _contentColIndex == col;

          final item = items[index];

          if (item is GroupedSeries) {
            return SmallSeriesCard(
              series: item,
              isFocused: isFocused,
              onTap: () {
                setState(() {
                  _currentSection = 3;
                  _contentRowIndex = row;
                  _contentColIndex = col;
                });
                _selectItem(items);
              },
            );
          } else if (item is Movie) {
            return SmallMovieCard(
              movie: item,
              isFocused: isFocused,
              onTap: () {
                setState(() {
                  _currentSection = 3;
                  _contentRowIndex = row;
                  _contentColIndex = col;
                });
                _selectItem(items);
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),
    ),
    // Indicador de loading quando está carregando mais
    if (_isLoadingMore || hasMore)
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoadingMore)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(SaimoTheme.primary),
                ),
              ),
            if (_isLoadingMore) const SizedBox(width: 8),
            Text(
              _isLoadingMore ? 'Carregando mais...' : 'Role para carregar mais',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
    );
  }
}

/// Card compacto de filme
class SmallMovieCard extends StatefulWidget {
  final Movie movie;
  final bool isFocused;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const SmallMovieCard({
    super.key,
    required this.movie,
    this.isFocused = false,
    this.onTap,
    this.width = 100,
    this.height = 140,
  });

  @override
  State<SmallMovieCard> createState() => _SmallMovieCardState();
}

class _SmallMovieCardState extends State<SmallMovieCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      lowerBound: 1.0,
      upperBound: 1.06,
    );
  }

  @override
  void didUpdateWidget(covariant SmallMovieCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused && !oldWidget.isFocused) {
      _scaleController.forward();
    } else if (!widget.isFocused && oldWidget.isFocused) {
      _scaleController.reverse();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleController.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isFocused ? SaimoTheme.primary : Colors.transparent,
              width: widget.isFocused ? 2 : 0,
            ),
            boxShadow: widget.isFocused
                ? [
                    BoxShadow(
                      color: SaimoTheme.primary.withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isFocused ? 6 : 8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPoster(),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.height * 0.45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.9),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.movie.seriesName ?? widget.movie.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                      if (widget.movie.episodeTag != null) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: SaimoTheme.primary.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            widget.movie.episodeTag!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: widget.movie.type == MovieType.series
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.movie.type == MovieType.series
                          ? Icons.tv_rounded
                          : Icons.movie_rounded,
                      color: Colors.white,
                      size: 7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoster() {
    if (widget.movie.logo != null && widget.movie.logo!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.movie.logo!,
        fit: BoxFit.cover,
        memCacheWidth: 200, // Cache em baixa resolução
        memCacheHeight: 280,
        maxWidthDiskCache: 300,
        maxHeightDiskCache: 420,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, url) => _buildFallbackPoster(),
        errorWidget: (context, url, error) => _buildFallbackPoster(),
      );
    }
    return _buildFallbackPoster();
  }

  Widget _buildFallbackPoster() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(MovieCategory.getColor(widget.movie.category)),
            Color(MovieCategory.getColor(widget.movie.category)).withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          widget.movie.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Card compacto de série
class SmallSeriesCard extends StatefulWidget {
  final GroupedSeries series;
  final bool isFocused;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const SmallSeriesCard({
    super.key,
    required this.series,
    this.isFocused = false,
    this.onTap,
    this.width = 100,
    this.height = 140,
  });

  @override
  State<SmallSeriesCard> createState() => _SmallSeriesCardState();
}

class _SmallSeriesCardState extends State<SmallSeriesCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      lowerBound: 1.0,
      upperBound: 1.06,
    );
  }

  @override
  void didUpdateWidget(covariant SmallSeriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused && !oldWidget.isFocused) {
      _scaleController.forward();
    } else if (!widget.isFocused && oldWidget.isFocused) {
      _scaleController.reverse();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleController.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isFocused
                  ? const Color(0xFF8B5CF6)
                  : Colors.transparent,
              width: widget.isFocused ? 2 : 0,
            ),
            boxShadow: widget.isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isFocused ? 6 : 8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPoster(),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.height * 0.45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.9),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.series.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${widget.series.seasonCount}T • ${widget.series.episodeCount}E',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 7,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.tv_rounded,
                      color: Colors.white,
                      size: 7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoster() {
    if (widget.series.logo != null && widget.series.logo!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.series.logo!,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        memCacheHeight: 280,
        maxWidthDiskCache: 300,
        maxHeightDiskCache: 420,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, url) => _buildFallbackPoster(),
        errorWidget: (context, url, error) => _buildFallbackPoster(),
      );
    }
    return _buildFallbackPoster();
  }

  Widget _buildFallbackPoster() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF8B5CF6),
            const Color(0xFF8B5CF6).withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          widget.series.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
