import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

/// Screensaver para TV - Previne burn-in em telas OLED
/// Ativa automaticamente após período de inatividade
class TVScreensaver extends StatefulWidget {
  final Duration inactivityTimeout;
  final VoidCallback onDismiss;
  final Widget child;

  const TVScreensaver({
    super.key,
    this.inactivityTimeout = const Duration(minutes: 5),
    required this.onDismiss,
    required this.child,
  });

  @override
  State<TVScreensaver> createState() => _TVScreensaverState();
}

class _TVScreensaverState extends State<TVScreensaver> {
  Timer? _inactivityTimer;
  bool _showScreensaver = false;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(widget.inactivityTimeout, () {
      if (mounted) {
        setState(() => _showScreensaver = true);
      }
    });
  }

  void _dismissScreensaver() {
    setState(() => _showScreensaver = false);
    _resetTimer();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showScreensaver ? _dismissScreensaver : _resetTimer,
      child: Focus(
        onKeyEvent: (node, event) {
          if (_showScreensaver) {
            _dismissScreensaver();
            return KeyEventResult.handled;
          }
          _resetTimer();
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            widget.child,
            if (_showScreensaver)
              const _ScreensaverOverlay(),
          ],
        ),
      ),
    );
  }
}

class _ScreensaverOverlay extends StatefulWidget {
  const _ScreensaverOverlay();

  @override
  State<_ScreensaverOverlay> createState() => _ScreensaverOverlayState();
}

class _ScreensaverOverlayState extends State<_ScreensaverOverlay>
    with TickerProviderStateMixin {
  late AnimationController _positionController;
  late AnimationController _fadeController;
  final Random _random = Random();
  
  double _xPosition = 0;
  double _yPosition = 0;
  double _xDirection = 1;
  double _yDirection = 1;
  
  Timer? _moveTimer;

  @override
  void initState() {
    super.initState();
    
    _positionController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..forward();
    
    // Inicia posição aleatória
    _xPosition = _random.nextDouble() * 0.6;
    _yPosition = _random.nextDouble() * 0.6;
    
    // Move o logo periodicamente
    _moveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _moveToNewPosition();
    });
  }

  void _moveToNewPosition() {
    setState(() {
      // Movimento suave tipo "DVD logo bounce"
      _xPosition += 0.15 * _xDirection;
      _yPosition += 0.1 * _yDirection;
      
      // Inverte direção nas bordas
      if (_xPosition <= 0 || _xPosition >= 0.7) {
        _xDirection *= -1;
        _xPosition = _xPosition.clamp(0.0, 0.7);
      }
      if (_yPosition <= 0 || _yPosition >= 0.7) {
        _yDirection *= -1;
        _yPosition = _yPosition.clamp(0.0, 0.7);
      }
    });
  }

  @override
  void dispose() {
    _positionController.dispose();
    _fadeController.dispose();
    _moveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // Logo animado
            AnimatedPositioned(
              duration: const Duration(seconds: 5),
              curve: Curves.easeInOutCubic,
              left: _xPosition * size.width,
              top: _yPosition * size.height,
              child: AnimatedBuilder(
                animation: _positionController,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.3 + 0.3 * _positionController.value,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            SaimoTheme.primary.withOpacity(0.3),
                            SaimoTheme.accent.withOpacity(0.2),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              gradient: SaimoTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              Icons.live_tv,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'SAIMO TV',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Instrução de dismiss
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Pressione qualquer tecla para voltar',
                  style: TextStyle(
                    color: SaimoTheme.textTertiary.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            
            // Relógio
            Positioned(
              top: 40,
              right: 40,
              child: StreamBuilder(
                stream: Stream.periodic(const Duration(seconds: 1)),
                builder: (context, snapshot) {
                  final now = DateTime.now();
                  final hour = now.hour.toString().padLeft(2, '0');
                  final minute = now.minute.toString().padLeft(2, '0');
                  
                  return Text(
                    '$hour:$minute',
                    style: TextStyle(
                      color: SaimoTheme.textSecondary.withOpacity(0.5),
                      fontSize: 48,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 8,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AnimatedBuilder helper
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
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
