import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/stream_caption_service.dart';

/// A wrapper around VideoPlayer that adds controllable closed caption support.
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
      return Container();
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            VideoPlayer(controller),
            if (showCaptions)
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, VideoPlayerValue value, child) {
                  final text = value.caption.text;
                  // Se tiver legenda oficial no vídeo, usa ela
                  if (text.trim().isNotEmpty) {
                    return _buildCaptionOverlay(text);
                  }

                  // Se não, usa o serviço de Legenda via Stream (Vosk)
                  return AnimatedBuilder(
                    animation: StreamCaptionService(),
                    builder: (context, _) {
                      final autoText = StreamCaptionService().currentText;
                      final status = StreamCaptionService().statusMessage;
                      
                      if (autoText.trim().isEmpty) {
                        // Opcional: Mostrar status de init (ex: Baixando modelo...)
                        if (status.isNotEmpty && StreamCaptionService().isListening) {
                           return _buildStatusOverlay(status);
                        }
                        return const SizedBox.shrink();
                      }
                      
                      return _buildCaptionOverlay(autoText, isAuto: true);
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptionOverlay(String text, {bool isAuto = false}) {
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            border: isAuto ? Border.all(color: Colors.red.withOpacity(0.5), width: 1) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                  ],
                ),
              ),
              if (isAuto)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '(Gerado via Áudio)',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildStatusOverlay(String status) {
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          status,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ),
    );
  }
}
