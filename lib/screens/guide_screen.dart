import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../providers/channels_provider.dart';
import '../providers/epg_provider.dart';
import '../providers/player_provider.dart';
import '../utils/theme.dart';

/// Tela do Guia de Programação (EPG) - Otimizada para TV/Fire TV
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  int _selectedChannelIndex = 0;
  int _selectedHourOffset = 0;
  final FocusNode _mainFocusNode = FocusNode();
  
  final List<int> _hours = List.generate(24, (i) => i);

  @override
  void initState() {
    super.initState();
    _loadEPGData();
    _scrollToCurrentTime();
    _initializeSelectedChannel();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _mainFocusNode.dispose();
    super.dispose();
  }
  
  void _initializeSelectedChannel() {
    // Seleciona o canal atualmente sendo reproduzido
    final playerProvider = context.read<PlayerProvider>();
    final channelsProvider = context.read<ChannelsProvider>();
    final currentChannel = playerProvider.currentChannel;
    
    if (currentChannel != null) {
      final index = channelsProvider.channels.indexWhere((c) => c.id == currentChannel.id);
      if (index >= 0) {
        _selectedChannelIndex = index;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToChannel(index);
        });
      }
    }
  }

  Future<void> _loadEPGData() async {
    final channelsProvider = context.read<ChannelsProvider>();
    final epgProvider = context.read<EpgProvider>();
    
    // Carrega EPG de TODOS os canais para garantir que apareçam no guia
    final channelIds = channelsProvider.channels.map((c) => c.id).toList();
    
    // Força carregamento de todos (em lotes para não travar)
    for (final id in channelIds) {
      await epgProvider.loadChannelEPG(id);
    }
  }

  void _scrollToCurrentTime() {
    final now = DateTime.now();
    final currentHourIndex = now.hour;
    
    // Scroll para a hora atual
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalController.hasClients) {
        final offset = currentHourIndex * 200.0;
        _horizontalController.animateTo(
          offset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    // Responde tanto a KeyDownEvent quanto KeyRepeatEvent
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final channelsProvider = context.read<ChannelsProvider>();
    final totalChannels = channelsProvider.channels.length;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        setState(() {
          _selectedChannelIndex = (_selectedChannelIndex - 1).clamp(0, totalChannels - 1);
        });
        _scrollToChannel(_selectedChannelIndex);
        break;
        
      case LogicalKeyboardKey.arrowDown:
        setState(() {
          _selectedChannelIndex = (_selectedChannelIndex + 1).clamp(0, totalChannels - 1);
        });
        _scrollToChannel(_selectedChannelIndex);
        break;
        
      case LogicalKeyboardKey.arrowLeft:
        setState(() {
          _selectedHourOffset = (_selectedHourOffset - 1).clamp(-12, 12);
        });
        _scrollHorizontally(-200);
        break;
        
      case LogicalKeyboardKey.arrowRight:
        setState(() {
          _selectedHourOffset = (_selectedHourOffset + 1).clamp(-12, 12);
        });
        _scrollHorizontally(200);
        break;
        
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        _playSelectedChannel();
        break;
        
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        Navigator.of(context).pop();
        break;
    }
  }
  
  void _scrollHorizontally(double offset) {
    if (_horizontalController.hasClients) {
      final newOffset = (_horizontalController.offset + offset).clamp(
        0.0, 
        _horizontalController.position.maxScrollExtent,
      );
      _horizontalController.animateTo(
        newOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToChannel(int index) {
    const channelHeight = 90.0;
    final offset = (index * channelHeight) - 150;
    
    if (_verticalController.hasClients) {
      _verticalController.animateTo(
        offset.clamp(0.0, _verticalController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _playSelectedChannel() {
    final channelsProvider = context.read<ChannelsProvider>();
    final channel = channelsProvider.channels[_selectedChannelIndex];
    
    context.read<PlayerProvider>().setChannel(channel);
    Navigator.of(context).pushReplacementNamed('/player');
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _mainFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: SaimoTheme.background,
        body: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Timeline (horas)
            _buildTimeline(),
            
            // Grid de programação
            Expanded(
              child: _buildProgramGrid(),
            ),
            
            // Barra de atalhos
            _buildShortcutsBar(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildShortcutsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: SaimoTheme.surface,
        border: Border(
          top: BorderSide(color: SaimoTheme.surfaceLight),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildKeyHint('▲▼', 'Canal'),
          const SizedBox(width: 24),
          _buildKeyHint('◀▶', 'Horário'),
          const SizedBox(width: 24),
          _buildKeyHint('OK', 'Assistir'),
          const SizedBox(width: 24),
          _buildKeyHint('⏎', 'Voltar'),
        ],
      ),
    );
  }
  
  Widget _buildKeyHint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SaimoTheme.surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: SaimoTheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: SaimoTheme.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final selectedDate = now.add(Duration(hours: _selectedHourOffset));
    
    return Container(
      padding: const EdgeInsets.all(20),
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
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          
          const SizedBox(width: 16),
          
          // Título
          const Icon(Icons.calendar_month, color: SaimoTheme.primary, size: 28),
          const SizedBox(width: 12),
          const Text(
            'Guia de Programação',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const Spacer(),
          
          // Data selecionada
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: SaimoTheme.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.today, color: SaimoTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  _formatDate(selectedDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Relógio
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, snapshot) {
              final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              return Text(
                time,
                style: const TextStyle(
                  color: SaimoTheme.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final now = DateTime.now();
    
    return Container(
      height: 50,
      color: SaimoTheme.card,
      child: Row(
        children: [
          // Espaço para coluna de canais (com logo)
          Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              'Canal',
              style: TextStyle(
                color: SaimoTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          // Horas
          Expanded(
            child: ListView.builder(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              itemCount: 24,
              itemBuilder: (context, index) {
                final hour = _hours[index];
                final isCurrentHour = hour == now.hour;
                
                return Container(
                  width: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCurrentHour 
                        ? SaimoTheme.primary.withOpacity(0.2)
                        : null,
                    border: Border(
                      left: BorderSide(
                        color: SaimoTheme.surfaceLight,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      color: isCurrentHour 
                          ? SaimoTheme.primary
                          : SaimoTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: isCurrentHour 
                          ? FontWeight.bold 
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramGrid() {
    return Consumer3<ChannelsProvider, EpgProvider, PlayerProvider>(
      builder: (context, channelsProvider, epgProvider, playerProvider, child) {
        final channels = channelsProvider.channels;
        final currentPlayingChannel = playerProvider.currentChannel;

        return ListView.builder(
          controller: _verticalController,
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final channel = channels[index];
            final isSelected = index == _selectedChannelIndex;
            final isPlaying = channel.id == currentPlayingChannel?.id;
            final epg = epgProvider.getEPG(channel.id);
            
            return _buildChannelRow(
              channel: channel,
              programs: epg?.programs ?? [],
              isSelected: isSelected,
              isPlaying: isPlaying,
              onTap: () {
                setState(() => _selectedChannelIndex = index);
              },
              onPlay: () {
                context.read<PlayerProvider>().setChannel(channel);
                Navigator.of(context).pushReplacementNamed('/player');
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChannelRow({
    required Channel channel,
    required List programs,
    required bool isSelected,
    required bool isPlaying,
    required VoidCallback onTap,
    required VoidCallback onPlay,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onPlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 90,
        decoration: BoxDecoration(
          color: isSelected 
              ? SaimoTheme.primary.withOpacity(0.2)
              : isPlaying
                  ? SaimoTheme.primary.withOpacity(0.08)
                  : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: SaimoTheme.surfaceLight, width: 1),
            left: BorderSide(
              color: isSelected 
                  ? SaimoTheme.primary
                  : isPlaying
                      ? SaimoTheme.live
                      : Colors.transparent,
              width: isSelected ? 4 : isPlaying ? 3 : 0,
            ),
          ),
        ),
        child: Row(
          children: [
            // Info do canal com logo
            Container(
              width: 260,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  // Logo do canal
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? SaimoTheme.primary.withOpacity(0.3)
                          : SaimoTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? SaimoTheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: channel.logo != null && channel.logo!.isNotEmpty
                          ? Image.network(
                              channel.logo!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildChannelLogo(channel, isSelected),
                            )
                          : _buildChannelLogo(channel, isSelected),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Número e nome
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Número do canal
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? SaimoTheme.primary
                                    : SaimoTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${channel.channelNumber}',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : SaimoTheme.textSecondary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isPlaying)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: SaimoTheme.live,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow, color: Colors.white, size: 12),
                                    SizedBox(width: 3),
                                    Text(
                                      'ATUAL',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          channel.name,
                          style: TextStyle(
                            color: isSelected 
                                ? SaimoTheme.primary
                                : Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          channel.category,
                          style: const TextStyle(
                            color: SaimoTheme.textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Programação
            Expanded(
              child: _buildProgramsTimeline(programs, isSelected),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildChannelLogo(Channel channel, bool isSelected) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: isSelected 
            ? SaimoTheme.primaryGradient
            : LinearGradient(
                colors: [
                  SaimoTheme.surfaceLight,
                  SaimoTheme.card,
                ],
              ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        channel.name.substring(0, channel.name.length.clamp(0, 2)).toUpperCase(),
        style: TextStyle(
          color: isSelected ? Colors.white : SaimoTheme.textSecondary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildProgramsTimeline(List programs, bool isSelected) {
    if (programs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Center(
          child: Text(
            'Programação indisponível',
            style: TextStyle(
              color: SaimoTheme.textTertiary,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: ScrollController(),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: programs.length,
      itemBuilder: (context, index) {
        final program = programs[index];
        final isAiring = program.isCurrentlyAiring;
        
        // Calcula largura baseada na duração
        final duration = program.durationMinutes;
        final width = (duration / 60) * 200.0;
        
        return Container(
          width: width.clamp(120.0, 600.0),
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isAiring 
                ? SaimoTheme.primary.withOpacity(isSelected ? 0.5 : 0.3)
                : SaimoTheme.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: isAiring 
                ? Border.all(color: SaimoTheme.primary, width: 2)
                : Border.all(color: Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  if (isAiring)
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: SaimoTheme.live,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SaimoTheme.live.withOpacity(0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Text(
                      program.title,
                      style: TextStyle(
                        color: isAiring 
                            ? Colors.white
                            : SaimoTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: isAiring ? FontWeight.bold : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.schedule, 
                    size: 16, 
                    color: isAiring ? Colors.white70 : SaimoTheme.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    program.formattedPeriod,
                    style: TextStyle(
                      color: isAiring ? Colors.white70 : SaimoTheme.textTertiary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    const days = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    const months = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    
    return '${days[date.weekday % 7]}, ${date.day} ${months[date.month - 1]}';
  }
}
