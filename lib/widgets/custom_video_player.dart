import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/stream_caption_service.dart';

/// Widget de player de vídeo com suporte a legendas automáticas em tempo real.
/// 
/// Exibe legendas geradas automaticamente via reconhecimento de fala (Vosk)
/// ou legendas embutidas no stream quando disponíveis.
class CustomVideoPlayer extends StatelessWidget {
  final VideoPlayerController controller;
  final bool showCaptions;

  const CustomVideoPlayer({
    super.key,
    required this.controller,
    this.showCaptions = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(color: Colors.black);
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            // Video layer
            VideoPlayer(controller),
            
            // Caption layer
            if (showCaptions) _buildCaptionLayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptionLayer() {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, VideoPlayerValue value, child) {
        // Priority 1: Embedded captions in video stream
        final embeddedText = value.caption.text;
        if (embeddedText.trim().isNotEmpty) {
          return _CaptionOverlay(
            text: embeddedText,
            isAuto: false,
          );
        }

        // Priority 2: Auto-generated captions via Vosk
        return AnimatedBuilder(
          animation: StreamCaptionService(),
          builder: (context, _) {
            final service = StreamCaptionService();
            final autoText = service.currentText;
            final status = service.statusMessage;
            final isListening = service.isListening;
            
            // Show caption text if available
            if (autoText.trim().isNotEmpty) {
              return _CaptionOverlay(
                text: autoText,
                isAuto: true,
              );
            }
            
            // Show status indicator when initializing/downloading
            if (status.isNotEmpty && !isListening) {
              return _StatusIndicator(
                status: status,
                progress: service.downloadProgress,
              );
            }
            
            // Show listening indicator
            if (isListening && status == 'Ouvindo...') {
              return _ListeningIndicator();
            }
            
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

/// Overlay para exibição de legendas com visual moderno
class _CaptionOverlay extends StatelessWidget {
  final String text;
  final bool isAuto;

  const _CaptionOverlay({
    required this.text,
    this.isAuto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 40,
      left: 24,
      right: 24,
      child: Center(
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(10),
              border: isAuto 
                  ? Border.all(color: Colors.blue.withOpacity(0.5), width: 1)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Caption text
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _getFontSize(context),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    shadows: const [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 3,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
                
                // Auto-generated indicator
                if (isAuto)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'CC Automático',
                          style: TextStyle(
                            color: Colors.blue.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getFontSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 26;
    if (width > 800) return 22;
    return 18;
  }
}

/// Indicador de status durante carregamento/download do modelo
class _StatusIndicator extends StatelessWidget {
  final String status;
  final double progress;

  const _StatusIndicator({
    required this.status,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.closed_caption, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (progress > 0 && progress < 1) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 120,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.blue),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Indicador pulsante de "ouvindo"
class _ListeningIndicator extends StatefulWidget {
  @override
  State<_ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<_ListeningIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(_animation.value),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(_animation.value * 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'CC',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
