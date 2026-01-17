import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../utils/theme.dart';

/// Card de "Continue Assistindo" para TV
/// Mostra o último canal com opção de retomar
class ContinueWatchingCard extends StatefulWidget {
  final Channel channel;
  final String? programTitle;
  final VoidCallback onPlay;
  final bool autofocus;

  const ContinueWatchingCard({
    super.key,
    required this.channel,
    this.programTitle,
    required this.onPlay,
    this.autofocus = false,
  });

  @override
  State<ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<ContinueWatchingCard>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onPlay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..scale(_isFocused ? 1.02 : 1.0),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                SaimoTheme.primary.withOpacity(0.3),
                SaimoTheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: _isFocused ? SaimoTheme.primary : Colors.transparent,
              width: 3,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: SaimoTheme.primary.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Logo do canal
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: SaimoTheme.surfaceLight,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.channel.logo != null
                      ? CachedNetworkImage(
                          imageUrl: widget.channel.logo!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: Icon(
                              Icons.tv,
                              color: SaimoTheme.textSecondary,
                              size: 32,
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.tv,
                              color: SaimoTheme.textSecondary,
                              size: 32,
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.tv,
                            color: SaimoTheme.textSecondary,
                            size: 32,
                          ),
                        ),
                ),
                const SizedBox(width: 20),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: SaimoTheme.live,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 8, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'CONTINUE ASSISTINDO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.channel.name,
                        style: const TextStyle(
                          color: SaimoTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.programTitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.programTitle!,
                          style: TextStyle(
                            color: SaimoTheme.textSecondary,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Botão play
                ScaleTransition(
                  scale: _isFocused ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: SaimoTheme.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: SaimoTheme.primary.withOpacity(0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seção de categorias rápidas para TV
class QuickCategoriesBar extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const QuickCategoriesBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  State<QuickCategoriesBar> createState() => _QuickCategoriesBarState();
}

class _QuickCategoriesBarState extends State<QuickCategoriesBar> {
  final ScrollController _scrollController = ScrollController();
  final List<FocusNode> _focusNodes = [];
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.categories.length; i++) {
      _focusNodes.add(FocusNode());
    }
    
    // Encontra índice da categoria selecionada
    _focusedIndex = widget.categories.indexOf(widget.selectedCategory);
    if (_focusedIndex < 0) _focusedIndex = 0;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      setState(() => _focusedIndex = index - 1);
      _focusNodes[_focusedIndex].requestFocus();
      _scrollToIndex(_focusedIndex);
    } else if (key == LogicalKeyboardKey.arrowRight && 
               index < widget.categories.length - 1) {
      setState(() => _focusedIndex = index + 1);
      _focusNodes[_focusedIndex].requestFocus();
      _scrollToIndex(_focusedIndex);
    }
  }

  void _scrollToIndex(int index) {
    if (_scrollController.hasClients) {
      const itemWidth = 140.0;
      final offset = (index * itemWidth) - 100;
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: widget.categories.length,
        itemBuilder: (context, index) {
          final category = widget.categories[index];
          final isSelected = category == widget.selectedCategory;

          return Focus(
            focusNode: _focusNodes[index],
            onKeyEvent: (node, event) {
              _handleKeyEvent(event, index);

              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                   event.logicalKey == LogicalKeyboardKey.select)) {
                widget.onCategorySelected(category);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final hasFocus = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () => widget.onCategorySelected(category),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SaimoTheme.primary
                          : hasFocus
                              ? SaimoTheme.primary.withOpacity(0.3)
                              : SaimoTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: hasFocus ? SaimoTheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected || hasFocus
                              ? Colors.white
                              : SaimoTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
