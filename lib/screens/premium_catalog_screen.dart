import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../providers/movies_provider.dart';
import '../widgets/tmdb_details_modal.dart';
import '../screens/movie_player_screen.dart';

/// Tela de Catálogo de Filmes e Séries - Design Premium Netflix-Style
/// Completamente redesenhada com visual moderno e navegação fluida
class PremiumCatalogScreen extends StatefulWidget {
  const PremiumCatalogScreen({super.key});

  @override
  State<PremiumCatalogScreen> createState() => _PremiumCatalogScreenState();
}

class _PremiumCatalogScreenState extends State<PremiumCatalogScreen>
    with TickerProviderStateMixin {
  // === CORES DO TEMA ===
  static const _bgColor = Color(0xFF0a0a0a);
  static const _surfaceColor = Color(0xFF141414);
  static const _accentRed = Color(0xFFE50914);
  static const _accentGold = Color(0xFFFFD700);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFFB3B3B3);
  static const _textMuted = Color(0xFF808080);

  // === NAVEGAÇÃO ===
  int _currentSection = 0; // 0=hero, 1=categorias, 2=conteúdo
  int _categoryIndex = 0;
  int _rowIndex = 0;
  int _colIndex = 0;

  // === HERO BANNER ===
  int _heroIndex = 0;
  Timer? _heroTimer;
  late PageController _heroController;

  // === CONTROLADORES ===
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _contentScrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();
  final Map<String, ScrollController> _rowScrollControllers = {};

  // === ANIMAÇÕES ===
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // === ESTADO ===
  String _currentTime = '';
  Timer? _clockTimer;
  bool _isTransitioning = false;

  // === DIMENSÕES ===
  static const double _cardWidth = 180.0;
  static const double _cardHeight = 270.0;
  static const double _cardSpacing = 12.0;
  static const double _rowHeight = 320.0;
  static const double _categoryHeight = 44.0;

  @override
  void initState() {
    super.initState();
    
    _heroController = PageController();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();

    _updateTime();
    _startClockTimer();
    _startHeroAutoPlay();
    _loadMovies();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _contentScrollController.dispose();
    _categoriesScrollController.dispose();
    _heroController.dispose();
    _fadeController.dispose();
    _heroTimer?.cancel();
    _clockTimer?.cancel();
    for (var controller in _rowScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  void _startClockTimer() {
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
  }

  void _startHeroAutoPlay() {
    _heroTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && _currentSection != 0) {
        final provider = context.read<MoviesProvider>();
        final heroItems = _getHeroItems(provider);
        if (heroItems.isNotEmpty) {
          setState(() {
            _heroIndex = (_heroIndex + 1) % heroItems.length;
          });
          if (_heroController.hasClients) {
            _heroController.animateToPage(
              _heroIndex,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        }
      }
    });
  }

  Future<void> _loadMovies() async {
    final provider = context.read<MoviesProvider>();
    await provider.loadMovies();
  }

  List<Movie> _getHeroItems(MoviesProvider provider) {
    final lancamentos = provider.getMoviesForCategory('Lançamentos');
    return lancamentos.take(10).toList();
  }

  ScrollController _getRowController(String key) {
    if (!_rowScrollControllers.containsKey(key)) {
      _rowScrollControllers[key] = ScrollController();
    }
    return _rowScrollControllers[key]!;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _isTransitioning) return;

    final key = event.logicalKey;
    final provider = context.read<MoviesProvider>();

    // Voltar
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_currentSection > 0) {
        setState(() => _currentSection = 0);
        HapticFeedback.selectionClick();
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    switch (_currentSection) {
      case 0:
        _handleHeroNavigation(key, provider);
        break;
      case 1:
        _handleCategoryNavigation(key, provider);
        break;
      case 2:
        _handleContentNavigation(key, provider);
        break;
    }
  }

  void _handleHeroNavigation(LogicalKeyboardKey key, MoviesProvider provider) {
    final heroItems = _getHeroItems(provider);

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_heroIndex > 0) {
        setState(() => _heroIndex--);
        _heroController.animateToPage(
          _heroIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_heroIndex < heroItems.length - 1) {
        setState(() => _heroIndex++);
        _heroController.animateToPage(
          _heroIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _currentSection = 1;
        _categoryIndex = 0;
      });
      _scrollToCategory(0);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (heroItems.isNotEmpty) {
        _showMovieDetails(heroItems[_heroIndex]);
      }
    }
  }

  void _handleCategoryNavigation(LogicalKeyboardKey key, MoviesProvider provider) {
    final categories = provider.availableCategories;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_categoryIndex > 0) {
        setState(() => _categoryIndex--);
        provider.selectCategory(categories[_categoryIndex]);
        _scrollToCategory(_categoryIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_categoryIndex < categories.length - 1) {
        setState(() => _categoryIndex++);
        provider.selectCategory(categories[_categoryIndex]);
        _scrollToCategory(_categoryIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _currentSection = 0);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _currentSection = 2;
        _rowIndex = 0;
        _colIndex = 0;
      });
      _scrollToContent();
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      setState(() {
        _currentSection = 2;
        _rowIndex = 0;
        _colIndex = 0;
      });
      HapticFeedback.mediumImpact();
    }
  }

  void _handleContentNavigation(LogicalKeyboardKey key, MoviesProvider provider) {
    final content = _getContentSections(provider);
    if (content.isEmpty) return;

    final currentRow = content[_rowIndex];
    final items = currentRow['items'] as List;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_colIndex > 0) {
        setState(() => _colIndex--);
        _scrollToItem(_rowIndex, _colIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_colIndex < items.length - 1) {
        setState(() => _colIndex++);
        _scrollToItem(_rowIndex, _colIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_rowIndex > 0) {
        setState(() {
          _rowIndex--;
          _colIndex = _colIndex.clamp(0, (content[_rowIndex]['items'] as List).length - 1);
        });
        _scrollToContent();
        _scrollToItem(_rowIndex, _colIndex);
        HapticFeedback.selectionClick();
      } else {
        setState(() => _currentSection = 1);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_rowIndex < content.length - 1) {
        setState(() {
          _rowIndex++;
          _colIndex = _colIndex.clamp(0, (content[_rowIndex]['items'] as List).length - 1);
        });
        _scrollToContent();
        _scrollToItem(_rowIndex, _colIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      final item = items[_colIndex];
      if (item is Movie) {
        _showMovieDetails(item);
      } else if (item is GroupedSeries) {
        _showSeriesDetails(item);
      }
    }
  }

  void _scrollToCategory(int index) {
    if (!_categoriesScrollController.hasClients) return;
    final itemWidth = 120.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final offset = (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
    _categoriesScrollController.animateTo(
      offset.clamp(0.0, _categoriesScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToContent() {
    if (!_contentScrollController.hasClients) return;
    final offset = _rowIndex * _rowHeight;
    _contentScrollController.animateTo(
      offset.clamp(0.0, _contentScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToItem(int rowIndex, int colIndex) {
    final content = _getContentSections(context.read<MoviesProvider>());
    if (rowIndex >= content.length) return;
    
    final key = '${content[rowIndex]['title']}_$rowIndex';
    final controller = _getRowController(key);
    
    if (!controller.hasClients) return;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final offset = (colIndex * (_cardWidth + _cardSpacing)) - (screenWidth / 2) + (_cardWidth / 2);
    controller.animateTo(
      offset.clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _showMovieDetails(Movie movie) {
    HapticFeedback.mediumImpact();
    TMDBDetailsModal.show(
      context,
      title: movie.seriesName ?? movie.name,
      isSeries: movie.type == MovieType.series,
      existingLogo: movie.logo,
      onPlay: () => _playMovie(movie),
    );
  }

  void _showSeriesDetails(GroupedSeries series) {
    HapticFeedback.mediumImpact();
    TMDBDetailsModal.show(
      context,
      title: series.name,
      isSeries: true,
      existingLogo: series.logo,
      onPlay: () {
        // Toca primeiro episódio
        final firstSeason = series.sortedSeasons.first;
        final episodes = series.getSeasonEpisodes(firstSeason);
        if (episodes.isNotEmpty) {
          _playMovie(episodes.first);
        }
      },
    );
  }

  void _playMovie(Movie movie) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MoviePlayerScreen(movie: movie),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  List<Map<String, dynamic>> _getContentSections(MoviesProvider provider) {
    final selectedCategory = provider.selectedCategory;
    final sections = <Map<String, dynamic>>[];

    if (selectedCategory == 'Todos') {
      // Mostra seções por categoria
      final categoriesWithCount = provider.categoriesWithCount;
      for (final category in categoriesWithCount.keys) {
        final movies = provider.getMoviesForCategory(category);
        final series = provider.getSeriesForCategory(category);
        
        final items = <dynamic>[...series, ...movies.where((m) => m.seriesName == null)];
        
        if (items.isNotEmpty) {
          sections.add({
            'title': category,
            'items': items.take(20).toList(),
          });
        }
      }
    } else {
      // Categoria específica - mostra tudo em uma seção
      final movies = provider.getMoviesForCategory(selectedCategory);
      final series = provider.getSeriesForCategory(selectedCategory);
      
      if (series.isNotEmpty) {
        sections.add({
          'title': 'Séries',
          'items': series,
        });
      }
      
      final onlyMovies = movies.where((m) => m.seriesName == null).toList();
      if (onlyMovies.isNotEmpty) {
        sections.add({
          'title': 'Filmes',
          'items': onlyMovies,
        });
      }
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: KeyboardListener(
        focusNode: _mainFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: Consumer<MoviesProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return _buildLoadingState();
            }

            return FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  // Header
                  _buildHeader(provider),
                  
                  // Conteúdo principal
                  Expanded(
                    child: CustomScrollView(
                      controller: _contentScrollController,
                      slivers: [
                        // Hero Banner
                        SliverToBoxAdapter(
                          child: _buildHeroBanner(provider),
                        ),

                        // Categorias
                        SliverToBoxAdapter(
                          child: _buildCategoriesBar(provider),
                        ),

                        // Seções de conteúdo
                        ..._buildContentSections(provider),

                        // Espaço inferior
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 40),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(_accentRed),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Carregando catálogo...',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(MoviesProvider provider) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _bgColor,
            _bgColor.withOpacity(0.8),
          ],
        ),
      ),
      child: Row(
        children: [
          // Logo / Voltar
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios, color: _textPrimary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'SAIMO',
                  style: TextStyle(
                    color: _accentRed,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Filtros
          _buildHeaderFilter(
            'Todos',
            provider.filterType == MovieFilterType.all,
            () => provider.setFilterType(MovieFilterType.all),
          ),
          const SizedBox(width: 16),
          _buildHeaderFilter(
            'Filmes',
            provider.filterType == MovieFilterType.movies,
            () => provider.setFilterType(MovieFilterType.movies),
          ),
          const SizedBox(width: 16),
          _buildHeaderFilter(
            'Séries',
            provider.filterType == MovieFilterType.series,
            () => provider.setFilterType(MovieFilterType.series),
          ),

          const Spacer(),

          // Busca
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search, color: _textPrimary, size: 24),
          ),

          // Horário
          const SizedBox(width: 16),
          Text(
            _currentTime,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderFilter(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _accentRed : _textMuted,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _textPrimary : _textSecondary,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(MoviesProvider provider) {
    final heroItems = _getHeroItems(provider);
    if (heroItems.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final isHeroFocused = _currentSection == 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: isHeroFocused ? size.height * 0.55 : size.height * 0.45,
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          // PageView com banners
          PageView.builder(
            controller: _heroController,
            onPageChanged: (index) {
              setState(() => _heroIndex = index);
            },
            itemCount: heroItems.length,
            itemBuilder: (context, index) {
              final movie = heroItems[index];
              final isSelected = index == _heroIndex && isHeroFocused;

              return _buildHeroItem(movie, isSelected, size);
            },
          ),

          // Gradiente inferior
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    _bgColor.withOpacity(0.8),
                    _bgColor,
                  ],
                ),
              ),
            ),
          ),

          // Indicadores
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(heroItems.length, (index) {
                final isActive = index == _heroIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 24 : 8,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isActive ? _accentRed : _textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),

          // Info do item atual
          Positioned(
            bottom: 50,
            left: 48,
            right: size.width * 0.4,
            child: _buildHeroInfo(heroItems[_heroIndex], isHeroFocused),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroItem(Movie movie, bool isSelected, Size size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Imagem de fundo
        if (movie.logo != null && movie.logo!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: movie.logo!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            color: Colors.black45,
            colorBlendMode: BlendMode.darken,
            errorWidget: (_, __, ___) => Container(
              color: _surfaceColor,
              child: Center(
                child: Text(
                  movie.name,
                  style: const TextStyle(color: _textMuted, fontSize: 24),
                ),
              ),
            ),
          )
        else
          Container(
            color: _surfaceColor,
            child: Center(
              child: Text(
                movie.name,
                style: const TextStyle(color: _textMuted, fontSize: 24),
              ),
            ),
          ),

        // Borda de foco
        if (isSelected)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _accentRed, width: 3),
            ),
          ),
      ],
    );
  }

  Widget _buildHeroInfo(Movie movie, bool isFocused) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Título
        Text(
          movie.seriesName ?? movie.name,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 10,
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 12),

        // Meta info
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _accentRed,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                movie.type == MovieType.series ? 'SÉRIE' : 'FILME',
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              movie.category,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Botões
        if (isFocused)
          Row(
            children: [
              _buildHeroButton(
                icon: Icons.play_arrow,
                label: 'Assistir',
                isPrimary: true,
                onTap: () => _playMovie(movie),
              ),
              const SizedBox(width: 12),
              _buildHeroButton(
                icon: Icons.info_outline,
                label: 'Mais Info',
                isPrimary: false,
                onTap: () => _showMovieDetails(movie),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildHeroButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? _textPrimary : _textPrimary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? _bgColor : _textPrimary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? _bgColor : _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesBar(MoviesProvider provider) {
    final categories = provider.availableCategories;
    final isFocused = _currentSection == 1;

    return Container(
      height: _categoryHeight + 20,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        controller: _categoriesScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = provider.selectedCategory == category;
          final hasFocus = isFocused && _categoryIndex == index;

          return GestureDetector(
            onTap: () {
              provider.selectCategory(category);
              setState(() => _categoryIndex = index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? _accentRed
                    : hasFocus
                        ? _accentRed.withOpacity(0.3)
                        : _surfaceColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFocus ? _accentRed : Colors.transparent,
                  width: 2,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: _accentRed.withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected || hasFocus ? _textPrimary : _textSecondary,
                  fontSize: 14,
                  fontWeight: isSelected || hasFocus ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildContentSections(MoviesProvider provider) {
    final sections = _getContentSections(provider);
    final widgets = <Widget>[];

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      widgets.add(
        SliverToBoxAdapter(
          child: _buildContentRow(
            title: section['title'] as String,
            items: section['items'] as List,
            rowIndex: i,
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildContentRow({
    required String title,
    required List items,
    required int rowIndex,
  }) {
    final key = '${title}_$rowIndex';
    final controller = _getRowController(key);
    final isRowFocused = _currentSection == 2 && _rowIndex == rowIndex;

    return Container(
      height: _rowHeight,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título da seção
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 12),
            child: Row(
              children: [
                if (isRowFocused)
                  Container(
                    width: 4,
                    height: 20,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _accentRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Text(
                  title,
                  style: TextStyle(
                    color: isRowFocused ? _textPrimary : _textSecondary,
                    fontSize: isRowFocused ? 20 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${items.length})',
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Lista de itens
          Expanded(
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = isRowFocused && _colIndex == index;

                if (item is Movie) {
                  return _buildMovieCard(item, isSelected, rowIndex, index);
                } else if (item is GroupedSeries) {
                  return _buildSeriesCard(item, isSelected, rowIndex, index);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieCard(Movie movie, bool isSelected, int rowIndex, int colIndex) {
    return GestureDetector(
      onTap: () => _showMovieDetails(movie),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _cardWidth,
        margin: const EdgeInsets.only(right: _cardSpacing),
        transform: Matrix4.identity()..scale(isSelected ? 1.08 : 1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? _accentRed : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _accentRed.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isSelected ? 5 : 8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster
                      movie.logo != null && movie.logo!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: movie.logo!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _buildCardPlaceholder(movie.name),
                              errorWidget: (_, __, ___) => _buildCardPlaceholder(movie.name),
                            )
                          : _buildCardPlaceholder(movie.name),

                      // Gradiente inferior
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 80,
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

                      // Badge de tipo
                      if (movie.type == MovieType.series)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _accentRed,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'SÉRIE',
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                      // Título no card
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Text(
                          movie.seriesName ?? movie.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesCard(GroupedSeries series, bool isSelected, int rowIndex, int colIndex) {
    return GestureDetector(
      onTap: () => _showSeriesDetails(series),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _cardWidth,
        margin: const EdgeInsets.only(right: _cardSpacing),
        transform: Matrix4.identity()..scale(isSelected ? 1.08 : 1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? _accentRed : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _accentRed.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isSelected ? 5 : 8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster
                      series.logo != null && series.logo!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: series.logo!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _buildCardPlaceholder(series.name),
                              errorWidget: (_, __, ___) => _buildCardPlaceholder(series.name),
                            )
                          : _buildCardPlaceholder(series.name),

                      // Gradiente inferior
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 80,
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

                      // Badge de série
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tv, color: _textPrimary, size: 10),
                              const SizedBox(width: 4),
                              Text(
                                '${series.seasonCount} temp',
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Episódios
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${series.episodeCount} ep',
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),

                      // Título no card
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Text(
                          series.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPlaceholder(String name) {
    return Container(
      color: _surfaceColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie, color: _textMuted, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
