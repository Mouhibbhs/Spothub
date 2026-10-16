import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';

import '../../search/domain/track.dart';
import '../domain/playback_repository.dart';
import 'personal_youtube_audio_handler.dart';

class PersonalYouTubePlaybackRepository implements PlaybackRepository {
  const PersonalYouTubePlaybackRepository(this.handler);

  final PersonalYouTubeAudioHandler handler;

  @override
  PlaybackSession open(
    Track track, {
    List<Track> queue = const [],
    int queueIndex = 0,
    bool loopQueue = true,
    Duration initialPosition = Duration.zero,
  }) => PersonalYouTubePlaybackSession(
    handler: handler,
    track: track,
    queue: queue.isEmpty ? [track] : List.unmodifiable(queue),
    queueIndex: queue.isEmpty ? 0 : queueIndex,
    loopQueue: loopQueue,
    initialPosition: initialPosition,
  );
}

class PersonalYouTubePlaybackSession
    implements PlaybackSession, BackgroundPlaybackSession {
  const PersonalYouTubePlaybackSession({
    required this.handler,
    required this.track,
    required this.queue,
    required this.queueIndex,
    required this.loopQueue,
    required this.initialPosition,
  });

  final PersonalYouTubeAudioHandler handler;
  final Track track;
  final List<Track> queue;
  final int queueIndex;
  final bool loopQueue;
  final Duration initialPosition;

  @override
  Widget get playerSurface => const SizedBox.shrink();

  @override
  Stream<PlaybackProgress> get progress =>
      Stream<PlaybackProgress>.multi((controller) {
        void emit() {
          final state = handler.playbackState.value;
          final item = handler.mediaItem.value;
          controller.add(
            PlaybackProgress(
              position: handler.currentPosition,
              duration:
                  item?.duration ??
                  Duration(seconds: handler.currentTrack?.durationSeconds ?? 0),
              isPlaying: state.playing,
              hasError: state.processingState == AudioProcessingState.error,
              track: handler.currentTrack ?? track,
              queueIndex: state.queueIndex ?? queueIndex,
            ),
          );
        }

        final subscriptions = <StreamSubscription<dynamic>>[
          handler.playbackState.listen((_) => emit()),
          handler.mediaItem.listen((_) => emit()),
          handler.positionStream.listen((_) => emit()),
        ];
        controller.onCancel = () {
          for (final subscription in subscriptions) {
            unawaited(subscription.cancel());
          }
        };
        emit();
      });

  @override
  Future<void> play() {
    if (handler.currentTrack?.videoId == track.videoId) {
      if (handler.isStopped && initialPosition > Duration.zero) {
        return handler.playQueue(
          queue,
          startIndex: queueIndex,
          loopQueue: loopQueue,
          initialPosition: initialPosition,
        );
      }
      if (handler.isPreparing) return Future<void>.value();
      final missingTracks = queue
          .where((item) => !handler.hasTrack(item.videoId))
          .toList(growable: false);
      return handler.appendToQueue(missingTracks).then((_) async {
        await handler.play();
      });
    }
    return handler.playQueue(
      queue,
      startIndex: queueIndex,
      loopQueue: loopQueue,
      initialPosition: initialPosition,
    );
  }

  @override
  Future<void> pause() => handler.pause();

  @override
  Future<void> seek(Duration position) => handler.seek(position);

  @override
  Future<void> dispose() async {
    // The app screen can close while the Android media service keeps playing.
  }
}
