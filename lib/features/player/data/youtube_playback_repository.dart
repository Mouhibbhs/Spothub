import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../search/domain/track.dart';
import '../domain/playback_repository.dart';

class YouTubePlaybackRepository implements PlaybackRepository {
  @override
  PlaybackSession open(
    Track track, {
    List<Track> queue = const [],
    int queueIndex = 0,
    bool loopQueue = true,
    Duration initialPosition = Duration.zero,
  }) => YouTubePlaybackSession(track.videoId);
}

class YouTubePlaybackSession implements PlaybackSession {
  YouTubePlaybackSession(String videoId)
    : _controller = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          privacyEnhancedMode: true,
          color: 'white',
        ),
      );

  final YoutubePlayerController _controller;

  @override
  Widget get playerSurface => YoutubePlayer(
    controller: _controller,
    aspectRatio: 16 / 9,
    autoFullScreen: true,
  );

  @override
  Stream<PlaybackProgress> get progress =>
      _controller.videoStateStream.asyncMap((videoState) async {
        final seconds = await _controller.duration;
        return PlaybackProgress(
          position: videoState.position,
          duration: Duration(milliseconds: (seconds * 1000).round()),
          isPlaying: _controller.value.playerState == PlayerState.playing,
          hasError: _controller.value.hasError,
        );
      });

  @override
  Future<void> play() => _controller.playVideo();

  @override
  Future<void> pause() => _controller.pauseVideo();

  @override
  Future<void> seek(Duration position) =>
      _controller.seekTo(seconds: position.inMilliseconds / 1000);

  @override
  Future<void> dispose() => _controller.close();
}
