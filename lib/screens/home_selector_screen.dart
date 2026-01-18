import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';
import '../utils/key_debouncer.dart';

/// Tela de seleção inicial - Canais ou Filmes & Séries
class HomeSelectorScreen extends StatefulWidget {
  const HomeSelectorScreen({super.key});

  @override
  State<HomeSelectorScreen> createState() => _HomeSelectorScreenState();
}

class _HomeSelectorScreenState extends State<HomeSelectorScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final FocusNode _mainFocusNode = FocusNode();
  final KeyDebouncer _debouncer = KeyDebouncer();
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  
  // 2 opções: Canais, Filmes
  static const int _totalOptions = 2;
  
  // Controle de saída - duplo tap para sair
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      lowerBound: 0.95,
      upperBound: 1.0,
    )..value = 1.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _mainFocusNode.dispose();
    super.dispose();
  }
  
  Future<bool> _handleBackPress() async {
    final now = DateTime.now();
    if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      // Duplo tap em 2 segundos - fecha o app
      SystemNavigator.pop();
      return true;
    }
    
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pressione VOLTAR novamente para sair'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFFE50914),
      ),
    );
    return false;
  }

  void _selectOption() {
    HapticFeedback.mediumImpact();
    switch (_selectedIndex) {
      case 0:
        Navigator.pushReplacementNamed(context, '/channels');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/movies');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Este callback captura o evento de sistema Android quando Focus não captura
        if (!didPop) {
          // Não faz nada aqui - o Focus.onKeyEvent já tratou
          // Este PopScope existe apenas para bloquear o pop padrão
        }
      },
      child: Scaffold(
        backgroundColor: SaimoTheme.background,
        body: Focus(
          focusNode: _mainFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            
            final key = event.logicalKey;
            
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowUp) {
              setState(() => _selectedIndex = (_selectedIndex - 1).clamp(0, _totalOptions - 1));
              HapticFeedback.selectionClick();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.arrowRight ||
                       key == LogicalKeyboardKey.arrowDown) {
              setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, _totalOptions - 1));
              HapticFeedback.selectionClick();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.select ||
                       key == LogicalKeyboardKey.enter ||
                       key == LogicalKeyboardKey.gameButtonA) {
              _selectOption();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.goBack || 
                       key == LogicalKeyboardKey.escape ||
                       key == LogicalKeyboardKey.browserBack) {
              if (_debouncer.shouldProcessBack()) {
                _handleBackPress();
              }
              return KeyEventResult.handled;
            }
            
            return KeyEventResult.ignored;
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SaimoTheme.background,
                  SaimoTheme.background.withOpacity(0.95),
                  const Color(0xFF1a1a2e),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Logo e título - Compacto para TV
                  Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      TVAnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: SaimoTheme.primary.withOpacity(
                                    0.3 + (_pulseController.value * 0.2),
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.live_tv_rounded,
                              size: 40,
                              color: SaimoTheme.primary,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      // Título
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                SaimoTheme.primary,
                                SaimoTheme.accent,
                              ],
                            ).createShader(bounds),
                            child: const Text(
                              'Saimo TV',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          Text(
                            'Entretenimento sem limites',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Pergunta
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'O que você quer assistir?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),

                // Cards de seleção
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildOptionCard(
                            index: 0,
                            icon: Icons.live_tv_rounded,
                            title: 'TV ao Vivo',
                            subtitle: 'Canais em tempo real',
                            features: [
                              '📺 +90 canais',
                              '✨ Design Premium',
                              '📡 Mini guia EPG',
                            ],
                            gradientColors: [
                              SaimoTheme.primary,
                              SaimoTheme.primaryDark,
                            ],
                          ),
                          const SizedBox(width: 24),
                          _buildOptionCard(
                            index: 1,
                            icon: Icons.movie_rounded,
                            title: 'Filmes & Séries',
                            subtitle: 'Catálogo completo on-demand',
                            features: [
                              '🎬 +10.000 títulos',
                              '📺 Séries completas',
                              '🆕 Lançamentos',
                            ],
                            gradientColors: [
                              const Color(0xFFEF4444),
                              const Color(0xFFDC2626),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Dica de navegação
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildKeyHint('←→', 'Navegar'),
                      const SizedBox(width: 30),
                      _buildKeyHint('OK', 'Selecionar'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildOptionCard({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> features,
    required List<Color> gradientColors,
  }) {
    final isSelected = _selectedIndex == index;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardHeight = (screenHeight * 0.50).clamp(180.0, 280.0);
    final cardWidth = (cardHeight * 0.72).clamp(140.0, 200.0);

    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        _selectOption();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth,
        height: cardHeight,
        transform: Matrix4.identity()
          ..scale(isSelected ? 1.05 : 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isSelected
                  ? gradientColors
                  : [
                      const Color(0xFF2D2D3A),
                      const Color(0xFF1F1F2A),
                    ],
            ),
            border: Border.all(
              color: isSelected
                  ? gradientColors[0].withOpacity(0.8)
                  : Colors.white.withOpacity(0.1),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: gradientColors[0].withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                  ),
                  child: Icon(
                    icon,
                    size: 36,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 12),

                // Título
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 4),

                // Subtítulo
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? Colors.white.withOpacity(0.9)
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 12),

                // Features
                ...features.map((feature) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white.withOpacity(0.95)
                              : Colors.white.withOpacity(0.6),
                        ),
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyHint(String key, String label) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
