import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import 'movie_detail_modal.dart' show ActorFilmographyModal;

/// Modal de série otimizado para TV - Layout simplificado com navegação D-PAD
/// Temporadas em grid que quebra de 10 em 10, episódios em lista vertical
class SeriesModalOptimized extends StatefulWidget {
  final GroupedSeries series;

  const SeriesModalOptimized({super.key, required this.series});

  @override
  State<SeriesModalOptimized> createState() => _SeriesModalOptimizedState();
}

class _SeriesModalOptimizedState extends State<SeriesModalOptimized> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _seasonsScrollController = ScrollController();
  final ScrollController _episodesScrollController = ScrollController();
  final ScrollController _castScrollController = ScrollController();
  
  // Navegação: 0=elenco, 1=temporadas, 2=episódios
  int _currentSection = 1; // Começa nas temporadas
  int _selectedSeasonIndex = 0;
  int _selectedEpisodeIndex = 0;
  int _selectedCastIndex = 0;
  
  // TMDB data - direto do JSON
  TMDBData? get _tmdb => widget.series.tmdb;

  List<CastMember> get _castList {
    final cast = _tmdb?.cast;
    if (cast == null || cast.isEmpty) return [];
    return cast.length > 8 ? cast.sublist(0, 8) : cast;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  List<int> get _availableSeasons => widget.series.sortedSeasons;
  
  int get _seasonRowCount => (_availableSeasons.length / 10).ceil();

  List<Movie> get _currentSeasonEpisodes {
    if (_availableSeasons.isEmpty) return [];
    final season = _availableSeasons[_selectedSeasonIndex];
    return widget.series.getSeasonEpisodes(season);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _seasonsScrollController.dispose();
    _episodesScrollController.dispose();
    _castScrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      _navigateUp();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _navigateDown();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _navigateLeft();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _navigateRight();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _handleSelect();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _navigateUp() {
    setState(() {
      if (_currentSection == 0) {
        // No elenco - não faz nada (já está no topo)
      } else if (_currentSection == 1) {
        // Nas temporadas - sobe linha (se tiver mais de 10)
        if (_selectedSeasonIndex >= 10) {
          _selectedSeasonIndex -= 10;
          _scrollToSeason(_selectedSeasonIndex);
        } else if (_castList.isNotEmpty) {
          // Vai para elenco
          _currentSection = 0;
          _selectedCastIndex = 0;
          _scrollToCast(0);
        }
      } else {
        // Nos episódios - sobe na lista
        if (_selectedEpisodeIndex > 0) {
          _selectedEpisodeIndex--;
          _scrollToEpisode(_selectedEpisodeIndex);
        } else {
          // Volta para temporadas
          _currentSection = 1;
        }
      }
    });
  }

  void _navigateDown() {
    setState(() {
      if (_currentSection == 0) {
        // No elenco - vai para temporadas
        _currentSection = 1;
        _selectedSeasonIndex = 0;
        _scrollToSeason(0);
      } else if (_currentSection == 1) {
        // Nas temporadas - desce linha ou vai para episódios
        final nextIndex = _selectedSeasonIndex + 10;
        if (nextIndex < _availableSeasons.length) {
          _selectedSeasonIndex = nextIndex;
          _scrollToSeason(_selectedSeasonIndex);
        } else {
          // Vai para episódios
          _currentSection = 2;
          _selectedEpisodeIndex = 0;
          _scrollToEpisode(0);
        }
      } else {
        // Nos episódios - desce na lista
        if (_selectedEpisodeIndex < _currentSeasonEpisodes.length - 1) {
          _selectedEpisodeIndex++;
          _scrollToEpisode(_selectedEpisodeIndex);
        }
      }
    });
  }

  void _navigateLeft() {
    setState(() {
      if (_currentSection == 0) {
        // No elenco - move para esquerda
        if (_selectedCastIndex > 0) {
          _selectedCastIndex--;
          _scrollToCast(_selectedCastIndex);
        }
      } else if (_currentSection == 1) {
        // Nas temporadas - move para esquerda
        if (_selectedSeasonIndex > 0 && _selectedSeasonIndex % 10 > 0) {
          _selectedSeasonIndex--;
        }
      } else {
        // Nos episódios - volta para temporadas
        _currentSection = 1;
      }
    });
  }

  void _navigateRight() {
    setState(() {
      if (_currentSection == 0) {
        // No elenco - move para direita
        if (_selectedCastIndex < _castList.length - 1) {
          _selectedCastIndex++;
          _scrollToCast(_selectedCastIndex);
        } else {
          // Vai para temporadas
          _currentSection = 1;
          _selectedSeasonIndex = 0;
        }
      } else if (_currentSection == 1) {
        // Nas temporadas - move para direita ou vai para episódios
        final nextIndex = _selectedSeasonIndex + 1;
        if (nextIndex < _availableSeasons.length && nextIndex % 10 != 0) {
          _selectedSeasonIndex = nextIndex;
        } else {
          // Vai para episódios
          _currentSection = 2;
          _selectedEpisodeIndex = 0;
          _scrollToEpisode(0);
        }
      }
    });
  }

  void _scrollToCast(int index) {
    if (!_castScrollController.hasClients) return;
    const itemWidth = 120.0;
    final viewportWidth = _castScrollController.position.viewportDimension;
    final itemCenter = (index * itemWidth) + (itemWidth / 2);
    final viewportCenter = viewportWidth / 2;
    final targetOffset = itemCenter - viewportCenter;
    
    _castScrollController.animateTo(
      targetOffset.clamp(0.0, _castScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _scrollToSeason(int index) {
    if (!_seasonsScrollController.hasClients) return;
    final row = index ~/ 10;
    const rowHeight = 48.0;
    _seasonsScrollController.animateTo(
      (row * rowHeight).clamp(0.0, _seasonsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _scrollToEpisode(int index) {
    if (!_episodesScrollController.hasClients) return;
    const itemHeight = 48.0;
    final viewportHeight = _episodesScrollController.position.viewportDimension;
    final itemCenter = (index * itemHeight) + (itemHeight / 2);
    final viewportCenter = viewportHeight / 2;
    final targetOffset = itemCenter - viewportCenter;
    
    _episodesScrollController.animateTo(
      targetOffset.clamp(0.0, _episodesScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _handleSelect() {
    if (_currentSection == 0) {
      // No elenco - abre filmografia do ator
      final cast = _castList;
      if (_selectedCastIndex < cast.length) {
        _showActorFilmography(cast[_selectedCastIndex]);
      }
    } else if (_currentSection == 1) {
      // Seleciona temporada e vai para episódios
      setState(() {
        _currentSection = 2;
        _selectedEpisodeIndex = 0;
      });
      _scrollToEpisode(0);
    } else {
      // Reproduz episódio
      final episodes = _currentSeasonEpisodes;
      if (_selectedEpisodeIndex < episodes.length) {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed('/movie-player', arguments: episodes[_selectedEpisodeIndex]);
      }
    }
  }

  void _showActorFilmography(CastMember actor) {
    showDialog(
      context: context,
      builder: (context) => ActorFilmographyModal(actor: actor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: size.width * 0.9,
          height: size.height * 0.85,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Lado esquerdo - Info + Temporadas
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header com poster e info
                      _buildHeader(),
                      const SizedBox(height: 12),
                      
                      // Sinopse (se tiver)
                      if (_tmdb?.overview != null && _tmdb!.overview!.isNotEmpty) ...[
                        Text(
                          _tmdb!.overview!,
                          style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // Elenco (se tiver)
                      if (_tmdb?.cast != null && _tmdb!.cast!.isNotEmpty) ...[
                        _buildCastSection(),
                        const SizedBox(height: 12),
                      ],
                      
                      // Título da seção Temporadas
                      Row(
                        children: [
                          Container(
                            width: 3,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'TEMPORADAS',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_availableSeasons.length} temporadas',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Grid de temporadas (10 por linha)
                      Expanded(
                        child: _buildSeasonsGrid(),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Divisor
              Container(width: 1, color: Colors.white10),
              
              // Lado direito - Episódios
              Expanded(
                flex: 5,
                child: _buildEpisodesPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final posterUrl = widget.series.posterUrl;
    final rating = _tmdb?.rating;
    final year = _tmdb?.year ?? _tmdb?.firstAirDate?.split('-').first;
    final genres = _tmdb?.genres;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Poster
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 80,
            height: 120,
            child: posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 160,
                    errorWidget: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
          ),
        ),
        const SizedBox(width: 12),
        
        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              Text(
                _tmdb?.title ?? widget.series.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              
              // Stats
              Row(
                children: [
                  _buildStat(Icons.folder_rounded, '${_availableSeasons.length}'),
                  const SizedBox(width: 12),
                  _buildStat(Icons.movie_rounded, '${widget.series.episodeCount}'),
                  if (rating != null) ...[
                    const SizedBox(width: 12),
                    _buildStat(Icons.star_rounded, rating.toStringAsFixed(1), color: Colors.amber),
                  ],
                  if (year != null) ...[
                    const SizedBox(width: 12),
                    _buildStat(Icons.calendar_today, year),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              
              // Gêneros
              if (genres != null && genres.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: genres.take(3).map((g) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(g, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                  )).toList(),
                ),
            ],
          ),
        ),
        
        // Botão fechar
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildCastSection() {
    final cast = _castList;
    if (cast.isEmpty) return const SizedBox.shrink();
    
    final isCastSection = _currentSection == 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'ELENCO',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (isCastSection) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  '← → navegar | OK filmografia',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 8),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 58,
          child: ListView.builder(
            controller: _castScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            itemBuilder: (context, index) {
              final actor = cast[index];
              final isFocused = isCastSection && _selectedCastIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _showActorFilmography(actor),
                  child: _buildActorChip(actor, isFocused),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActorChip(CastMember actor, bool isFocused) {
    final hasPhoto = actor.photo != null && actor.photo!.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused ? const Color(0xFFE50914).withOpacity(0.3) : Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isFocused ? const Color(0xFFFFD700) : Colors.white10,
          width: isFocused ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CachedNetworkImage(
                imageUrl: actor.photo!,
                width: 28,
                height: 40,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 28,
                  height: 40,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.person, size: 16, color: Colors.white38),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 28,
                  height: 40,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.person, size: 16, color: Colors.white38),
                ),
              ),
            )
          else
            Container(
              width: 28,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(Icons.person, size: 16, color: Colors.white38),
            ),
          const SizedBox(width: 6),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                actor.name,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (actor.character != null)
                Text(
                  actor.character!,
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(color: color ?? Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildSeasonsGrid() {
    return ListView.builder(
      controller: _seasonsScrollController,
      itemCount: _seasonRowCount,
      itemBuilder: (context, rowIndex) {
        final startIndex = rowIndex * 10;
        final endIndex = (startIndex + 10).clamp(0, _availableSeasons.length);
        final rowSeasons = _availableSeasons.sublist(startIndex, endIndex);
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: rowSeasons.asMap().entries.map((entry) {
              final localIndex = entry.key;
              final season = entry.value;
              final globalIndex = startIndex + localIndex;
              final isSelected = _selectedSeasonIndex == globalIndex;
              final isFocused = _currentSection == 1 && isSelected;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSeasonIndex = globalIndex;
                    _selectedEpisodeIndex = 0;
                    _currentSection = 2;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 52,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB00710)])
                        : null,
                    color: isSelected ? null : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(6),
                    border: isFocused
                        ? Border.all(color: const Color(0xFFFFD700), width: 2)
                        : Border.all(color: Colors.white10),
                  ),
                  child: Center(
                    child: Text(
                      'T$season',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildEpisodesPanel() {
    final episodes = _currentSeasonEpisodes;
    final selectedSeason = _availableSeasons.isNotEmpty 
        ? _availableSeasons[_selectedSeasonIndex] 
        : 1;
    
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'TEMPORADA $selectedSeason',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${episodes.length} episódios',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        
        // Lista de episódios
        Expanded(
          child: episodes.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum episódio',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  controller: _episodesScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final isFocused = _currentSection == 2 && _selectedEpisodeIndex == index;
                    
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pushNamed('/movie-player', arguments: episode);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isFocused ? const Color(0xFFE50914) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: isFocused
                              ? Border.all(color: const Color(0xFFFFD700), width: 2)
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Número do episódio
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isFocused ? Colors.white24 : Colors.white10,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(
                                  '${episode.episode ?? index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            
                            // Nome
                            Expanded(
                              child: Text(
                                episode.name,
                                style: TextStyle(
                                  color: isFocused ? Colors.white : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            
                            // Play
                            Icon(
                              Icons.play_arrow_rounded,
                              color: isFocused ? Colors.white : Colors.white24,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        
        // Footer com dicas
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF0A0A0A),
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKeyHint('↑↓', 'Navegar'),
              const SizedBox(width: 16),
              _buildKeyHint('←→', 'Seção'),
              const SizedBox(width: 16),
              _buildKeyHint('OK', 'Assistir'),
            ],
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            key,
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Icon(Icons.tv, color: Colors.white24, size: 32),
      ),
    );
  }
}
