import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/movie.dart';
import '../providers/lazy_movies_provider.dart';
import '../providers/movie_favorites_provider.dart';
import '../utils/tv_constants.dart';
import '../utils/key_debouncer.dart';
import 'series_detail_modal.dart';

/// Modal completo de detalhes de filme/série com todas as informações TMDB
class MovieDetailModal extends StatefulWidget {
  final Movie movie;

  const MovieDetailModal({super.key, required this.movie});

  @override
  State<MovieDetailModal> createState() => _MovieDetailModalState();
}

class _MovieDetailModalState extends State<MovieDetailModal> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final KeyDebouncer _debouncer = KeyDebouncer();
  
  // Navegação: 0=botões, 1=elenco, 2=recomendações
  int _currentSection = 0;
  int _selectedButton = 0;
  int _selectedCastIndex = 0;
  int _selectedRecommendationIndex = 0;
  
  // Dados TMDB - sempre do JSON
  TMDBData? get _tmdb => widget.movie.tmdb;
  
  bool get _hasCast => _tmdb?.cast != null && _tmdb!.cast!.isNotEmpty;
  
  // Recomendações filtradas (só as que existem no catálogo)
  List<Recommendation> _filteredRecommendations = [];
  bool _recommendationsLoaded = false;
  
  bool get _hasRecommendations => _filteredRecommendations.isNotEmpty;

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
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isSeries = widget.movie.type == MovieType.series;
    final hasEpisodes = widget.movie.episodes != null;
    // Botões: 0=Assistir, 1=Favorito, 2=Episódios (se série), último=Fechar
    final maxButton = (isSeries && hasEpisodes) ? 3 : 2;

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
      _navigateLeft(maxButton);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      HapticFeedback.selectionClick();
      _navigateRight(maxButton);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      HapticFeedback.mediumImpact();
      _handleSelect();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
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
        // Nos botões, só faz scroll
        _scrollController.animateTo(
          (_scrollController.offset - 100).clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else if (_currentSection == 1) {
        // No elenco - navega para linha de cima ou volta para botões
        _navigateUpInCast();
      } else if (_currentSection == 2) {
        // Nas recomendações - navega para linha de cima ou volta para elenco/botões
        _navigateUpInRecommendations();
      }
    });
  }

  void _navigateDown() {
    setState(() {
      if (_currentSection == 0) {
        // Dos botões, vai para elenco (se tiver) ou recomendações (se tiver)
        if (_hasCast) {
          _currentSection = 1;
          _selectedCastIndex = 0;
          _scrollToSection(1);
        } else if (_hasRecommendations) {
          _currentSection = 2;
          _selectedRecommendationIndex = 0;
          _scrollToSection(2);
        }
      } else if (_currentSection == 1) {
        // No elenco - navega para próxima linha ou vai para recomendações
        _navigateDownInCast();
      } else {
        // Nas recomendações - navega para próxima linha ou scroll
        _navigateDownInRecommendations();
      }
    });
  }

  void _navigateLeft(int maxButton) {
    setState(() {
      if (_currentSection == 0) {
        if (_selectedButton > 0) _selectedButton--;
      } else if (_currentSection == 1) {
        // Grid 8 colunas - navega para esquerda
        if (_selectedCastIndex % 8 > 0) {
          _selectedCastIndex--;
        }
      } else if (_currentSection == 2) {
        // Grid 8 colunas - navega para esquerda
        if (_selectedRecommendationIndex % 8 > 0) {
          _selectedRecommendationIndex--;
        }
      }
    });
  }

  void _navigateRight(int maxButton) {
    setState(() {
      if (_currentSection == 0) {
        if (_selectedButton < maxButton) _selectedButton++;
      } else if (_currentSection == 1) {
        // Grid 8 colunas - navega para direita
        final maxCast = ((_tmdb?.cast?.length ?? 0).clamp(0, 16)) - 1;
        if (_selectedCastIndex < maxCast && _selectedCastIndex % 8 < 7) {
          _selectedCastIndex++;
        }
      } else if (_currentSection == 2) {
        // Grid 8 colunas - navega para direita
        final maxRec = _filteredRecommendations.length - 1;
        if (_selectedRecommendationIndex < maxRec && _selectedRecommendationIndex % 8 < 7) {
          _selectedRecommendationIndex++;
        }
      }
    });
  }
  
  void _navigateUpInCast() {
    // Navega para linha de cima no grid
    if (_selectedCastIndex >= 8) {
      setState(() => _selectedCastIndex -= 8);
    } else {
      setState(() => _currentSection = 0);
    }
  }
  
  void _navigateDownInCast() {
    final maxCast = ((_tmdb?.cast?.length ?? 0).clamp(0, 16));
    if (_selectedCastIndex + 8 < maxCast) {
      setState(() => _selectedCastIndex += 8);
    } else if (_hasRecommendations) {
      setState(() {
        _currentSection = 2;
        _selectedRecommendationIndex = 0;
        _scrollToSection(2);
      });
    }
  }
  
  void _navigateUpInRecommendations() {
    // Navega para linha de cima no grid
    if (_selectedRecommendationIndex >= 8) {
      setState(() => _selectedRecommendationIndex -= 8);
    } else if (_hasCast) {
      setState(() => _currentSection = 1);
    } else {
      setState(() => _currentSection = 0);
    }
  }
  
  void _navigateDownInRecommendations() {
    final maxRec = _filteredRecommendations.length;
    if (_selectedRecommendationIndex + 8 < maxRec) {
      setState(() => _selectedRecommendationIndex += 8);
    } else {
      _scrollController.animateTo(
        (_scrollController.offset + 100).clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToSection(int section) {
    // Scroll para mostrar a seção selecionada
    double targetOffset = 0;
    if (section == 1) targetOffset = 400; // Aproximadamente onde está o elenco
    if (section == 2) targetOffset = 600; // Aproximadamente onde estão as recomendações
    
    _scrollController.animateTo(
      targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _handleSelect() {
    // Se está na seção de elenco, abre filmografia do ator selecionado
    if (_currentSection == 1 && _hasCast) {
      final cast = _tmdb!.cast!;
      if (_selectedCastIndex >= 0 && _selectedCastIndex < cast.length) {
        _showActorFilmography(cast[_selectedCastIndex]);
      }
      return;
    }
    
    // Se está na seção de recomendações, abre o filme recomendado
    if (_currentSection == 2 && _hasRecommendations) {
      final recommendations = _tmdb!.recommendations!;
      if (_selectedRecommendationIndex >= 0 && _selectedRecommendationIndex < recommendations.length) {
        _openRecommendation(recommendations[_selectedRecommendationIndex]);
      }
      return;
    }
    
    // Seção de botões
    final isSeries = widget.movie.type == MovieType.series;
    final hasEpisodes = widget.movie.episodes != null;
    // Botões: 0=Assistir, 1=Favorito, 2=Episódios (se série), último=Fechar
    final maxButtons = isSeries && hasEpisodes ? 3 : 2;
    
    if (_selectedButton == 0) {
      // Assistir - não fecha o modal para poder voltar a ele
      Navigator.of(context).pushNamed('/movie-player', arguments: widget.movie);
    } else if (_selectedButton == 1) {
      // Favorito
      final favProvider = context.read<MovieFavoritesProvider>();
      favProvider.toggleFavorite(widget.movie);
      setState(() {}); // Atualiza UI
    } else if (_selectedButton == 2 && isSeries && hasEpisodes) {
      // Ver Episódios (só para séries) - não fecha o modal
      Navigator.of(context).pushNamed('/series-episodes', arguments: widget.movie);
    } else {
      // Fechar
      Navigator.of(context).pop();
    }
  }
  
  void _openRecommendation(Recommendation rec) async {
    // Busca o filme/série no catálogo pelo tmdbId
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final movie = await provider.findByTmdbId(rec.id);
    
    if (movie != null && mounted) {
      Navigator.of(context).pop(); // Fecha modal atual
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
    final isSeries = widget.movie.type == MovieType.series;
    
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
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Poster + Info Principal
                      _buildHeader(size, isSeries),
                      
                      const SizedBox(height: 24),
                      
                      // Botões de Ação
                      _buildActionButtons(isSeries),
                      
                      const SizedBox(height: 24),
                      
                      // Sinopse
                      _buildSynopsis(),
                      
                      // Elenco
                      if (_tmdb?.cast != null && _tmdb!.cast!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildCastSection(),
                      ],
                      
                      // Criadores (para séries)
                      if (_tmdb?.creators != null && _tmdb!.creators!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildCreatorsSection(),
                      ],
                      
                      // Recomendações
                      if (_tmdb?.recommendations != null && _tmdb!.recommendations!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildRecommendationsSection(),
                      ],
                      
                      // Keywords/Tags
                      if (_tmdb?.keywords != null && _tmdb!.keywords!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildKeywordsSection(),
                      ],
                      
                      // Informações Adicionais
                      const SizedBox(height: 24),
                      _buildAdditionalInfo(isSeries),
                      
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

  Widget _buildHeader(Size size, bool isSeries) {
    final posterWidth = size.width * 0.18;
    final posterHeight = posterWidth * 1.5;
    
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
            child: _tmdb?.poster != null
                ? CachedNetworkImage(
                    imageUrl: _tmdb!.posterHD ?? _tmdb!.poster!,
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
                  color: isSeries ? const Color(0xFF8B5CF6) : const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isSeries ? '📺 SÉRIE' : '🎬 FILME',
                  style: const TextStyle(
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
                _tmdb?.title ?? widget.movie.name,
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
                  if (_tmdb?.rating != null)
                    _buildRatingBadge(_tmdb!.rating!, _tmdb?.voteCount),
                  
                  // Ano
                  if (_tmdb?.year != null)
                    _buildInfoChip(Icons.calendar_today, _tmdb!.year!, Colors.blue),
                  
                  // Duração
                  if (_tmdb?.formattedRuntime.isNotEmpty ?? false)
                    _buildInfoChip(Icons.schedule, _tmdb!.formattedRuntime, Colors.purple),
                  
                  // Temporadas/Episódios (para séries)
                  if (isSeries) ...[
                    if (widget.movie.totalSeasons != null)
                      _buildInfoChip(Icons.folder, '${widget.movie.totalSeasons} temp.', Colors.teal),
                    if (widget.movie.totalEpisodes != null)
                      _buildInfoChip(Icons.video_library, '${widget.movie.totalEpisodes} ep.', Colors.orange),
                  ],
                  
                  // Certificação
                  if (_tmdb?.certification != null)
                    _buildCertificationBadge(_tmdb!.certification!),
                  
                  // Status
                  if (_tmdb?.status != null)
                    _buildStatusBadge(_tmdb!.status!),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Gêneros
              if (_tmdb?.genres != null && _tmdb!.genres!.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _tmdb!.genres!.map((genre) => Container(
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

  Widget _buildCertificationBadge(String cert) {
    final color = _getCertColor(cert);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        cert,
        style: TextStyle(
          color: cert == '18' ? Colors.white : Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
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
      case 'released':
        color = Colors.blue;
        label = 'Lançado';
        icon = Icons.check;
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

  Widget _buildActionButtons(bool isSeries) {
    final hasEpisodes = widget.movie.episodes != null;
    final favProvider = context.watch<MovieFavoritesProvider>();
    final isFavorite = favProvider.isFavorite(widget.movie.id);
    
    return Row(
      children: [
        // Botão Assistir
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).pushNamed('/movie-player', arguments: widget.movie);
            },
            child: _buildActionButton(
              'Assistir',
              Icons.play_arrow_rounded,
              _selectedButton == 0,
              isPrimary: true,
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Botão Favorito
        GestureDetector(
          onTap: () {
            favProvider.toggleFavorite(widget.movie);
          },
          child: _buildActionButton(
            isFavorite ? 'Favoritado' : 'Favoritar',
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            _selectedButton == 1,
            isFavorite: isFavorite,
          ),
        ),
        
        // Botão Ver Episódios (só para séries)
        if (isSeries && hasEpisodes) ...[
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushNamed('/series-episodes', arguments: widget.movie);
              },
              child: _buildActionButton(
                'Episódios',
                Icons.list,
                _selectedButton == 2,
              ),
            ),
          ),
        ],
        
        const SizedBox(width: 12),
        
        // Botão Fechar
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: _buildActionButton(
            'Fechar',
            Icons.close,
            _selectedButton == (isSeries && hasEpisodes ? 3 : 2),
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
    final overview = _tmdb?.overview ?? 'Sem descrição disponível.';
    
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
          overview,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildCastSection() {
    final isCastFocused = _currentSection == 1;
    final castList = _tmdb!.cast!.take(16).toList(); // Máximo 16 (2 linhas de 8)
    
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
                  '← → ↑ ↓ navegar  •  OK ver filmografia',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16), // Espaço extra para não cortar quando focado
        Padding(
          padding: const EdgeInsets.only(top: 8), // Padding extra em cima
          child: Wrap(
            spacing: 10,
            runSpacing: 16,
            children: List.generate(castList.length, (index) {
              final actor = castList[index];
              final isSelected = isCastFocused && _selectedCastIndex == index;
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
          width: 85,
          child: Column(
            children: [
              // Foto do ator
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
              // Nome do ator
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
              // Personagem
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

  void _showActorFilmography(CastMember actor) {
    showDialog(
      context: context,
      builder: (context) => ActorFilmographyModal(actor: actor),
    );
  }

  Widget _buildCreatorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Criadores',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _tmdb!.creators!.map((creator) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.purple.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, color: Colors.purple, size: 14),
                const SizedBox(width: 6),
                Text(
                  creator,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildRecommendationsSection() {
    final isRecFocused = _currentSection == 2;
    
    if (_filteredRecommendations.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Recomendações',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_filteredRecommendations.length} no catálogo)',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            if (isRecFocused) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '← → ↑ ↓ navegar  •  OK abrir',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
                ),
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
              final isSelected = isRecFocused && _selectedRecommendationIndex == index;
              return _buildRecommendationCard(rec, isSelected);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(Recommendation rec, bool isSelected) {
    return GestureDetector(
      onTap: () => _findAndShowRecommendation(rec),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: isSelected ? (Matrix4.identity()..scale(1.08)) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: SizedBox(
          width: 105,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              Container(
                width: 105,
                height: 145,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: const Color(0xFFFFD700), width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: isSelected 
                          ? const Color(0xFFFFD700).withOpacity(0.5)
                          : Colors.black.withOpacity(0.3),
                      blurRadius: isSelected ? 12 : 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isSelected ? 5 : 8),
                  child: rec.poster != null
                      ? CachedNetworkImage(
                          imageUrl: rec.poster!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFF333333),
                            child: const Center(
                              child: Icon(Icons.movie, color: Colors.white24, size: 30),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF333333),
                            child: const Center(
                              child: Icon(Icons.movie, color: Colors.white24, size: 30),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF333333),
                          child: const Center(
                            child: Icon(Icons.movie, color: Colors.white24, size: 30),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              // Título
              Text(
                rec.title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findAndShowRecommendation(Recommendation rec) async {
    // Busca o filme/série nos dados carregados
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    // Mostra indicador de carregamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      ),
    );
    
    try {
      // Primeiro tenta buscar pelo TMDB ID (mais preciso)
      Movie? found = await provider.findByTmdbId(rec.id);
      
      // Se não encontrou, tenta buscar todos por título (fallback)
      if (found == null) {
        final results = await provider.searchAll(rec.title, limit: 10);
        final recTitle = rec.title.toLowerCase();
        
        for (final movie in results) {
          final tmdbTitle = movie.tmdb?.title?.toLowerCase() ?? '';
          final originalTitle = movie.tmdb?.originalTitle?.toLowerCase() ?? '';
          final movieName = movie.name.toLowerCase();
          
          if (tmdbTitle == recTitle || 
              originalTitle == recTitle ||
              movieName == recTitle ||
              tmdbTitle.contains(recTitle) || 
              recTitle.contains(tmdbTitle) ||
              _similarityMatch(tmdbTitle, recTitle)) {
            found = movie;
            break;
          }
        }
      }
      
      // Fecha indicador de carregamento
      if (mounted) Navigator.of(context).pop();
      
      if (found != null && mounted) {
        Navigator.of(context).pop(); // Fecha modal atual
        showDialog(
          context: context,
          builder: (context) => MovieDetailModal(movie: found!),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rec.title} não encontrado no catálogo'),
            backgroundColor: Colors.grey[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Erro ao buscar recomendação: $e');
    }
  }
  
  /// Verifica similaridade entre duas strings (para títulos que podem ter pequenas diferenças)
  bool _similarityMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    // Remove artigos e caracteres especiais
    final cleanA = a.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\b(the|a|an|o|os|a|as|um|uma)\b', caseSensitive: false), '').trim();
    final cleanB = b.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\b(the|a|an|o|os|a|as|um|uma)\b', caseSensitive: false), '').trim();
    return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
  }

  Widget _buildKeywordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tags',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _tmdb!.keywords!.take(15).map((keyword) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '#$keyword',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 11,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildActorPlaceholder(String name) {
    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      color: const Color(0xFF333333),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildAdditionalInfo(bool isSeries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informações',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        // Grid de informações
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            // Idioma Original
            if (_tmdb?.language != null)
              _buildInfoItem('Idioma', _getLanguageName(_tmdb!.language!)),
            
            // Data de Lançamento
            if (_tmdb?.releaseDate != null)
              _buildInfoItem('Lançamento', _formatDate(_tmdb!.releaseDate!)),
            
            // Primeira exibição (séries)
            if (isSeries && _tmdb?.firstAirDate != null)
              _buildInfoItem('Estreia', _formatDate(_tmdb!.firstAirDate!)),
            
            // Última exibição (séries)
            if (isSeries && _tmdb?.lastAirDate != null)
              _buildInfoItem('Último episódio', _formatDate(_tmdb!.lastAirDate!)),
            
            // IMDB ID
            if (_tmdb?.imdbId != null)
              _buildInfoItem('IMDB', _tmdb!.imdbId!),
            
            // Popularidade
            if (_tmdb?.popularity != null && _tmdb!.popularity! > 0)
              _buildInfoItem('Popularidade', '${_tmdb!.popularity!.toStringAsFixed(0)} pts'),
            
            // Categoria
            _buildInfoItem('Categoria', widget.movie.category),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _getLanguageName(String code) {
    const languages = {
      'en': 'Inglês',
      'pt': 'Português',
      'es': 'Espanhol',
      'fr': 'Francês',
      'de': 'Alemão',
      'it': 'Italiano',
      'ja': 'Japonês',
      'ko': 'Coreano',
      'zh': 'Chinês',
      'ru': 'Russo',
      'hi': 'Hindi',
      'ar': 'Árabe',
      'tr': 'Turco',
    };
    return languages[code] ?? code.toUpperCase();
  }

  String _formatDate(String date) {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return date;
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: const Color(0xFF1a1a1a),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.movie.type == MovieType.series ? Icons.tv : Icons.movie,
            color: Colors.grey[700],
            size: 48,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.movie.name,
              style: TextStyle(color: Colors.grey[600], fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal de Filmografia do Ator
/// Mostra todos os filmes e séries onde o ator aparece no catálogo
class ActorFilmographyModal extends StatefulWidget {
  final CastMember actor;

  const ActorFilmographyModal({super.key, required this.actor});

  @override
  State<ActorFilmographyModal> createState() => _ActorFilmographyModalState();
}

class _ActorFilmographyModalState extends State<ActorFilmographyModal> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<Movie> _filmography = [];
  bool _isLoading = true;
  int _selectedIndex = 0;
  bool _closeButtonFocused = false; // Foco no botão fechar
  
  // Grid: 6 colunas para cards menores
  static const int _columns = 6;

  @override
  void initState() {
    super.initState();
    _loadFilmography();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadFilmography() async {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    final actorId = widget.actor.id;
    final actorName = widget.actor.name;
    
    debugPrint('🎭 Buscando filmografia de: $actorName (ID: $actorId)');
    
    // Primeiro tenta por ID (mais preciso), depois por nome
    List<Movie> results = await provider.findByActorId(actorId);
    
    // Se não encontrou por ID, tenta por nome
    if (results.isEmpty) {
      debugPrint('   Não encontrou por ID, tentando por nome...');
      results = await provider.findByActorName(actorName);
    }
    
    debugPrint('   Total encontrado antes de deduplicar: ${results.length}');
    
    // Remove duplicados inteligentemente:
    // 1. Usa TMDB ID quando disponível
    // 2. Para séries (episódios), agrupa pelo nome da série e pega o primeiro episódio
    // 3. Remove filmes com mesmo título
    final seenTmdbIds = <int>{};
    final seenSeriesNames = <String>{};
    final seenMovieTitles = <String>{};
    final uniqueResults = <Movie>[];
    
    for (final movie in results) {
      final tmdbId = movie.tmdb?.id;
      final isSeries = movie.type == MovieType.series;
      
      if (isSeries) {
        // Para séries, agrupa pelo nome da série (não pelo episódio)
        final seriesName = (movie.seriesName ?? movie.tmdb?.title ?? movie.name).toLowerCase().trim();
        
        // Remove sufixos de temporada/episódio para agrupar melhor
        final cleanSeriesName = seriesName
            .replaceAll(RegExp(r'\s*s\d+\s*e\d+.*', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*\(\d{4}\)'), '')
            .replaceAll(RegExp(r'\s*temporada\s*\d+.*', caseSensitive: false), '')
            .trim();
        
        if (!seenSeriesNames.contains(cleanSeriesName)) {
          seenSeriesNames.add(cleanSeriesName);
          if (tmdbId != null && tmdbId > 0) {
            seenTmdbIds.add(tmdbId);
          }
          uniqueResults.add(movie);
        }
      } else {
        // Para filmes, usa TMDB ID ou título
        final title = (movie.tmdb?.title ?? movie.name).toLowerCase().trim();
        
        if (tmdbId != null && tmdbId > 0) {
          if (!seenTmdbIds.contains(tmdbId)) {
            seenTmdbIds.add(tmdbId);
            seenMovieTitles.add(title);
            uniqueResults.add(movie);
          }
        } else {
          if (!seenMovieTitles.contains(title)) {
            seenMovieTitles.add(title);
            uniqueResults.add(movie);
          }
        }
      }
    }
    
    debugPrint('   Total após deduplicar: ${uniqueResults.length}');
    debugPrint('   Filmes: ${uniqueResults.where((m) => m.type != MovieType.series).length}');
    debugPrint('   Séries: ${uniqueResults.where((m) => m.type == MovieType.series).length}');
    
    // Ordena por ano (mais recente primeiro)
    uniqueResults.sort((a, b) {
      final yearA = int.tryParse(a.tmdb?.year ?? '0') ?? 0;
      final yearB = int.tryParse(b.tmdb?.year ?? '0') ?? 0;
      return yearB.compareTo(yearA);
    });
    
    if (mounted) {
      setState(() {
        _filmography = uniqueResults;
        _isLoading = false;
        _selectedIndex = uniqueResults.isNotEmpty ? 0 : -1;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled; // Sempre handled para não sair

    final key = event.logicalKey;
    final maxIndex = _filmography.length - 1;

    // Se está no botão fechar
    if (_closeButtonFocused) {
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_filmography.isNotEmpty) {
          setState(() {
            _closeButtonFocused = false;
            _selectedIndex = 0;
          });
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // Navegação no grid
    if (maxIndex < 0) {
      // Se não tem filmes, permite fechar
      if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
      } else if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _closeButtonFocused = true);
      }
      return KeyEventResult.handled;
    }

    // Navegação em grid: left/right = mesma linha, up/down = colunas
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_selectedIndex > 0) {
        setState(() => _selectedIndex--);
        _ensureVisible(_selectedIndex);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_selectedIndex < maxIndex) {
        setState(() => _selectedIndex++);
        _ensureVisible(_selectedIndex);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_selectedIndex >= _columns) {
        setState(() => _selectedIndex -= _columns);
        _ensureVisible(_selectedIndex);
      } else {
        // Primeira linha - vai para botão fechar
        setState(() => _closeButtonFocused = true);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final newIndex = _selectedIndex + _columns;
      if (newIndex <= maxIndex) {
        setState(() => _selectedIndex = newIndex);
        _ensureVisible(_selectedIndex);
      } else if (_selectedIndex < maxIndex) {
        // Se não pode descer uma linha completa, vai para o último
        setState(() => _selectedIndex = maxIndex);
        _ensureVisible(_selectedIndex);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < _filmography.length) {
        _openMovie(_filmography[_selectedIndex]);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled; // Sempre handled para não sair
  }

  void _ensureVisible(int index) {
    if (!_scrollController.hasClients) return;
    
    // Calcula a row do item selecionado
    final row = index ~/ _columns;
    
    // Cada card tem altura aproximada baseada no gridDelegate
    // crossAxisCount: 6, childAspectRatio: 0.65, mainAxisSpacing: 12
    // Largura disponível: (widthModal - 24px padding - 50px spacing) / 6 colunas
    // Assumindo modal de ~84% de 1280px = ~1075px, width por card ~170px
    // Altura do card = width / 0.65 = ~260px + 12px spacing = ~272px por row
    final cardHeight = 220.0; // Altura aproximada de cada linha no grid
    final targetOffset = row * cardHeight;
    
    final viewportHeight = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;
    
    // Sempre centraliza o item focado na viewport
    final centeredOffset = targetOffset - (viewportHeight / 2) + (cardHeight / 2);
    
    // Faz scroll suave para centralizar o item
    _scrollController.animateTo(
      centeredOffset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _openMovie(Movie movie) {
    Navigator.of(context).pop(); // Fecha modal de filmografia
    
    // Se for série, abre o modal de séries
    if (movie.type == MovieType.series) {
      // Busca o GroupedSeries correspondente
      final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
      provider.findGroupedSeriesByMovie(movie).then((series) {
        if (series != null) {
          showDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (context) => SeriesDetailModal(series: series),
          );
        } else {
          // Fallback: abre como filme
          showDialog(
            context: context,
            builder: (context) => MovieDetailModal(movie: movie),
          );
        }
      });
    } else {
      showDialog(
        context: context,
        builder: (context) => MovieDetailModal(movie: movie),
      );
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
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width * 0.08,
          vertical: size.height * 0.05,
        ),
        child: Container(
          width: size.width * 0.84,
          height: size.height * 0.9,
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
            child: Column(
              children: [
                // Header com info do ator
                _buildActorHeader(),
                
                // Lista de filmes
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFFE50914)),
                        )
                      : _filmography.isEmpty
                          ? _buildEmptyState()
                          : _buildFilmographyGrid(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActorHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a1a1a),
            const Color(0xFF0D0D0D),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          // Foto do ator
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE50914), width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withOpacity(0.3),
                  blurRadius: 15,
                ),
              ],
            ),
            child: ClipOval(
              child: widget.actor.photo != null
                  ? CachedNetworkImage(
                      imageUrl: widget.actor.photo!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _buildActorInitials(),
                    )
                  : _buildActorInitials(),
            ),
          ),
          
          const SizedBox(width: 20),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.actor.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_filmography.length} título${_filmography.length != 1 ? 's' : ''} no catálogo',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          
          // Botão fechar
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _closeButtonFocused 
                    ? const Color(0xFFE50914)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: _closeButtonFocused 
                    ? Border.all(color: const Color(0xFFFFD700), width: 2)
                    : null,
                boxShadow: _closeButtonFocused 
                    ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.5), blurRadius: 10)]
                    : null,
              ),
              child: Icon(Icons.close, color: Colors.white, size: _closeButtonFocused ? 28 : 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActorInitials() {
    final initials = widget.actor.name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    return Container(
      color: const Color(0xFF333333),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_filter, color: Colors.grey[700], size: 64),
          const SizedBox(height: 16),
          Text(
            'Nenhum título encontrado',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Não encontramos filmes ou séries com ${widget.actor.name} no catálogo',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilmographyGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,  // 6 colunas para cards menores
        childAspectRatio: 0.65,  // Mais quadrado
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: _filmography.length,
      itemBuilder: (context, index) {
        final movie = _filmography[index];
        final isSelected = _selectedIndex == index;
        final isSeries = movie.type == MovieType.series;
        
        return GestureDetector(
          onTap: () => _openMovie(movie),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: isSelected 
                ? (Matrix4.identity()..scale(1.08))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: isSelected
                  ? Border.all(color: const Color(0xFFFFD700), width: 2.5)
                  : null,
              boxShadow: isSelected
                  ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.5), blurRadius: 12)]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(isSelected ? 4 : 6),
                        child: movie.posterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: movie.posterUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                placeholder: (_, __) => Container(
                                  color: const Color(0xFF333333),
                                  child: const Center(
                                    child: Icon(Icons.movie, color: Colors.white24, size: 20),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: const Color(0xFF333333),
                                  child: const Center(
                                    child: Icon(Icons.movie, color: Colors.white24, size: 20),
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF333333),
                                child: const Center(
                                  child: Icon(Icons.movie, color: Colors.white24, size: 20),
                                ),
                              ),
                      ),
                      // Badge de tipo (Série/Filme)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSeries 
                                ? const Color(0xFF0077FF)
                                : const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            isSeries ? 'SÉRIE' : 'FILME',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Título (usa nome da série para séries)
                Text(
                  isSeries 
                      ? (movie.seriesName ?? movie.tmdb?.title ?? movie.name)
                      : (movie.tmdb?.title ?? movie.name),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // Ano
                if (movie.tmdb?.year != null)
                  Text(
                    movie.tmdb!.year!,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _getCharacterInMovie(Movie movie) {
    if (movie.tmdb?.cast == null) return null;
    for (final cast in movie.tmdb!.cast!) {
      if (cast.id == widget.actor.id || cast.name.toLowerCase() == widget.actor.name.toLowerCase()) {
        return cast.character;
      }
    }
    return null;
  }
}
