import 'package:flutter/material.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wyw/pages/player/player_controller.dart';

class PlayerItemSurface extends StatefulWidget {
  const PlayerItemSurface({
    super.key,
    required this.playerController,
  });

  final PlayerController playerController;

  @override
  State<PlayerItemSurface> createState() => _PlayerItemSurfaceState();
}

class _PlayerItemSurfaceState extends State<PlayerItemSurface> {
  @override
  Widget build(BuildContext context) {
    final playerController = widget.playerController;
    return Observer(builder: (context) {
      if (playerController.playback.loading ||
          playerController.playback.videoController == null) {
        return Container(
          color: MediaChromeColors.surface,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final aspectRatioMode = playerController.panel.aspectRatioMode;
      final video = Video(
        controller: playerController.playback.videoController!,
        controls: NoVideoControls,
        pauseUponEnteringBackgroundMode: false,
        fit: aspectRatioMode.fit,
        subtitleViewConfiguration: SubtitleViewConfiguration(
          // 字幕样式属媒体铬层（见 MediaChromeColors.subtitleStyle 注释）
          style: MediaChromeColors.subtitleStyle,
          textAlign: TextAlign.center,
          padding: const EdgeInsets.all(24.0),
        ),
      );

      final frameAspectRatio = aspectRatioMode.frameAspectRatio;
      if (frameAspectRatio == null) {
        return video;
      }
      return AspectRatio(
        aspectRatio: frameAspectRatio,
        child: video,
      );
    });
  }
}
