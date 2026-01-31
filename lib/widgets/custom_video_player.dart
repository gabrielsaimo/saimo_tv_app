import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Widget de player de vídeo simples.
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
            
            // Embedded caption layer (from stream)
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
        // Only show embedded captions from video stream
        final embeddedText = value.caption.text;
        if (embeddedText.trim().isNotEmpty) {
          return Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  embeddedText,
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
              ),
            ),
          );
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  double _getFontSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 26;
    if (width > 800) return 22;
    return 18;
  }
}
