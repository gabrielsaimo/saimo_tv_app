import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/tmdb_model.dart';
import '../services/tmdb_service.dart';

/// Modal moderno para exibir detalhes de filme/série do TMDB
/// Design inspirado em Netflix/Prime Video com todas as informações do IMDB
class TMDBDetailsModal extends StatefulWidget {
  final String title;
  final bool isSeries;
  final VoidCallback? onPlay;
  final String? existingLogo;

  const TMDBDetailsModal({
    super.key,
    required this.title,
    this.isSeries = false,
    this.onPlay,
    this.existingLogo,
  });

  /// Método estático para mostrar o modal
  static Future<void> show(
    BuildContext context, {
    required String title,
    bool isSeries = false,
    VoidCallback? onPlay,
    String? existingLogo,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return TMDBDetailsModal(
          title: title,
          isSeries: isSeries,
          onPlay: onPlay,
          existingLogo: existingLogo,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<TMDBDetailsModal> createState() => _TMDBDetailsModalState();
}

class _TMDBDetailsModalState extends State<TMDBDetailsModal>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  final TMDBService _tmdbService = TMDBService();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _castScrollController = ScrollController();

  bool _isLoading = true;
  TMDBMovie? _movie;
  TMDBSeries? _series;
  String? _error;

  // Navegação
  int _selectedSection = 0; // 0=Play, 1=Cast, 2=More
  int _castIndex = 0;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _loadDetails();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _castScrollController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    try {
      final details = await _tmdbService.getDetailsByTitle(
        widget.title,
        isSeries: widget.isSeries,
      );

      if (mounted) {
        setState(() {
          if (details is TMDBMovie) {
            _movie = details;
          } else if (details is TMDBSeries) {
            _series = details;
          } else {
            _error = 'Não foi possível encontrar informações';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar informações';
          _isLoading = false;
        });
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    // Fechar modal
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return;
    }

    // Navegação
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_selectedSection > 0) {
        setState(() => _selectedSection--);
        _scrollToSection();
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_selectedSection < 2) {
        setState(() => _selectedSection++);
        _scrollToSection();
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (_selectedSection == 1) {
        // Navegação no cast
        if (_castIndex > 0) {
          setState(() => _castIndex--);
          _scrollToCast();
          HapticFeedback.selectionClick();
        }
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_selectedSection == 1) {
        final maxCast = (_movie?.cast.length ?? _series?.cast.length ?? 1) - 1;
        if (_castIndex < maxCast) {
          setState(() => _castIndex++);
          _scrollToCast();
          HapticFeedback.selectionClick();
        }
      }
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (_selectedSection == 0 && widget.onPlay != null) {
        Navigator.of(context).pop();
        widget.onPlay!();
      }
    }
  }

  void _scrollToSection() {
    if (!_scrollController.hasClients) return;
    final offset = _selectedSection * 200.0;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToCast() {
    if (!_castScrollController.hasClients) return;
    const cardWidth = 120.0;
    final screenWidth = MediaQuery.of(context).size.width * 0.5;
    final offset = (_castIndex * cardWidth) - (screenWidth / 2) + (cardWidth / 2);
    _castScrollController.animateTo(
      offset.clamp(0.0, _castScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: Container(
          width: size.width * 0.9,
          height: size.height * 0.9,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _isLoading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : _buildContent(size),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1a1a1a),
                const Color(0xFF2a2a2a),
                const Color(0xFF1a1a1a),
              ],
              stops: [
                0.0,
                _shimmerController.value,
                1.0,
              ],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Color(0xFFE50914),
                  strokeWidth: 3,
                ),
                SizedBox(height: 20),
                Text(
                  'Carregando informações...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.white54,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          _buildRetryButton(),
        ],
      ),
    );
  }

  Widget _buildRetryButton() {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _isLoading = true;
          _error = null;
        });
        _loadDetails();
      },
      icon: const Icon(Icons.refresh),
      label: const Text('Tentar novamente'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE50914),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }

  Widget _buildContent(Size size) {
    final backdropUrl = _movie?.backdropUrl ?? _series?.backdropUrl ?? '';
    final posterUrl = _movie?.posterUrl ?? _series?.posterUrl ?? widget.existingLogo ?? '';
    final title = _movie?.title ?? _series?.name ?? widget.title;
    final rating = _movie?.formattedRating ?? _series?.formattedRating ?? '';
    final year = _movie?.releaseYear ?? _series?.firstAirYear ?? '';
    final genres = _movie?.genresString ?? _series?.genresString ?? '';
    final overview = _movie?.overview ?? _series?.overview ?? '';
    final runtime = _movie?.formattedRuntime ?? '';
    final tagline = _movie?.tagline ?? _series?.tagline ?? '';
    final voteCount = _movie?.voteCount ?? _series?.voteCount ?? 0;
    final cast = _movie?.cast ?? _series?.cast ?? [];
    final directors = _movie?.directors ?? [];
    final networks = _series?.networks ?? [];
    final seasons = _series?.numberOfSeasons;
    final episodes = _series?.numberOfEpisodes;

    return Stack(
      children: [
        // Background com backdrop
        if (backdropUrl.isNotEmpty)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: backdropUrl,
              fit: BoxFit.cover,
              color: Colors.black54,
              colorBlendMode: BlendMode.darken,
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF1a1a1a),
              ),
            ),
          ),

        // Gradiente sobre backdrop
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF141414).withOpacity(0.7),
                  const Color(0xFF141414),
                ],
                stops: const [0.0, 0.3, 0.6],
              ),
            ),
          ),
        ),

        // Gradiente lateral
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF141414),
                  const Color(0xFF141414).withOpacity(0.8),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.6],
              ),
            ),
          ),
        ),

        // Conteúdo principal
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coluna esquerda - Info
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),

                    // Tagline
                    if (tagline.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '"$tagline"',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Meta info
                    _buildMetaInfo(rating, year, runtime, genres, voteCount, seasons, episodes),

                    const SizedBox(height: 24),

                    // Botões de ação
                    _buildActionButtons(),

                    const SizedBox(height: 32),

                    // Sinopse
                    if (overview.isNotEmpty) ...[
                      const Text(
                        'Sinopse',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        overview,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 15,
                          height: 1.5,
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    // Diretores
                    if (directors.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildInfoRow('Direção', directors.take(3).join(', ')),
                    ],

                    // Networks (para séries)
                    if (networks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow('Disponível em', networks.join(', ')),
                    ],

                    const SizedBox(height: 32),

                    // Elenco
                    if (cast.isNotEmpty) ...[
                      const Text(
                        'Elenco Principal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCastList(cast),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Coluna direita - Poster
            Container(
              width: size.width * 0.25,
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Poster
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
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
                              width: size.width * 0.18,
                              height: size.width * 0.27,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFF2a2a2a),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFE50914),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                            )
                          : _buildPosterPlaceholder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Rating badge grande
                  if (rating.isNotEmpty)
                    _buildRatingBadge(double.tryParse(rating) ?? 0.0),
                ],
              ),
            ),
          ],
        ),

        // Botão fechar
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaInfo(
    String rating,
    String year,
    String runtime,
    String genres,
    int voteCount,
    int? seasons,
    int? episodes,
  ) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Rating com estrela
        if (rating.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star,
                  color: Color(0xFFFFD700),
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  rating,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (voteCount > 0) ...[
                  Text(
                    ' (${_formatVoteCount(voteCount)})',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Ano
        if (year.isNotEmpty)
          _buildMetaChip(year, Icons.calendar_today),

        // Duração ou temporadas
        if (runtime.isNotEmpty)
          _buildMetaChip(runtime, Icons.schedule)
        else if (seasons != null)
          _buildMetaChip(
            '$seasons temporada${seasons > 1 ? 's' : ''}',
            Icons.video_library,
          ),

        // Episódios
        if (episodes != null)
          _buildMetaChip('$episodes episódios', Icons.movie),

        // Gêneros
        if (genres.isNotEmpty)
          Text(
            genres,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
      ],
    );
  }

  Widget _buildMetaChip(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Botão Play
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()
            ..scale(_selectedSection == 0 ? 1.05 : 1.0),
          child: ElevatedButton.icon(
            onPressed: widget.onPlay != null
                ? () {
                    Navigator.of(context).pop();
                    widget.onPlay!();
                  }
                : null,
            icon: const Icon(Icons.play_arrow, size: 28),
            label: const Text(
              'Assistir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedSection == 0
                  ? Colors.white
                  : Colors.white.withOpacity(0.9),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: _selectedSection == 0 ? 8 : 2,
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Botão Mais Informações
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()
            ..scale(_selectedSection == 2 ? 1.05 : 1.0),
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.info_outline, size: 24),
            label: const Text(
              'Mais Info',
              style: TextStyle(fontSize: 16),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(
                color: _selectedSection == 2 ? Colors.white : Colors.white54,
                width: _selectedSection == 2 ? 2 : 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCastList(List<TMDBCastMember> cast) {
    return SizedBox(
      height: 160,
      child: ListView.builder(
        controller: _castScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: cast.length.clamp(0, 15),
        itemBuilder: (context, index) {
          final member = cast[index];
          final isSelected = _selectedSection == 1 && _castIndex == index;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 12),
            transform: Matrix4.identity()..scale(isSelected ? 1.08 : 1.0),
            child: Container(
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFE50914)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  // Foto
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    child: member.profileUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: member.profileUrl,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: const Color(0xFF2a2a2a),
                              child: const Icon(Icons.person, color: Colors.white24),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF2a2a2a),
                              child: const Icon(Icons.person, color: Colors.white24),
                            ),
                          )
                        : Container(
                            width: 96,
                            height: 96,
                            color: const Color(0xFF2a2a2a),
                            child: Center(
                              child: Text(
                                member.name.isNotEmpty ? member.name[0] : '?',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                  ),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1a1a1a),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (member.character != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            member.character!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.18,
      height: MediaQuery.of(context).size.width * 0.27,
      color: const Color(0xFF2a2a2a),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.movie, color: Colors.white24, size: 48),
          const SizedBox(height: 8),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBadge(double rating) {
    Color ratingColor;
    String ratingText;

    if (rating >= 8.0) {
      ratingColor = const Color(0xFF4CAF50);
      ratingText = 'Excelente';
    } else if (rating >= 7.0) {
      ratingColor = const Color(0xFF8BC34A);
      ratingText = 'Muito Bom';
    } else if (rating >= 6.0) {
      ratingColor = const Color(0xFFFFD700);
      ratingText = 'Bom';
    } else if (rating >= 5.0) {
      ratingColor = const Color(0xFFFF9800);
      ratingText = 'Regular';
    } else {
      ratingColor = const Color(0xFFF44336);
      ratingText = 'Fraco';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: ratingColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ratingColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, color: ratingColor, size: 28),
              const SizedBox(width: 8),
              Text(
                rating.toStringAsFixed(1),
                style: TextStyle(
                  color: ratingColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '/10',
                style: TextStyle(
                  color: ratingColor.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ratingText,
            style: TextStyle(
              color: ratingColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatVoteCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
