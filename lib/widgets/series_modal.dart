import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../utils/theme.dart';

// Cores Premium consistentes com a tela principal
class _SeriesColors {
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceLight = Color(0xFF2A2A2A);
  static const Color accent = Color(0xFFE50914); // Vermelho Netflix-style
  static const Color accentGold = Color(0xFFFFD700);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF808080);
}

/// Modal compacto para exibir temporadas e episódios de uma série
class SeriesModal extends StatefulWidget {
  final GroupedSeries series;
  final Function(Movie episode) onSelectEpisode;

  const SeriesModal({
    super.key,
    required this.series,
    required this.onSelectEpisode,
  });

  @override
  State<SeriesModal> createState() => _SeriesModalState();
}

class _SeriesModalState extends State<SeriesModal> {
  final FocusNode _focusNode = FocusNode();
  late int _selectedSeason;
  int _selectedSeasonIndex = 0; // Índice na lista de temporadas
  int _selectedEpisodeIndex = 0;
  int _focusSection = 0; // 0 = temporadas, 1 = episódios, 2 = botão fechar
  final ScrollController _seasonsScrollController = ScrollController();
  final ScrollController _episodesScrollController = ScrollController();

  // Constantes de tamanho compacto
  static const double _episodeCardWidth = 130.0;
  static const double _episodeCardHeight = 160.0;
  static const double _posterWidth = 80.0;
  static const double _posterHeight = 120.0;
  static const int _seasonsPerRow = 10; // Temporadas por linha

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.series.sortedSeasons.first;
    _selectedSeasonIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _seasonsScrollController.dispose();
    _episodesScrollController.dispose();
    super.dispose();
  }

  List<Movie> get _currentEpisodes => widget.series.getSeasonEpisodes(_selectedSeason);

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return;
    }

    switch (_focusSection) {
      case 0:
        _handleSeasonNavigation(key);
        break;
      case 1:
        _handleEpisodeNavigation(key);
        break;
      case 2:
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.gameButtonA) {
          Navigator.of(context).pop();
        } else if (key == LogicalKeyboardKey.arrowDown) {
          setState(() => _focusSection = 0);
        }
        break;
    }
  }

  void _handleSeasonNavigation(LogicalKeyboardKey key) {
    final seasons = widget.series.sortedSeasons;
    final totalSeasons = seasons.length;
    
    // Calcula posição atual na grade
    final currentRow = _selectedSeasonIndex ~/ _seasonsPerRow;
    final currentCol = _selectedSeasonIndex % _seasonsPerRow;
    final totalRows = (totalSeasons / _seasonsPerRow).ceil();
    final itemsInCurrentRow = currentRow == totalRows - 1 
        ? totalSeasons - (currentRow * _seasonsPerRow) 
        : _seasonsPerRow;
    final itemsInNextRow = currentRow + 1 < totalRows 
        ? (currentRow + 1 == totalRows - 1 
            ? totalSeasons - ((currentRow + 1) * _seasonsPerRow) 
            : _seasonsPerRow)
        : 0;

    if (key == LogicalKeyboardKey.arrowLeft) {
      // Move para esquerda na mesma linha
      if (currentCol > 0) {
        setState(() {
          _selectedSeasonIndex--;
          _selectedSeason = seasons[_selectedSeasonIndex];
          _selectedEpisodeIndex = 0;
        });
        _scrollToSeasonVisible();
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      // Move para direita na mesma linha
      if (currentCol < itemsInCurrentRow - 1) {
        setState(() {
          _selectedSeasonIndex++;
          _selectedSeason = seasons[_selectedSeasonIndex];
          _selectedEpisodeIndex = 0;
        });
        _scrollToSeasonVisible();
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      // Se tem mais linhas de temporadas abaixo
      if (currentRow < totalRows - 1) {
        // Calcula a posição na próxima linha
        final nextRowStart = (currentRow + 1) * _seasonsPerRow;
        final targetCol = currentCol.clamp(0, itemsInNextRow - 1);
        final targetIndex = nextRowStart + targetCol;
        
        setState(() {
          _selectedSeasonIndex = targetIndex.clamp(0, totalSeasons - 1);
          _selectedSeason = seasons[_selectedSeasonIndex];
          _selectedEpisodeIndex = 0;
        });
        _scrollToSeasonVisible();
        HapticFeedback.selectionClick();
      } else {
        // Última linha de temporadas, vai para episódios
        setState(() => _focusSection = 1);
        _scrollToEpisodeCenter(_selectedEpisodeIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      // Se tem mais linhas de temporadas acima
      if (currentRow > 0) {
        // Vai para linha anterior mantendo a coluna
        final prevRowStart = (currentRow - 1) * _seasonsPerRow;
        final targetIndex = prevRowStart + currentCol;
        
        setState(() {
          _selectedSeasonIndex = targetIndex;
          _selectedSeason = seasons[_selectedSeasonIndex];
          _selectedEpisodeIndex = 0;
        });
        _scrollToSeasonVisible();
        HapticFeedback.selectionClick();
      } else {
        // Primeira linha, vai para botão fechar
        setState(() => _focusSection = 2);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      // OK/Enter na temporada vai direto para os episódios
      setState(() {
        _selectedEpisodeIndex = 0;
        _focusSection = 1;
      });
      _scrollToEpisodeCenter(0);
      HapticFeedback.mediumImpact();
    }
  }

  void _scrollToSeasonVisible() {
    // Scroll automático para manter a temporada visível
    if (!_seasonsScrollController.hasClients) return;
    
    final row = _selectedSeasonIndex ~/ _seasonsPerRow;
    const rowHeight = 38.0;
    final targetOffset = row * rowHeight;
    
    _seasonsScrollController.animateTo(
      targetOffset.clamp(0.0, _seasonsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleEpisodeNavigation(LogicalKeyboardKey key) {
    final episodes = _currentEpisodes;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_selectedEpisodeIndex > 0) {
        setState(() => _selectedEpisodeIndex--);
        _scrollToEpisodeCenter(_selectedEpisodeIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_selectedEpisodeIndex < episodes.length - 1) {
        setState(() => _selectedEpisodeIndex++);
        _scrollToEpisodeCenter(_selectedEpisodeIndex);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusSection = 0);
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _playEpisode(episodes[_selectedEpisodeIndex]);
    }
  }

  void _scrollToSeasonCenter(int index) {
    if (!_seasonsScrollController.hasClients) return;
    const itemWidth = 50.0;
    final screenWidth = MediaQuery.of(context).size.width * 0.85;
    final offset = (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
    _seasonsScrollController.animateTo(
      offset.clamp(0.0, _seasonsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToEpisodeCenter(int index) {
    if (!_episodesScrollController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width * 0.85;
    final offset = (index * (_episodeCardWidth + 8)) - (screenWidth / 2) + (_episodeCardWidth / 2);
    _episodesScrollController.animateTo(
      offset.clamp(0.0, _episodesScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _playEpisode(Movie episode) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    widget.onSelectEpisode(episode);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        child: Container(
          width: size.width * 0.85,
          height: size.height * 0.75,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _SeriesColors.surface,
                _SeriesColors.background,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _SeriesColors.surfaceLight,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 40,
                spreadRadius: 10,
              ),
              BoxShadow(
                color: _SeriesColors.accent.withOpacity(0.1),
                blurRadius: 60,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildSeasonTabs(),
              Expanded(child: _buildEpisodesList()),
              _buildFooterHints(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _SeriesColors.surface.withOpacity(0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster compacto com sombra premium
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: _SeriesColors.accent.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: _posterWidth,
                height: _posterHeight,
                child: widget.series.logo != null
                    ? CachedNetworkImage(
                        imageUrl: widget.series.logoUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _buildPosterPlaceholder(),
                        errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                      )
                    : _buildPosterPlaceholder(),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Informações compactas
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome
                Text(
                  widget.series.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _SeriesColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Categoria
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _SeriesColors.accent,
                        _SeriesColors.accent.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.series.category,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Stats compactos
                Row(
                  children: [
                    _buildStat('${widget.series.seasonCount}', 'Temp.', Icons.folder_rounded),
                    const SizedBox(width: 20),
                    _buildStat('${widget.series.episodeCount}', 'Eps.', Icons.video_library_rounded),
                  ],
                ),
              ],
            ),
          ),

          // Botão fechar premium
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _focusSection == 2
                  ? _SeriesColors.accent
                  : _SeriesColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focusSection == 2 ? Colors.white : _SeriesColors.surfaceLight,
                width: 2,
              ),
              boxShadow: _focusSection == 2 ? [
                BoxShadow(
                  color: _SeriesColors.accent.withOpacity(0.5),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ] : null,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.close_rounded,
                color: _focusSection == 2 ? Colors.white : _SeriesColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _SeriesColors.surface,
            _SeriesColors.surfaceLight,
          ],
        ),
      ),
      child: Center(
        child: Text(
          widget.series.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _SeriesColors.accent, size: 14),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: _SeriesColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            color: _SeriesColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonTabs() {
    final seasons = widget.series.sortedSeasons;
    
    // Calcula quantas linhas de temporadas (10 por linha)
    final totalLines = (seasons.length / 10).ceil();
    // Altura dinâmica: cada linha tem ~38px
    final containerHeight = (totalLines * 38.0).clamp(50.0, 150.0);

    return Container(
      constraints: BoxConstraints(minHeight: 50, maxHeight: containerHeight + 30),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: _SeriesColors.accent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'TEMPORADAS',
                style: TextStyle(
                  color: _SeriesColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              // Indicador visual da temporada selecionada
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _SeriesColors.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'T$_selectedSeason selecionada',
                  style: TextStyle(
                    color: _SeriesColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Grid de temporadas - 10 por linha com quebra forçada
          Expanded(
            child: SingleChildScrollView(
              controller: _seasonsScrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildSeasonRows(seasons),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Constrói linhas de temporadas com máximo 10 por linha
  List<Widget> _buildSeasonRows(List<int> seasons) {
    final rows = <Widget>[];
    
    for (int rowIndex = 0; rowIndex < seasons.length; rowIndex += _seasonsPerRow) {
      final endIndex = (rowIndex + _seasonsPerRow).clamp(0, seasons.length);
      final rowSeasons = seasons.sublist(rowIndex, endIndex);
      
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: endIndex < seasons.length ? 6 : 0),
          child: Row(
            children: rowSeasons.asMap().entries.map((entry) {
              final colIndex = entry.key;
              final season = entry.value;
              final absoluteIndex = rowIndex + colIndex;
              final isSelected = season == _selectedSeason;
              final isFocused = _focusSection == 0 && absoluteIndex == _selectedSeasonIndex;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedSeasonIndex = absoluteIndex;
                      _selectedSeason = season;
                      _selectedEpisodeIndex = 0;
                      _focusSection = 1; // Vai para episódios ao clicar
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: isSelected ? LinearGradient(
                        colors: [_SeriesColors.accent, _SeriesColors.accent.withOpacity(0.7)],
                      ) : null,
                      color: isSelected ? null : _SeriesColors.surfaceLight.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isFocused ? Colors.white : (isSelected ? _SeriesColors.accent : Colors.transparent),
                        width: isFocused ? 3 : 2,
                      ),
                      boxShadow: isFocused
                          ? [
                              BoxShadow(
                                color: _SeriesColors.accent.withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : (isSelected ? [
                              BoxShadow(
                                color: _SeriesColors.accent.withOpacity(0.3),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ] : null),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'T$season',
                      style: TextStyle(
                        color: isSelected ? Colors.white : _SeriesColors.textSecondary,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }
    
    return rows;
  }

  Widget _buildEpisodesList() {
    final episodes = _currentEpisodes;

    if (episodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: _SeriesColors.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(
              'Nenhum episódio disponível',
              style: TextStyle(
                color: _SeriesColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: _SeriesColors.accentGold,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'EPISÓDIOS',
                style: TextStyle(
                  color: _SeriesColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _SeriesColors.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${episodes.length}',
                  style: TextStyle(
                    color: _SeriesColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              controller: _episodesScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: episodes.length,
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final isFocused = _focusSection == 1 && index == _selectedEpisodeIndex;

                return GestureDetector(
                  onTap: () => _playEpisode(episode),
                  child: _buildEpisodeCard(episode, index, isFocused),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard(Movie episode, int index, bool isFocused) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _episodeCardWidth,
      height: _episodeCardHeight,
      margin: const EdgeInsets.only(right: 10),
      transform: isFocused 
          ? (Matrix4.identity()..scale(1.05))
          : Matrix4.identity(),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: isFocused
            ? _SeriesColors.surfaceLight
            : _SeriesColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFocused ? Colors.white : _SeriesColors.surfaceLight,
          width: isFocused ? 2 : 1,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: _SeriesColors.accent.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  episode.logo != null
                      ? CachedNetworkImage(
                          imageUrl: episode.logoUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildEpisodePlaceholder(episode),
                          errorWidget: (_, __, ___) => _buildEpisodePlaceholder(episode),
                        )
                      : _buildEpisodePlaceholder(episode),

                  // Overlay de play premium
                  if (isFocused)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.black.withOpacity(0.6),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _SeriesColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _SeriesColors.accent.withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),

                  // Badge de episódio
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _SeriesColors.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'E${episode.episode ?? (index + 1)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              episode.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isFocused ? _SeriesColors.textPrimary : _SeriesColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodePlaceholder(Movie episode) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_SeriesColors.surface, _SeriesColors.surfaceLight],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_rounded,
              color: _SeriesColors.textMuted,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              'E${episode.episode ?? '?'}',
              style: TextStyle(
                color: _SeriesColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterHints() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _SeriesColors.surfaceLight, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildKeyHint('←→', 'Navegar'),
          const SizedBox(width: 20),
          _buildKeyHint('↑↓', 'Seção'),
          const SizedBox(width: 20),
          _buildKeyHint('OK', 'Play'),
          const SizedBox(width: 20),
          _buildKeyHint('⬅', 'Fechar'),
        ],
      ),
    );
  }

  Widget _buildKeyHint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _SeriesColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _SeriesColors.textMuted.withOpacity(0.3)),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: _SeriesColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: _SeriesColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
