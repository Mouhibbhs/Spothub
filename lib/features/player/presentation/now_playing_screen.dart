import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/music_motion.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../features/downloads/presentation/download_actions.dart';
import '../../../features/player/application/playback_controller.dart';
import '../../../features/search/domain/track.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with WidgetsBindingObserver {
  double? _dragValue;
  bool _isDownloadingTrack = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(playbackControllerProvider.notifier).currentSession ==
              null) {
        unawaited(
          ref.read(playbackControllerProvider.notifier).resumeSelectedTrack(),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(
        ref.read(playbackControllerProvider.notifier).pauseForBackground(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ref.read(playbackControllerProvider.notifier).releaseSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackControllerProvider);
    final personal = ref.watch(personalFlavorProvider);
    final track = playback.track;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(
          child: Text('Choose a video from Search or Your Library.'),
        ),
      );
    }

    final maxMilliseconds = playback.duration.inMilliseconds;
    final sliderValue =
        _dragValue ??
        (maxMilliseconds > 0
            ? playback.position.inMilliseconds
                  .clamp(0, maxMilliseconds)
                  .toDouble()
            : 0.0);
    final favorite = ref.watch(isFavoriteProvider(track.videoId));
    final isFavorite = favorite.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );
    final isDownloaded = personal && track.canPlayOnYouTube
        ? ref.watch(downloadedTrackProvider(track.videoId)).value ?? false
        : false;
    final remaining = playback.duration - playback.position;
    final nextIndex = playback.queueIndex + 1;
    final nextTrack =
        playback.queueIndex >= 0 && nextIndex < playback.queue.length
        ? playback.queue[nextIndex]
        : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: playback.isPlaying
            ? const Color(0xFF18251C)
            : AppTheme.background,
        centerTitle: true,
        leading: const BackButton(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'final-icon.png',
                width: 22,
                height: 22,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 9),
            const Text('Now Playing'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open queue',
            onPressed: () => _showQueue(context, playback.isRadio),
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.82),
            colors: playback.isPlaying
                ? const [
                    Color(0xFF1B3223),
                    Color(0xFF171B18),
                    AppTheme.background,
                  ]
                : const [
                    Color(0xFF222522),
                    Color(0xFF191A19),
                    AppTheme.background,
                  ],
            stops: const [0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 42,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.38),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
                              ),
                              BoxShadow(
                                color: AppTheme.accent.withValues(
                                  alpha: playback.isPlaying ? 0.08 : 0,
                                ),
                                blurRadius: 42,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: personal ? 1 : 16 / 9,
                              child: personal
                                  ? AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 440,
                                      ),
                                      reverseDuration: const Duration(
                                        milliseconds: 280,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, animation) {
                                        final settled = CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutBack,
                                        );
                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0.12, 0.02),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: ScaleTransition(
                                              scale: Tween<double>(
                                                begin: 0.91,
                                                end: 1,
                                              ).animate(settled),
                                              child: child,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Hero(
                                        key: ValueKey(track.videoId),
                                        tag: 'track-art-${track.videoId}',
                                        child: _PlayingArtwork(
                                          isPlaying: playback.isPlaying,
                                          child: Artwork(
                                            key: ValueKey(
                                              'player-art-${track.videoId}',
                                            ),
                                            url: track.thumbnailUrl,
                                            expand: true,
                                            radius: 0,
                                            icon: Icons.music_note_rounded,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ref
                                            .read(
                                              playbackControllerProvider
                                                  .notifier,
                                            )
                                            .playerSurface ??
                                        _PlayerPlaceholder(track: track),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 340),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final curve = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              );
                              return ClipRect(
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.24),
                                    end: Offset.zero,
                                  ).animate(curve),
                                  child: ScaleTransition(
                                    alignment: Alignment.centerLeft,
                                    scale: Tween<double>(
                                      begin: 0.96,
                                      end: 1,
                                    ).animate(curve),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              key: ValueKey('track-info-${track.videoId}'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    height: 1.12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.45,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  track.channelName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.secondaryText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (personal && track.canPlayOnYouTube)
                          IconButton(
                            tooltip: isDownloaded
                                ? 'Downloaded for offline playback'
                                : 'Download for offline playback',
                            onPressed: isDownloaded || _isDownloadingTrack
                                ? null
                                : () => _downloadTrack(track),
                            color: isDownloaded
                                ? AppTheme.accentPressed
                                : AppTheme.secondaryText,
                            icon: _isDownloadingTrack
                                ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    isDownloaded
                                        ? Icons.download_done_rounded
                                        : Icons.download_for_offline_outlined,
                                  ),
                          ),
                        AnimatedFavoriteButton(
                          selected: isFavorite,
                          onPressed: () => _toggleFavorite(track),
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (maxMilliseconds > 0) ...[
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                        ),
                        child: Slider(
                          value: sliderValue,
                          max: maxMilliseconds.toDouble(),
                          activeColor: AppTheme.accentPressed,
                          inactiveColor: Colors.white.withValues(alpha: 0.24),
                          onChanged: playback.hasError
                              ? null
                              : (value) => setState(() => _dragValue = value),
                          onChangeEnd: (value) {
                            setState(() => _dragValue = null);
                            ref
                                .read(playbackControllerProvider.notifier)
                                .seek(Duration(milliseconds: value.round()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _time(playback.position),
                              style: const TextStyle(
                                color: AppTheme.primaryText,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              '-${_time(remaining.isNegative ? Duration.zero : remaining)}',
                              style: const TextStyle(
                                color: AppTheme.secondaryText,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      const SizedBox(height: 19),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (personal)
                          AnimatedModeButton(
                            active: playback.isShuffling,
                            icon: Icons.shuffle_rounded,
                            onPressed: () => ref
                                .read(playbackControllerProvider.notifier)
                                .toggleShuffle(),
                            tooltip: playback.isShuffling
                                ? 'Turn shuffle off'
                                : 'Turn shuffle on',
                            size: 23,
                          )
                        else
                          const SizedBox(width: 42),
                        IconButton(
                          tooltip: 'Previous video',
                          onPressed: playback.canGoPrevious
                              ? () => ref
                                    .read(playbackControllerProvider.notifier)
                                    .previous()
                              : null,
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 34,
                          ),
                        ),
                        PressScale(
                          pressedScale: 0.91,
                          child: IconButton.filled(
                            tooltip: playback.hasError
                                ? 'Retry playback'
                                : playback.isPlaying
                                ? (personal ? 'Pause audio' : 'Pause video')
                                : (personal ? 'Play audio' : 'Play video'),
                            onPressed: () => ref
                                .read(playbackControllerProvider.notifier)
                                .togglePlayback(),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.primaryText,
                              foregroundColor: AppTheme.background,
                              minimumSize: const Size(68, 68),
                              shape: const CircleBorder(),
                            ),
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 190),
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
                              child: playback.hasError
                                  ? const Icon(
                                      Icons.refresh_rounded,
                                      key: ValueKey('retry'),
                                      size: 35,
                                    )
                                  : AnimatedPlayPauseIcon(
                                      key: const ValueKey('play-pause'),
                                      isPlaying: playback.isPlaying,
                                      size: 34,
                                      color: AppTheme.background,
                                    ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next video',
                          onPressed: playback.canGoNext
                              ? () => ref
                                    .read(playbackControllerProvider.notifier)
                                    .next()
                              : null,
                          icon: const Icon(Icons.skip_next_rounded, size: 34),
                        ),
                        if (personal)
                          AnimatedModeButton(
                            active:
                                playback.repeatMode != PlaybackRepeatMode.off,
                            icon: Icons.repeat_rounded,
                            activeIcon:
                                playback.repeatMode == PlaybackRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            onPressed: () => ref
                                .read(playbackControllerProvider.notifier)
                                .cycleRepeatMode(),
                            tooltip: switch (playback.repeatMode) {
                              PlaybackRepeatMode.off => 'Turn repeat on',
                              PlaybackRepeatMode.all => 'Repeat one song',
                              PlaybackRepeatMode.one => 'Turn repeat off',
                            },
                            size: 23,
                          )
                        else
                          const SizedBox(width: 42),
                      ],
                    ),
                    const SizedBox(height: 23),
                    if (playback.hasError)
                      _PlayerStatusCard(
                        icon: Icons.error_outline_rounded,
                        color: const Color(0xFFFF7B75),
                        title: 'Playback needs attention',
                        message:
                            'Tap the play button to retry with a fresh stream, or choose another track.',
                      )
                    else
                      _PlayerStatusCard(
                        icon: personal
                            ? Icons.graphic_eq_rounded
                            : Icons.smart_display_outlined,
                        color: AppTheme.accentPressed,
                        title: personal ? 'YouTube audio' : 'YouTube player',
                        message: personal
                            ? 'Background audio and lock-screen controls are available for this build.'
                            : 'Keep SpotHub open while the embedded YouTube player is active.',
                      ),
                    if (nextTrack != null) ...[
                      const SizedBox(height: 27),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Up next',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showQueue(context, playback.isRadio),
                            icon: const Icon(Icons.queue_music_rounded),
                            label: const Text('Queue'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      TrackTile(
                        track: nextTrack,
                        queue: playback.queue,
                        compact: true,
                        onTap: () => unawaited(
                          ref
                              .read(playbackControllerProvider.notifier)
                              .playTrack(
                                nextTrack,
                                queue: playback.queue,
                                isRadio: playback.isRadio,
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
      ),
    );
  }

  String _time(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _toggleFavorite(Track track) async {
    await ref.read(trackRepositoryProvider).toggleFavorite(track);
    ref.invalidate(favoritesProvider);
    ref.invalidate(isFavoriteProvider(track.videoId));
  }

  Future<void> _downloadTrack(Track track) async {
    setState(() => _isDownloadingTrack = true);
    try {
      await downloadTracks(context, ref, [track]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download this song.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingTrack = false);
    }
  }

  void _showQueue(BuildContext context, bool isRadio) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QueueSheet(isRadio: isRadio),
    );
  }
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet({required this.isRadio});

  final bool isRadio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackControllerProvider);
    final queue = playback.queue;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 3),
              child: Text(
                'Queue',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Hold and drag to reorder · Swipe non-playing songs to remove',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
              ),
            ),
            Expanded(
              child: queue.isEmpty
                  ? const Center(
                      child: Text(
                        'No songs in this queue.',
                        style: TextStyle(color: AppTheme.secondaryText),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: queue.length,
                      onReorder: (oldIndex, newIndex) => unawaited(
                        ref
                            .read(playbackControllerProvider.notifier)
                            .reorderQueue(oldIndex, newIndex),
                      ),
                      itemBuilder: (context, index) {
                        final track = queue[index];
                        final isCurrent = index == playback.queueIndex;
                        return Dismissible(
                          key: ValueKey('queue-${track.videoId}'),
                          direction: isCurrent
                              ? DismissDirection.none
                              : DismissDirection.horizontal,
                          background: const _QueueDismissBackground(
                            alignment: Alignment.centerLeft,
                          ),
                          secondaryBackground: const _QueueDismissBackground(
                            alignment: Alignment.centerRight,
                          ),
                          onDismissed: (_) => unawaited(
                            ref
                                .read(playbackControllerProvider.notifier)
                                .removeQueueTrack(track.videoId),
                          ),
                          child: ReorderableDelayedDragStartListener(
                            index: index,
                            child: ListTile(
                              leading: isCurrent
                                  ? const Icon(
                                      Icons.equalizer_rounded,
                                      color: AppTheme.accent,
                                    )
                                  : Artwork(url: track.thumbnailUrl, size: 46),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                track.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(
                                Icons.drag_handle_rounded,
                                color: AppTheme.secondaryText,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                unawaited(
                                  ref
                                      .read(playbackControllerProvider.notifier)
                                      .playTrack(
                                        track,
                                        queue: queue,
                                        isRadio: isRadio,
                                      ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueDismissBackground extends StatelessWidget {
  const _QueueDismissBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    alignment: alignment,
    decoration: BoxDecoration(
      color: const Color(0xFF572B30),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
  );
}

class _PlayerPlaceholder extends StatelessWidget {
  const _PlayerPlaceholder({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Artwork(url: track.thumbnailUrl, expand: true, radius: 0),
      const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accent,
          ),
        ),
      ),
    ],
  );
}

class _PlayerStatusCard extends StatelessWidget {
  const _PlayerStatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PlayingArtwork extends StatefulWidget {
  const _PlayingArtwork({required this.isPlaying, required this.child});

  final bool isPlaying;
  final Widget child;

  @override
  State<_PlayingArtwork> createState() => _PlayingArtworkState();
}

class _PlayingArtworkState extends State<_PlayingArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _pulse.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MusicMotion.reduced(context);
    if (_reducedMotion == reduced) return;
    _reducedMotion = reduced;
    if (reduced) {
      _pulse.stop();
    } else if (widget.isPlaying) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PlayingArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying == widget.isPlaying) return;
    if (MusicMotion.reduced(context)) {
      _pulse.stop();
      return;
    }
    if (widget.isPlaying) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: widget.child,
    builder: (context, child) =>
        Transform.scale(scale: 1 + (_pulse.value * 0.018), child: child),
  );
}
