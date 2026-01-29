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
    if (provider.selectedCategoryName == 'Todos') {
       // Se for primeira vez ou realmente Todos, ok.
       // O importante é não forçar 'Todos' se o user já tinha selecionado outra coisa.
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
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    // Pula tendências em qualquer tela que NÃO seja a categoria específica de Tendências
    final skipTrending = provider.selectedCategoryName != '📊 Tendências' || _showingFavorites || _isSearchMode;
    
    setState(() {
      if (_section == 4) {
        // Na grid de categorias/conteúdo
        if (_contentRow > 0) {
          _contentRow--;
          _scrollToRow();
        } else {
          // Se deve pular tendências, vai direto para filtros
          if (skipTrending) {
            _section = 1;
            _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          } else {
            // Sobe para tendências da semana (se existir) ou de hoje
            if (_trendingWeek.isNotEmpty) {
              _section = 3;
              _scrollToMainSection(3);
            } else if (_trendingToday.isNotEmpty) {
              _section = 2;
              _scrollToMainSection(2);
            } else {
              _section = 1;
              _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          }
        }
      } else if (_section == 3) {
        // Na seção de tendências da semana
        if (_trendingToday.isNotEmpty) {
          _section = 2;
          _scrollToMainSection(2);
        } else {
          _section = 1;
          _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      } else if (_section == 2) {
        // Na seção de tendências de hoje
        _section = 1;
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else if (_section == 1) {
        _section = 0;
      }
    });
  }

  void _onDown() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    // Pula tendências em qualquer tela que NÃO seja a categoria específica de Tendências
    final skipTrending = provider.selectedCategoryName != '📊 Tendências' || _showingFavorites || _isSearchMode;
    
    // Determina o número de itens baseado no modo atual
    int itemCount;
    if (_showingFavorites) {
      final favProvider = Provider.of<MovieFavoritesProvider>(context, listen: false);
      itemCount = favProvider.count;
    } else if (provider.selectedCategoryName == 'Todos') {
      itemCount = provider.availableCategories.length - 1; // Exclui "Todos"
    } else {
      // Tendências AGORA tem grid, então usa displayItems normalmente
      itemCount = provider.displayItems.length;
    }
    final rows = (itemCount / _columns).ceil();
    
    setState(() {
      if (_section == 0) {
        _section = 1;
      } else if (_section == 1) {
        // Se deve pular tendências, vai para conteúdo/categorias
        if (skipTrending) {
          _section = 4;
          _contentRow = 0;
          _contentCol = 0;
          _scrollToRow();
        } else {
          // Desce para tendências de hoje (se existir)
          if (_trendingToday.isNotEmpty) {
            _section = 2;
            _trendingTodayIndex = 0;
            _scrollToMainSection(2);
          } else if (_trendingWeek.isNotEmpty) {
            _section = 3;
            _trendingWeekIndex = 0;
            _scrollToMainSection(3);
          } else {
            // Se não tem tendências, vai para o grid
            _section = 4;
            _contentRow = 0;
            _contentCol = 0;
            _scrollToRow();
          }
        }
      } else if (_section == 2) {
        // De tendências de hoje para tendências da semana ou grid
        if (_trendingWeek.isNotEmpty) {
          _section = 3;
          _trendingWeekIndex = 0;
          _scrollToMainSection(3);
        } else {
          // Vai para o grid
          _section = 4;
          _contentRow = 0;
          _contentCol = 0;
          _scrollToRow();
        }
      } else if (_section == 3) {
        // De tendências da semana para o grid
        _section = 4;
        _contentRow = 0;
        _contentCol = 0;
        _scrollToRow();
      } else if (_section == 4 && _contentRow < rows - 1) {
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
        // Tendências de hoje
        if (_trendingTodayIndex > 0) {
          _trendingTodayIndex--;
          _scrollTrendingToday();
        } else {
          _openCategoryModal(provider);
        }
      } else if (_section == 3) {
        // Tendências da semana
        if (_trendingWeekIndex > 0) {
          _trendingWeekIndex--;
          _scrollTrendingWeek();
        } else {
          _openCategoryModal(provider);
        }
      } else if (_section == 4) {
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
    
    // Determina o número de itens baseado no modo atual
    int itemCount;
    if (_showingFavorites) {
      final favProvider = Provider.of<MovieFavoritesProvider>(context, listen: false);
      itemCount = favProvider.count;
    } else if (provider.selectedCategoryName == 'Todos') {
      itemCount = provider.availableCategories.length - 1;
    } else {
      itemCount = provider.displayItems.length;
    }
    
    setState(() {
      if (_section == 0) {
        if (_headerIndex < 2) _headerIndex++;
      } else if (_section == 1) {
        if (_filterIndex < 6) _filterIndex++; // Agora vai até 6 (buscar)
      } else if (_section == 2) {
        // Tendências de hoje
        if (_trendingTodayIndex < _trendingToday.length - 1) {
          _trendingTodayIndex++;
          _scrollTrendingToday();
        }
      } else if (_section == 3) {
        // Tendências da semana
        if (_trendingWeekIndex < _trendingWeek.length - 1) {
          _trendingWeekIndex++;
          _scrollTrendingWeek();
        }
      } else if (_section == 4) {
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
  
  void _scrollTrendingToday() {
    if (!_trendingTodayScroll.hasClients) return;
    final offset = _trendingTodayIndex * (_cardWidth + 12);
    _trendingTodayScroll.animateTo(
      offset.clamp(0.0, _trendingTodayScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
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
    } else if (_section == 2) {
      // Tendências de hoje
      if (_trendingTodayIndex < _trendingToday.length) {
        _showTrendingDetail(_trendingToday[_trendingTodayIndex]);
      }
    } else if (_section == 3) {
      // Tendências da semana
      if (_trendingWeekIndex < _trendingWeek.length) {
        _showTrendingDetail(_trendingWeek[_trendingWeekIndex]);
      }
    } else if (_section == 4) {
      if (_showingFavorites) {
        // Está mostrando favoritos - abre detalhe do filme/série favorito
        final favProvider = context.read<MovieFavoritesProvider>();
        final favorites = favProvider.favorites;
        final idx = _contentRow * _columns + _contentCol;
        if (idx < favorites.length) {
          final movie = favorites[idx];
          // Verifica se é série com episódios
          if (movie.type == MovieType.series && movie.episodes != null && movie.episodes!.isNotEmpty) {
            // Cria GroupedSeries a partir do Movie
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
      } else if (provider.selectedCategoryName == 'Todos' && !_isSearchMode) {
        // Seleciona categoria
        final cats = provider.availableCategories.where((c) => c != 'Todos').toList();
        final idx = _contentRow * _columns + _contentCol;
        if (idx < cats.length) {
          provider.selectCategory(cats[idx]);
          setState(() {
            _showingFavorites = false; // Sai do modo favoritos
          });
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

  void _scrollToMainSection(int section) {
    if (!_scrollController.hasClients) return;
    
    // Calcula offsets aproximados
    // Header (56) + Filtros (48) + Padding (12)
    double offset = 0;
    
    if (section == 2) {
      // Tendências Hoje: logo abaixo dos filtros
      offset = 0; // Scroll principal fica no topo
    } else if (section == 3) {
      // Tendências Semana: Abaixo de Hoje
      // Altura aprox de Hoje: Título (40) + Card (210) + Spacing (20)
      if (_trendingToday.isNotEmpty) {
        offset = 40 + _cardHeight + 20; 
      }
    }
    
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
              setState(() {
                _showingFavorites = !_showingFavorites;
                _contentRow = 0;
                _contentCol = 0;
              });
              _scrollController.jumpTo(0);
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
    
    // Se está mostrando favoritos
    if (_showingFavorites) {
      return _buildFavoritesGrid();
    }
    
    // Se categoria é "Todos", mostra cards de categorias
    if (provider.selectedCategoryName == 'Todos') {
      return _buildCategoryCards(provider);
    }
    
    // Se categoria é "📊 Tendências", mostra seções de hoje e semana
    if (provider.selectedCategoryName == '📊 Tendências') {
      return _buildTrendingContent(provider);
    }
    
    // Senão, mostra grid de filmes/séries
    return _buildContentGrid(provider);
  }
  
  /// Conteúdo especial para categoria Tendências com seções Hoje e Semana
  Widget _buildTrendingContent(LazyMoviesProvider provider) {
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
      children: [
        // === TENDÊNCIAS DE HOJE ===
        if (_trendingToday.isNotEmpty || _loadingTrending)
          _buildTrendingSection(
            title: '🔥 Tendências de Hoje',
            items: _trendingToday,
            isLoading: _loadingTrending,
            isFocused: _section == 2,
            selectedIndex: _trendingTodayIndex,
            scrollController: _trendingTodayScroll,
          ),
        
        if (_trendingToday.isNotEmpty || _loadingTrending) 
          const SizedBox(height: 20),
        
        // === TENDÊNCIAS DA SEMANA ===
        if (_trendingWeek.isNotEmpty || _loadingTrending)
          _buildTrendingSection(
            title: '📅 Tendências da Semana',
            items: _trendingWeek,
            isLoading: _loadingTrending,
            isFocused: _section == 3,
            selectedIndex: _trendingWeekIndex,
            scrollController: _trendingWeekScroll,
          ),
        
        const SizedBox(height: 20),
        
        // === RESTO DO CONTEÚDO (GRID) ===
        // Permite navegação contínua para baixo
        if (provider.displayItems.isNotEmpty) ...[
           const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              '📜 Outros Títulos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: provider.displayItems.length,
            itemBuilder: (context, index) {
              final row = index ~/ _columns;
              final col = index % _columns;
              final isFocused = _section == 4 && _contentRow == row && _contentCol == col;
              
              return _ContentCard(
                item: provider.displayItems[index],
                isFocused: isFocused,
                onTap: () => _showDetail(provider.displayItems[index]),
              );
            },
          ),
          const SizedBox(height: 40), // Espaço extra no final
        ],
      ],
    );
  }
  
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
            padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
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
    
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
      children: [
        // === CATEGORIAS ===
        if (categories.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              '📺 Categorias',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
              final isFocused = _section == 4 && _contentRow == row && _contentCol == col;
              
              return _CategoryCard(
                name: category,
                isFocused: isFocused,
                onTap: () {
                  provider.selectCategory(category);
                  setState(() {
                    _showingFavorites = false;
                    _contentRow = 0;
                    _contentCol = 0;
                  });
                  _scrollController.jumpTo(0);
                },
              );
            },
          ),
        ],
      ],
    );
  }
  
  Widget _buildTrendingSection({
    required String title,
    required List<TrendingItem> items,
    required bool isLoading,
    required bool isFocused,
    required int selectedIndex,
    required ScrollController scrollController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isFocused) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '← → navegar  •  OK selecionar',
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: _cardHeight + 40,
          child: isLoading
              ? _buildTrendingLoading()
              : items.isEmpty
                  ? const Center(child: Text('Sem tendências disponíveis', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      // OTIMIZADO: Cache para scroll mais suave
                      cacheExtent: 500,
                      addAutomaticKeepAlives: false,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = isFocused && selectedIndex == index;
                        
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _TrendingCard(
                            item: item,
                            width: _cardWidth,
                            height: _cardHeight,
                            isFocused: isSelected,
                            onTap: () => _showTrendingDetail(item),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
  
  Widget _buildTrendingLoading() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            width: _cardWidth,
            height: _cardHeight,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFE50914),
                strokeWidth: 2,
              ),
            ),
          ),
        );
      },
    );
  }
  
  void _showTrendingDetail(TrendingItem item) {
    final movie = item.localMovie;
    
    // Se é série COM episódios, usa o modal de série otimizado
    if ((movie.type == MovieType.series || item.isSeries) && 
        movie.episodes != null && movie.episodes!.isNotEmpty) {
      final groupedSeries = _createGroupedSeriesFromMovie(movie);
      showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => SeriesModalOptimized(series: groupedSeries),
      );
      return;
    }
    
    // Filme ou série sem episódios estruturados
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => MovieDetailModal(movie: movie),
    );
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
      // OTIMIZADO: Reduz consumo de memória
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
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
        final isFocused = _section == 4 && _contentRow == row && _contentCol == col;
        
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

class _TrendingCard extends StatelessWidget {
  final TrendingItem item;
  final double width;
  final double height;
  final bool isFocused;
  final VoidCallback onTap;

  const _TrendingCard({
    required this.item,
    required this.width,
    required this.height,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: height + 40,
        transform: isFocused 
            ? (Matrix4.identity()..scale(1.05))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isFocused 
                      ? Border.all(color: const Color(0xFFFFD700), width: 3)
                      : null,
                  boxShadow: isFocused
                      ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 12)]
                      : [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Imagem do poster
                      // OTIMIZADO: CachedNetworkImage ao invés de Image.network
                      item.posterUrl != null
                          ? CachedNetworkImage(
                              imageUrl: item.posterUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              placeholder: (_, __) => _buildPlaceholder(),
                              errorWidget: (_, __, ___) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                      
                      // Gradiente inferior
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                            ),
                          ),
                        ),
                      ),
                      
                      // Badge de tipo (série ou filme)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.isSeries 
                                ? const Color(0xFF8B5CF6)
                                : const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.isSeries ? 'SÉRIE' : 'FILME',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      
                      // Rating
                      if (item.rating > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Color(0xFFFFD700), size: 12),
                                const SizedBox(width: 2),
                                Text(
                                  item.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
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
                ),
              ),
            ),
            
            // Título
            const SizedBox(height: 6),
            Text(
              item.localMovie.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isFocused ? const Color(0xFFFFD700) : Colors.white,
                fontSize: 12,
                fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[850],
      child: const Center(
        child: Icon(Icons.movie, color: Colors.white24, size: 40),
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

/// OTIMIZADO: Convertido para StatelessWidget, usa dados TMDB pré-carregados
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
                          item.displayName,
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
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Icon(
          item.type == DisplayItemType.series ? Icons.tv : Icons.movie,
          color: Colors.white24,
          size: 32,
        ),
      ),
    );
  }

  Color _getRatingColor(double rating) {
    if (rating >= 7.5) return const Color(0xFF22C55E);
    if (rating >= 6.0) return const Color(0xFFF59E0B);
    if (rating >= 4.0) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  Color _getCertificationColor(String cert) {
    final c = cert.toUpperCase();
    if (c == 'L' || c == 'G' || c == 'TV-G' || c == 'TV-Y') return const Color(0xFF22C55E);
    if (c == '10' || c == 'PG' || c == 'TV-PG' || c == 'TV-Y7') return const Color(0xFF3B82F6);
    if (c == '12' || c == 'PG-13' || c == 'TV-14') return const Color(0xFFF59E0B);
    if (c == '14') return const Color(0xFFF97316);
    if (c == '16' || c == 'R' || c == 'TV-MA') return const Color(0xFFEF4444);
    if (c == '18' || c == 'NC-17' || c == 'NR') return const Color(0xFF000000);
    return const Color(0xFF6B7280);
  }
}
