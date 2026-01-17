import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

/// Widget de toast/notificação otimizado para TV
/// Aparece no canto da tela sem interromper o fluxo
class TVToast extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? iconColor;
  final Duration duration;
  final ToastPosition position;
  final VoidCallback? onDismiss;

  const TVToast({
    super.key,
    required this.message,
    this.icon,
    this.backgroundColor,
    this.iconColor,
    this.duration = const Duration(seconds: 3),
    this.position = ToastPosition.bottomCenter,
    this.onDismiss,
  });

  @override
  State<TVToast> createState() => _TVToastState();
}

enum ToastPosition {
  topCenter,
  topLeft,
  topRight,
  bottomCenter,
  bottomLeft,
  bottomRight,
}

class _TVToastState extends State<TVToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    final isTop = widget.position.name.startsWith('top');
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, isTop ? -1 : 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss?.call();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? SaimoTheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  color: widget.iconColor ?? SaimoTheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 16),
              ],
              Flexible(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    fontSize: 18,
                    color: SaimoTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gerenciador global de toasts
class TVToastManager {
  static final TVToastManager _instance = TVToastManager._();
  factory TVToastManager() => _instance;
  TVToastManager._();

  OverlayEntry? _currentToast;

  void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Color? backgroundColor,
    Color? iconColor,
    Duration duration = const Duration(seconds: 3),
    ToastPosition position = ToastPosition.bottomCenter,
  }) {
    _currentToast?.remove();

    final overlay = Overlay.of(context);

    _currentToast = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: _getLeft(position),
          right: _getRight(position),
          top: _getTop(position),
          bottom: _getBottom(position),
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: TVToast(
                message: message,
                icon: icon,
                backgroundColor: backgroundColor,
                iconColor: iconColor,
                duration: duration,
                position: position,
                onDismiss: () {
                  _currentToast?.remove();
                  _currentToast = null;
                },
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_currentToast!);
  }

  double? _getLeft(ToastPosition position) {
    switch (position) {
      case ToastPosition.topLeft:
      case ToastPosition.bottomLeft:
        return 20;
      case ToastPosition.topCenter:
      case ToastPosition.bottomCenter:
        return 20;
      default:
        return null;
    }
  }

  double? _getRight(ToastPosition position) {
    switch (position) {
      case ToastPosition.topRight:
      case ToastPosition.bottomRight:
        return 20;
      case ToastPosition.topCenter:
      case ToastPosition.bottomCenter:
        return 20;
      default:
        return null;
    }
  }

  double? _getTop(ToastPosition position) {
    switch (position) {
      case ToastPosition.topCenter:
      case ToastPosition.topLeft:
      case ToastPosition.topRight:
        return 20;
      default:
        return null;
    }
  }

  double? _getBottom(ToastPosition position) {
    switch (position) {
      case ToastPosition.bottomCenter:
      case ToastPosition.bottomLeft:
      case ToastPosition.bottomRight:
        return 20;
      default:
        return null;
    }
  }

  void dismiss() {
    _currentToast?.remove();
    _currentToast = null;
  }
}

/// Extension para mostrar toast facilmente
extension TVToastExtension on BuildContext {
  void showTVToast(
    String message, {
    IconData? icon,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 3),
    ToastPosition position = ToastPosition.bottomCenter,
  }) {
    TVToastManager().show(
      this,
      message: message,
      icon: icon,
      backgroundColor: backgroundColor,
      duration: duration,
      position: position,
    );
  }

  void showSuccessToast(String message) {
    showTVToast(
      message,
      icon: Icons.check_circle,
      backgroundColor: SaimoTheme.success.withOpacity(0.9),
    );
  }

  void showErrorToast(String message) {
    showTVToast(
      message,
      icon: Icons.error,
      backgroundColor: SaimoTheme.error.withOpacity(0.9),
    );
  }

  void showInfoToast(String message) {
    showTVToast(
      message,
      icon: Icons.info,
      backgroundColor: SaimoTheme.primary.withOpacity(0.9),
    );
  }
}
