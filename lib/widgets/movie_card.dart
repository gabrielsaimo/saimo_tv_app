import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';

/// Card de filme/série para o catálogo
class MovieCard extends StatefulWidget {
  final Movie movie;
  final bool isFocused;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double width;
  final double height;

  const MovieCard({
    super.key,
    required this.movie,
    this.isFocused = false,
    this.onTap,
    this.onLongPress,
    this.width = 160,
    this.height = 240,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      lowerBound: 1.0,
      upperBound: 1.08,
    );
  }

  @override
  void didUpdateWidget(covariant MovieCard oldWidget) {
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
      onLongPress: widget.onLongPress,
      child: TVAnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleController.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: TVConstants.animNormal,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TVConstants.radiusM),
            border: Border.all(
              color: widget.isFocused
                  ? TVConstants.focusColor
                  : Colors.transparent,
              width: widget.isFocused ? TVConstants.focusBorderWidth : 0,
            ),
            boxShadow: widget.isFocused
                ? [
                    BoxShadow(
                      color: TVConstants.focusColor.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isFocused ? 9 : 12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Imagem de fundo
                _buildPoster(),

                // Gradiente inferior
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.height * 0.5,
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

                // Informações
                Positioned(
                  bottom: TVConstants.paddingS,
                  left: TVConstants.paddingS,
                  right: TVConstants.paddingS,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Rating TMDB e Ano
                      if (widget.movie.rating != null || widget.movie.year != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              if (widget.movie.rating != null) ...[
                                const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: TVConstants.fontS,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.movie.ratingText,
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: TVConstants.fontXS,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (widget.movie.year != null)
                                Text(
                                  widget.movie.year!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
                                    fontSize: TVConstants.fontXS,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      
                      // Título
                      Text(
                        widget.movie.seriesName ?? widget.movie.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: TVConstants.fontS,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      
                      // Tag de episódio ou categoria
                      Row(
                        children: [
                          if (widget.movie.episodeTag != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: TVConstants.paddingS,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: SaimoTheme.primary,
                                borderRadius: BorderRadius.circular(TVConstants.radiusS),
                              ),
                              child: Text(
                                widget.movie.episodeTag!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: TVConstants.fontXS,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              widget.movie.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
                                fontSize: TVConstants.fontXS,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Badge de tipo (filme/série)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: widget.movie.type == MovieType.movie
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.movie.type == MovieType.movie ? '🎬' : '📺',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),

                // Badge adulto
                if (widget.movie.isAdult)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '🔞',
                        style: TextStyle(fontSize: 10),
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
    // PRIORIZA poster TMDB, depois logo original, depois fallback
    final posterUrl = widget.movie.posterUrl;

    // Se tem poster TMDB ou logo existente
    if ((widget.movie.tmdb?.poster != null && widget.movie.tmdb!.poster!.isNotEmpty) ||
        (widget.movie.logo != null && widget.movie.logo!.isNotEmpty)) {
      return CachedNetworkImage(
        imageUrl: posterUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildFallback(),
      );
    }

    return _buildFallback();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2D2D3A),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            SaimoTheme.primary.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
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
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Card de série agrupada
class SeriesCard extends StatefulWidget {
  final GroupedSeries series;
  final bool isFocused;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const SeriesCard({
    super.key,
    required this.series,
    this.isFocused = false,
    this.onTap,
    this.width = 160,
    this.height = 240,
  });

  @override
  State<SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<SeriesCard> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      lowerBound: 1.0,
      upperBound: 1.08,
    );
  }

  @override
  void didUpdateWidget(covariant SeriesCard oldWidget) {
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
      child: TVAnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleController.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: TVConstants.animNormal,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TVConstants.radiusM),
            border: Border.all(
              color: widget.isFocused
                  ? TVConstants.focusColor
                  : Colors.transparent,
              width: widget.isFocused ? TVConstants.focusBorderWidth : 0,
            ),
            boxShadow: widget.isFocused
                ? [
                    BoxShadow(
                      color: TVConstants.focusColor.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isFocused ? 9 : TVConstants.radiusM),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Imagem de fundo
                _buildPoster(),

                // Gradiente inferior
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.height * 0.55,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.95),
                        ],
                      ),
                    ),
                  ),
                ),

                // Informações
                Positioned(
                  bottom: TVConstants.paddingS,
                  left: TVConstants.paddingS,
                  right: TVConstants.paddingS,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Título
                      Text(
                        widget.series.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: TVConstants.fontS,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Temporadas e episódios
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TVConstants.paddingS,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6),
                              borderRadius: BorderRadius.circular(TVConstants.radiusS),
                            ),
                            child: Text(
                              '${widget.series.seasonCount}T',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: TVConstants.fontXS,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TVConstants.paddingS,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(TVConstants.radiusS),
                            ),
                            child: Text(
                              '${widget.series.episodeCount} eps',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: TVConstants.fontXS,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Categoria
                      Text(
                        widget.series.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
                          fontSize: TVConstants.fontXS,
                        ),
                      ),
                    ],
                  ),
                ),

                // Badge série
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('📺', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 4),
                        Text(
                          'Série',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Badge adulto
                if (widget.series.isAdult)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '🔞',
                        style: TextStyle(fontSize: 10),
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
    final logoUrl = widget.series.logoUrl;

    if (widget.series.logo != null && widget.series.logo!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: logoUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildFallback(),
      );
    }

    return _buildFallback();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2D2D3A),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(MovieCategory.getColor(widget.series.category)),
            Color(MovieCategory.getColor(widget.series.category)).withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          widget.series.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
