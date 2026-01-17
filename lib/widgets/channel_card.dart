import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../utils/theme.dart';

/// Card de canal otimizado para TV com navegação D-Pad
class ChannelCard extends StatefulWidget {
  final Channel channel;
  final bool isFavorite;
  final bool isSelected;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavoriteToggle;
  final bool autofocus;
  final String? currentProgram;
  final double? progress;

  const ChannelCard({
    super.key,
    required this.channel,
    this.isFavorite = false,
    this.isSelected = false,
    this.onPressed,
    this.onLongPress,
    this.onFavoriteToggle,
    this.autofocus = false,
    this.currentProgram,
    this.progress,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard>
    with SingleTickerProviderStateMixin {
  late FocusNode _focusNode;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
    if (_isFocused) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event.logicalKey.keyLabel == 'Select' ||
            event.logicalKey.keyLabel == 'Enter') {
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnim.value,
              child: _buildCard(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 200,
      decoration: BoxDecoration(
        color: widget.isSelected 
            ? SaimoTheme.primary.withOpacity(0.2)
            : SaimoTheme.card,
        borderRadius: BorderRadius.circular(SaimoTheme.borderRadius),
        border: Border.all(
          color: _isFocused
              ? SaimoTheme.primary
              : widget.isSelected
                  ? SaimoTheme.primary.withOpacity(0.5)
                  : Colors.transparent,
          width: _isFocused ? 3 : 2,
        ),
        boxShadow: _isFocused ? SaimoTheme.focusShadow : SaimoTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo e número do canal
          _buildHeader(),
          
          // Nome e programa atual
          _buildInfo(),
          
          // Barra de progresso
          if (widget.progress != null) _buildProgress(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        // Logo
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SaimoTheme.borderRadius),
          ),
          child: Container(
            height: 110,
            width: double.infinity,
            color: SaimoTheme.surfaceLight,
            child: CachedNetworkImage(
              imageUrl: widget.channel.logoUrl,
              fit: BoxFit.contain,
              placeholder: (context, url) => _buildPlaceholder(),
              errorWidget: (context, url, error) => _buildPlaceholder(),
            ),
          ),
        ),
        
        // Número do canal
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${widget.channel.channelNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        // Favorito
        if (widget.isFavorite)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: widget.onFavoriteToggle,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star,
                  color: SaimoTheme.favorite,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: SaimoTheme.primary.withOpacity(0.3),
      child: Center(
        child: Text(
          widget.channel.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildInfo() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome do canal
          Text(
            widget.channel.name,
            style: TextStyle(
              color: _isFocused ? SaimoTheme.primary : SaimoTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 4),
          
          // Programa atual ou categoria
          Text(
            widget.currentProgram ?? widget.channel.category,
            style: const TextStyle(
              color: SaimoTheme.textSecondary,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      height: 3,
      margin: const EdgeInsets.only(bottom: 4, left: 12, right: 12),
      decoration: BoxDecoration(
        color: SaimoTheme.surfaceLight,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (widget.progress! / 100).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: SaimoTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Builder animado
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
