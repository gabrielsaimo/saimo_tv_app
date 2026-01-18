import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';
import '../utils/key_debouncer.dart';
import '../services/storage_service.dart';

/// Player de filmes e séries
class MoviePlayerScreen extends StatefulWidget {
  final Movie? movie;
  
  const MoviePlayerScreen({super.key, this.movie});

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  VideoPlayerController? _videoController;
  Timer? _hideControlsTimer;
  Timer? _progressTimer;
  Timer? _saveProgressTimer;
  final FocusNode _mainFocusNode = FocusNode();
  final FocusNode _nextEpisodeFocusNode = FocusNode();
  final KeyDebouncer _debouncer = KeyDebouncer();
  
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

  @override
  void initState() {
    super.initState();
    _enableWakelock();
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
  void dispose() {
    _disableWakelock();
    _saveProgress();
    _videoController?.dispose();
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _saveProgressTimer?.cancel();
    _mainFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    super.dispose();
  }

  void _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Erro ao ativar wakelock: $e');
    }
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
    
    // Verifica se deve mostrar botão de próximo episódio (série + últimos 60 segundos)
    _checkNextEpisodeButton();
  }
  
  /// Verifica se deve mostrar o botão de próximo episódio
  void _checkNextEpisodeButton() {
    if (_currentMovie == null || !_isInitialized || _videoController == null) return;
    
    // Só para séries
    if (_currentMovie!.type != MovieType.series || _currentMovie!.episodes == null) {
      return;
    }
    
    final value = _videoController!.value;
    final position = value.position;
    final duration = value.duration;
    
    if (duration.inSeconds <= 0) return;
    
    // Mostra nos últimos 60 segundos do episódio
    final remaining = duration - position;
    final shouldShow = remaining.inSeconds <= 60 && remaining.inSeconds > 0;
    
    if (shouldShow != _showNextEpisodeButton) {
      // Calcula o próximo episódio quando for mostrar o botão
      if (shouldShow) {
        _calculateNextEpisode();
      }
      
      setState(() {
        _showNextEpisodeButton = shouldShow;
        if (shouldShow) {
          // Transfere foco para o botão de próximo episódio
          _isNextEpisodeButtonFocused = true;
        } else {
          _isNextEpisodeButtonFocused = false;
        }
      });
    }
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
        // Se botão de próximo episódio estiver focado, volta para controles normais
        if (_isNextEpisodeButtonFocused) {
          setState(() => _isNextEpisodeButtonFocused = false);
          _mainFocusNode.requestFocus();
          return;
        }
        _goBack();
      }
      return;
    }

    // Se o botão de próximo episódio estiver visível, navegar com seta direita foca nele
    if (_showNextEpisodeButton) {
      if (key == LogicalKeyboardKey.arrowRight && !_isNextEpisodeButtonFocused) {
        setState(() => _isNextEpisodeButtonFocused = true);
        _startHideControlsTimer();
        return;
      }
      if (key == LogicalKeyboardKey.arrowLeft && _isNextEpisodeButtonFocused) {
        setState(() => _isNextEpisodeButtonFocused = false);
        _startHideControlsTimer();
        return;
      }
      // Enter/Select no botão focado
      if (_isNextEpisodeButtonFocused && 
          (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter)) {
        _goToNextEpisode();
        return;
      }
    }

    // Play/Pause
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return;
    }

    // Seek
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(-10);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(10);
      return;
    }

    // Volume
    if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(0.1);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-0.1);
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
    
    // Sempre volta para /movies de forma segura
    // Não usa pop() pois a stack pode estar vazia devido ao uso de pushReplacementNamed
    Navigator.of(context).pushReplacementNamed('/movies');
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
              
              // Botão inteligente de próximo episódio
              if (_showNextEpisodeButton && _nextEpisode != null)
                _buildNextEpisodeButton(),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Constrói o botão flutuante de próximo episódio
  Widget _buildNextEpisodeButton() {
    final isLastEp = _isLastEpisode;
    final nextSeasonNum = _nextSeason ?? 1;
    final nextEpNum = _nextEpisode?.episode ?? 1;
    
    String buttonText;
    String subtitleText;
    IconData buttonIcon;
    
    if (isLastEp) {
      buttonText = 'Recomeçar Série';
      subtitleText = 'S${nextSeasonNum.toString().padLeft(2, '0')}E${nextEpNum.toString().padLeft(2, '0')}';
      buttonIcon = Icons.replay_rounded;
    } else {
      buttonText = 'Próximo Episódio';
      subtitleText = 'S${nextSeasonNum.toString().padLeft(2, '0')}E${nextEpNum.toString().padLeft(2, '0')} • ${_nextEpisode?.name ?? ''}';
      buttonIcon = Icons.skip_next_rounded;
    }
    
    return Positioned(
      right: 32,
      bottom: 140,
      child: AnimatedOpacity(
        opacity: _showNextEpisodeButton ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: AnimatedScale(
          scale: _isNextEpisodeButtonFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: GestureDetector(
            onTap: _goToNextEpisode,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isNextEpisodeButtonFocused
                      ? [const Color(0xFFE50914), const Color(0xFFB20710)]
                      : [Colors.black.withOpacity(0.85), Colors.black.withOpacity(0.75)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isNextEpisodeButtonFocused
                      ? const Color(0xFFFFD700)
                      : Colors.white.withOpacity(0.3),
                  width: _isNextEpisodeButtonFocused ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isNextEpisodeButtonFocused
                        ? const Color(0xFFFFD700).withOpacity(0.4)
                        : Colors.black.withOpacity(0.5),
                    blurRadius: _isNextEpisodeButtonFocused ? 16 : 10,
                    spreadRadius: _isNextEpisodeButtonFocused ? 2 : 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isNextEpisodeButtonFocused
                          ? Colors.white.withOpacity(0.2)
                          : SaimoTheme.primary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      buttonIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          buttonText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: TVConstants.fontM,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                  if (_isNextEpisodeButtonFocused) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: TVConstants.fontXS,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
          child: Column(
            children: [
              // Top bar
              _buildTopBar(),
              
              const Spacer(),
              
              // Bottom bar
              _buildBottomBar(),
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
        ],
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
          // Progress bar
          Row(
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
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: SaimoTheme.primary,
                    inactiveTrackColor: Colors.white.withOpacity(0.3),
                    thumbColor: SaimoTheme.primary,
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
          const SizedBox(height: 12),
          
          // Controles
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Volume
              Row(
                children: [
                  IconButton(
                    onPressed: _toggleMute,
                    icon: Icon(
                      _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: TVConstants.iconM,
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                        thumbColor: Colors.white,
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
              
              const SizedBox(width: 32),
              
              // Seek backward
              IconButton(
                onPressed: () => _seekRelative(-10),
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.replay_rounded,
                      color: Colors.white,
                      size: TVConstants.iconXL,
                    ),
                    Positioned(
                      top: 10,
                      child: Text(
                        '10',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Play/Pause
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SaimoTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SaimoTheme.primary.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: TVConstants.iconXL,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Seek forward
              IconButton(
                onPressed: () => _seekRelative(10),
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.forward_10_rounded,
                      color: Colors.white,
                      size: TVConstants.iconXL,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 32),
              
              // Dicas de teclas
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildKeyHint('←→', 'Seek'),
                    const SizedBox(width: 16),
                    _buildKeyHint('↑↓', 'Volume'),
                    const SizedBox(width: 16),
                    _buildKeyHint('OK', 'Play/Pause'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyHint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
