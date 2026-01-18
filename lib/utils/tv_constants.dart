import 'package:flutter/material.dart';

/// Constantes otimizadas para TV e navegação D-PAD
/// Baseadas nas guidelines de Android TV e Fire TV
class TVConstants {
  TVConstants._();

  // === TAMANHOS DE FONTE (mínimo legível a 3 metros) ===
  static const double fontXS = 14.0;   // Apenas para badges pequenas
  static const double fontS = 16.0;    // Mínimo recomendado
  static const double fontM = 18.0;    // Padrão para corpo
  static const double fontL = 22.0;    // Subtítulos
  static const double fontXL = 28.0;   // Títulos
  static const double fontXXL = 36.0;  // Destaque
  static const double fontHero = 48.0; // Hero/Splash

  // === TAMANHOS DE ÍCONES ===
  static const double iconXS = 16.0;   // Badges
  static const double iconS = 20.0;    // Mínimo para TV
  static const double iconM = 24.0;    // Padrão
  static const double iconL = 32.0;    // Botões de ação
  static const double iconXL = 48.0;   // Player controls
  static const double iconXXL = 56.0;  // Ícones grandes para destaque
  static const double iconHero = 64.0; // Hero/Destaque

  // === PADDING/MARGIN (áreas de toque) ===
  static const double paddingXS = 8.0;
  static const double paddingS = 12.0;
  static const double paddingM = 16.0;
  static const double paddingL = 24.0;
  static const double paddingXL = 32.0;
  
  // Área mínima clicável/focável (Android TV guidelines)
  static const double minTouchTarget = 48.0;

  // === BORDER RADIUS ===
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;

  // === TAMANHOS DE CARDS ===
  static const double cardWidthSmall = 160.0;
  static const double cardHeightSmall = 240.0;
  static const double cardWidthMedium = 200.0;
  static const double cardHeightMedium = 300.0;
  static const double cardWidthLarge = 240.0;
  static const double cardHeightLarge = 360.0;

  // === ANIMAÇÕES ===
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 200);
  static const Duration animSlow = Duration(milliseconds: 300);
  static const Duration animVerySlow = Duration(milliseconds: 500);
  static const Duration focusAnimDuration = Duration(milliseconds: 150); // Para transições de foco

  // Timeout de controles do player (8 segundos é melhor para TV)
  static const Duration playerControlsTimeout = Duration(seconds: 8);
  
  // Debounce para busca
  static const Duration searchDebounce = Duration(milliseconds: 400);

  // === FOCO ===
  static const double focusScale = 1.05;
  static const double focusBorderWidth = 3.0;
  static const Color focusColor = Color(0xFFFFD700); // Dourado - cor padrão de foco
  static const Color focusColorAlt = Color(0xFF8B5CF6); // Roxo - alternativo

  // === BREAKPOINTS DE RESOLUÇÃO ===
  static const double breakpointSD = 960.0;    // SD (até 720p)
  static const double breakpointHD = 1280.0;   // HD (720p)
  static const double breakpointFHD = 1920.0;  // Full HD (1080p)
  static const double breakpoint4K = 3840.0;   // 4K

  // === COLUNAS POR RESOLUÇÃO ===
  static int getColumnsForWidth(double width) {
    if (width >= breakpoint4K) return 10;
    if (width >= breakpointFHD) return 8;
    if (width >= breakpointHD) return 7;
    if (width >= breakpointSD) return 5;
    return 4;
  }

  // === DETECÇÃO DE TV ===
  static bool isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLargeScreen = size.shortestSide > 600;
    final isLandscape = size.width > size.height;
    final isVeryLarge = size.width >= 1280 || size.height >= 720;
    return (isLargeScreen && isLandscape) || (isVeryLarge && isLandscape);
  }

  static bool isTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide > 600 && size.shortestSide <= 900;
  }

  // === OPACIDADES ===
  static const double opacityDisabled = 0.38;
  static const double opacityMedium = 0.6;
  static const double opacityHigh = 0.87;
  static const double opacityFull = 1.0;

  // === CONTRASTE (WCAG AA) ===
  // Texto secundário deve ter no mínimo 70% de opacidade sobre fundo escuro
  static const double textSecondaryOpacity = 0.7;
  static const double textTertiaryOpacity = 0.5;
}

/// AnimatedBuilder corretamente implementado
/// Use este em vez de criar versões locais
class TVAnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const TVAnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

/// Widget de estado vazio para listas/grids
class TVEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onAction;
  final String? actionLabel;

  const TVEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TVConstants.paddingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: TVConstants.paddingL),
            Text(
              title,
              style: const TextStyle(
                fontSize: TVConstants.fontL,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: TVConstants.paddingS),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: TVConstants.fontM,
                  color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: TVConstants.paddingL),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TVConstants.paddingL,
                    vertical: TVConstants.paddingM,
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontSize: TVConstants.fontM),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget de erro com retry para TV
class TVErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  const TVErrorState({
    super.key,
    this.title = 'Ocorreu um erro',
    this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TVConstants.paddingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 80,
              color: const Color(0xFFEF4444),
            ),
            const SizedBox(height: TVConstants.paddingL),
            Text(
              title,
              style: const TextStyle(
                fontSize: TVConstants.fontL,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: TVConstants.paddingS),
              Text(
                message!,
                style: TextStyle(
                  fontSize: TVConstants.fontM,
                  color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: TVConstants.paddingL),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: TVConstants.iconM),
                label: const Text(
                  'Tentar novamente',
                  style: TextStyle(fontSize: TVConstants.fontM),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TVConstants.paddingL,
                    vertical: TVConstants.paddingM,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Indicador de carregamento padronizado
class TVLoadingState extends StatelessWidget {
  final String? message;

  const TVLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(TVConstants.focusColor),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: TVConstants.paddingL),
            Text(
              message!,
              style: TextStyle(
                fontSize: TVConstants.fontM,
                color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
