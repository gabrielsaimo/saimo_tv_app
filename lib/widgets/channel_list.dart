import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../models/category.dart';
import '../utils/theme.dart';
import 'channel_card.dart';

/// Lista horizontal de canais por categoria
class ChannelRow extends StatefulWidget {
  final String category;
  final List<Channel> channels;
  final Set<String> favorites;
  final Channel? selectedChannel;
  final Function(Channel) onChannelSelected;
  final Function(String) onFavoriteToggle;
  final bool autofocusFirst;

  const ChannelRow({
    super.key,
    required this.category,
    required this.channels,
    required this.favorites,
    this.selectedChannel,
    required this.onChannelSelected,
    required this.onFavoriteToggle,
    this.autofocusFirst = false,
  });

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToChannel(int index) {
    const cardWidth = 216.0; // 200 + 16 margin
    final targetOffset = index * cardWidth;
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = Color(ChannelCategory.getColor(widget.category));
    final categoryIcon = ChannelCategory.getIcon(widget.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header da categoria
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              // Ícone
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  categoryIcon,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Nome da categoria
              Text(
                widget.category,
                style: const TextStyle(
                  color: SaimoTheme.textPrimary,
                  fontSize: SaimoTheme.fontSizeM,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Contador
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SaimoTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${widget.channels.length} canais',
                  style: const TextStyle(
                    color: SaimoTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Lista de canais
        SizedBox(
          height: 200,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.channels.length,
            itemBuilder: (context, index) {
              final channel = widget.channels[index];
              final isFavorite = widget.favorites.contains(channel.id);
              final isSelected = widget.selectedChannel?.id == channel.id;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ChannelCard(
                  channel: channel,
                  isFavorite: isFavorite,
                  isSelected: isSelected,
                  autofocus: widget.autofocusFirst && index == 0,
                  onPressed: () => widget.onChannelSelected(channel),
                  onLongPress: () => widget.onFavoriteToggle(channel.id),
                  onFavoriteToggle: () => widget.onFavoriteToggle(channel.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Lista vertical de categorias com canais
class ChannelList extends StatelessWidget {
  final Map<String, List<Channel>> channelsByCategory;
  final Set<String> favorites;
  final Channel? selectedChannel;
  final Function(Channel) onChannelSelected;
  final Function(String) onFavoriteToggle;
  final ScrollController? scrollController;

  const ChannelList({
    super.key,
    required this.channelsByCategory,
    required this.favorites,
    this.selectedChannel,
    required this.onChannelSelected,
    required this.onFavoriteToggle,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // Ordena categorias
    final categories = channelsByCategory.keys.toList()
      ..sort((a, b) => ChannelCategory.getIndex(a).compareTo(ChannelCategory.getIndex(b)));

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 16, bottom: 100),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final channels = channelsByCategory[category] ?? [];

        if (channels.isEmpty) return const SizedBox.shrink();

        return ChannelRow(
          category: category,
          channels: channels,
          favorites: favorites,
          selectedChannel: selectedChannel,
          onChannelSelected: onChannelSelected,
          onFavoriteToggle: onFavoriteToggle,
          autofocusFirst: index == 0,
        );
      },
    );
  }
}
