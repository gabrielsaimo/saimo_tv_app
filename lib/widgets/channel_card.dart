import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';

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

  // Timer para detectar long press no D-Pad
  Timer? _longPressTimer;
  bool _isLongPress = false;

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _animController.dispose();
    _longPressTimer?.cancel();
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

  void _handleDpadPress(bool isDown) {
    if (isDown) {
      _isLongPress = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 600), () {
        _isLongPress = true;
        if (widget.onLongPress != null) {
          HapticFeedback.heavyImpact();
          widget.onLongPress!();
        }
      });
    } else {
      _longPressTimer?.cancel();
      if (!_isLongPress) {
        // Only trigger normal press if it wasn't a long press
        HapticFeedback.selectionClick();
        widget.onPressed?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.gameButtonA || 
            key == LogicalKeyboardKey.numpadEnter) {
          
          if (event is KeyDownEvent) {
             // Avoid repeating if system sends multiple down events for hold
             if (_longPressTimer == null || !_longPressTimer!.isActive) {
               _handleDpadPress(true);
             }
             return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
             _handleDpadPress(false);
             return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress,
        child: TVAnimatedBuilder(
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
              memCacheWidth: 300, // Optimization: Limit cache size
              placeholder: (context, url) => _buildPlaceholder(),
              errorWidget: (context, url, error) => _buildPlaceholder(),
            ),
          ),
        ),
        
        // Número do canal
        Positioned(
          top: TVConstants.paddingS,
          left: TVConstants.paddingS,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: TVConstants.paddingS, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(TVConstants.radiusS),
            ),
            child: Text(
              '${widget.channel.channelNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: TVConstants.fontS,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        // Favorito
        if (widget.isFavorite)
          Positioned(
            top: TVConstants.paddingS,
            right: TVConstants.paddingS,
            child: GestureDetector(
              onTap: widget.onFavoriteToggle,
              child: Container(
                padding: const EdgeInsets.all(TVConstants.paddingS),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star,
                  color: SaimoTheme.favorite,
                  size: TVConstants.iconS,
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
      padding: const EdgeInsets.all(TVConstants.paddingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome do canal
          Text(
            widget.channel.name,
            style: TextStyle(
              color: _isFocused ? TVConstants.focusColor : SaimoTheme.textPrimary,
              fontSize: TVConstants.fontM,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 6),
          
          // Programa atual ou categoria
          Text(
            widget.currentProgram ?? widget.channel.category,
            style: TextStyle(
              color: Colors.white.withOpacity(TVConstants.textSecondaryOpacity),
              fontSize: TVConstants.fontS,
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

// AnimatedBuilder removido - usar TVAnimatedBuilder de tv_constants.dart
