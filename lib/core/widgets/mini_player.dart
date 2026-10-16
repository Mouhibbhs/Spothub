import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../features/player/application/playback_controller.dart';
import 'artwork.dart';
import 'music_motion.dart';

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
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Material(
        color: AppTheme.elevated,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/now-playing'),
          child: SizedBox(
            height: 56,
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
                            size: 40,
                            radius: 4,
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
                                style: TextStyle(
                                  color: playback.isPlaying
                                      ? AppTheme.accent
                                      : AppTheme.primaryText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
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
                        visualDensity: VisualDensity.compact,
                        icon: AnimatedPlayPauseIcon(
                          isPlaying: playback.isPlaying,
                          size: 25,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next track',
                        onPressed: playback.canGoNext
                            ? () => ref
                                  .read(playbackControllerProvider.notifier)
                                  .next()
                            : null,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_next_rounded, size: 23),
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
                            backgroundColor: const Color(0xFF535353),
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
