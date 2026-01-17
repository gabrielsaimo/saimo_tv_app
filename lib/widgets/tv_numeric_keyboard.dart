import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

/// Componente de teclado numérico para TV
/// Otimizado para navegação D-Pad
class TVNumericKeyboard extends StatefulWidget {
  final Function(String) onNumberPressed;
  final VoidCallback? onBackspace;
  final VoidCallback? onClear;
  final VoidCallback? onConfirm;
  final int maxLength;

  const TVNumericKeyboard({
    super.key,
    required this.onNumberPressed,
    this.onBackspace,
    this.onClear,
    this.onConfirm,
    this.maxLength = 4,
  });

  @override
  State<TVNumericKeyboard> createState() => _TVNumericKeyboardState();
}

class _TVNumericKeyboardState extends State<TVNumericKeyboard> {
  final List<FocusNode> _focusNodes = [];
  int _currentFocusIndex = 0;

  @override
  void initState() {
    super.initState();
    // 12 botões: 0-9, backspace, confirm
    for (int i = 0; i < 12; i++) {
      _focusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleKeyNavigation(KeyEvent event, int index) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final key = event.logicalKey;
    int newIndex = index;

    // Grid 3x4: colunas 0,1,2
    int row = index ~/ 3;
    int col = index % 3;

    if (key == LogicalKeyboardKey.arrowUp && row > 0) {
      newIndex = index - 3;
    } else if (key == LogicalKeyboardKey.arrowDown && row < 3) {
      newIndex = index + 3;
    } else if (key == LogicalKeyboardKey.arrowLeft && col > 0) {
      newIndex = index - 1;
    } else if (key == LogicalKeyboardKey.arrowRight && col < 2) {
      newIndex = index + 1;
    }

    if (newIndex != index && newIndex >= 0 && newIndex < 12) {
      setState(() => _currentFocusIndex = newIndex);
      _focusNodes[newIndex].requestFocus();
    }
  }

  Widget _buildKey(String label, int index, {
    VoidCallback? onTap,
    IconData? icon,
    Color? backgroundColor,
  }) {
    return Focus(
      focusNode: _focusNodes[index],
      onKeyEvent: (node, event) {
        _handleKeyNavigation(event, index);

        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: hasFocus
                    ? SaimoTheme.primary
                    : (backgroundColor ?? SaimoTheme.surface),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? SaimoTheme.accent : Colors.transparent,
                  width: 3,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: SaimoTheme.primary.withOpacity(0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: icon != null
                    ? Icon(
                        icon,
                        size: 28,
                        color: hasFocus ? Colors.white : SaimoTheme.textPrimary,
                      )
                    : Text(
                        label,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: hasFocus ? Colors.white : SaimoTheme.textPrimary,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Layout 3x4 grid
    // 1 2 3
    // 4 5 6
    // 7 8 9
    // ← 0 ✓
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['←', '0', '✓'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (row) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (col) {
            final index = row * 3 + col;
            final label = keys[row][col];

            if (label == '←') {
              return SizedBox(
                width: 70,
                height: 70,
                child: _buildKey(
                  label,
                  index,
                  icon: Icons.backspace_outlined,
                  onTap: widget.onBackspace,
                ),
              );
            } else if (label == '✓') {
              return SizedBox(
                width: 70,
                height: 70,
                child: _buildKey(
                  label,
                  index,
                  icon: Icons.check_circle_outline,
                  backgroundColor: SaimoTheme.success.withOpacity(0.3),
                  onTap: widget.onConfirm,
                ),
              );
            } else {
              return SizedBox(
                width: 70,
                height: 70,
                child: _buildKey(
                  label,
                  index,
                  onTap: () => widget.onNumberPressed(label),
                ),
              );
            }
          }),
        );
      }),
    );
  }
}

/// Dialog de PIN com teclado numérico otimizado para TV
class TVPinDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String correctPin;
  final int pinLength;
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;

  const TVPinDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.correctPin,
    this.pinLength = 4,
    this.onSuccess,
    this.onCancel,
  });

  @override
  State<TVPinDialog> createState() => _TVPinDialogState();
}

class _TVPinDialogState extends State<TVPinDialog>
    with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  bool _isError = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    if (_enteredPin.length < widget.pinLength) {
      setState(() {
        _enteredPin += number;
        _isError = false;
      });

      if (_enteredPin.length == widget.pinLength) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _isError = false;
      });
    }
  }

  void _verifyPin() {
    if (_enteredPin == widget.correctPin) {
      widget.onSuccess?.call();
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isError = true);
      _shakeController.forward().then((_) {
        _shakeController.reset();
        setState(() => _enteredPin = '');
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SaimoTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone de cadeado
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SaimoTheme.primary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 48,
                color: SaimoTheme.primary,
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

            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 14,
                  color: SaimoTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 32),

            // PIN dots com shake animation
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value * (_isError ? 1 : 0), 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.pinLength, (index) {
                      final isFilled = index < _enteredPin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled
                              ? (_isError ? SaimoTheme.error : SaimoTheme.primary)
                              : Colors.transparent,
                          border: Border.all(
                            color: _isError
                                ? SaimoTheme.error
                                : (isFilled ? SaimoTheme.primary : SaimoTheme.textSecondary),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),

            if (_isError) ...[
              const SizedBox(height: 16),
              Text(
                'PIN incorreto. Tente novamente.',
                style: TextStyle(
                  fontSize: 14,
                  color: SaimoTheme.error,
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Teclado numérico
            TVNumericKeyboard(
              onNumberPressed: _onNumberPressed,
              onBackspace: _onBackspace,
              onConfirm: () {
                if (_enteredPin.length == widget.pinLength) {
                  _verifyPin();
                }
              },
            ),

            const SizedBox(height: 16),

            // Botão cancelar
            TextButton(
              onPressed: () {
                widget.onCancel?.call();
                Navigator.of(context).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  fontSize: 16,
                  color: SaimoTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mostra o dialog de PIN e retorna true se correto
Future<bool> showTVPinDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String correctPin,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => TVPinDialog(
      title: title,
      subtitle: subtitle,
      correctPin: correctPin,
    ),
  );
  return result ?? false;
}
