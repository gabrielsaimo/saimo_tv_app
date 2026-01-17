import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

/// Indicador de carregamento otimizado para TV
/// Com animação suave e mensagens de status
class TVLoadingIndicator extends StatefulWidget {
  final String? message;
  final bool showProgress;
  final double? progress;
  final Color? color;

  const TVLoadingIndicator({
    super.key,
    this.message,
    this.showProgress = false,
    this.progress,
    this.color,
  });

  @override
  State<TVLoadingIndicator> createState() => _TVLoadingIndicatorState();
}

class _TVLoadingIndicatorState extends State<TVLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );

    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SaimoTheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Indicador animado customizado
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Círculo externo girando
              RotationTransition(
                turns: _rotationAnimation,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 4,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Logo pulsante no centro
              ScaleTransition(
                scale: _pulseAnimation,
                child: Icon(
                  Icons.play_circle_filled,
                  color: color,
                  size: 28,
                ),
              ),
            ],
          ),
        ),

        if (widget.message != null) ...[
          const SizedBox(height: 24),
          Text(
            widget.message!,
            style: const TextStyle(
              fontSize: 16,
              color: SaimoTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        if (widget.showProgress && widget.progress != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: widget.progress,
                backgroundColor: SaimoTheme.surface,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(widget.progress! * 100).toInt()}%',
            style: TextStyle(
              fontSize: 14,
              color: SaimoTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Overlay de carregamento de tela cheia para TV
class TVLoadingOverlay extends StatelessWidget {
  final String? message;
  final bool visible;
  final Widget child;

  const TVLoadingOverlay({
    super.key,
    this.message,
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (visible)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: TVLoadingIndicator(message: message),
            ),
          ),
      ],
    );
  }
}

/// Placeholder de erro com retry para TV
class TVErrorWidget extends StatefulWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  const TVErrorWidget({
    super.key,
    this.title = 'Ocorreu um erro',
    this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  State<TVErrorWidget> createState() => _TVErrorWidgetState();
}

class _TVErrorWidgetState extends State<TVErrorWidget> {
  final FocusNode _retryFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focar no botão retry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _retryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone de erro
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: SaimoTheme.error.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                size: 64,
                color: SaimoTheme.error,
              ),
            ),
            const SizedBox(height: 24),

            // Título
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: SaimoTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            if (widget.message != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.message!,
                style: TextStyle(
                  fontSize: 16,
                  color: SaimoTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            if (widget.onRetry != null) ...[
              const SizedBox(height: 32),
              Focus(
                focusNode: _retryFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                       event.logicalKey == LogicalKeyboardKey.select)) {
                    widget.onRetry?.call();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      transform: Matrix4.identity()
                        ..scale(hasFocus ? 1.1 : 1.0),
                      child: ElevatedButton.icon(
                        onPressed: widget.onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasFocus
                              ? SaimoTheme.primary
                              : SaimoTheme.surface,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: hasFocus
                                  ? SaimoTheme.accent
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'Tentar Novamente',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget de "nenhum resultado" para TV
class TVEmptyWidget extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;

  const TVEmptyWidget({
    super.key,
    this.title = 'Nenhum resultado',
    this.message,
    this.icon = Icons.search_off,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 80,
              color: SaimoTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: SaimoTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 16,
                  color: SaimoTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
