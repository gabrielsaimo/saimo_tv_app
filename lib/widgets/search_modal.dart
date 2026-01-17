import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/lazy_movies_provider.dart';
import '../models/movie.dart';
import 'movie_detail_modal.dart';
import 'series_detail_modal.dart';

/// Cores consistentes com a tela principal
class _SearchColors {
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF141414);
  static const Color surfaceLight = Color(0xFF1F1F1F);
  static const Color surfaceElevated = Color(0xFF262626);
  static const Color accent = Color(0xFFE50914);
  static const Color accentLight = Color(0xFFFF2D2D);
  static const Color accentGold = Color(0xFFFFD700);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF666666);
}

/// Modal de pesquisa inteligente para filmes e séries
class SearchModal extends StatefulWidget {
  const SearchModal({super.key});

  @override
  State<SearchModal> createState() => _SearchModalState();
}

class _SearchModalState extends State<SearchModal> {
  final FocusNode _mainFocusNode = FocusNode();
  final FocusNode _textFieldFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  
  Timer? _debounceTimer;
  int _focusSection = 0; // 0 = campo de texto, 1 = resultados, 2 = botão fechar
  int _selectedResultIndex = 0;
  bool _isSearching = false;
  List<CatalogDisplayItem> _results = [];
  String _lastQuery = '';
  
  // Layout
  static const int _columnsPerRow = 5;
  static const double _cardWidth = 140.0;
  static const double _cardHeight = 210.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
      _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mainFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _lastQuery = '';
        _isSearching = false;
      });
      return;
    }
    
    if (query == _lastQuery) return;
    
    setState(() => _isSearching = true);
    
    // Debounce de 300ms para não sobrecarregar
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    try {
      // Busca global em todas as categorias
      await provider.performGlobalSearch(query);
      
      if (!mounted) return;
      
      // Obtém os resultados do provider
      final items = provider.displayItems;
      
      setState(() {
        _results = items.take(50).toList(); // Limita a 50 resultados
        _lastQuery = query;
        _isSearching = false;
        _selectedResultIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    final key = event.logicalKey;
    
    // Escape/Voltar sempre fecha
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      _closeModal();
      return KeyEventResult.handled;
    }
    
    switch (_focusSection) {
      case 0: // Campo de texto
        return _handleTextFieldNavigation(key);
      case 1: // Resultados
        return _handleResultsNavigation(key);
      case 2: // Botão fechar
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _closeModal();
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowDown) {
          setState(() => _focusSection = 0);
          _textFieldFocusNode.requestFocus();
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          setState(() => _focusSection = 0);
          _textFieldFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        break;
    }
    
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTextFieldNavigation(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_results.isNotEmpty) {
        setState(() {
          _focusSection = 1;
          _selectedResultIndex = 0;
        });
        // Remove foco do TextField
        _textFieldFocusNode.unfocus();
      }
      // Sempre handled para não ter comportamento estranho no D-PAD
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusSection = 2);
      _textFieldFocusNode.unfocus();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      // Se estiver no fim do texto, vai para o botão fechar
      if (_searchController.selection.baseOffset >= _searchController.text.length) {
        setState(() => _focusSection = 2);
        _textFieldFocusNode.unfocus();
        return KeyEventResult.handled;
      }
      // Permite navegação dentro do texto
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      // Permite navegação dentro do texto
      return KeyEventResult.ignored;
    }
    
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultsNavigation(LogicalKeyboardKey key) {
    final totalResults = _results.length;
    if (totalResults == 0) {
      setState(() => _focusSection = 0);
      _textFieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    
    final currentRow = _selectedResultIndex ~/ _columnsPerRow;
    final currentCol = _selectedResultIndex % _columnsPerRow;
    final totalRows = (totalResults / _columnsPerRow).ceil();
    
    if (key == LogicalKeyboardKey.arrowUp) {
      if (currentRow > 0) {
        setState(() {
          _selectedResultIndex -= _columnsPerRow;
          _scrollToResult(_selectedResultIndex);
        });
      } else {
        // Volta para campo de texto
        setState(() => _focusSection = 0);
        _textFieldFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (currentRow < totalRows - 1) {
        final newIndex = _selectedResultIndex + _columnsPerRow;
        if (newIndex < totalResults) {
          setState(() {
            _selectedResultIndex = newIndex;
            _scrollToResult(_selectedResultIndex);
          });
        }
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (_selectedResultIndex > 0) {
        setState(() {
          _selectedResultIndex--;
          _scrollToResult(_selectedResultIndex);
        });
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_selectedResultIndex < totalResults - 1) {
        setState(() {
          _selectedResultIndex++;
          _scrollToResult(_selectedResultIndex);
        });
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select ||
               key == LogicalKeyboardKey.enter) {
      _selectResult(_results[_selectedResultIndex]);
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }

  void _scrollToResult(int index) {
    if (!_resultsScrollController.hasClients) return;
    
    final row = index ~/ _columnsPerRow;
    final rowHeight = _cardHeight + 16;
    final targetOffset = row * rowHeight;
    final viewportHeight = _resultsScrollController.position.viewportDimension;
    
    // Centraliza a linha no viewport
    final centeredOffset = targetOffset - (viewportHeight / 2) + (rowHeight / 2);
    
    _resultsScrollController.animateTo(
      centeredOffset.clamp(0.0, _resultsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _selectResult(CatalogDisplayItem item) {
    // Limpa a busca global do provider antes de fechar
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    provider.clearSearch();
    
    Navigator.of(context).pop();
    
    // Abre o detalhe do item selecionado
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

  void _closeModal() {
    // Limpa a busca global do provider
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    provider.clearSearch();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Focus(
      focusNode: _mainFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: size.width * 0.9,
          height: size.height * 0.85,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _SearchColors.surface,
                _SearchColors.background,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _SearchColors.surfaceLight,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchField(),
              const SizedBox(height: 16),
              Expanded(child: _buildResults()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _SearchColors.surfaceElevated,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _SearchColors.accent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: _SearchColors.accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pesquisar',
                  style: TextStyle(
                    color: _SearchColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Encontre filmes e séries em todas as categorias',
                  style: TextStyle(
                    color: _SearchColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Botão fechar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _focusSection == 2
                  ? _SearchColors.accent
                  : _SearchColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focusSection == 2 ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: _focusSection == 2 ? [
                BoxShadow(
                  color: _SearchColors.accent.withOpacity(0.5),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ] : null,
            ),
            child: IconButton(
              onPressed: _closeModal,
              icon: Icon(
                Icons.close_rounded,
                color: _focusSection == 2 ? Colors.white : _SearchColors.textSecondary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _SearchColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _focusSection == 0
                ? _SearchColors.accent
                : _SearchColors.surfaceElevated,
            width: 2,
          ),
          boxShadow: _focusSection == 0 ? [
            BoxShadow(
              color: _SearchColors.accent.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _textFieldFocusNode,
          style: const TextStyle(
            color: _SearchColors.textPrimary,
            fontSize: 18,
          ),
          decoration: InputDecoration(
            hintText: 'Digite o nome do filme ou série...',
            hintStyle: TextStyle(
              color: _SearchColors.textMuted,
              fontSize: 18,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: _focusSection == 0 
                  ? _SearchColors.accent 
                  : _SearchColors.textMuted,
              size: 24,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: _SearchColors.textMuted,
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
          onChanged: _onSearchChanged,
          onTap: () {
            setState(() => _focusSection = 0);
          },
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: _SearchColors.accent,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Buscando...',
              style: TextStyle(
                color: _SearchColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 64,
              color: _SearchColors.textMuted.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Digite para pesquisar',
              style: TextStyle(
                color: _SearchColors.textMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use o teclado virtual ou controle remoto',
              style: TextStyle(
                color: _SearchColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_results.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: _SearchColors.textMuted.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum resultado para "${_searchController.text}"',
              style: const TextStyle(
                color: _SearchColors.textMuted,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tente outro termo de busca',
              style: TextStyle(
                color: _SearchColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contador de resultados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: _SearchColors.accentGold,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'RESULTADOS',
                style: TextStyle(
                  color: _SearchColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _SearchColors.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_results.length}',
                  style: TextStyle(
                    color: _SearchColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Grid de resultados
        Expanded(
          child: GridView.builder(
            controller: _resultsScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columnsPerRow,
              childAspectRatio: _cardWidth / _cardHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final item = _results[index];
              final isFocused = _focusSection == 1 && _selectedResultIndex == index;
              
              return _buildResultCard(item, isFocused, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(CatalogDisplayItem item, bool isFocused, int index) {
    return GestureDetector(
      onTap: () => _selectResult(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isFocused
            ? (Matrix4.identity()..scale(1.05))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused ? _SearchColors.accentGold : Colors.transparent,
            width: 3,
          ),
          boxShadow: isFocused ? [
            BoxShadow(
              color: _SearchColors.accentGold.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster
              item.logo != null
                  ? CachedNetworkImage(
                      imageUrl: item.logo!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _buildPlaceholder(item),
                      errorWidget: (_, __, ___) => _buildPlaceholder(item),
                      memCacheWidth: 200,
                      memCacheHeight: 300,
                    )
                  : _buildPlaceholder(item),
              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // Info
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Badge de tipo
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.type == DisplayItemType.series
                            ? Colors.blue.withOpacity(0.8)
                            : _SearchColors.accent.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.type == DisplayItemType.series ? 'SÉRIE' : 'FILME',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Nome
                    Text(
                      item.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
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

  Widget _buildPlaceholder(CatalogDisplayItem item) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _SearchColors.surfaceLight,
            _SearchColors.surface,
          ],
        ),
      ),
      child: Center(
        child: Text(
          item.initials,
          style: const TextStyle(
            color: _SearchColors.textMuted,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _SearchColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: _SearchColors.surfaceElevated,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildKeyHint('↑↓←→', 'Navegar'),
          const SizedBox(width: 20),
          _buildKeyHint('OK', 'Selecionar'),
          const SizedBox(width: 20),
          _buildKeyHint('VOLTAR', 'Fechar'),
        ],
      ),
    );
  }

  Widget _buildKeyHint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _SearchColors.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: _SearchColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _SearchColors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
