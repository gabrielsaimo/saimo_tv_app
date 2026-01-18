import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';

/// Widget wrapper para itens focáveis otimizado para TV
/// Implementa as melhores práticas de navegação D-Pad do Android TV/Fire TV
class TVFocusWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final bool enabled;
  final double focusScale;
  final Color? focusBorderColor;
  final double borderWidth;
  final BorderRadius? borderRadius;
  final Duration animationDuration;
  final bool showFocusEffect;
  final EdgeInsets padding;

  const TVFocusWrapper({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongPress,
    this.autofocus = false,
    this.enabled = true,
    this.focusScale = TVConstants.focusScale,
    this.focusBorderColor,
    this.borderWidth = TVConstants.focusBorderWidth,
    this.borderRadius,
    this.animationDuration = TVConstants.animNormal,
    this.showFocusEffect = true,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<TVFocusWrapper> createState() => _TVFocusWrapperState();
}

class _TVFocusWrapperState extends State<TVFocusWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.focusScale,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    setState(() => _isFocused = hasFocus);
    
    if (hasFocus) {
      _animationController.forward();
      HapticFeedback.selectionClick(); // Feedback haptic ao focar
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusColor = widget.focusBorderColor ?? TVConstants.focusColor;
    final radius = widget.borderRadius ?? BorderRadius.circular(TVConstants.radiusM);

    return Focus(
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onFocusChange: _handleFocusChange,
      onKeyEvent: (node, event) {
        if (!widget.enabled) return KeyEventResult.ignored;
        
        if (event is KeyDownEvent) {
          // OK / Enter / Select
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            HapticFeedback.mediumImpact();
            widget.onSelect?.call();
            return KeyEventResult.handled;
          }
          
          // Long press com Menu
          if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
              event.logicalKey == LogicalKeyboardKey.gameButtonX) {
            HapticFeedback.heavyImpact();
            widget.onLongPress?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.enabled ? widget.onSelect : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: TVAnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: widget.showFocusEffect ? _scaleAnimation.value : 1.0,
              child: AnimatedContainer(
                duration: widget.animationDuration,
                padding: widget.padding,
                decoration: widget.showFocusEffect ? BoxDecoration(
                  borderRadius: radius,
                  border: _isFocused
                      ? Border.all(color: focusColor, width: widget.borderWidth)
                      : Border.all(color: Colors.transparent, width: widget.borderWidth),
                  boxShadow: _isFocused
                      ? [
                          BoxShadow(
                            color: focusColor.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ) : null,
                child: widget.child,
              ),
            );
          },
        ),
      ),
    );
  }
}

// AnimatedBuilder e isTV agora são de tv_constants.dart - TVAnimatedBuilder e TVConstants.isTV()
