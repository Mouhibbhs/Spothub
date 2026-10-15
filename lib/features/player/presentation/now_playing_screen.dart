import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
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

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const BackButton(),
        title: Column(
          children: [
            Text(
              'NOW PLAYING',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppTheme.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 2),
            Text(
              personal ? 'SpotHub Personal' : 'SpotHub',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open queue',
            onPressed: () => _showQueue(
              context,
              playback.queue,
              playback.queueIndex,
              playback.isRadio,
            ),
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 44,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(personal ? 8 : 12),
                    child: AspectRatio(
                      aspectRatio: personal ? 1 : 16 / 9,
                      child: personal
                          ? AnimatedSwitcher(
                              duration: const Duration(milliseconds: 520),
                              reverseDuration: const Duration(
                                milliseconds: 360,
                              ),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final scale = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                );
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.055, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: RotationTransition(
                                      turns: Tween<double>(
                                        begin: 0.012,
                                        end: 0,
                                      ).animate(animation),
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: 0.88,
                                          end: 1,
                                        ).animate(scale),
                                        child: child,
                                      ),
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
                                    key: ValueKey(track.videoId),
                                    url: track.thumbnailUrl,
                                    expand: true,
                                    radius: 0,
                                    icon: Icons.music_note_rounded,
                                  ),
                                ),
                              ),
                            )
                          : ref
                                    .read(playbackControllerProvider.notifier)
                                    .playerSurface ??
                                _PlayerPlaceholder(track: track),
                    ),
                  ),
                  const SizedBox(height: 23),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.18),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Column(
                            key: ValueKey(track.videoId),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                track.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.secondaryText,
                                  fontSize: 14,
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
                              ? AppTheme.accent
                              : AppTheme.secondaryText,
                          icon: _isDownloadingTrack
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  isDownloaded
                                      ? Icons.download_done_rounded
                                      : Icons.download_for_offline_rounded,
                                ),
                        ),
                      IconButton(
                        tooltip: isFavorite
                            ? 'Remove from Liked Songs'
                            : 'Add to Liked Songs',
                        onPressed: () => _toggleFavorite(track),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                                child: child,
                              ),
                          child: Icon(
                            key: ValueKey(isFavorite),
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite ? AppTheme.accent : Colors.white,
                            size: 27,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  if (maxMilliseconds > 0) ...[
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: sliderValue,
                        max: maxMilliseconds.toDouble(),
                        activeColor: AppTheme.accent,
                        inactiveColor: Colors.white24,
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
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _time(playback.position),
                            style: const TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _time(playback.duration),
                            style: const TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    const SizedBox(height: 16),
                  const SizedBox(height: 11),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (personal)
                        IconButton(
                          tooltip: playback.isShuffling
                              ? 'Turn shuffle off'
                              : 'Turn shuffle on',
                          onPressed: () => ref
                              .read(playbackControllerProvider.notifier)
                              .toggleShuffle(),
                          color: playback.isShuffling
                              ? AppTheme.accent
                              : AppTheme.secondaryText,
                          icon: const Icon(Icons.shuffle_rounded, size: 21),
                        ),
                      IconButton(
                        tooltip: 'Previous video',
                        onPressed: playback.canGoPrevious
                            ? () => ref
                                  .read(playbackControllerProvider.notifier)
                                  .previous()
                            : null,
                        icon: const Icon(Icons.skip_previous_rounded, size: 32),
                      ),
                      IconButton.filled(
                        tooltip: playback.hasError
                            ? 'Retry playback'
                            : playback.isPlaying
                            ? (personal ? 'Pause audio' : 'Pause video')
                            : (personal ? 'Play audio' : 'Play video'),
                        onPressed: () => ref
                            .read(playbackControllerProvider.notifier)
                            .togglePlayback(),
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: const Color(0xFF06200F),
                          minimumSize: const Size(62, 62),
                        ),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
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
                            key: ValueKey(
                              '${playback.hasError}-${playback.isPlaying}',
                            ),
                            playback.hasError
                                ? Icons.refresh_rounded
                                : playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 35,
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
                        icon: const Icon(Icons.skip_next_rounded, size: 32),
                      ),
                      if (personal)
                        IconButton(
                          tooltip: switch (playback.repeatMode) {
                            PlaybackRepeatMode.off => 'Turn repeat on',
                            PlaybackRepeatMode.all => 'Repeat one song',
                            PlaybackRepeatMode.one => 'Turn repeat off',
                          },
                          onPressed: () => ref
                              .read(playbackControllerProvider.notifier)
                              .cycleRepeatMode(),
                          color: playback.repeatMode == PlaybackRepeatMode.off
                              ? AppTheme.secondaryText
                              : AppTheme.accent,
                          icon: Icon(
                            playback.repeatMode == PlaybackRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            size: 21,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 19),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            playback.hasError
                                ? 'This track could not be played after a retry. Tap retry to resolve a fresh stream, or choose another track.'
                                : personal
                                ? 'Personal playback continues in the background. Control it from the notification or lock screen.'
                                : 'Playback stays in SpotHub. YouTube requires its embedded player to remain visible, so playback pauses when SpotHub goes to the background.',
                            style: const TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 11,
                              height: 1.4,
                            ),
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

  void _showQueue(
    BuildContext context,
    List<Track> queue,
    int currentIndex,
    bool isRadio,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Text(
                  'Queue',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: queue.isEmpty
                    ? const Center(
                        child: Text(
                          'No more videos in this queue.',
                          style: TextStyle(color: AppTheme.secondaryText),
                        ),
                      )
                    : ListView.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, index) => ListTile(
                          leading: index == currentIndex
                              ? const Icon(
                                  Icons.equalizer_rounded,
                                  color: AppTheme.accent,
                                )
                              : Artwork(
                                  url: queue[index].thumbnailUrl,
                                  size: 46,
                                ),
                          title: Text(
                            queue[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            queue[index].channelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            ref
                                .read(playbackControllerProvider.notifier)
                                .playTrack(
                                  queue[index],
                                  queue: queue,
                                  isRadio: isRadio,
                                );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PlayingArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying == widget.isPlaying) return;
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
        Transform.scale(scale: 1 + (_pulse.value * 0.012), child: child),
  );
}
