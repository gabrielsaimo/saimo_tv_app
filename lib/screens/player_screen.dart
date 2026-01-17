import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/channel.dart';
import '../models/program.dart';
import '../providers/channels_provider.dart';
import '../providers/player_provider.dart';
import '../providers/epg_provider.dart';
import '../providers/favorites_provider.dart';
import '../utils/theme.dart';
import '../widgets/program_info.dart';
import '../widgets/channel_logo.dart';
import '../services/epg_service.dart';
import '../services/volume_boost_service.dart';

/// Tela do Player de Vídeo
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoController;
  Timer? _hideControlsTimer;
  Timer? _progressTimer;
  Timer? _videoHealthTimer; // Timer para verificar saúde do vídeo e evitar tela preta
  final VolumeBoostService _volumeBoostService = VolumeBoostService();
  bool _showControls = true;
  bool _isBuffering = true;
  String? _error;
  double _volume = 1.0;
  bool _isMuted = false;
  
  // EPG Loading progress
  int _epgLoaded = 0;
  int _epgTotal = 0;
  
  // Digitação de número do canal
  String _channelNumberInput = '';
  Timer? _channelInputTimer;
  
  // Overlay de lista de canais para navegação TV
  bool _showChannelList = false;
  int _selectedChannelIndex = 0;
  int _selectedProgramIndex = 0;  // Para navegação na programação
  final ScrollController _channelListController = ScrollController();
  final ScrollController _programsListController = ScrollController();
  Timer? _channelListHideTimer;
  
  // Focus Node para captura de teclas consistente
  final FocusNode _mainFocusNode = FocusNode();
  
  // Controle de gestos para touch
  double _startDragX = 0;
  double _startDragY = 0;
  double _startVolume = 1.0;
  bool _isDraggingVolume = false;
  bool _isDraggingChannel = false;

  @override
  void initState() {
    super.initState();
    _enableWakelock();
    _initializePlayer();
    _startHideControlsTimer();
    _setupEpgProgressListener();
    _initializeChannelIndex();
    _startVideoHealthMonitor();
  }
  
  /// Mantém a tela ligada durante reprodução de vídeo
  void _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Erro ao ativar wakelock: $e');
    }
  }
  
  /// Desativa o wakelock
  void _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Erro ao desativar wakelock: $e');
    }
  }
  
  /// Monitora a saúde do vídeo para evitar tela preta
  void _startVideoHealthMonitor() {
    _videoHealthTimer?.cancel();
    _videoHealthTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkVideoHealth();
    });
  }
  
  /// Verifica se o vídeo está funcionando e tenta recuperar se necessário
  void _checkVideoHealth() {
    if (_videoController == null || !mounted) return;
    
    final value = _videoController!.value;
    
    // Se não está inicializado, não há muito o que fazer
    if (!value.isInitialized) return;
    
    // Se está em buffering por muito tempo ou se a posição está travada
    // tenta reiniciar o player
    if (!value.isPlaying && !_isBuffering && _error == null) {
      debugPrint('Video health check: vídeo parado, tentando reiniciar...');
      _retryVideoPlayback();
    }
  }
  
  /// Tenta reiniciar a reprodução sem recarregar o canal
  void _retryVideoPlayback() async {
    if (_videoController == null) return;
    
    try {
      // Tenta dar play novamente
      await _videoController!.play();
      
      // Se ainda não funcionar depois de 3 segundos, reinicia
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _videoController != null && !_videoController!.value.isPlaying) {
          debugPrint('Video ainda parado, reiniciando canal...');
          _initializePlayer();
        }
      });
    } catch (e) {
      debugPrint('Erro ao tentar reiniciar vídeo: $e');
      _initializePlayer();
    }
  }
  
  void _initializeChannelIndex() {
    final playerProvider = context.read<PlayerProvider>();
    final channelsProvider = context.read<ChannelsProvider>();
    final currentChannel = playerProvider.currentChannel;
    
    if (currentChannel != null) {
      final index = channelsProvider.channels.indexWhere((c) => c.id == currentChannel.id);
      if (index >= 0) {
        _selectedChannelIndex = index;
      }
    }
  }
  
  void _setupEpgProgressListener() {
    final epgService = EpgService();
    _epgLoaded = epgService.loadedCount;
    _epgTotal = epgService.totalCount;
    
    epgService.addProgressListener(_onEpgProgress);
  }
  
  void _onEpgProgress(int loaded, int total) {
    if (mounted) {
      setState(() {
        _epgLoaded = loaded;
        _epgTotal = total;
      });
    }
  }

  @override
  void dispose() {
    _disableWakelock();
    _volumeBoostService.disableBoost(); // Desativa boost ao sair
    EpgService().removeProgressListener(_onEpgProgress);
    _videoController?.dispose();
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _videoHealthTimer?.cancel();
    _channelInputTimer?.cancel();
    _channelListHideTimer?.cancel();
    _channelListController.dispose();
    _programsListController.dispose();
    _mainFocusNode.dispose();
    super.dispose();
  }
  
  /// Carrega EPG para o canal selecionado (se não estiver no cache)
  void _loadEpgForSelectedChannel(String channelId) {
    final epgProvider = context.read<EpgProvider>();
    // Verifica se já tem dados no cache
    if (epgProvider.getEPG(channelId) == null || 
        epgProvider.getEPG(channelId)!.programs.isEmpty) {
      epgProvider.loadChannelEPG(channelId);
    }
  }


  Future<void> _initializePlayer() async {
    final playerProvider = context.read<PlayerProvider>();
    final channel = playerProvider.currentChannel;
    
    if (channel == null) {
      _navigateBack();
      return;
    }

    setState(() {
      _isBuffering = true;
      _error = null;
    });

    try {
      _videoController?.dispose();
      
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(channel.url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      await _videoController!.initialize();
      await _videoController!.setVolume(_volume);
      await _videoController!.play();

      _videoController!.addListener(_onVideoUpdate);

      // Carrega EPG do canal
      final epgProvider = context.read<EpgProvider>();
      epgProvider.loadChannelEPG(channel.id);

      setState(() => _isBuffering = false);
      
    } catch (e) {
      setState(() {
        _error = 'Erro ao carregar o canal: ${e.toString()}';
        _isBuffering = false;
      });
    }
  }

  void _onVideoUpdate() {
    if (_videoController == null) return;
    
    final isBuffering = _videoController!.value.isBuffering;
    if (isBuffering != _isBuffering) {
      setState(() => _isBuffering = isBuffering);
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  void _handleKeyEvent(KeyEvent event) {
    // Responde tanto a KeyDownEvent quanto KeyRepeatEvent para navegação fluida
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    
    _showControlsTemporarily();
    
    // Verificação especial para botão VOLTAR do Android/Fire TV
    // O botão back pode ser identificado por diferentes códigos dependendo do dispositivo
    final keyLabel = event.logicalKey.keyLabel.toLowerCase();
    final keyId = event.logicalKey.keyId;
    
    // KeyId 4294967425 = GoBack no Android
    // KeyId 4294967511 = Escape
    // Também verifica pelo label que pode ser "go back" ou "browser back"
    final isBackButton = 
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.browserBack ||
        keyLabel.contains('back') ||
        keyId == 0x100000125 || // GoBack
        keyId == 0x100000169;   // BrowserBack
    
    if (isBackButton) {
      if (_showChannelList) {
        _hideChannelList();
      } else {
        _navigateBack();
      }
      return; // Importante: retorna para não processar mais nada
    }

    final channelsProvider = context.read<ChannelsProvider>();
    final playerProvider = context.read<PlayerProvider>();
    final currentChannel = playerProvider.currentChannel;
    final channels = channelsProvider.channels;

    switch (event.logicalKey) {
      // OK/Select - Abre lista de canais ou confirma canal selecionado
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        if (_showChannelList) {
          // Confirma o canal selecionado
          if (_selectedChannelIndex >= 0 && _selectedChannelIndex < channels.length) {
            _changeChannel(channels[_selectedChannelIndex]);
          }
          _hideChannelList();
        } else {
          // Abre a lista de canais (não vai mais para o Guia)
          _showChannelListOverlay();
        }
        break;
        
      // Navegação para cima - MUDA CANAL quando fora da lista, navega programação quando na lista
      case LogicalKeyboardKey.arrowUp:
        if (_showChannelList) {
          // Navega para cima na programação (programa anterior)
          setState(() {
            _selectedProgramIndex = (_selectedProgramIndex - 1).clamp(0, 20);
          });
          _scrollToSelectedProgram();
          _resetChannelListTimer();
        } else {
          // MUDA PARA O CANAL ANTERIOR
          final newIndex = (_selectedChannelIndex - 1).clamp(0, channels.length - 1);
          if (newIndex != _selectedChannelIndex && newIndex < channels.length) {
            setState(() => _selectedChannelIndex = newIndex);
            _changeChannel(channels[newIndex]);
          }
        }
        break;
        
      // Navegação para baixo - MUDA CANAL quando fora da lista, navega programação quando na lista
      case LogicalKeyboardKey.arrowDown:
        if (_showChannelList) {
          // Navega para baixo na programação (próximo programa)
          setState(() {
            _selectedProgramIndex = (_selectedProgramIndex + 1).clamp(0, 20);
          });
          _scrollToSelectedProgram();
          _resetChannelListTimer();
        } else {
          // MUDA PARA O PRÓXIMO CANAL
          final newIndex = (_selectedChannelIndex + 1).clamp(0, channels.length - 1);
          if (newIndex != _selectedChannelIndex && newIndex < channels.length) {
            setState(() => _selectedChannelIndex = newIndex);
            _changeChannel(channels[newIndex]);
          }
        }
        break;

      // Navegação para direita - AUMENTA VOLUME quando fora da lista, muda canal quando na lista
      case LogicalKeyboardKey.arrowRight:
        if (_showChannelList) {
          // Navega para o próximo canal na lista
          final newIndex = (_selectedChannelIndex + 1).clamp(0, channels.length - 1);
          setState(() {
            _selectedChannelIndex = newIndex;
            _selectedProgramIndex = 0;  // Reseta seleção de programa
          });
          _scrollToSelectedChannel();
          _resetChannelListTimer();
          // Carrega EPG do canal selecionado
          _loadEpgForSelectedChannel(channels[newIndex].id);
        } else {
          // AUMENTA O VOLUME
          _setVolume(_volume + 0.1);
          _showControlsTemporarily();
        }
        break;
        
      // Navegação para esquerda - DIMINUI VOLUME quando fora da lista, muda canal quando na lista
      case LogicalKeyboardKey.arrowLeft:
        if (_showChannelList) {
          // Navega para o canal anterior na lista
          final newIndex = (_selectedChannelIndex - 1).clamp(0, channels.length - 1);
          setState(() {
            _selectedChannelIndex = newIndex;
            _selectedProgramIndex = 0;  // Reseta seleção de programa
          });
          _scrollToSelectedChannel();
          _resetChannelListTimer();
          // Carrega EPG do canal selecionado
          _loadEpgForSelectedChannel(channels[newIndex].id);
        } else {
          // DIMINUI O VOLUME
          _setVolume(_volume - 0.1);
          _showControlsTemporarily();
        }
        break;
        
      // Canal + dedicado (controle remoto)
      case LogicalKeyboardKey.channelUp:
        {
          final newIndex = (_selectedChannelIndex + 1).clamp(0, channels.length - 1);
          if (newIndex != _selectedChannelIndex && newIndex < channels.length) {
            setState(() => _selectedChannelIndex = newIndex);
            _changeChannel(channels[newIndex]);
          }
        }
        break;
        
      // Canal - dedicado (controle remoto)
      case LogicalKeyboardKey.channelDown:
        {
          final newIndex = (_selectedChannelIndex - 1).clamp(0, channels.length - 1);
          if (newIndex != _selectedChannelIndex && newIndex < channels.length) {
            setState(() => _selectedChannelIndex = newIndex);
            _changeChannel(channels[newIndex]);
          }
        }
        break;
        
      // Volume +
      case LogicalKeyboardKey.audioVolumeUp:
        _setVolume(_volume + 0.1);
        break;
        
      // Volume -
      case LogicalKeyboardKey.audioVolumeDown:
        _setVolume(_volume - 0.1);
        break;
        
      // Mute
      case LogicalKeyboardKey.keyM:
      case LogicalKeyboardKey.audioVolumeMute:
        _toggleMute();
        break;
        
      // Play/Pause
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
        _togglePlayPause();
        break;
        
      // Favorito
      case LogicalKeyboardKey.keyF:
        if (currentChannel != null) {
          context.read<FavoritesProvider>().toggleFavorite(currentChannel.id);
        }
        break;
        
      // Info (mostra controles)
      case LogicalKeyboardKey.keyI:
      case LogicalKeyboardKey.info:
        setState(() => _showControls = !_showControls);
        break;
        
      // Teclas numéricas (0-9)
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        _onNumberPressed('0');
        break;
      case LogicalKeyboardKey.digit1:
      case LogicalKeyboardKey.numpad1:
        _onNumberPressed('1');
        break;
      case LogicalKeyboardKey.digit2:
      case LogicalKeyboardKey.numpad2:
        _onNumberPressed('2');
        break;
      case LogicalKeyboardKey.digit3:
      case LogicalKeyboardKey.numpad3:
        _onNumberPressed('3');
        break;
      case LogicalKeyboardKey.digit4:
      case LogicalKeyboardKey.numpad4:
        _onNumberPressed('4');
        break;
      case LogicalKeyboardKey.digit5:
      case LogicalKeyboardKey.numpad5:
        _onNumberPressed('5');
        break;
      case LogicalKeyboardKey.digit6:
      case LogicalKeyboardKey.numpad6:
        _onNumberPressed('6');
        break;
      case LogicalKeyboardKey.digit7:
      case LogicalKeyboardKey.numpad7:
        _onNumberPressed('7');
        break;
      case LogicalKeyboardKey.digit8:
      case LogicalKeyboardKey.numpad8:
        _onNumberPressed('8');
        break;
      case LogicalKeyboardKey.digit9:
      case LogicalKeyboardKey.numpad9:
        _onNumberPressed('9');
        break;
    }
  }
  
  void _showChannelListOverlay() {
    setState(() {
      _showChannelList = true;
      _selectedProgramIndex = 0;  // Reseta seleção de programa
    });
    _resetChannelListTimer();
    // Scroll para o canal selecionado quando a lista abre
    _scrollToSelectedChannel();
    
    // Carrega EPG do canal selecionado
    final channelsProvider = context.read<ChannelsProvider>();
    if (_selectedChannelIndex < channelsProvider.channels.length) {
      _loadEpgForSelectedChannel(channelsProvider.channels[_selectedChannelIndex].id);
    }
  }
  
  void _hideChannelList() {
    _channelListHideTimer?.cancel();
    setState(() {
      _showChannelList = false;
      _selectedProgramIndex = 0;
    });
  }
  
  void _resetChannelListTimer() {
    _channelListHideTimer?.cancel();
    _channelListHideTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _showChannelList) {
        // Muda para o canal selecionado automaticamente após 8 segundos
        final channelsProvider = context.read<ChannelsProvider>();
        final channels = channelsProvider.channels;
        if (_selectedChannelIndex >= 0 && _selectedChannelIndex < channels.length) {
          final selectedChannel = channels[_selectedChannelIndex];
          final playerProvider = context.read<PlayerProvider>();
          if (selectedChannel.id != playerProvider.currentChannel?.id) {
            _changeChannel(selectedChannel);
          }
        }
        _hideChannelList();
      }
    });
  }
  
  void _scrollToSelectedProgram() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_programsListController.hasClients && mounted) {
        final itemWidth = 210.0;  // Largura do card de programa
        final targetOffset = _selectedProgramIndex * itemWidth;
        final maxScroll = _programsListController.position.maxScrollExtent;
        
        _programsListController.animateTo(
          targetOffset.clamp(0.0, maxScroll),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }
  
  void _scrollToSelectedChannel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_channelListController.hasClients && mounted) {
        // Calcula altura do item baseado no viewport disponível
        // Em TV geralmente cabe ~8 itens, precisamos garantir que o item fique visível
        final viewportHeight = _channelListController.position.viewportDimension;
        final maxScroll = _channelListController.position.maxScrollExtent;
        
        // Altura estimada do item (baseado no total de itens e scroll máximo)
        final totalContentHeight = maxScroll + viewportHeight;
        final channelsProvider = context.read<ChannelsProvider>();
        final totalItems = channelsProvider.channels.length;
        final estimatedItemHeight = totalItems > 0 ? totalContentHeight / totalItems : 56.0;
        
        // Calcula o offset para centralizar o item selecionado
        final itemOffset = _selectedChannelIndex * estimatedItemHeight;
        final centeredOffset = itemOffset - (viewportHeight / 2) + (estimatedItemHeight / 2);
        
        // Garante que o offset está dentro dos limites
        final targetOffset = centeredOffset.clamp(0.0, maxScroll);
        
        _channelListController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }
  
  void _onNumberPressed(String digit) {
    // Cancela timer anterior
    _channelInputTimer?.cancel();
    
    // Adiciona dígito (máximo 3 dígitos)
    if (_channelNumberInput.length < 3) {
      setState(() {
        _channelNumberInput += digit;
      });
    }
    
    // Inicia timer para trocar de canal após 1.5 segundos sem digitar
    _channelInputTimer = Timer(const Duration(milliseconds: 1500), () {
      _switchToChannelNumber();
    });
  }
  
  void _switchToChannelNumber() {
    if (_channelNumberInput.isEmpty) return;
    
    final number = int.tryParse(_channelNumberInput);
    if (number != null) {
      final channelsProvider = context.read<ChannelsProvider>();
      final channel = channelsProvider.getChannelByNumber(number);
      
      if (channel != null) {
        _changeChannel(channel);
      }
    }
    
    // Limpa o input
    setState(() {
      _channelNumberInput = '';
    });
  }

  void _changeChannel(Channel channel) async {
    final playerProvider = context.read<PlayerProvider>();
    final channelsProvider = context.read<ChannelsProvider>();
    
    // Atualiza o índice do canal selecionado
    final index = channelsProvider.channels.indexWhere((c) => c.id == channel.id);
    if (index >= 0) {
      setState(() {
        _selectedChannelIndex = index;
      });
    }
    
    await playerProvider.setChannel(channel);
    _initializePlayer();
  }

  void _setVolume(double value) async {
    // Volume até 200% (2.0) - acima de 100% é boost de áudio via ganho nativo
    final newVolume = value.clamp(0.0, 2.0);
    setState(() {
      _volume = newVolume;
      _isMuted = newVolume == 0;
    });
    
    // Define o volume base no player (máximo 1.0)
    final baseVolume = newVolume.clamp(0.0, 1.0);
    _videoController?.setVolume(baseVolume);
    
    // Se o volume for maior que 100%, usa o LoudnessEnhancer nativo para boost
    if (newVolume > 1.0 && _videoController != null) {
      // Obtém o audio session ID do player (se disponível)
      // Como o video_player não expõe diretamente, usamos o ID do sistema
      try {
        await _volumeBoostService.setVolumeBoost(newVolume, sessionId: 0);
      } catch (e) {
        debugPrint('Erro ao aplicar boost: $e');
      }
    } else {
      // Desativa o boost quando volume <= 100%
      _volumeBoostService.disableBoost();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _videoController?.setVolume(_isMuted ? 0 : _volume.clamp(0.0, 1.0));
    
    // Também ajusta o boost
    if (_isMuted) {
      _volumeBoostService.disableBoost();
    } else if (_volume > 1.0) {
      _volumeBoostService.setVolumeBoost(_volume, sessionId: 0);
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
    setState(() {});
  }

  void _retryLoad() {
    _initializePlayer();
  }

  /// Navega de volta para a tela de canais de forma segura
  void _navigateBack() {
    // Para o vídeo antes de sair
    _videoController?.pause();
    
    // Usa um pequeno delay para garantir que a navegação aconteça
    Future.microtask(() {
      if (mounted) {
        // Sempre volta para a tela de canais - NUNCA fecha o app
        // Isso garante que o botão voltar do controle remoto não feche o app
        Navigator.of(context).pushNamedAndRemoveUntil('/channels', (route) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Intercepta o botão voltar do sistema
      onPopInvokedWithResult: (didPop, result) {
        // Se já fez pop, ignora
        if (didPop) return;
        
        // Trata o voltar manualmente
        if (_showChannelList) {
          _hideChannelList();
        } else {
          _navigateBack();
        }
      },
      child: Focus(
        focusNode: _mainFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          _handleKeyEvent(event);
          return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _showControlsTemporarily,
          onDoubleTap: () {
            // Double tap abre/fecha a lista de canais
            if (_showChannelList) {
              _hideChannelList();
            } else {
              _showChannelListOverlay();
            }
          },
          onLongPress: () {
            // Long press abre lista de canais para usuários mobile
            _showChannelListOverlay();
          },
          // === GESTOS DE SWIPE PARA TOUCH ===
          onVerticalDragStart: (details) {
            _startDragY = details.globalPosition.dy;
            _isDraggingChannel = true;
          },
          onVerticalDragUpdate: (details) {
            if (!_isDraggingChannel) return;
            
            final deltaY = details.globalPosition.dy - _startDragY;
            
            // Swipe para cima = próximo canal, swipe para baixo = canal anterior
            if (deltaY.abs() > 50) {
              final channelsProvider = context.read<ChannelsProvider>();
              final channels = channelsProvider.channels;
              
              if (deltaY < 0) {
                // Swipe para cima = próximo canal
                final newIndex = (_selectedChannelIndex + 1).clamp(0, channels.length - 1);
                if (newIndex != _selectedChannelIndex) {
                  setState(() => _selectedChannelIndex = newIndex);
                  _changeChannel(channels[newIndex]);
                }
              } else {
                // Swipe para baixo = canal anterior
                final newIndex = (_selectedChannelIndex - 1).clamp(0, channels.length - 1);
                if (newIndex != _selectedChannelIndex) {
                  setState(() => _selectedChannelIndex = newIndex);
                  _changeChannel(channels[newIndex]);
                }
              }
              
              _startDragY = details.globalPosition.dy;
            }
          },
          onVerticalDragEnd: (details) {
            _isDraggingChannel = false;
          },
          onHorizontalDragStart: (details) {
            _startDragX = details.globalPosition.dx;
            _startVolume = _volume;
            _isDraggingVolume = true;
            _showControlsTemporarily();
          },
          onHorizontalDragUpdate: (details) {
            if (!_isDraggingVolume) return;
            
            final deltaX = details.globalPosition.dx - _startDragX;
            final screenWidth = MediaQuery.of(context).size.width;
            
            // Cada arrasto de 1/3 da tela = 100% do volume
            final volumeChange = deltaX / (screenWidth / 3);
            final newVolume = (_startVolume + volumeChange).clamp(0.0, 1.0);
            
            _setVolume(newVolume);
          },
          onHorizontalDragEnd: (details) {
            _isDraggingVolume = false;
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Player de vídeo
              _buildVideoPlayer(),
              
              // Loading/Buffering
              if (_isBuffering) _buildBuffering(),
              
              // Erro
              if (_error != null) _buildError(),
              
              // Controles
              if (_showControls && _error == null) _buildControls(),
              
              // Indicador de carregamento EPG (canto superior direito)
              if (_epgTotal > 0 && _epgLoaded < _epgTotal)
                _buildEpgLoadingIndicator(),
              
              // Número do canal sendo digitado
              if (_channelNumberInput.isNotEmpty)
                _buildChannelNumberOverlay(),
              
              // Overlay de lista de canais (navegação TV)
              if (_showChannelList)
                _buildChannelListOverlay(),
            ],
          ),
        ),
      ),
      ),
    );
  }
  
  Widget _buildChannelListOverlay() {
    return Consumer3<ChannelsProvider, PlayerProvider, EpgProvider>(
      builder: (context, channelsProvider, playerProvider, epgProvider, child) {
        final channels = channelsProvider.channels;
        final currentChannel = playerProvider.currentChannel;
        final selectedChannel = _selectedChannelIndex < channels.length 
            ? channels[_selectedChannelIndex] 
            : null;
        final currentProgram = selectedChannel != null 
            ? epgProvider.getCurrentProgram(selectedChannel.id) 
            : null;
        final programs = selectedChannel != null 
            ? epgProvider.getUpcomingPrograms(selectedChannel.id, limit: 8) 
            : <Program>[];
        
        // Escala responsiva baseada na resolução e DPI da tela
        // Para telas de alta densidade (320dpi), usar escala menor
        final screenHeight = MediaQuery.of(context).size.height;
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        // Ajusta escala baseado no DPI: 320dpi = ~2.0 ratio
        final dpiAdjustment = devicePixelRatio >= 2.0 ? 0.65 : 1.0;
        final baseScale = (screenHeight / 1080).clamp(0.8, 1.4);
        final scale = baseScale * dpiAdjustment;
        
        return GestureDetector(
          onTap: _hideChannelList,
          child: Container(
            color: Colors.transparent,
            child: Column(
              children: [
                // Área superior transparente (toca para fechar)
                const Expanded(child: SizedBox()),
                
                // === BARRA DE GUIA ESTILO TV ===
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.95),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.15, 0.3],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // === INFO DO CANAL SELECIONADO + EPG ATUAL ===
                        if (selectedChannel != null)
                          _buildChannelInfoBar(selectedChannel, currentProgram, currentChannel, scale),
                        
                        // === GRADE DE PROGRAMAÇÃO HORIZONTAL ===
                        if (programs.isNotEmpty)
                          _buildProgramsStrip(programs, scale),
                        
                        SizedBox(height: 6 * scale),
                        
                        // === LISTA DE CANAIS HORIZONTAL ===
                        _buildChannelsStrip(channels, currentChannel, scale),
                        
                        // === DICAS DE NAVEGAÇÃO ===
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8 * scale),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildKeyHint('◀▶', 'Canais', scale),
                              SizedBox(width: 16 * scale),
                              _buildKeyHint('▲▼', 'Programação', scale),
                              SizedBox(width: 16 * scale),
                              _buildKeyHint('OK', 'Assistir', scale),
                              SizedBox(width: 16 * scale),
                              _buildKeyHint('VOLTAR', 'Fechar', scale),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // === BARRA DE INFO DO CANAL ===
  Widget _buildChannelInfoBar(Channel channel, CurrentProgram? epg, Channel? currentChannel, double scale) {
    final program = epg?.current;
    final isCurrent = channel.id == currentChannel?.id;
    
    // Calcula progresso
    double progress = 0.0;
    int remaining = 0;
    if (program != null) {
      final now = DateTime.now();
      final totalDuration = program.endTime.difference(program.startTime).inMinutes;
      final elapsed = now.difference(program.startTime).inMinutes;
      progress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.0;
      remaining = program.endTime.difference(now).inMinutes;
    }
    
    return Container(
      margin: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 8 * scale),
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: SaimoTheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(
          color: isCurrent ? SaimoTheme.primary : SaimoTheme.surfaceLight,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Logo do canal
          Container(
            width: 70 * scale,
            height: 70 * scale,
            decoration: BoxDecoration(
              color: SaimoTheme.surfaceLight,
              borderRadius: BorderRadius.circular(10 * scale),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: buildChannelLogoImage(
                channel,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _buildChannelInitials(channel, scale),
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          
          // Info do canal e programa
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Número + Nome do canal
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                      decoration: BoxDecoration(
                        color: SaimoTheme.primary,
                        borderRadius: BorderRadius.circular(5 * scale),
                      ),
                      child: Text(
                        '${channel.channelNumber}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 10 * scale),
                    Expanded(
                      child: Text(
                        channel.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                        decoration: BoxDecoration(
                          color: SaimoTheme.success,
                          borderRadius: BorderRadius.circular(4 * scale),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 10 * scale),
                            SizedBox(width: 5 * scale),
                            Text(
                              'AO VIVO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 8 * scale),
                
                // Programa atual
                if (program != null) ...[
                  Row(
                    children: [
                      Text(
                        '${_formatTime(program.startTime)} - ${_formatTime(program.endTime)}',
                        style: TextStyle(
                          color: SaimoTheme.primary,
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 10 * scale),
                      if (remaining > 0)
                        Text(
                          '• ${remaining}min restantes',
                          style: TextStyle(
                            color: SaimoTheme.textTertiary,
                            fontSize: 12 * scale,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 5 * scale),
                  Text(
                    program.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8 * scale),
                  // Barra de progresso
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4 * scale),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: SaimoTheme.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(SaimoTheme.primary),
                      minHeight: 6 * scale,
                    ),
                  ),
                ] else
                  Text(
                    'Programação não disponível',
                    style: TextStyle(
                      color: SaimoTheme.textTertiary,
                      fontSize: 14 * scale,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChannelInitials(Channel channel, double scale) {
    return Container(
      alignment: Alignment.center,
      color: SaimoTheme.card,
      child: Text(
        channel.name.substring(0, channel.name.length.clamp(0, 2)).toUpperCase(),
        style: TextStyle(
          color: SaimoTheme.primary,
          fontSize: 18 * scale,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  // === FAIXA DE PROGRAMAÇÃO HORIZONTAL COM NAVEGAÇÃO ===
  Widget _buildProgramsStrip(List<Program> programs, double scale) {
    // Limita o índice selecionado ao tamanho real da lista
    final maxIndex = programs.length - 1;
    final safeSelectedIndex = _selectedProgramIndex.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    
    return Container(
      height: 130 * scale,
      margin: EdgeInsets.symmetric(horizontal: 12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título da seção
          Padding(
            padding: EdgeInsets.only(bottom: 10 * scale, left: 6 * scale),
            child: Row(
              children: [
                Icon(Icons.schedule, color: SaimoTheme.primary, size: 22 * scale),
                SizedBox(width: 8 * scale),
                Text(
                  'PROGRAMAÇÃO',
                  style: TextStyle(
                    color: SaimoTheme.primary,
                    fontSize: 17 * scale,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(width: 14 * scale),
                Text(
                  '▲▼ navegar',
                  style: TextStyle(
                    color: SaimoTheme.textTertiary,
                    fontSize: 14 * scale,
                  ),
                ),
              ],
            ),
          ),
          // Lista de programas
          Expanded(
            child: ListView.builder(
              controller: _programsListController,
              scrollDirection: Axis.horizontal,
              itemCount: programs.length,
              itemBuilder: (context, index) {
                final program = programs[index];
                final isNow = program.isCurrentlyAiring;
                final isSelected = index == safeSelectedIndex;
                
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedProgramIndex = index);
                    _resetChannelListTimer();
                  },
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 230 * scale,
                  margin: EdgeInsets.only(right: 10 * scale),
                  padding: EdgeInsets.all(12 * scale),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? SaimoTheme.primary.withOpacity(0.3)
                        : isNow 
                            ? SaimoTheme.primary.withOpacity(0.15)
                            : SaimoTheme.card.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(6 * scale),
                    border: Border.all(
                      color: isSelected 
                          ? Colors.white 
                          : isNow 
                              ? SaimoTheme.primary 
                              : Colors.transparent,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: SaimoTheme.primary.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ] : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          if (isNow)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                              margin: EdgeInsets.only(right: 6 * scale),
                              decoration: BoxDecoration(
                                color: SaimoTheme.error,
                                borderRadius: BorderRadius.circular(3 * scale),
                              ),
                              child: Text(
                                'AGORA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Text(
                            '${_formatTime(program.startTime)} - ${_formatTime(program.endTime)}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : isNow ? SaimoTheme.primary : SaimoTheme.textSecondary,
                              fontSize: 15 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6 * scale),
                      Text(
                        program.title,
                        style: TextStyle(
                          color: isSelected || isNow ? Colors.white : SaimoTheme.textPrimary,
                          fontSize: 17 * scale,
                          fontWeight: isSelected || isNow ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
  
  // === FAIXA DE CANAIS HORIZONTAL ===
  Widget _buildChannelsStrip(List<Channel> channels, Channel? currentChannel, double scale) {
    return Container(
      height: 120 * scale,
      margin: EdgeInsets.symmetric(horizontal: 12 * scale),
      child: ListView.builder(
        controller: _channelListController,
        scrollDirection: Axis.horizontal,
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          final isSelected = index == _selectedChannelIndex;
          final isCurrent = channel.id == currentChannel?.id;
          
          return GestureDetector(
            onTap: () {
              setState(() => _selectedChannelIndex = index);
              _scrollToSelectedChannel();
              // Carrega EPG do canal selecionado
              _loadEpgForSelectedChannel(channel.id);
              _resetChannelListTimer();
            },
            onDoubleTap: () {
              _changeChannel(channel);
              _hideChannelList();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isSelected ? 140 * scale : 100 * scale,
              margin: EdgeInsets.symmetric(horizontal: 4 * scale),
              decoration: BoxDecoration(
                color: isSelected 
                    ? SaimoTheme.primary
                    : isCurrent
                        ? SaimoTheme.primary.withOpacity(0.3)
                        : SaimoTheme.card.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10 * scale),
                border: Border.all(
                  color: isSelected 
                      ? Colors.white
                      : isCurrent
                          ? SaimoTheme.primary
                          : Colors.transparent,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: SaimoTheme.primary.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ] : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8 * scale),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Logo do canal como fundo (semi-transparente)
                    if (channel.logo != null && channel.logo!.isNotEmpty)
                      Positioned.fill(
                        child: Opacity(
                          opacity: isSelected ? 0.45 : 0.35,
                          child: buildChannelLogoImage(
                            channel,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                        ),
                      ),
                    // Conteúdo sobre o logo
                    Padding(
                      padding: EdgeInsets.all(8 * scale),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Número do canal
                          Text(
                            '${channel.channelNumber}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : SaimoTheme.textSecondary,
                              fontSize: isSelected ? 24 * scale : 18 * scale,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.7),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 5 * scale),
                          // Nome do canal
                          Text(
                            channel.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : SaimoTheme.textPrimary,
                              fontSize: isSelected ? 14 * scale : 11 * scale,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.7),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (isCurrent && !isSelected) ...[
                            SizedBox(height: 4 * scale),
                            Container(
                              width: 8 * scale,
                              height: 8 * scale,
                              decoration: const BoxDecoration(
                                color: SaimoTheme.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  
  // Item compacto de canal
  Widget _buildCompactChannelItem({
    required Channel channel,
    required bool isSelected,
    required bool isCurrent,
    required VoidCallback onTap,
    required VoidCallback onDoubleTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
              ? SaimoTheme.primary.withOpacity(0.3)
              : isCurrent
                  ? SaimoTheme.primary.withOpacity(0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected 
                ? SaimoTheme.primary 
                : isCurrent
                    ? SaimoTheme.primary.withOpacity(0.5)
                    : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Número
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected 
                    ? SaimoTheme.primary
                    : isCurrent
                        ? SaimoTheme.primary.withOpacity(0.5)
                        : SaimoTheme.surfaceLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                channel.channelNumber.toString(),
                style: TextStyle(
                  color: isSelected || isCurrent ? Colors.white : SaimoTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Nome
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : SaimoTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isCurrent)
                    Text(
                      '● Assistindo',
                      style: TextStyle(
                        color: SaimoTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            // Indicador
            if (isSelected)
              const Icon(Icons.chevron_right, color: SaimoTheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
  
  // Painel direito com EPG
  Widget _buildEpgPanel(Channel channel, EpgProvider epgProvider, Channel? currentChannel) {
    final programs = epgProvider.getUpcomingPrograms(channel.id, limit: 12);
    final currentProgram = epgProvider.getCurrentProgram(channel.id);
    final isCurrent = channel.id == currentChannel?.id;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header do canal
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: SaimoTheme.surface,
            border: Border(
              bottom: BorderSide(color: SaimoTheme.surfaceLight),
            ),
          ),
          child: Row(
            children: [
              // Logo
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: SaimoTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: buildChannelLogoImage(
                    channel,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        channel.name.substring(0, channel.name.length.clamp(0, 2)).toUpperCase(),
                        style: const TextStyle(
                          color: SaimoTheme.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: SaimoTheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'CH ${channel.channelNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: SaimoTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            channel.category,
                            style: const TextStyle(
                              color: SaimoTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: SaimoTheme.success,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '● AO VIVO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: SaimoTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Botão assistir
              ElevatedButton.icon(
                onPressed: () {
                  _changeChannel(channel);
                  _hideChannelList();
                },
                icon: Icon(isCurrent ? Icons.check : Icons.play_arrow, size: 20),
                label: Text(isCurrent ? 'ASSISTINDO' : 'ASSISTIR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCurrent ? SaimoTheme.success : SaimoTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Programa atual em destaque
        if (currentProgram?.current != null)
          _buildCurrentProgramCard(currentProgram!.current!),
        
        // Título da programação
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: SaimoTheme.primary, size: 22),
              const SizedBox(width: 10),
              const Text(
                'PROGRAMAÇÃO',
                style: TextStyle(
                  color: SaimoTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(),
                style: const TextStyle(
                  color: SaimoTheme.textTertiary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        
        // Lista de programas
        Expanded(
          child: programs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tv_off, color: SaimoTheme.textTertiary, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Programação não disponível',
                        style: TextStyle(color: SaimoTheme.textTertiary, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: programs.length,
                  itemBuilder: (context, index) {
                    final program = programs[index];
                    return _buildProgramListItem(program);
                  },
                ),
        ),
        
        // Footer com dicas
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: SaimoTheme.surface,
            border: Border(top: BorderSide(color: SaimoTheme.surfaceLight)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKeyHintSimple('▲▼', 'Navegar'),
              const SizedBox(width: 20),
              _buildKeyHintSimple('OK', 'Assistir'),
              const SizedBox(width: 20),
              _buildKeyHintSimple('←', 'Voltar'),
            ],
          ),
        ),
      ],
    );
  }
  
  /// KeyHint simples sem scale (para uso fora do overlay)
  Widget _buildKeyHintSimple(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
  
  // Card do programa atual
  Widget _buildCurrentProgramCard(Program program) {
    final now = DateTime.now();
    final totalDuration = program.endTime.difference(program.startTime).inMinutes;
    final elapsed = now.difference(program.startTime).inMinutes;
    final progress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.0;
    final remaining = program.endTime.difference(now).inMinutes;
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SaimoTheme.primary.withOpacity(0.3),
            SaimoTheme.primary.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SaimoTheme.primary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SaimoTheme.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.white, size: 10),
                    SizedBox(width: 5),
                    Text(
                      'AGORA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatTime(program.startTime)} - ${_formatTime(program.endTime)}',
                style: const TextStyle(color: SaimoTheme.textSecondary, fontSize: 14),
              ),
              const Spacer(),
              if (remaining > 0)
                Text(
                  'Restam ${remaining}min',
                  style: const TextStyle(color: SaimoTheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            program.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (program.description != null && program.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              program.description!,
              style: const TextStyle(color: SaimoTheme.textSecondary, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          // Barra de progresso
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(SaimoTheme.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
  
  // Item de programa na lista
  Widget _buildProgramListItem(Program program) {
    final isNow = program.isCurrentlyAiring;
    final isPast = program.endTime.isBefore(DateTime.now());
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNow 
            ? SaimoTheme.primary.withOpacity(0.15)
            : isPast 
                ? Colors.white.withOpacity(0.02)
                : SaimoTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: isNow ? Border.all(color: SaimoTheme.primary.withOpacity(0.5)) : null,
      ),
      child: Row(
        children: [
          // Horário
          SizedBox(
            width: 65,
            child: Text(
              _formatTime(program.startTime),
              style: TextStyle(
                color: isNow ? SaimoTheme.primary : isPast ? SaimoTheme.textTertiary : SaimoTheme.textSecondary,
                fontSize: 16,
                fontWeight: isNow ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          // Título
          Expanded(
            child: Text(
              program.title,
              style: TextStyle(
                color: isPast ? SaimoTheme.textTertiary : SaimoTheme.textPrimary,
                fontSize: 17,
                fontWeight: isNow ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Duração
          Text(
            '${program.endTime.difference(program.startTime).inMinutes}min',
            style: TextStyle(
              color: SaimoTheme.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  String _formatDate() {
    final now = DateTime.now();
    final weekdays = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    return '${weekdays[now.weekday % 7]}, ${now.day}/${now.month}';
  }
  
  Widget _buildKeyHint(String key, String label, double scale) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6 * scale),
          ),
          child: Text(
            key,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(width: 5 * scale),
        Text(
          label,
          style: TextStyle(color: Colors.white70, fontSize: 12 * scale),
        ),
      ],
    );
  }
  
  Widget _buildChannelLogoFallback(Channel channel, bool isSelected) {
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
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  Widget _buildEpgLoadingIndicator() {
    final percent = (_epgLoaded / _epgTotal * 100).round();
    return Positioned(
      top: 16,
      right: 16,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 18,
                child: CircularProgressIndicator(
                  value: _epgLoaded / _epgTotal,
                  strokeWidth: 2,
                  color: SaimoTheme.primary,
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'EPG $percent%',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildChannelNumberOverlay() {
    // Verifica se o canal existe
    final number = int.tryParse(_channelNumberInput);
    final channelsProvider = context.read<ChannelsProvider>();
    final channel = number != null ? channelsProvider.getChannelByNumber(number) : null;
    
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: channel != null ? SaimoTheme.primary : Colors.white30,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _channelNumberInput,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              if (channel != null) ...[
                const SizedBox(height: 8),
                Text(
                  channel.name,
                  style: TextStyle(
                    color: SaimoTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else if (_channelNumberInput.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Canal não encontrado',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(color: Colors.black);
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }

  Widget _buildBuffering() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: SaimoTheme.primary,
              strokeWidth: 4,
            ),
            SizedBox(height: 20),
            Text(
              'Carregando...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: SaimoTheme.error,
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              _error!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _retryLoad,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaimoTheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _navigateBack(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Consumer2<PlayerProvider, EpgProvider>(
      builder: (context, playerProvider, epgProvider, child) {
        final channel = playerProvider.currentChannel;
        if (channel == null) return const SizedBox.shrink();

        final currentProgram = epgProvider.getCurrentProgram(channel.id);

        return AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.2, 0.7, 1.0],
              ),
            ),
            child: Column(
              children: [
                // Header
                _buildHeader(channel),
                
                const Spacer(),
                
                // Footer com controles e EPG
                _buildFooter(channel, currentProgram),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Channel channel) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Botão voltar
            _buildControlButton(
              icon: Icons.arrow_back,
              onTap: () => _navigateBack(),
            ),
            
            const SizedBox(width: 20),
            
            // Info do canal
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: SaimoTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${channel.channelNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        channel.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    channel.category,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            // Favorito
            Consumer<FavoritesProvider>(
              builder: (context, favorites, child) {
                final isFavorite = favorites.isFavorite(channel.id);
                return _buildControlButton(
                  icon: isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? SaimoTheme.favorite : null,
                  onTap: () => favorites.toggleFavorite(channel.id),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(Channel channel, currentProgram) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Controles
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Volume
                _buildVolumeControl(),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // EPG embaixo dos controles
            if (currentProgram?.current != null)
              ProgramInfo(
                currentProgram: currentProgram?.current,
                nextProgram: currentProgram?.next,
                compact: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    String? label,
    double size = 48,
    Color? color,
    VoidCallback? onTap,
  }) {
    return Focus(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color ?? Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl() {
    // Calcula a porcentagem para exibição (0-200%)
    final volumePercent = (_volume * 100).round();
    final isBoost = _volume > 1.0;
    
    return Row(
      children: [
        GestureDetector(
          onTap: _toggleMute,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isBoost ? Colors.orange.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isMuted || _volume == 0
                  ? Icons.volume_off
                  : _volume < 0.5
                      ? Icons.volume_down
                      : isBoost 
                          ? Icons.speaker // Ícone especial para boost
                          : Icons.volume_up,
              color: isBoost ? Colors.orange : Colors.white,
              size: 32,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Indicador de porcentagem com visual melhorado
        Container(
          width: 70,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isBoost 
                ? Colors.orange.withOpacity(0.2) 
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: isBoost ? Border.all(color: Colors.orange, width: 1) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$volumePercent%',
            style: TextStyle(
              color: isBoost ? Colors.orange : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Slider com marcação de 100%
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 180,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                ),
                child: Slider(
                  value: _isMuted ? 0 : _volume,
                  min: 0.0,
                  max: 2.0, // Máximo 200%
                  divisions: 20, // Divisões de 10%
                  onChanged: (value) => _setVolume(value),
                  activeColor: isBoost ? Colors.orange : SaimoTheme.primary,
                  inactiveColor: Colors.white.withOpacity(0.3),
                ),
              ),
            ),
            // Marcador de 100%
            Positioned(
              left: 90 - 1, // Metade do slider
              child: Container(
                width: 2,
                height: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // Indicador de boost melhorado
        if (isBoost)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withOpacity(0.4),
                  Colors.deepOrange.withOpacity(0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: Colors.orange, size: 18),
                const SizedBox(width: 4),
                const Text(
                  'BOOST',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildShortcutsHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⬆⬇', style: TextStyle(color: Colors.white70, fontSize: 14)),
          Text(' Canal  ', style: TextStyle(color: Colors.white54, fontSize: 14)),
          Text('⬅➡', style: TextStyle(color: Colors.white70, fontSize: 14)),
          Text(' Volume  ', style: TextStyle(color: Colors.white54, fontSize: 14)),
          Text('M', style: TextStyle(color: Colors.white70, fontSize: 14)),
          Text(' Mudo  ', style: TextStyle(color: Colors.white54, fontSize: 14)),
          Text('F', style: TextStyle(color: Colors.white70, fontSize: 14)),
          Text(' Favorito', style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }
  
}
