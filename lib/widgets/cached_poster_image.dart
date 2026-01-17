import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';

/// Widget otimizado para exibir posters com cache e lazy loading
class CachedPosterImage extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final Color fallbackColor;
  final double width;
  final double height;
  final BoxFit fit;
  
  const CachedPosterImage({
    super.key,
    required this.imageUrl,
    required this.fallbackText,
    this.fallbackColor = const Color(0xFF8B5CF6),
    this.width = 100,
    this.height = 140,
    this.fit = BoxFit.cover,
  });

  /// Factory para Movie
  factory CachedPosterImage.movie({
    Key? key,
    required Movie movie,
    double width = 100,
    double height = 140,
    BoxFit fit = BoxFit.cover,
  }) {
    return CachedPosterImage(
      key: key,
      imageUrl: movie.logo,
      fallbackText: movie.initials,
      fallbackColor: Color(MovieCategory.getColor(movie.category)),
      width: width,
      height: height,
      fit: fit,
    );
  }

  /// Factory para GroupedSeries
  factory CachedPosterImage.series({
    Key? key,
    required GroupedSeries series,
    double width = 100,
    double height = 140,
    BoxFit fit = BoxFit.cover,
  }) {
    return CachedPosterImage(
      key: key,
      imageUrl: series.logo,
      fallbackText: series.initials,
      fallbackColor: const Color(0xFF8B5CF6),
      width: width,
      height: height,
      fit: fit,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildFallback();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      // Configurações de cache e memória (ULTRA otimizado para Fire TV)
      memCacheWidth: (width * 1.5).toInt(), // Resolução mínima em RAM
      memCacheHeight: (height * 1.5).toInt(),
      maxWidthDiskCache: 300, // Limite menor no disco
      maxHeightDiskCache: 450,
      // Fade in rápido
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 100),
      // Placeholder mínimo para economizar memória
      placeholder: (context, url) => Container(color: fallbackColor.withOpacity(0.3)),
      // Erro - fallback
      errorWidget: (context, url, error) => _buildFallback(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fallbackColor.withOpacity(0.3),
            fallbackColor.withOpacity(0.1),
          ],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              fallbackColor.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fallbackColor,
            fallbackColor.withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          fallbackText,
          style: TextStyle(
            color: Colors.white,
            fontSize: (width * 0.18).clamp(12, 24),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Widget de shimmer para loading states
class ShimmerPoster extends StatelessWidget {
  final double width;
  final double height;

  const ShimmerPoster({
    super.key,
    this.width = 100,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.05),
          ],
        ),
      ),
    );
  }
}
