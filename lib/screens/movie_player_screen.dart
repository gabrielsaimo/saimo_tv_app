import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:floating/floating.dart';
import '../services/casting_service.dart';
import '../widgets/options_modal.dart';
import '../models/movie.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';
import '../utils/key_debouncer.dart';
import '../services/storage_service.dart';

/// Enum para rastreamento de elemento focado no D-PAD
enum _FocusElement { playPause, volume, seek, nextEpisode }

/// Player de filmes e séries
class MoviePlayerScreen extends StatefulWidget {
  final Movie? movie;
  
  const MoviePlayerScreen({super.key, this.movie});

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  Timer? _hideControlsTimer;
  Timer? _progressTimer;
  Timer? _saveProgressTimer;
  Timer? _wakelockTimer; // Timer para heartbeat do wakelock
  final FocusNode _mainFocusNode = FocusNode();
  final FocusNode _nextEpisodeFocusNode = FocusNode();
  final KeyDebouncer _debouncer = KeyDebouncer();
  final Floating _floating = Floating();
  
  bool _showControls = true;
  bool _isBuffering = true;
  String? _error;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isInitialized = false;
  
  Movie? _currentMovie;
  Duration _savedPosition = Duration.zero;
  
  // Controle do botão próximo episódio
  bool _showNextEpisodeButton = false;
  bool _isNextEpisodeButtonFocused = false;
  Episode? _nextEpisode;
  int? _nextSeason;
  bool _isLastEpisode = false;
  int _autoPlayCountdown = 10; // Segundos para auto-play
  Timer? _autoPlayTimer;
  
  // Sistema de navegação D-PAD
  _FocusElement _currentFocus = _FocusElement.playPause;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableWakelock();
    _startWakelockHeartbeat();
    _startHideControlsTimer();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
      // Tenta pegar movie/episode do construtor ou dos argumentos da rota
      final args = ModalRoute.of(context)?.settings.arguments;
      Movie? movie = widget.movie;
      
      if (movie == null && args != null) {
        if (args is Movie) {
          movie = args;
        } else if (args is Episode) {
          // Converte Episode para Movie para reprodução
          movie = Movie(
            id: args.id,
            name: args.name,
            url: args.url,
            category: '',
            type: MovieType.series,
          );
          debugPrint('Convertido Episode para Movie: ${args.name} - URL: ${args.url}');
        }
      }
      
      if (movie != null) {
        _currentMovie = movie;
        _loadSavedProgress();
        _initializePlayer();
      } else {
        debugPrint('ERRO: Nenhum filme ou episódio recebido para reprodução!');
        setState(() {
          _error = 'Nenhum conteúdo para reproduzir';
        });
      }
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableWakelock();
      if (_videoController != null && !_videoController!.value.isPlaying && _error == null) {
         _videoController!.play();
      }
    }
  }

  Future<void> _enablePip() async {
    try {
      if (await _floating.isPipAvailable) {
        // Enters PiP mode. 
        // Note: On Android, the Activity takes care of video surface.
        // We might need to handle ratio.
        await _floating.enable(const ImmediatePiP());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PiP não disponível neste dispositivo')),
        );
      }
    } catch (e) {
      debugPrint('Erro PiP: $e');
    }
  }

  double get _aspectRatio {
    if (_videoController != null && _videoController!.value.isInitialized) {
      return _videoController!.value.aspectRatio;
    }
    return 16 / 9;
  }

  void _showCastDialogStandalone() {
    showDialog(
      context: context,
      barrierColor: Colors.transparent, // Let user see video behind if possible? No, overlay.
      builder: (context) => OptionsModal(
        title: _currentMovie?.name ?? 'Vídeo',
        isFavorite: false, // Contextual
        onToggleFavorite: () {}, // No favorite logic here per se, or connect if needed
        onCastSelected: (device) {
           final castingService = CastingService();
           castingService.castMedia(
             device: device,
             url: _currentMovie!.url,
             title: _currentMovie!.name,
             // Add image and subtitle if available
             imageUrl: _currentMovie!.posterUrl,
           );
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Transmitindo para ${device.name}...')),
           );
        },
        // We set initial focus to Cast logic inside modal?
        // Actually OptionsModal defaults to Play or Favorite.
        // We might need to modify OptionsModal to auto-expand Cast if we want direct Cast access.
        // But the user just asked for a button. This is fine.
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disableWakelock();
    _saveProgress();
    _videoController?.dispose();
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _saveProgressTimer?.cancel();
    _autoPlayTimer?.cancel();
    _wakelockTimer?.cancel();
    _mainFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    super.dispose();
  }

  void _enableWakelock() async {
    try {
      if (await WakelockPlus.enabled == false) {
        await WakelockPlus.enable();
      }
    } catch (e) {
      debugPrint('Erro ao ativar wakelock: $e');
    }
  }

  /// Timer periódico (Heartbeat) para garantir que o Wakelock não caia
  void _startWakelockHeartbeat() {
    _wakelockTimer?.cancel();
    _wakelockTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _enableWakelock();
    });
  }

  void _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Erro ao desativar wakelock: $e');
    }
  }

  Future<void> _loadSavedProgress() async {
    if (_currentMovie == null) return;
    
    try {
      final storage = StorageService();
      final progressSeconds = await storage.getMovieProgress(_currentMovie!.id);
      if (progressSeconds > 0) {
        _savedPosition = Duration(seconds: progressSeconds);
        debugPrint('Progresso carregado: $_savedPosition');
      }
    } catch (e) {
      debugPrint('Erro ao carregar progresso: $e');
    }
  }

  Future<void> _saveProgress() async {
    if (_currentMovie == null || _videoController == null) return;
    if (!_videoController!.value.isInitialized) return;
    
    try {
      final position = _videoController!.value.position;
      final storage = StorageService();
      await storage.saveMovieProgress(_currentMovie!.id, position.inSeconds);
    } catch (e) {
      debugPrint('Erro ao salvar progresso: $e');
    }
  }

  void _startProgressSaver() {
    _saveProgressTimer?.cancel();
    _saveProgressTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _saveProgress();
    });
  }

  /// Resolve redirects HTTP e retorna a URL final
  /// Usa GET com Range header pois alguns servidores IPTV não respondem redirects para HEAD
  Future<String> _resolveRedirects(String url) async {
    try {
      final client = http.Client();
      var currentUrl = url;
      var redirectCount = 0;
      const maxRedirects = 10;
      
      while (redirectCount < maxRedirects) {
        // Usa GET com Range para detectar redirects (HEAD não funciona em alguns servidores IPTV)
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Android TV) AppleWebKit/537.36 SaimoTV/1.0'
          ..headers['Range'] = 'bytes=0-0';  // Solicita apenas 1 byte para economizar banda
        
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        
        // Verifica redirect pelo status code (301, 302, 307, 308)
        if (response.statusCode == 301 || response.statusCode == 302 || 
            response.statusCode == 307 || response.statusCode == 308) {
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) {
            // Se a location é relativa, constrói URL absoluta
            if (location.startsWith('/')) {
              final uri = Uri.parse(currentUrl);
              currentUrl = '${uri.scheme}://${uri.host}:${uri.port}$location';
            } else {
              currentUrl = location;
            }
            redirectCount++;
            debugPrint('Redirect $redirectCount: $currentUrl');
          } else {
            break;
          }
        } else {
          // Não é redirect (200, 206, etc), retorna URL atual
          client.close();
          return currentUrl;
        }
      }
      
      client.close();
      return currentUrl;
    } catch (e) {
      debugPrint('Erro ao resolver redirects: $e');
      // Em caso de erro, retorna a URL original
      return url;
    }
  }

  Future<void> _initializePlayer() async {
    if (_currentMovie == null) return;

    setState(() {
      _isBuffering = true;
      _error = null;
    });

    try {
      _videoController?.dispose();
      _videoController = null;
      
      // Validação da URL
      var url = _currentMovie!.url.trim();
      if (url.isEmpty) {
        throw Exception('URL do vídeo inválida');
      }
      
      debugPrint('========================================');
      debugPrint('Iniciando player para: ${_currentMovie!.name}');
      debugPrint('URL original: $url');
      
      // Resolve redirects para obter URL final (muitos servidores IPTV usam redirect)
      debugPrint('Resolvendo redirects...');
      url = await _resolveRedirects(url);
      debugPrint('URL final resolvida: $url');
      debugPrint('========================================');
      
      // Cria novo controller - tenta com e sem headers
      debugPrint('Criando VideoPlayerController para URL: $url');
      
      // Primeiro tenta sem headers customizados (mais compatível)
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(url),
      );

      // Adiciona listener para erros do player
      _videoController!.addListener(() {
        if (_videoController!.value.hasError) {
          debugPrint('ERRO DO VIDEO PLAYER: ${_videoController!.value.errorDescription}');
          if (mounted && _error == null) {
            setState(() {
              _error = 'Erro de reprodução: ${_videoController!.value.errorDescription}';
              _isBuffering = false;
            });
          }
        }
      });

      debugPrint('Inicializando controller...');
      await _videoController!.initialize().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception('Tempo limite excedido ao conectar (45s)'),
      );
      
      // Verifica se inicializou corretamente
      if (!_videoController!.value.isInitialized) {
        throw Exception('Falha na inicialização do vídeo');
      }
      
      debugPrint('Controller inicializado com sucesso!');
      debugPrint('Duração: ${_videoController!.value.duration}');
      debugPrint('Tamanho: ${_videoController!.value.size}');
      
      // IMPORTANTE: Definir volume ANTES de dar play para evitar problemas de áudio em TVs
      final effectiveVolume = _isMuted ? 0.0 : _volume.clamp(0.0, 1.0);
      await _videoController!.setVolume(effectiveVolume);
      
      // Restaura posição salva
      if (_savedPosition > Duration.zero) {
        await _videoController!.seekTo(_savedPosition);
      }
      
      await _videoController!.play();

      _videoController!.addListener(_onVideoUpdate);
      
      _startProgressSaver();

      if (mounted) {
        setState(() {
          _isBuffering = false;
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao inicializar player: $e');
      if (mounted) {
        setState(() {
          _error = 'Erro ao reproduzir: $e';
          _isBuffering = false;
        });
      }
    }
  }

  void _onVideoUpdate() {
    if (!mounted || _videoController == null) return;
    
    final value = _videoController!.value;
    
    if (value.isBuffering != _isBuffering) {
      setState(() => _isBuffering = value.isBuffering);
    }
    
    if (value.hasError && _error == null) {
      setState(() => _error = value.errorDescription ?? 'Erro de reprodução');
    }
    
    // Verifica se deve mostrar botão de próximo episódio (série + sempre visível)
    _checkNextEpisodeButton();
  }
  
  /// Verifica se deve mostrar o botão de próximo episódio
  /// Agora sempre mostra para séries (não apenas nos últimos 60 segundos)
  void _checkNextEpisodeButton() {
    if (_currentMovie == null || !_isInitialized || _videoController == null) return;
    
    // Só para séries
    if (_currentMovie!.type != MovieType.series || _currentMovie!.episodes == null) {
      setState(() => _showNextEpisodeButton = false);
      return;
    }
    
    // Calcula o próximo episódio uma vez
    if (!_showNextEpisodeButton) {
      _calculateNextEpisode();
      setState(() => _showNextEpisodeButton = _nextEpisode != null);
    }
    
    // Inicia auto-play nos últimos 60 segundos
    final value = _videoController!.value;
    final position = value.position;
    final duration = value.duration;
    
    if (duration.inSeconds <= 0) return;
    
    final remaining = duration - position;
    final shouldAutoPlay = remaining.inSeconds <= 60 && remaining.inSeconds > 0;
    
    if (shouldAutoPlay && _autoPlayTimer == null) {
      _startAutoPlayTimer();
    } else if (!shouldAutoPlay && _autoPlayTimer != null) {
      _cancelAutoPlayTimer();
    }
  }
  
  /// Inicia o timer de auto-play
  void _startAutoPlayTimer() {
    _cancelAutoPlayTimer();
    _autoPlayCountdown = 10;
    
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _autoPlayCountdown--;
      });
      
      // Auto-play quando chega a 0
      if (_autoPlayCountdown <= 0) {
        timer.cancel();
        if (_nextEpisode != null && !_isLastEpisode) {
          _goToNextEpisode();
        }
      }
    });
  }
  
  /// Cancela o timer de auto-play
  void _cancelAutoPlayTimer() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }
  
  /// Calcula qual é o próximo episódio
  void _calculateNextEpisode() {
    if (_currentMovie == null || _currentMovie!.episodes == null) return;
    
    final episodes = _currentMovie!.episodes!;
    final currentSeason = _currentMovie!.season ?? 1;
    final currentEpisode = _currentMovie!.episode ?? 1;
    
    // Ordenar temporadas
    final sortedSeasons = episodes.keys.toList()..sort((a, b) {
      final aNum = int.tryParse(a) ?? 0;
      final bNum = int.tryParse(b) ?? 0;
      return aNum.compareTo(bNum);
    });
    
    final currentSeasonKey = currentSeason.toString();
    final currentSeasonEpisodes = episodes[currentSeasonKey] ?? [];
    
    // Procura o próximo episódio na mesma temporada
    Episode? nextEp;
    int? nextSeasonNum;
    
    for (final ep in currentSeasonEpisodes) {
      if (ep.episode == currentEpisode + 1) {
        nextEp = ep;
        nextSeasonNum = currentSeason;
        break;
      }
    }
    
    // Se não achou, procura na próxima temporada
    if (nextEp == null) {
      final currentSeasonIndex = sortedSeasons.indexOf(currentSeasonKey);
      if (currentSeasonIndex >= 0 && currentSeasonIndex < sortedSeasons.length - 1) {
        // Próxima temporada existe
        final nextSeasonKey = sortedSeasons[currentSeasonIndex + 1];
        final nextSeasonEpisodes = episodes[nextSeasonKey] ?? [];
        if (nextSeasonEpisodes.isNotEmpty) {
          nextEp = nextSeasonEpisodes.first;
          nextSeasonNum = int.tryParse(nextSeasonKey) ?? currentSeason + 1;
        }
      } else {
        // É o último episódio - vai para o primeiro da primeira temporada
        _isLastEpisode = true;
        if (sortedSeasons.isNotEmpty) {
          final firstSeasonKey = sortedSeasons.first;
          final firstSeasonEpisodes = episodes[firstSeasonKey] ?? [];
          if (firstSeasonEpisodes.isNotEmpty) {
            nextEp = firstSeasonEpisodes.first;
            nextSeasonNum = int.tryParse(firstSeasonKey) ?? 1;
          }
        }
      }
    } else {
      _isLastEpisode = false;
    }
    
    _nextEpisode = nextEp;
    _nextSeason = nextSeasonNum;
  }
  
  /// Navega para o próximo episódio
  void _goToNextEpisode() {
    if (_nextEpisode == null || _currentMovie == null) return;
    
    HapticFeedback.mediumImpact();
    
    // Cria novo Movie para o próximo episódio
    final nextMovie = _currentMovie!.copyWith(
      id: _nextEpisode!.id,
      name: _nextEpisode!.name,
      url: _nextEpisode!.url,
      season: _nextSeason,
      episode: _nextEpisode!.episode,
    );
    
    // Navega para o player com o novo episódio
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MoviePlayerScreen(movie: nextMovie),
      ),
    );
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    
    // Mostra controles em qualquer tecla
    if (!_showControls) {
      setState(() => _showControls = true);
      _startHideControlsTimer();
    }

    // Voltar
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_debouncer.shouldProcessBack()) {
        _goBack();
      }
      return;
    }

    // === NAVEGAÇÃO D-PAD ===
    // Esquerda
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_currentFocus == _FocusElement.seek) {
        _seekRelative(-10);
      } else {
        HapticFeedback.selectionClick();
        if (_currentFocus == _FocusElement.nextEpisode) {
          // De nextEpisode vai para seek (é mais intuitivo voltar para a barra)
          setState(() => _currentFocus = _FocusElement.seek);
        } else if (_currentFocus == _FocusElement.volume) {
          // De volume vai para playPause
          setState(() => _currentFocus = _FocusElement.playPause);
        } else if (_currentFocus == _FocusElement.playPause) {
          // De playPause mantém foco (fim da linha à esquerda)
          // Opcional: poderia ir para volume (ciclo)
        }
      }
      return;
    }

    // Direita
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_currentFocus == _FocusElement.seek) {
        _seekRelative(10);
      } else {
        HapticFeedback.selectionClick();
        if (_currentFocus == _FocusElement.playPause) {
          // De playPause vai para volume
          setState(() => _currentFocus = _FocusElement.volume);
        } else if (_currentFocus == _FocusElement.volume) {
          // De volume vai para nextEpisode (se existir)
          if (_showNextEpisodeButton) {
            setState(() => _currentFocus = _FocusElement.nextEpisode);
          }
        }
      }
      return;
    }

    // Cima: Move foco visualmente para CIMA
    if (key == LogicalKeyboardKey.arrowUp) {
      HapticFeedback.selectionClick();
      if (_currentFocus == _FocusElement.playPause || _currentFocus == _FocusElement.volume) {
        // Dos controles de baixo, SOBE para o seek
        setState(() => _currentFocus = _FocusElement.seek);
      } else if (_currentFocus == _FocusElement.seek) {
        // Do seek, SOBE para nextEpisode (se existir)
        if (_showNextEpisodeButton) {
          setState(() => _currentFocus = _FocusElement.nextEpisode);
        }
      }
      return;
    }

    // Baixo: Move foco visualmente para BAIXO
    if (key == LogicalKeyboardKey.arrowDown) {
      HapticFeedback.selectionClick();
      if (_currentFocus == _FocusElement.nextEpisode) {
        // De nextEpisode, DESCE para o seek
        setState(() => _currentFocus = _FocusElement.seek);
      } else if (_currentFocus == _FocusElement.seek) {
        // Do seek, DESCE para playPause (controles principais)
        setState(() => _currentFocus = _FocusElement.playPause);
      }
      return;
    }

    // Select/Enter/A: Ativa a ação do elemento focado
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.numpadEnter) {
      HapticFeedback.mediumImpact();
      if (_currentFocus == _FocusElement.playPause) {
        _togglePlayPause();
      } else if (_currentFocus == _FocusElement.nextEpisode && _showNextEpisodeButton) {
        _goToNextEpisode();
      } else if (_currentFocus == _FocusElement.volume) {
        _toggleMute();
      }
      return;
    }

    // Seek shortcuts (mediaRewind/mediaFastForward ainda funcionam)
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(-10);
      return;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(10);
      return;
    }

    // Play/Pause
    if (key == LogicalKeyboardKey.mediaPlayPause || 
        key == LogicalKeyboardKey.space) {
      _togglePlayPause();
      return;
    }

    // Mute
    if (key == LogicalKeyboardKey.keyM ||
        key == LogicalKeyboardKey.audioVolumeMute) {
      _toggleMute();
      return;
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    
    HapticFeedback.lightImpact();
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
    setState(() {});
    _startHideControlsTimer();
  }

  void _seekRelative(int seconds) {
    if (_videoController == null) return;
    
    HapticFeedback.selectionClick();
    final position = _videoController!.value.position;
    final newPosition = position + Duration(seconds: seconds);
    _videoController!.seekTo(newPosition);
    _startHideControlsTimer();
  }

  void _adjustVolume(double delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      _isMuted = _volume == 0;
    });
    _videoController?.setVolume(_volume);
    _startHideControlsTimer();
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() {
      _isMuted = !_isMuted;
    });
    _videoController?.setVolume(_isMuted ? 0 : _volume);
    _startHideControlsTimer();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Volta para a tela anterior de forma segura (nunca fecha o app)
  void _goBack() {
    _saveProgress();
    
    // Usa pop() para voltar para a tela anterior (modal do filme/série)
    // Isso preserva o estado da navegação
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // Se não pode dar pop (stack vazia), vai para o catálogo
      Navigator.of(context).pushReplacementNamed('/movies');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Intercepta o botão voltar do sistema
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _goBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: _mainFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Vídeo
                if (_videoController != null && _isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                ),

              // Buffering indicator
              if (_isBuffering)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            SaimoTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Carregando...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: TVConstants.fontM,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Error
              if (_error != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red,
                          size: TVConstants.iconXL,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Erro de reprodução',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: TVConstants.fontL,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: TVConstants.fontM,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _initializePlayer,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SaimoTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Controles
              if (_showControls) _buildControls(),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Constrói o botão flutuante de próximo episódio (sempre visível para séries)
  Widget _buildNextEpisodeButton() {
    final isLastEp = _isLastEpisode;
    final nextSeasonNum = _nextSeason ?? 1;
    final nextEpNum = _nextEpisode?.episode ?? 1;
    final showCountdown = _autoPlayTimer != null && _autoPlayCountdown > 0 && !isLastEp;
    final isFocused = _currentFocus == _FocusElement.nextEpisode;
    
    String buttonText;
    String subtitleText;
    IconData buttonIcon;
    
    if (isLastEp) {
      buttonText = 'Recomeçar Série';
      subtitleText = 'S${nextSeasonNum.toString().padLeft(2, '0')}E${nextEpNum.toString().padLeft(2, '0')}';
      buttonIcon = Icons.replay_rounded;
    } else {
      buttonText = showCountdown ? 'Próximo em ${_autoPlayCountdown}s' : 'Próximo Episódio';
      subtitleText = 'S${nextSeasonNum.toString().padLeft(2, '0')}E${nextEpNum.toString().padLeft(2, '0')} • ${_nextEpisode?.name ?? ''}';
      buttonIcon = Icons.skip_next_rounded;
    }
    
    return AnimatedOpacity(
      // Sempre visível para séries (opacidade reduzida quando não focado)
      opacity: _showNextEpisodeButton ? (isFocused ? 1.0 : 0.6) : 0.0,
      duration: const Duration(milliseconds: 300),
      child: AnimatedScale(
        scale: isFocused ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          onTap: _goToNextEpisode,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isFocused
                    ? [const Color(0xFFE50914), const Color(0xFFB20710)]
                    : [Colors.black.withOpacity(0.85), Colors.black.withOpacity(0.75)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFocused
                    ? const Color(0xFFFFD700)
                    : Colors.white.withOpacity(0.2),
                width: isFocused ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isFocused
                      ? const Color(0xFFFFD700).withOpacity(0.5)
                      : Colors.black.withOpacity(0.3),
                  blurRadius: isFocused ? 18 : 8,
                  spreadRadius: isFocused ? 2 : 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícone com countdown circular
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (showCountdown)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: _autoPlayCountdown / 10,
                          strokeWidth: 3,
                          backgroundColor: Colors.white.withOpacity(0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                        ),
                      ),
                    Container(
                      padding: EdgeInsets.all(showCountdown ? 6 : 8),
                      decoration: BoxDecoration(
                        color: isFocused
                            ? Colors.white.withOpacity(0.25)
                            : SaimoTheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        buttonIcon,
                        color: Colors.white,
                        size: showCountdown ? 20 : 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        buttonText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: TVConstants.fontM,
                          fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: TVConstants.fontS,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFocused) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFFFFD700), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'OK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: TVConstants.fontXS,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
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
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Top bar
                  _buildTopBar(),
                  
                  const Spacer(),
                  
                  // Bottom bar
                  _buildBottomBar(),
                ],
              ),
              
              // Botão de próximo episódio (posicionado no canto inferior direito)
              if (_showNextEpisodeButton && _nextEpisode != null)
                Positioned(
                  right: 32,
                  bottom: 140,
                  child: _buildNextEpisodeButton(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Botão voltar
          IconButton(
            onPressed: _goBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: TVConstants.iconL,
            ),
          ),
          const SizedBox(width: 12),
          
          // Título
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentMovie?.seriesName ?? _currentMovie?.name ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: TVConstants.fontXL,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_currentMovie?.episodeTag != null)
                  Text(
                    '${_currentMovie!.episodeTag} • ${_currentMovie!.name}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: TVConstants.fontM,
                    ),
                  ),
              ],
            ),
          ),
          
          // Categoria
          if (_currentMovie != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Color(MovieCategory.getColor(_currentMovie!.category)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _currentMovie!.category,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: TVConstants.fontS,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Cast & PiP Buttons (Touch/Mouse)
           Row(
            children: [
              _buildTouchButton(
                icon: Icons.picture_in_picture_alt,
                onTap: _enablePip,
                tooltip: 'PiP',
              ),
              const SizedBox(width: 16),
              _buildTouchButton(
                icon: Icons.cast,
                onTap: _showCastDialogStandalone,
                tooltip: 'Transmitir',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTouchButton({required IconData icon, required VoidCallback onTap, required String tooltip}) {
    return FocusableActionDetector(
      focusNode: FocusNode(canRequestFocus: false), // NO D-PAD
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white30, width: 1),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_videoController == null || !_isInitialized) {
      return const SizedBox.shrink();
    }

    final value = _videoController!.value;
    final position = value.position;
    final duration = value.duration;
    final progress = duration.inSeconds > 0
        ? position.inSeconds / duration.inSeconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar (focável)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _currentFocus == _FocusElement.seek 
                  ? Colors.white.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: TVConstants.fontM,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: _currentFocus == _FocusElement.seek ? 6 : 4,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: _currentFocus == _FocusElement.seek ? 10 : 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTrackColor: _currentFocus == _FocusElement.seek
                          ? const Color(0xFFFFD700)
                          : SaimoTheme.primary,
                      inactiveTrackColor: Colors.white.withOpacity(0.3),
                      thumbColor: _currentFocus == _FocusElement.seek
                          ? const Color(0xFFFFD700)
                          : SaimoTheme.primary,
                      overlayColor: SaimoTheme.primary.withOpacity(0.3),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: (value) {
                        final newPosition = Duration(
                          seconds: (duration.inSeconds * value).toInt(),
                        );
                        _videoController!.seekTo(newPosition);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: TVConstants.fontM,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Controles principais
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Play/Pause (focável)
              GestureDetector(
                onTap: _togglePlayPause,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _currentFocus == _FocusElement.playPause
                        ? const Color(0xFFFFD700)
                        : SaimoTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_currentFocus == _FocusElement.playPause
                            ? const Color(0xFFFFD700)
                            : SaimoTheme.primary).withOpacity(0.4),
                        blurRadius: _currentFocus == _FocusElement.playPause ? 24 : 16,
                        spreadRadius: _currentFocus == _FocusElement.playPause ? 2 : 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: _currentFocus == _FocusElement.playPause
                        ? Colors.black
                        : Colors.white,
                    size: TVConstants.iconXL,
                  ),
                ),
              ),
              
              const SizedBox(width: 24),
              
              // Volume (focável)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _currentFocus == _FocusElement.volume
                      ? Colors.white.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: _currentFocus == _FocusElement.volume
                      ? Border.all(color: const Color(0xFFFFD700), width: 1)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: _currentFocus == _FocusElement.volume
                          ? const Color(0xFFFFD700)
                          : Colors.white,
                      size: TVConstants.iconM,
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: _currentFocus == _FocusElement.volume ? 7 : 5,
                          ),
                          activeTrackColor: _currentFocus == _FocusElement.volume
                              ? const Color(0xFFFFD700)
                              : Colors.white,
                          inactiveTrackColor: Colors.white.withOpacity(0.3),
                          thumbColor: _currentFocus == _FocusElement.volume
                              ? const Color(0xFFFFD700)
                              : Colors.white,
                        ),
                        child: Slider(
                          value: _isMuted ? 0 : _volume,
                          onChanged: (value) {
                            setState(() {
                              _volume = value;
                              _isMuted = value == 0;
                            });
                            _videoController?.setVolume(value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Dicas de navegação com D-PAD
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFocusHint('↑', 'Controles'),
                        const SizedBox(width: 12),
                        _buildFocusHint('↓', 'Seek'),
                        const SizedBox(width: 12),
                        _buildFocusHint('←→', 'Navega'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFocusHint('OK', 'Ativar'),
                        if (_showNextEpisodeButton) ...[
                          const SizedBox(width: 12),
                          _buildFocusHint('→OK', 'Próximo'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Widget auxiliar para mostrar dicas de foco
  Widget _buildFocusHint(String key, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          action,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
