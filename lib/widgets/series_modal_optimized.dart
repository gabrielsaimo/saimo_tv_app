import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/movie.dart';
import '../utils/tv_constants.dart';
import '../utils/key_debouncer.dart';
import '../providers/movie_favorites_provider.dart';
import '../services/storage_service.dart';
import 'movie_detail_modal.dart' show ActorFilmographyModal;

/// Modal de série otimizado para TV - Layout similar ao modal de filmes
/// Com botões de ação (Assistir, Favorito, Fechar), elenco e temporadas/episódios
class SeriesModalOptimized extends StatefulWidget {
  final GroupedSeries series;

  const SeriesModalOptimized({super.key, required this.series});

  @override
  State<SeriesModalOptimized> createState() => _SeriesModalOptimizedState();
}

class _SeriesModalOptimizedState extends State<SeriesModalOptimized> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _episodesScrollController = ScrollController();
  final KeyDebouncer _debouncer = KeyDebouncer();
  
  // Navegação: 0=botões, 1=elenco, 2=temporadas, 3=episódios
  int _currentSection = 0; // Começa nos botões
  int _selectedButton = 0; // 0=Assistir, 1=Favorito, 2=Fechar
  int _selectedSeasonIndex = 0;
  int _selectedEpisodeIndex = 0;
  int _selectedCastIndex = 0;
  
  // Histórico
  Map<String, dynamic>? _lastWatchedEpisode;
  bool _isLoadingHistory = true;
  
  // TMDB data - direto do JSON
  TMDBData? get _tmdb => widget.series.tmdb;
  
  // Tenta obter o cast do TMDB da série ou de um episódio
  List<CastMember>? get _seriesCast {
    // Primeiro tenta da série
    if (_tmdb?.cast != null && _tmdb!.cast!.isNotEmpty) {
      return _tmdb!.cast;
    }
    // Se não tem, tenta de um episódio
    for (final season in widget.series.sortedSeasons) {
      final episodes = widget.series.getSeasonEpisodes(season);
      for (final ep in episodes) {
        if (ep.tmdb?.cast != null && ep.tmdb!.cast!.isNotEmpty) {
          return ep.tmdb!.cast;
        }
      }
    }
    return null;
  }
  
  bool get _hasCast => _seriesCast != null && _seriesCast!.isNotEmpty;

  List<CastMember> get _castList {
    final cast = _seriesCast;
    if (cast == null || cast.isEmpty) return [];
    return cast.length > 16 ? cast.sublist(0, 16) : cast;
  }

  @override
  void initState() {
    super.initState();
    _checkLastWatchedEpisode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _checkLastWatchedEpisode() async {
    try {
      final storage = StorageService();
      // Tenta buscar pelo seriesName (mais confiável) ou pelo nome
      final seriesName = _tmdb?.title ?? widget.series.name;
      final history = await storage.getLastWatchedEpisode(seriesName);
      
      if (mounted) {
        setState(() {
          _lastWatchedEpisode = history;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  List<int> get _availableSeasons => widget.series.sortedSeasons;
  
  int get _seasonRowCount => (_availableSeasons.length / 10).ceil();

  List<Movie> get _currentSeasonEpisodes {
    if (_availableSeasons.isEmpty) return [];
    final season = _availableSeasons[_selectedSeasonIndex];
    return widget.series.getSeasonEpisodes(season);
  }
  
  /// Converte os episódios da série para o formato Map<String, List<Episode>>
  /// usado pelo player para navegar entre episódios
  Map<String, List<Episode>> _buildEpisodesMap() {
    final Map<String, List<Episode>> episodesMap = {};
    
    for (final season in _availableSeasons) {
      final episodes = widget.series.getSeasonEpisodes(season);
      final episodesList = episodes.map((movie) => Episode(
        id: movie.id,
        name: movie.name,
        url: movie.url,
        episode: movie.episode ?? 1,
      )).toList();
      
      episodesMap[season.toString()] = episodesList;
    }
    
    return episodesMap;
  }
  
  /// Cria um Movie enriquecido com todos os episódios da série
  /// para que o player possa navegar entre episódios
  Movie _createEnrichedEpisode(Movie episode) {
    return episode.copyWith(
      seriesName: _tmdb?.title ?? widget.series.name,
      episodes: _buildEpisodesMap(),
      tmdb: _tmdb ?? episode.tmdb,
    );
  }

  /// Retoma o último episódio assistido
  void _resumeLastEpisode() {
    if (_lastWatchedEpisode == null) return;
    
    final seasonNum = _lastWatchedEpisode!['season'] as int;
    final episodeNum = _lastWatchedEpisode!['episode'] as int;
    
    // Encontra o episódio correspondente
    final seasonEpisodes = widget.series.getSeasonEpisodes(seasonNum);
    
    Movie? targetEpisode;
    for (final ep in seasonEpisodes) {
      if (ep.episode == episodeNum) {
        targetEpisode = ep;
        break;
      }
    }
    
    if (targetEpisode != null) {
      final enrichedEpisode = _createEnrichedEpisode(targetEpisode);
      Navigator.of(context).pushNamed('/movie-player', arguments: enrichedEpisode);
    } else {
      // Fallback: tenta S1E1 se não achar
      final episodes = _currentSeasonEpisodes;
      if (episodes.isNotEmpty) {
        final enrichedEpisode = _createEnrichedEpisode(episodes.first);
        Navigator.of(context).pushNamed('/movie-player', arguments: enrichedEpisode);
      }
    }
  }
  
  // Cria um Movie com episódios para favoritar a série inteira
  Movie get _seriesAsMovie {
    // Pega o primeiro episódio da primeira temporada
    Movie? firstEpisode;
    final seasons = widget.series.sortedSeasons;
    if (seasons.isNotEmpty) {
      final episodes = widget.series.getSeasonEpisodes(seasons.first);
      if (episodes.isNotEmpty) {
        firstEpisode = episodes.first;
      }
    }
    
    return Movie(
      id: 'series_${widget.series.name.hashCode}',
      name: _tmdb?.title ?? widget.series.name,
      url: firstEpisode?.url ?? '',
      logo: widget.series.posterUrl,
      category: widget.series.category,
      type: MovieType.series,
      seriesName: _tmdb?.title ?? widget.series.name,
      tmdb: _tmdb,
      episodes: _buildEpisodesMap(), // IMPORTANTE: Inclui episódios para exibir no modal ao carregar do cache
      totalSeasons: _availableSeasons.length,
      totalEpisodes: widget.series.episodeCount,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _mainScrollController.dispose();
    _episodesScrollController.dispose();
    _debouncer.reset();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      HapticFeedback.selectionClick();
      _navigateUp();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      HapticFeedback.selectionClick();
      _navigateDown();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      HapticFeedback.selectionClick();
      _navigateLeft();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      HapticFeedback.selectionClick();
      _navigateRight();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      HapticFeedback.mediumImpact();
      _handleSelect();
      return KeyEventResult.handled;
    } else if (KeyDebouncer.isBackKey(key)) {
      if (_debouncer.shouldProcessBack()) {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _navigateUp() {
    setState(() {
      if (_currentSection == 0) {
        // Nos botões - não faz nada
      } else if (_currentSection == 1) {
        // No elenco - volta para botões
        _currentSection = 0;
        _selectedButton = 0;
      } else if (_currentSection == 2) {
        // Nas temporadas - vai para elenco/botões
        if (_hasCast) {
          _currentSection = 1;
          _selectedCastIndex = 0;
        } else {
          _currentSection = 0;
          _selectedButton = 0;
        }
      } else if (_currentSection == 3) {
        // Nos episódios - sobe na lista ou volta para temporadas
        if (_selectedEpisodeIndex > 0) {
          _selectedEpisodeIndex--;
          _scrollToEpisode(_selectedEpisodeIndex);
        } else {
          _currentSection = 2;
        }
      }
    });
    _scrollToSection(_currentSection);
  }

  void _navigateDown() {
    setState(() {
      if (_currentSection == 0) {
        // Nos botões - vai para elenco ou temporadas
        if (_hasCast) {
          _currentSection = 1;
          _selectedCastIndex = 0;
        } else {
          _currentSection = 2;
          _selectedSeasonIndex = 0;
        }
      } else if (_currentSection == 1) {
        // No elenco - vai para temporadas
        _currentSection = 2;
        _selectedSeasonIndex = 0;
        _scrollToSeason(0);
      } else if (_currentSection == 2) {
        // Nas temporadas - vai para episódios
        _currentSection = 3;
        _selectedEpisodeIndex = 0;
        _scrollToEpisode(0);
      } else if (_currentSection == 3) {
        // Nos episódios - desce na lista
        if (_selectedEpisodeIndex < _currentSeasonEpisodes.length - 1) {
          _selectedEpisodeIndex++;
          _scrollToEpisode(_selectedEpisodeIndex);
        }
      }
    });
    _scrollToSection(_currentSection);
  }

  void _navigateLeft() {
    setState(() {
      if (_currentSection == 0) {
        // Nos botões - move para esquerda
        if (_selectedButton > 0) _selectedButton--;
      } else if (_currentSection == 1) {
        // No elenco - move para esquerda
        if (_selectedCastIndex > 0) {
          _selectedCastIndex--;
        }
      } else if (_currentSection == 2) {
        // Nas temporadas - move para esquerda
        if (_selectedSeasonIndex > 0) {
          _selectedSeasonIndex--;
          _scrollToSeason(_selectedSeasonIndex);
          // Atualiza episódios da nova temporada
          _selectedEpisodeIndex = 0;
        }
      } else if (_currentSection == 3) {
        // Nos episódios - volta para temporadas
        _currentSection = 2;
      }
    });
  }

  void _navigateRight() {
    setState(() {
      if (_currentSection == 0) {
        // Nos botões - move para direita
        if (_selectedButton < 2) _selectedButton++;
      } else if (_currentSection == 1) {
        // No elenco - move para direita
        if (_selectedCastIndex < _castList.length - 1) {
          _selectedCastIndex++;
        }
      } else if (_currentSection == 2) {
        // Nas temporadas - move para direita ou vai para episódios
        if (_selectedSeasonIndex < _availableSeasons.length - 1) {
          _selectedSeasonIndex++;
          _scrollToSeason(_selectedSeasonIndex);
          // Atualiza episódios da nova temporada
          _selectedEpisodeIndex = 0;
        } else {
          // Se está na última temporada, vai para episódios
          _currentSection = 3;
          _selectedEpisodeIndex = 0;
          _scrollToEpisode(0);
        }
      }
    });
  }
  
  void _scrollToSection(int section) {
    if (!_mainScrollController.hasClients) return;
    
    // Scroll mais agressivo para garantir que episódios fiquem visíveis
    double targetOffset = 0;
    if (section == 1) targetOffset = 200; // Elenco
    if (section == 2) targetOffset = 400; // Temporadas
    if (section == 3) targetOffset = _mainScrollController.position.maxScrollExtent; // Episódios - vai até o final
    
    _mainScrollController.animateTo(
      targetOffset.clamp(0, _mainScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollToSeason(int index) {
    // Não precisa de scroll horizontal pois temporadas usam Wrap
    // Mas garante que a seção de temporadas esteja visível
    _scrollToSection(2);
  }

  void _scrollToEpisode(int index) {
    // Força scroll imediato e depois com delay para garantir
    _doEpisodeScroll(index);
    
    // Também garante que a seção de episódios esteja visível no scroll principal
    _scrollToSection(3);
    
    // Repete o scroll após um delay para garantir que o controller está ready
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _doEpisodeScroll(index);
    });
  }
  
  void _doEpisodeScroll(int index) {
    if (!_episodesScrollController.hasClients) return;
    
    try {
      // Altura de cada item de episódio (padding 12*2 + margem 2*2 + conteúdo ~24)
      const itemHeight = 56.0;
      
      final viewportHeight = _episodesScrollController.position.viewportDimension;
      final maxScroll = _episodesScrollController.position.maxScrollExtent;
      
      // Centraliza o item selecionado na viewport
      final itemCenter = (index * itemHeight) + (itemHeight / 2);
      final targetOffset = itemCenter - (viewportHeight / 2);
      
      _episodesScrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
    } catch (e) {
      debugPrint('Erro ao fazer scroll do episódio: $e');
    }
  }

  void _handleSelect() {
    if (_currentSection == 0) {
      // Nos botões
      if (_selectedButton == 0) {
        // Assistir primeiro episódio - não fecha o modal
        final episodes = _currentSeasonEpisodes;
        if (episodes.isNotEmpty) {
          final enrichedEpisode = _createEnrichedEpisode(episodes.first);
          Navigator.of(context).pushNamed('/movie-player', arguments: enrichedEpisode);
        }
      } else if (_selectedButton == 1) {
        // Favorito
        final favProvider = context.read<MovieFavoritesProvider>();
        favProvider.toggleFavorite(_seriesAsMovie);
        setState(() {});
      } else {
        // Fechar
        Navigator.of(context).pop();
      }
    } else if (_currentSection == 1) {
      // No elenco - abre filmografia do ator
      final cast = _castList;
      if (_selectedCastIndex < cast.length) {
        _showActorFilmography(cast[_selectedCastIndex]);
      }
    } else if (_currentSection == 2) {
      // Seleciona temporada e vai para episódios
      setState(() {
        _currentSection = 3;
        _selectedEpisodeIndex = 0;
      });
      _scrollToEpisode(0);
    } else if (_currentSection == 3) {
      // Reproduz episódio - não fecha o modal
      final episodes = _currentSeasonEpisodes;
      if (_selectedEpisodeIndex < episodes.length) {
        final enrichedEpisode = _createEnrichedEpisode(episodes[_selectedEpisodeIndex]);
        Navigator.of(context).pushNamed('/movie-player', arguments: enrichedEpisode);
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
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width * 0.05,
          vertical: size.height * 0.03,
        ),
        child: Container(
          width: size.width * 0.9,
          height: size.height * 0.94,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.9),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Backdrop de fundo com gradiente
                if (_tmdb?.backdrop != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: size.height * 0.45,
                    child: ShaderMask(
                      shaderCallback: (rect) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.6),
                          Colors.white.withOpacity(0.3),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(
                        imageUrl: _tmdb!.backdropHD ?? _tmdb!.backdrop!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFF1a1a1a),
                        ),
                      ),
                    ),
                  ),
                
                // Conteúdo principal com scroll
                SingleChildScrollView(
                  controller: _mainScrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Poster + Info Principal
                      _buildHeader(size),
                      
                      const SizedBox(height: 24),
                      
                      // Botões de Ação
                      _buildActionButtons(),
                      
                      const SizedBox(height: 24),
                      
                      // Sinopse
                      if (_tmdb?.overview != null && _tmdb!.overview!.isNotEmpty)
                        _buildSynopsis(),
                      
                      // Elenco
                      if (_hasCast) ...[
                        const SizedBox(height: 24),
                        _buildCastSection(),
                      ],
                      
                      // Temporadas e Episódios
                      const SizedBox(height: 24),
                      _buildSeasonsAndEpisodes(),
                      
                      // Espaço extra para scroll
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                
                // Botão de fechar
                Positioned(
                  top: 12,
                  right: 12,
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
    final posterWidth = size.width * 0.15;
    final posterHeight = posterWidth * 1.5;
    final posterUrl = widget.series.posterUrl;
    final rating = _tmdb?.rating;
    final year = _tmdb?.year ?? _tmdb?.firstAirDate?.split('-').first;
    final genres = _tmdb?.genres;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Poster
        Container(
          width: posterWidth,
          height: posterHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _buildPosterPlaceholder(),
                    errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                  )
                : _buildPosterPlaceholder(),
          ),
        ),
        
        const SizedBox(width: 24),
        
        // Info Principal
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tipo badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '📺 SÉRIE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Título
              Text(
                _tmdb?.title ?? widget.series.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              // Título Original
              if (_tmdb?.originalTitle != null && 
                  _tmdb!.originalTitle != _tmdb?.title) ...[
                const SizedBox(height: 4),
                Text(
                  _tmdb!.originalTitle!,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              
              // Tagline
              if (_tmdb?.tagline != null && _tmdb!.tagline!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '"${_tmdb!.tagline}"',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Meta Info Row
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Rating
                  if (rating != null)
                    _buildRatingBadge(rating, _tmdb?.voteCount),
                  
                  // Ano
                  if (year != null)
                    _buildInfoChip(Icons.calendar_today, year, Colors.blue),
                  
                  // Temporadas
                  _buildInfoChip(Icons.folder, '${_availableSeasons.length} temp.', Colors.teal),
                  
                  // Episódios
                  _buildInfoChip(Icons.video_library, '${widget.series.episodeCount} ep.', Colors.orange),
                  
                  // Status
                  if (_tmdb?.status != null)
                    _buildStatusBadge(_tmdb!.status!),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Gêneros
              if (genres != null && genres.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: genres.take(4).map((genre) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      genre,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  )).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingBadge(double rating, int? voteCount) {
    final color = rating >= 7.0 
        ? Colors.green 
        : rating >= 5.0 
            ? Colors.amber 
            : Colors.red;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: color, size: 18),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (voteCount != null && voteCount > 0) ...[
            const SizedBox(width: 6),
            Text(
              '(${_formatVotes(voteCount)})',
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatVotes(int votes) {
    if (votes >= 1000000) {
      return '${(votes / 1000000).toStringAsFixed(1)}M';
    } else if (votes >= 1000) {
      return '${(votes / 1000).toStringAsFixed(1)}K';
    }
    return votes.toString();
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'ended':
        color = Colors.grey;
        label = 'Finalizada';
        icon = Icons.check_circle;
        break;
      case 'returning series':
        color = Colors.green;
        label = 'Em exibição';
        icon = Icons.play_circle;
        break;
      case 'in production':
        color = Colors.orange;
        label = 'Em produção';
        icon = Icons.movie_creation;
        break;
      default:
        color = Colors.grey;
        label = status;
        icon = Icons.info;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildActionButtons() {
    final favProvider = context.watch<MovieFavoritesProvider>();
    final isFavorite = favProvider.isFavorite(_seriesAsMovie.id);
    
    // Texto do botão assistir/continuar
    String watchButtonLabel = 'Assistir';
    IconData watchButtonIcon = Icons.play_arrow_rounded;
    
    if (_lastWatchedEpisode != null) {
      final season = _lastWatchedEpisode!['season'];
      final episode = _lastWatchedEpisode!['episode'];
      watchButtonLabel = 'Continuar S${season}E$episode';
      watchButtonIcon = Icons.history_rounded;
    }
    
    return Row(
      children: [
        // Botão Assistir / Continuar
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () {
              if (_lastWatchedEpisode != null) {
                 // Continuar de onde parou
                 _resumeLastEpisode();
              } else {
                // Assistir do começo
                final episodes = _currentSeasonEpisodes;
                if (episodes.isNotEmpty) {
                  final enrichedEpisode = _createEnrichedEpisode(episodes.first);
                  Navigator.of(context).pushNamed('/movie-player', arguments: enrichedEpisode);
                }
              }
            },
            child: _buildActionButton(
              watchButtonLabel,
              watchButtonIcon,
              _currentSection == 0 && _selectedButton == 0,
              isPrimary: true,
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Botão Favorito
        Expanded(
          child: GestureDetector(
            onTap: () {
              favProvider.toggleFavorite(_seriesAsMovie);
            },
            child: _buildActionButton(
              isFavorite ? 'Favoritado' : 'Favoritar',
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              _currentSection == 0 && _selectedButton == 1,
              isFavorite: isFavorite,
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Botão Fechar
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: _buildActionButton(
            'Fechar',
            Icons.close,
            _currentSection == 0 && _selectedButton == 2,
            isSecondary: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, bool isFocused, {bool isPrimary = false, bool isSecondary = false, bool isFavorite = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: isPrimary && isFocused
            ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFFF2D2D)])
            : isFavorite && isFocused
                ? const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFFFF4081)])
                : null,
        color: isPrimary 
            ? (isFocused ? null : const Color(0xFFE50914))
            : isFavorite
                ? (isFocused ? null : const Color(0xFFE91E63).withOpacity(0.8))
                : isSecondary
                    ? (isFocused ? Colors.grey[700] : Colors.grey[850])
                    : (isFocused ? const Color(0xFF333333) : const Color(0xFF252525)),
        borderRadius: BorderRadius.circular(8),
        border: isFocused 
            ? Border.all(color: const Color(0xFFFFD700), width: 2.5) 
            : null,
        boxShadow: isFocused 
            ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 12)]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: isSecondary ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSynopsis() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sinopse',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _tmdb!.overview!,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 14,
            height: 1.6,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildCastSection() {
    final isCastFocused = _currentSection == 1;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Elenco Principal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isCastFocused) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '← → navegar  •  OK ver filmografia',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 16,
          children: List.generate(_castList.length, (index) {
            final actor = _castList[index];
            final isSelected = isCastFocused && _selectedCastIndex == index;
            return _buildCastCard(actor, isSelected);
          }),
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
          width: 85,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFFD700) : Colors.white24, 
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected 
                          ? const Color(0xFFFFD700).withOpacity(0.5) 
                          : Colors.black.withOpacity(0.3),
                      blurRadius: isSelected ? 12 : 8,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: actor.photo != null
                      ? CachedNetworkImage(
                          imageUrl: actor.photo!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildActorPlaceholder(actor.name),
                          errorWidget: (_, __, ___) => _buildActorPlaceholder(actor.name),
                        )
                      : _buildActorPlaceholder(actor.name),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                actor.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (actor.character != null)
                Text(
                  actor.character!,
                  style: TextStyle(
                    color: isSelected ? Colors.grey[400] : Colors.grey[500],
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActorPlaceholder(String name) {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonsAndEpisodes() {
    final episodes = _currentSeasonEpisodes;
    final selectedSeason = _availableSeasons.isNotEmpty 
        ? _availableSeasons[_selectedSeasonIndex] 
        : 1;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título Temporadas
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Temporadas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${_availableSeasons.length} temporadas • ${widget.series.episodeCount} episódios',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Grid de temporadas
        _buildSeasonsGrid(),
        
        const SizedBox(height: 24),
        
        // Episódios da temporada selecionada
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'TEMPORADA $selectedSeason',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${episodes.length} episódios',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            if (_currentSection == 3) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '↑ ↓ navegar  •  OK assistir',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        
        // Lista de episódios com altura fixa por item para scroll preciso
        SizedBox(
          height: 300, // Mostra ~5 episódios visíveis
          child: episodes.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum episódio disponível',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  controller: _episodesScrollController,
                  itemCount: episodes.length,
                  itemExtent: 56.0, // Altura fixa para scroll preciso
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final isFocused = _currentSection == 3 && _selectedEpisodeIndex == index;
                    
                    return GestureDetector(
                      onTap: () {
                        final enrichedEpisode = _createEnrichedEpisode(episode);
                        Navigator.of(context).pushNamed('/movie-player', arguments: enrichedEpisode);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: isFocused 
                              ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB00710)])
                              : null,
                          color: isFocused ? null : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: isFocused
                              ? Border.all(color: const Color(0xFFFFD700), width: 3)
                              : Border.all(color: Colors.transparent, width: 3),
                          boxShadow: isFocused
                              ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.6), blurRadius: 16, spreadRadius: 2)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Número do episódio com destaque
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isFocused ? Colors.white24 : Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                                border: isFocused 
                                    ? Border.all(color: Colors.white, width: 2)
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '${episode.episode ?? index + 1}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isFocused ? 16 : 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                episode.name,
                                style: TextStyle(
                                  color: isFocused ? Colors.white : Colors.white70,
                                  fontSize: 14,
                                  fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.play_arrow_rounded,
                              color: isFocused ? Colors.white : Colors.white30,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSeasonsGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_availableSeasons.length, (index) {
        final season = _availableSeasons[index];
        final isSelected = _selectedSeasonIndex == index;
        final isFocused = _currentSection == 2 && isSelected;
        
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedSeasonIndex = index;
              _selectedEpisodeIndex = 0;
              _currentSection = 3;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 60,
            height: 48,
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB00710)])
                  : null,
              color: isSelected ? null : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: isFocused
                  ? Border.all(color: const Color(0xFFFFD700), width: 2.5)
                  : Border.all(color: Colors.white10),
              boxShadow: isFocused
                  ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 8)]
                  : null,
            ),
            child: Center(
              child: Text(
                'T$season',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Icon(Icons.tv, color: Colors.white24, size: 48),
      ),
    );
  }
}
