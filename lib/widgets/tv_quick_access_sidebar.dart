import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

/// Barra lateral de atalhos para navegação rápida no player
/// Aparece ao pressionar seta para esquerda
class TVQuickAccessSidebar extends StatefulWidget {
  final VoidCallback? onGuide;
  final VoidCallback? onChannelList;
  final VoidCallback? onFavorites;
  final VoidCallback? onSettings;
  final VoidCallback? onRecents;
  final VoidCallback? onClose;
  final String? currentChannelName;
  final String? currentProgramName;

  const TVQuickAccessSidebar({
    super.key,
    this.onGuide,
    this.onChannelList,
    this.onFavorites,
    this.onSettings,
    this.onRecents,
    this.onClose,
    this.currentChannelName,
    this.currentProgramName,
  });

  @override
  State<TVQuickAccessSidebar> createState() => _TVQuickAccessSidebarState();
}

class _TVQuickAccessSidebarState extends State<TVQuickAccessSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final List<FocusNode> _focusNodes = [];
  int _selectedIndex = 0;

  final List<_QuickMenuItem> _menuItems = [];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: -1, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _setupMenuItems();

    for (int i = 0; i < _menuItems.length; i++) {
      _focusNodes.add(FocusNode());
    }

    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNodes.isNotEmpty) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  void _setupMenuItems() {
    _menuItems.addAll([
      _QuickMenuItem(
        icon: Icons.tv_outlined,
        label: 'Guia de TV',
        subtitle: 'Ver programação',
        onTap: widget.onGuide,
      ),
      _QuickMenuItem(
        icon: Icons.list_alt,
        label: 'Lista de Canais',
        subtitle: 'Navegar canais',
        onTap: widget.onChannelList,
      ),
      _QuickMenuItem(
        icon: Icons.favorite_border,
        label: 'Favoritos',
        subtitle: 'Seus canais favoritos',
        onTap: widget.onFavorites,
      ),
      _QuickMenuItem(
        icon: Icons.history,
        label: 'Recentes',
        subtitle: 'Últimos assistidos',
        onTap: widget.onRecents,
      ),
      _QuickMenuItem(
        icon: Icons.settings_outlined,
        label: 'Configurações',
        subtitle: 'Ajustes do app',
        onTap: widget.onSettings,
      ),
    ]);
  }

  @override
  void dispose() {
    _animationController.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp && index > 0) {
      setState(() => _selectedIndex = index - 1);
      _focusNodes[_selectedIndex].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowDown &&
        index < _menuItems.length - 1) {
      setState(() => _selectedIndex = index + 1);
      _focusNodes[_selectedIndex].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      widget.onClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Stack(
          children: [
            // Backdrop escuro
            FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ),

            // Sidebar
            Transform.translate(
              offset: Offset(
                _slideAnimation.value * 320,
                0,
              ),
              child: Container(
                width: 320,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      SaimoTheme.background,
                      SaimoTheme.background.withOpacity(0.95),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(10, 0),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header com info do canal atual
                      if (widget.currentChannelName != null) ...[
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: SaimoTheme.primaryGradient,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ASSISTINDO',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.currentChannelName!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.currentProgramName != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.currentProgramName!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Menu items
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _menuItems.length,
                          itemBuilder: (context, index) {
                            final item = _menuItems[index];
                            return _buildMenuItem(item, index);
                          },
                        ),
                      ),

                      // Hint de navegação
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.arrow_back,
                              size: 16,
                              color: SaimoTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pressione ← para fechar',
                              style: TextStyle(
                                fontSize: 12,
                                color: SaimoTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuItem(_QuickMenuItem item, int index) {
    return Focus(
      focusNode: _focusNodes[index],
      onKeyEvent: (node, event) {
        _handleKeyEvent(event, index);

        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          item.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: item.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: hasFocus
                    ? SaimoTheme.primary.withOpacity(0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus
                      ? SaimoTheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasFocus
                          ? SaimoTheme.primary
                          : SaimoTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.icon,
                      size: 24,
                      color: hasFocus
                          ? Colors.white
                          : SaimoTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: hasFocus
                                ? Colors.white
                                : SaimoTheme.textPrimary,
                          ),
                        ),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: hasFocus
                                ? Colors.white70
                                : SaimoTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: hasFocus
                        ? Colors.white
                        : SaimoTheme.textSecondary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickMenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  _QuickMenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
  });
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
