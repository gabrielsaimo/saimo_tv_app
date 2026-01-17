import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/movie.dart';
import '../providers/lazy_movies_provider.dart';
import 'movie_detail_modal.dart';

/// Modal completo de detalhes de série com TODOS os dados TMDB
/// Similar ao MovieDetailModal mas com seleção de temporadas/episódios
class SeriesDetailModal extends StatefulWidget {
  final GroupedSeries series;

  const SeriesDetailModal({super.key, required this.series});

  @override
  State<SeriesDetailModal> createState() => _SeriesDetailModalState();
}

class _SeriesDetailModalState extends State<SeriesDetailModal> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _episodesScrollController = ScrollController();
  
  // Navegação por seções: 0=botões, 1=temporadas, 2=episódios, 3=elenco, 4=recomendações
  int _currentSection = 0;
  int _selectedButton = 0;
  int _selectedSeasonIndex = 0;
  int _selectedEpisodeIndex = 0;
  int _selectedCastIndex = 0;
  int _selectedRecommendationIndex = 0;
  
  // TMDB data
  TMDBData? get _tmdb => widget.series.tmdb;
  
  bool get _hasCast => _tmdb?.cast != null && _tmdb!.cast!.isNotEmpty;
  
  // Recomendações filtradas (só as que existem no catálogo)
  List<Recommendation> _filteredRecommendations = [];
  bool _recommendationsLoaded = false;
  
  bool get _hasRecommendations => _filteredRecommendations.isNotEmpty;
  
  List<int> get _availableSeasons => widget.series.sortedSeasons;
  
  List<Movie> get _currentSeasonEpisodes {
    if (_availableSeasons.isEmpty) return [];
    final season = _availableSeasons[_selectedSeasonIndex];
    return widget.series.getSeasonEpisodes(season);
  }

  @override
  void initState() {
    super.initState();
    _loadFilteredRecommendations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }
  
  /// Filtra recomendações para mostrar apenas as que existem no catálogo
  Future<void> _loadFilteredRecommendations() async {
    if (_tmdb?.recommendations == null || _tmdb!.recommendations!.isEmpty) {
      setState(() => _recommendationsLoaded = true);
      return;
    }
    
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final filtered = <Recommendation>[];
    
    for (final rec in _tmdb!.recommendations!.take(20)) {
      final exists = await provider.findByTmdbId(rec.id);
      if (exists != null) {
        filtered.add(rec);
        if (filtered.length >= 16) break; // Máximo 16 (2 linhas de 8)
      }
    }
    
    if (mounted) {
      setState(() {
        _filteredRecommendations = filtered;
        _recommendationsLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _episodesScrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled; // Sempre handled para não sair

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

    return KeyEventResult.handled; // Sempre handled para não sair
  }

  void _navigateUp() {
    setState(() {
      switch (_currentSection) {
        case 0:
          _scrollUp();
          break;
        case 1:
          _currentSection = 0;
          _scrollToSection(0);
          break;
        case 2:
          if (_selectedEpisodeIndex > 0) {
            _selectedEpisodeIndex--;
            _centerEpisode(_selectedEpisodeIndex);
          } else {
            _currentSection = 1;
          }
          break;
        case 3:
          // Grid 8 colunas - navega para linha de cima ou volta para episódios
          if (_selectedCastIndex >= 8) {
            _selectedCastIndex -= 8;
          } else {
            _currentSection = 2;
            _scrollToSection(2);
          }
          break;
        case 4:
          // Grid 8 colunas - navega para linha de cima ou volta para elenco/episódios
          if (_selectedRecommendationIndex >= 8) {
            _selectedRecommendationIndex -= 8;
          } else if (_hasCast) {
            _currentSection = 3;
            _scrollToSection(3);
          } else {
            _currentSection = 2;
            _scrollToSection(2);
          }
          break;
      }
    });
  }

  void _navigateDown() {
    setState(() {
      switch (_currentSection) {
        case 0:
          _currentSection = 1;
          _selectedSeasonIndex = 0;
          _scrollToSection(1);
          break;
        case 1:
          _currentSection = 2;
          _selectedEpisodeIndex = 0;
          _scrollToSection(2);
          break;
        case 2:
          final maxEp = _currentSeasonEpisodes.length - 1;
          if (_selectedEpisodeIndex < maxEp) {
            _selectedEpisodeIndex++;
            _centerEpisode(_selectedEpisodeIndex);
          } else if (_hasCast) {
            _currentSection = 3;
            _selectedCastIndex = 0;
            _scrollToSection(3);
          } else if (_hasRecommendations) {
            _currentSection = 4;
            _selectedRecommendationIndex = 0;
            _scrollToSection(4);
          }
          break;
        case 3:
          // Grid 8 colunas - navega para próxima linha ou vai para recomendações
          final maxCast = ((_tmdb?.cast?.length ?? 0).clamp(0, 16));
          if (_selectedCastIndex + 8 < maxCast) {
            _selectedCastIndex += 8;
          } else if (_hasRecommendations) {
            _currentSection = 4;
            _selectedRecommendationIndex = 0;
            _scrollToSection(4);
          }
          break;
        case 4:
          // Grid 8 colunas - navega para próxima linha ou scroll
          final maxRec = _filteredRecommendations.length;
          if (_selectedRecommendationIndex + 8 < maxRec) {
            _selectedRecommendationIndex += 8;
          } else {
            _scrollDown();
          }
          break;
      }
    });
  }

  void _navigateLeft() {
    setState(() {
      switch (_currentSection) {
        case 0:
          if (_selectedButton > 0) _selectedButton--;
          break;
        case 1:
          if (_selectedSeasonIndex > 0) {
            _selectedSeasonIndex--;
            _selectedEpisodeIndex = 0;
          }
          break;
        case 2:
          break;
        case 3:
          // Grid 8 colunas - navega para esquerda
          if (_selectedCastIndex % 8 > 0) {
            _selectedCastIndex--;
          }
          break;
        case 4:
          // Grid 8 colunas - navega para esquerda
          if (_selectedRecommendationIndex % 8 > 0) {
            _selectedRecommendationIndex--;
          }
          break;
      }
    });
  }

  void _navigateRight() {
    setState(() {
      switch (_currentSection) {
        case 0:
          if (_selectedButton < 1) _selectedButton++;
          break;
        case 1:
          if (_selectedSeasonIndex < _availableSeasons.length - 1) {
            _selectedSeasonIndex++;
            _selectedEpisodeIndex = 0;
          }
          break;
        case 2:
          break;
        case 3:
          // Grid 8 colunas - navega para direita
          final maxCast = ((_tmdb?.cast?.length ?? 0).clamp(0, 16)) - 1;
          if (_selectedCastIndex < maxCast && _selectedCastIndex % 8 < 7) {
            _selectedCastIndex++;
          }
          break;
        case 4:
          // Grid 8 colunas - navega para direita
          final maxRec = _filteredRecommendations.length - 1;
          if (_selectedRecommendationIndex < maxRec && _selectedRecommendationIndex % 8 < 7) {
            _selectedRecommendationIndex++;
          }
          break;
      }
    });
  }

  void _handleSelect() {
    switch (_currentSection) {
      case 0:
        if (_selectedButton == 0) {
          final episodes = _currentSeasonEpisodes;
          if (episodes.isNotEmpty) {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/movie-player', arguments: episodes.first);
          }
        } else {
          Navigator.of(context).pop();
        }
        break;
      case 1:
        _currentSection = 2;
        _selectedEpisodeIndex = 0;
        break;
      case 2:
        final episodes = _currentSeasonEpisodes;
        if (_selectedEpisodeIndex < episodes.length) {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed('/movie-player', arguments: episodes[_selectedEpisodeIndex]);
        }
        break;
      case 3:
        if (_tmdb?.cast != null && _selectedCastIndex < _tmdb!.cast!.length) {
          _showActorFilmography(_tmdb!.cast![_selectedCastIndex]);
        }
        break;
      case 4:
        if (_filteredRecommendations.isNotEmpty && _selectedRecommendationIndex < _filteredRecommendations.length) {
          _openRecommendation(_filteredRecommendations[_selectedRecommendationIndex]);
        }
        break;
    }
  }

  void _scrollUp() {
    _scrollController.animateTo(
      (_scrollController.offset - 150).clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollDown() {
    _scrollController.animateTo(
      (_scrollController.offset + 150).clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollToSection(int section) {
    // Offsets aproximados baseados no conteúdo
    double offset = 0;
    switch (section) {
      case 0: offset = 0; break;        // Botões
      case 1: offset = 280; break;      // Temporadas
      case 2: offset = 340; break;      // Episódios
      case 3: offset = 550; break;      // Elenco (scroll mais para baixo)
      case 4: offset = 750; break;      // Recomendações
    }
    
    // Garantir que o scroll aconteça
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _centerEpisode(int index) {
    if (!_episodesScrollController.hasClients) return;
    final itemHeight = 60.0;
    final viewportHeight = _episodesScrollController.position.viewportDimension;
    final targetOffset = (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
    _episodesScrollController.animateTo(
      targetOffset.clamp(0, _episodesScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _showActorFilmography(CastMember actor) {
    showDialog(
      context: context,
      builder: (context) => ActorFilmographyModal(actor: actor),
    );
  }

  Future<void> _openRecommendation(Recommendation rec) async {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final movie = await provider.findByTmdbId(rec.id);
    if (movie != null && mounted) {
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (context) => MovieDetailModal(movie: movie),
      );
    }
  }

  Color _getCertColor(String? cert) {
    switch (cert) {
      case 'L': return const Color(0xFF00A651);
      case '10': return const Color(0xFF00AEEF);
      case '12': return const Color(0xFFFFCB05);
      case '14': return const Color(0xFFF58220);
      case '16': return const Color(0xFFED1C24);
      case '18': return const Color(0xFF1C1C1C);
      default: return Colors.grey;
    }
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
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: size.width * 0.92,
          height: size.height * 0.9,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (_tmdb?.backdrop != null)
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (rect) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.4),
                          Colors.white.withOpacity(0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.3, 0.6],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(
                        imageUrl: _tmdb!.backdrop!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFF0A0A0A)),
                      ),
                    ),
                  ),

                SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(size),
                      const SizedBox(height: 20),
                      _buildActionButtons(),
                      const SizedBox(height: 20),

                      if (_tmdb?.overview != null && _tmdb!.overview!.isNotEmpty) ...[
                        _buildSynopsis(),
                        const SizedBox(height: 20),
                      ],

                      _buildSeasonsSection(),
                      const SizedBox(height: 16),
                      _buildEpisodesSection(),
                      const SizedBox(height: 20),

                      if (_hasCast) ...[
                        _buildCastSection(),
                        const SizedBox(height: 20),
                      ],

                      if (_tmdb?.creators != null && _tmdb!.creators!.isNotEmpty) ...[
                        _buildCreatorsSection(),
                        const SizedBox(height: 20),
                      ],

                      if (_hasRecommendations) ...[
                        _buildRecommendationsSection(),
                        const SizedBox(height: 20),
                      ],

                      if (_tmdb?.keywords != null && _tmdb!.keywords!.isNotEmpty) ...[
                        _buildKeywordsSection(),
                        const SizedBox(height: 20),
                      ],

                      _buildAdditionalInfo(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),

                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
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

  Widget _buildHeader(Size size) {
    final posterWidth = size.width * 0.12;
    final posterHeight = posterWidth * 1.5;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: posterWidth,
          height: posterHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _tmdb?.poster != null
                ? CachedNetworkImage(
                    imageUrl: _tmdb!.poster!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.grey[900]),
                    errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                  )
                : _buildPosterPlaceholder(),
          ),
        ),
        const SizedBox(width: 20),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tmdb?.title ?? widget.series.name,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              if (_tmdb?.originalTitle != null && _tmdb!.originalTitle != _tmdb?.title) ...[
                const SizedBox(height: 4),
                Text(
                  _tmdb!.originalTitle!,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
              
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_tmdb?.rating != null)
                    _buildBadge(icon: Icons.star, text: _tmdb!.rating!.toStringAsFixed(1), color: Colors.amber),
                  if (_tmdb?.year != null)
                    _buildBadge(icon: Icons.calendar_today, text: _tmdb!.year!, color: Colors.white70),
                  _buildBadge(icon: Icons.layers, text: '${widget.series.seasonCount} temp', color: Colors.white70),
                  _buildBadge(icon: Icons.play_circle_outline, text: '${widget.series.episodeCount} ep', color: Colors.white70),
                  if (_tmdb?.certification != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getCertColor(_tmdb!.certification),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_tmdb!.certification!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              
              const SizedBox(height: 10),

              if (_tmdb?.genres != null && _tmdb!.genres!.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _tmdb!.genres!.take(5).map((genre) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  )).toList(),
                ),

              if (_tmdb?.tagline != null && _tmdb!.tagline!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '"${_tmdb!.tagline!}"',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBadge({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Text(widget.series.initials, style: const TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildActionButtons() {
    final isFocused = _currentSection == 0;

    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.play_arrow,
            label: 'Assistir',
            isSelected: isFocused && _selectedButton == 0,
          ),
        ),
        const SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.close,
          label: 'Fechar',
          isSelected: isFocused && _selectedButton == 1,
          isSecondary: true,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    bool isSecondary = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: isSecondary ? 16 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE50914) : isSecondary ? Colors.transparent : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: isSelected ? Border.all(color: const Color(0xFFFFD700), width: 2) : isSecondary ? Border.all(color: Colors.white24) : null,
        boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 10)] : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: isSecondary ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSynopsis() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sinopse', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_tmdb!.overview!, style: TextStyle(color: Colors.grey[300], fontSize: 12, height: 1.5)),
      ],
    );
  }

  Widget _buildSeasonsSection() {
    final isFocused = _currentSection == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('TEMPORADAS', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
            if (isFocused) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFD700).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('← → selecionar', style: TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableSeasons.length,
            itemBuilder: (context, index) {
              final season = _availableSeasons[index];
              final isSelected = isFocused && _selectedSeasonIndex == index;
              final isCurrent = _selectedSeasonIndex == index;
              
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isCurrent ? const Color(0xFFE50914) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: isSelected ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
                    boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 8)] : null,
                  ),
                  child: Text('T$season', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodesSection() {
    final episodes = _currentSeasonEpisodes;
    final isFocused = _currentSection == 2;
    final season = _availableSeasons.isNotEmpty ? _availableSeasons[_selectedSeasonIndex] : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Episódios da Temporada $season', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('${episodes.length} episódios', style: TextStyle(color: Colors.grey[600], fontSize: 10)),
            if (isFocused) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFD700).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('↑ ↓ navegar  •  OK assistir', style: TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(8),
            border: isFocused ? Border.all(color: Colors.white24) : null,
          ),
          child: ListView.builder(
            controller: _episodesScrollController,
            padding: const EdgeInsets.all(6),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final ep = episodes[index];
              final isSelected = isFocused && _selectedEpisodeIndex == index;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFE50914) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: isSelected ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(child: Text('${ep.episode ?? index + 1}', style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(ep.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (isSelected) const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCastSection() {
    final isFocused = _currentSection == 3;
    final castList = _tmdb!.cast!.take(16).toList(); // Máximo 16 (2 linhas de 8)

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Elenco Principal', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            if (isFocused) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFD700).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('← → ↑ ↓ navegar  •  OK ver filmografia', style: TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16), // Espaço extra para não cortar quando focado
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 16,
            children: List.generate(castList.length, (index) {
              final actor = castList[index];
              final isSelected = isFocused && _selectedCastIndex == index;
              return _buildCastCard(actor, isSelected);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildCastCard(CastMember actor, bool isSelected) {
    return GestureDetector(
      onTap: () => _showActorFilmography(actor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: isSelected ? (Matrix4.identity()..scale(1.08)) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: SizedBox(
          width: 80,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: isSelected ? const Color(0xFFFFD700) : Colors.white24, width: isSelected ? 2.5 : 2),
                  boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.5), blurRadius: 10)] : null,
                ),
                child: ClipOval(
                  child: actor.photo != null
                      ? CachedNetworkImage(imageUrl: actor.photo!, fit: BoxFit.cover, placeholder: (_, __) => _buildActorPlaceholder(actor.name), errorWidget: (_, __, ___) => _buildActorPlaceholder(actor.name))
                      : _buildActorPlaceholder(actor.name),
                ),
              ),
              const SizedBox(height: 6),
              Text(actor.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 9, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (actor.character != null) Text(actor.character!, style: TextStyle(color: Colors.grey[600], fontSize: 8), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActorPlaceholder(String name) {
    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(color: Colors.grey[800], child: Center(child: Text(initials, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold))));
  }

  Widget _buildCreatorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Criado por', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _tmdb!.creators!.map((creator) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)),
            child: Text(creator, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildRecommendationsSection() {
    final isFocused = _currentSection == 4;
    
    if (_filteredRecommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Recomendações', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(
              '(${_filteredRecommendations.length} no catálogo)',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            if (isFocused) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFD700).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('← → ↑ ↓ navegar  •  OK abrir', style: TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 16,
            children: List.generate(_filteredRecommendations.length, (index) {
              final rec = _filteredRecommendations[index];
              final isSelected = isFocused && _selectedRecommendationIndex == index;
              return _buildRecommendationCard(rec, isSelected);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(Recommendation rec, bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      transform: isSelected ? (Matrix4.identity()..scale(1.08)) : Matrix4.identity(),
      transformAlignment: Alignment.center,
      child: SizedBox(
        width: 95,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 95,
              height: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: isSelected ? Border.all(color: const Color(0xFFFFD700), width: 2.5) : null,
                boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.5), blurRadius: 10)] : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isSelected ? 4 : 6),
                child: rec.poster != null
                    ? CachedNetworkImage(imageUrl: rec.poster!, fit: BoxFit.cover, placeholder: (_, __) => Container(color: Colors.grey[900]), errorWidget: (_, __, ___) => Container(color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)))
                    : Container(color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 5),
            Text(rec.title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Palavras-chave', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _tmdb!.keywords!.take(10).map((keyword) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: Text(keyword, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildAdditionalInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Informações Adicionais', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            if (_tmdb?.status != null) _buildInfoItem('Status', _translateStatus(_tmdb!.status!)),
            if (_tmdb?.firstAirDate != null) _buildInfoItem('Estreia', _formatDate(_tmdb!.firstAirDate!)),
            if (_tmdb?.lastAirDate != null) _buildInfoItem('Último ep.', _formatDate(_tmdb!.lastAirDate!)),
            if (_tmdb?.episodeRuntime != null) _buildInfoItem('Duração ep.', '${_tmdb!.episodeRuntime} min'),
            if (_tmdb?.language != null) _buildInfoItem('Idioma', _tmdb!.language!.toUpperCase()),
            if (_tmdb?.voteCount != null) _buildInfoItem('Votos', _formatNumber(_tmdb!.voteCount!)),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _translateStatus(String status) {
    switch (status.toLowerCase()) {
      case 'returning series': return 'Em exibição';
      case 'ended': return 'Finalizada';
      case 'canceled': return 'Cancelada';
      case 'in production': return 'Em produção';
      default: return status;
    }
  }

  String _formatDate(String date) {
    try {
      final parts = date.split('-');
      if (parts.length >= 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {}
    return date;
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }
}
