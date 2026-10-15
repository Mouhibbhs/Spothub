import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../features/player/application/playback_controller.dart';
import 'artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackControllerProvider);
    final personal = ref.watch(personalFlavorProvider);
    final track = playback.track;
    if (track == null) return const SizedBox.shrink();
    final max = playback.duration.inMilliseconds;
    final value = max > 0
        ? (playback.position.inMilliseconds / max).clamp(0.0, 1.0)
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 3),
      child: Material(
        color: AppTheme.elevated,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/now-playing'),
          child: SizedBox(
            height: 60,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.08, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: 0.9,
                                end: 1,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                        ),
                        child: Hero(
                          key: ValueKey(track.videoId),
                          tag: 'track-art-${track.videoId}',
                          child: Artwork(
                            key: ValueKey(track.videoId),
                            url: track.thumbnailUrl,
                            size: 42,
                            radius: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (child, animation) =>
                                  _labelTransition(child, animation),
                              child: Text(
                                track.title,
                                key: ValueKey(track.videoId),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (child, animation) =>
                                  _labelTransition(child, animation),
                              child: Text(
                                track.channelName,
                                key: ValueKey('artist-${track.videoId}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.secondaryText,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: playback.isPlaying
                            ? (personal ? 'Pause audio' : 'Pause video')
                            : (personal ? 'Play audio' : 'Play video'),
                        onPressed: () {
                          final controller = ref.read(
                            playbackControllerProvider.notifier,
                          );
                          if (controller.currentSession == null) {
                            context.push('/now-playing');
                          } else {
                            controller.togglePlayback();
                          }
                        },
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                                child: RotationTransition(
                                  turns: Tween<double>(
                                    begin: -0.08,
                                    end: 0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Icon(
                            key: ValueKey(playback.isPlaying),
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 28,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next track',
                        onPressed: playback.canGoNext
                            ? () => ref
                                  .read(playbackControllerProvider.notifier)
                                  .next()
                            : null,
                        icon: const Icon(Icons.skip_next_rounded, size: 25),
                      ),
                    ],
                  ),
                ),
                if (value != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: value, end: value),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.linear,
                      builder: (context, progress, child) =>
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            color: AppTheme.accent,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _labelTransition(Widget child, Animation<double> animation) =>
    FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
