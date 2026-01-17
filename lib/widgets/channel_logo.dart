import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../utils/theme.dart';

/// Widget para exibir o logo de um canal
/// Suporta tanto URLs de rede quanto assets locais (prefixo 'asset:')
class ChannelLogo extends StatelessWidget {
  final Channel channel;
  final double size;
  final BoxFit fit;
  final double borderRadius;

  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = 50,
    this.fit = BoxFit.contain,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    // Se é um asset local
    if (channel.isLocalAsset) {
      return Image.asset(
        channel.assetPath,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    // Se tem logo de rede
    if (channel.logo != null && channel.logo!.isNotEmpty) {
      return Image.network(
        channel.logo!,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    // Fallback
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SaimoTheme.primary,
            SaimoTheme.primary.withOpacity(0.6),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        channel.initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Função helper para construir imagem de logo inline
/// Útil quando não se quer usar o widget completo
Widget buildChannelLogoImage(Channel channel, {BoxFit fit = BoxFit.contain, Widget Function(BuildContext, Object, StackTrace?)? errorBuilder}) {
  final fallback = errorBuilder ?? (_, __, ___) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          SaimoTheme.primary,
          SaimoTheme.primary.withOpacity(0.6),
        ],
      ),
    ),
    alignment: Alignment.center,
    child: Text(
      channel.initials,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  if (channel.isLocalAsset) {
    return Image.asset(
      channel.assetPath,
      fit: fit,
      errorBuilder: fallback,
    );
  }

  if (channel.logo != null && channel.logo!.isNotEmpty) {
    return Image.network(
      channel.logo!,
      fit: fit,
      errorBuilder: fallback,
    );
  }

  return fallback(null as dynamic, Object(), null);
}
