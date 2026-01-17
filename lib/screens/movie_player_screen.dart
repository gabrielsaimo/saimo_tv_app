import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/movie.dart';
import '../utils/theme.dart';
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
  
  bool _showControls = true;
  bool _isBuffering = true;
  String? _error;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isInitialized = false;
  
  Movie? _currentMovie;
  Duration _savedPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _enableWakelock();
    _startHideControlsTimer();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
      // Tenta pegar movie do construtor ou dos argumentos da rota
      final movie = widget.movie ?? (ModalRoute.of(context)?.settings.arguments as Movie?);
      if (movie != null) {
        _currentMovie = movie;
        _loadSavedProgress();
        _initializePlayer();
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

  Future<void> _initializePlayer() async {
    if (_currentMovie == null) return;

    setState(() {
      _isBuffering = true;
      _error = null;
    });

    try {
      _videoController?.dispose();
      
      // Cria novo controller
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_currentMovie!.url),
        httpHeaders: const {
          'User-Agent': 'SaimoTV/1.0',
        },
      );

      await _videoController!.initialize();
      
      // Restaura posição salva
      if (_savedPosition > Duration.zero) {
        await _videoController!.seekTo(_savedPosition);
      }
      
      await _videoController!.play();
      await _videoController!.setVolume(_volume);

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
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
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
      _goBack();
      return;
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
                            fontSize: 14,
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
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Erro de reprodução',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
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
              size: 28,
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_currentMovie?.episodeTag != null)
                  Text(
                    '${_currentMovie!.episodeTag} • ${_currentMovie!.name}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
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
                  fontSize: 12,
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
                  fontSize: 14,
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
                  fontSize: 14,
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
                      size: 24,
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
                      size: 36,
                    ),
                    Positioned(
                      top: 10,
                      child: Text(
                        '10',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 9,
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
                    size: 36,
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
                      size: 36,
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
