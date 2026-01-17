import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../providers/channels_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../utils/theme.dart';
import '../widgets/channel_card.dart';

/// Tela de Busca de Canais
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Channel> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Carrega todos os canais inicialmente
    _searchResults = context.read<ChannelsProvider>().channels;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final channelsProvider = context.read<ChannelsProvider>();
    
    setState(() {
      _isSearching = query.isNotEmpty;
      
      if (query.isEmpty) {
        _searchResults = channelsProvider.channels;
      } else {
        final lowerQuery = query.toLowerCase();
        _searchResults = channelsProvider.channels.where((channel) {
          return channel.name.toLowerCase().contains(lowerQuery) ||
              channel.category.toLowerCase().contains(lowerQuery) ||
              channel.channelNumber.toString().contains(query);
        }).toList();
      }
    });
  }

  void _onChannelSelected(Channel channel) {
    context.read<PlayerProvider>().setChannel(channel);
    Navigator.of(context).pushReplacementNamed('/player');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        if (_searchController.text.isNotEmpty) {
          _searchController.clear();
          _onSearch('');
        } else {
          Navigator.of(context).pop();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: SaimoTheme.background,
        body: Column(
          children: [
            // Header com busca
            _buildHeader(),
            
            // Resultados
            Expanded(
              child: _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SaimoTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          // Botão voltar
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          
          const SizedBox(width: 16),
          
          // Campo de busca
          Expanded(
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: SaimoTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _searchFocusNode.hasFocus 
                      ? SaimoTheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(
                    Icons.search,
                    color: _searchFocusNode.hasFocus 
                        ? SaimoTheme.primary
                        : SaimoTheme.textSecondary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Buscar canais...',
                        hintStyle: TextStyle(
                          color: SaimoTheme.textTertiary,
                          fontSize: 18,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: _onSearch,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, color: SaimoTheme.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        _onSearch('');
                      },
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 24),
          
          // Contador de resultados
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: SaimoTheme.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_searchResults.length} canais',
              style: const TextStyle(
                color: SaimoTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_searchResults.isEmpty) {
      return _buildEmptyState();
    }

    return Consumer<FavoritesProvider>(
      builder: (context, favoritesProvider, child) {
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            childAspectRatio: 0.85,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final channel = _searchResults[index];
            final isFavorite = favoritesProvider.isFavorite(channel.id);
            
            return ChannelCard(
              channel: channel,
              isFavorite: isFavorite,
              autofocus: index == 0,
              onPressed: () => _onChannelSelected(channel),
              onFavoriteToggle: () => favoritesProvider.toggleFavorite(channel.id),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSearching ? Icons.search_off : Icons.live_tv,
            color: SaimoTheme.textTertiary,
            size: 80,
          ),
          const SizedBox(height: 24),
          Text(
            _isSearching 
                ? 'Nenhum canal encontrado'
                : 'Digite para buscar canais',
            style: const TextStyle(
              color: SaimoTheme.textSecondary,
              fontSize: 20,
            ),
          ),
          if (_isSearching) ...[
            const SizedBox(height: 12),
            Text(
              'Tente buscar por nome, categoria ou número',
              style: const TextStyle(
                color: SaimoTheme.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
