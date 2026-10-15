import 'package:flutter/widgets.dart';

import '../../search/domain/track.dart';

abstract interface class PlaybackRepository {
  PlaybackSession open(
    Track track, {
    List<Track> queue = const [],
    int queueIndex = 0,
    bool loopQueue = true,
    Duration initialPosition = Duration.zero,
  });
}

abstract interface class PlaybackSession {
  Widget get playerSurface;
  Stream<PlaybackProgress> get progress;
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

abstract interface class BackgroundPlaybackSession {}

class PlaybackProgress {
  const PlaybackProgress({
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.hasError = false,
    this.track,
    this.queueIndex,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool hasError;
  final Track? track;
  final int? queueIndex;
}
