// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../downloads/data/audio_download_repository.dart';
import '../../search/domain/track.dart';

class PersonalYouTubeAudioHandler extends BaseAudioHandler with SeekHandler {
  PersonalYouTubeAudioHandler()
    : _player = AudioPlayer(),
      _youtube = YoutubeExplode(),
      _connectivity = Connectivity() {
    _player.playbackEventStream.listen((_) => _publishPlaybackState());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(_onTrackCompleted());
      }
    });
    _player.errorStream.listen((error) {
      unawaited(_handlePlaybackError(error, _playRequestId));
    });
    _player.positionStream.listen((_) {
      if (_player.position > const Duration(seconds: 3)) {
        _retriesCurrentTrack = 0;
      }
      unawaited(_maybePreloadNext(_playRequestId));
    });
    _player.currentIndexStream.listen((index) {
      if (index == 1) unawaited(_onPreloadedTrackStarted());
    });
  }

  final AudioPlayer _player;
  final YoutubeExplode _youtube;
  final Connectivity _connectivity;
  List<Track> _tracks = const [];
  int _index = 0;
  int _playRequestId = 0;
  int _lastHandledErrorRequest = -1;
  int _retriesCurrentTrack = 0;
  bool _currentTrackFailed = false;
  bool _loopQueue = true;
  bool _repeatOne = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  Duration? _taskRemovedPosition;
  Duration? _pendingStartPosition;
  int? _preparingQueueIndex;
  int? _preloadedQueueIndex;
  _PrimedAudioSource? _preloadedSource;
  final Map<String, Future<AudioOnlyStreamInfo>> _streamInfoCache = {};

  Track? get currentTrack =>
      _tracks.isEmpty || _index < 0 || _index >= _tracks.length
      ? null
      : _tracks[_index];

  Duration get currentPosition =>
      _taskRemovedPosition ?? _pendingStartPosition ?? _player.position;

  Stream<Duration> get positionStream => _player.positionStream;

  bool get isPreparing =>
      playbackState.value.processingState == AudioProcessingState.loading ||
      playbackState.value.processingState == AudioProcessingState.buffering;

  bool get isStopped => _player.processingState == ProcessingState.idle;

  bool matchesQueue(List<Track> tracks) {
    if (tracks.length != _tracks.length) return false;
    for (var index = 0; index < tracks.length; index++) {
      if (tracks[index].videoId != _tracks[index].videoId) return false;
    }
    return true;
  }

  bool hasTrack(String videoId) =>
      _tracks.any((track) => track.videoId == videoId);

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool loopQueue = true,
    Duration initialPosition = Duration.zero,
  }) async {
    if (tracks.isEmpty) return;
    _playRequestId++;
    await _discardPreloadedSource();
    _taskRemovedPosition = null;
    _pendingStartPosition = initialPosition > Duration.zero
        ? initialPosition
        : null;
    _tracks = List.unmodifiable(tracks);
    _index = startIndex.clamp(0, _tracks.length - 1);
    _loopQueue =
        loopQueue ||
        _repeatMode == AudioServiceRepeatMode.all ||
        _repeatMode == AudioServiceRepeatMode.group;
    _retriesCurrentTrack = 0;
    _currentTrackFailed = false;
    queue.add(_tracks.map(_toMediaItem).toList(growable: false));
    await _player.stop();
    await _playCurrent();
  }

  Future<void> appendToQueue(List<Track> tracks) async {
    if (tracks.isEmpty || _tracks.isEmpty) return;
    final knownIds = _tracks.map((track) => track.videoId).toSet();
    final additions = tracks
        .where((track) => knownIds.add(track.videoId))
        .toList(growable: false);
    if (additions.isEmpty) return;
    _tracks = List.unmodifiable([..._tracks, ...additions]);
    queue.add(_tracks.map(_toMediaItem).toList(growable: false));
    _publishPlaybackState();
    unawaited(_maybePreloadNext(_playRequestId));
  }

  Future<void> setQueueOrder(List<Track> tracks, int currentIndex) async {
    if (tracks.isEmpty || currentIndex < 0 || currentIndex >= tracks.length) {
      return;
    }
    final currentVideoId = currentTrack?.videoId;
    if (currentVideoId != null &&
        tracks[currentIndex].videoId != currentVideoId) {
      return;
    }
    _playRequestId++;
    await _discardPreloadedSource();
    _tracks = List.unmodifiable(tracks);
    _index = currentIndex;
    queue.add(_tracks.map(_toMediaItem).toList(growable: false));
    _publishPlaybackState();
  }

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.videoId,
    title: track.title,
    artist: track.channelName,
    duration: track.durationSeconds == null
        ? null
        : Duration(seconds: track.durationSeconds!),
    artUri: track.thumbnailUrl == null
        ? null
        : Uri.tryParse(track.thumbnailUrl!),
  );

  Future<void> _playCurrent() async {
    final requestId = ++_playRequestId;
    final track = currentTrack;
    if (track == null) return;
    await _discardPreloadedSource();

    if (!track.canPlayOnYouTube) {
      _publishPlaybackState(
        processingState: AudioProcessingState.error,
        errorMessage: 'This saved track is no longer playable.',
      );
      _currentTrackFailed = true;
      return;
    }

    _currentTrackFailed = false;
    mediaItem.add(_toMediaItem(track));
    _publishPlaybackState(loading: true);
    try {
      final item = _toMediaItem(track);
      // A device may not expose path_provider to the audio service isolate.
      // Local playback is optional, so fall back to the normal stream on error.
      String? localPath;
      try {
        localPath = await AudioDownloadRepository.findDownloadedFile(
          track.videoId,
        ).timeout(const Duration(milliseconds: 700));
      } catch (_) {
        localPath = null;
      }
      if (requestId != _playRequestId) return;
      if (localPath != null) {
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(localPath), tag: item),
        );
      } else {
        final streamInfo = await _resolveStreamInfo(track);
        if (requestId != _playRequestId) return;
        await _player.setAudioSource(
          _ExplodeAudioSource(_youtube, streamInfo, tag: item),
        );
      }
      if (requestId != _playRequestId) return;
      final resumePosition = _pendingStartPosition;
      if (resumePosition != null && resumePosition > Duration.zero) {
        final duration = _player.duration;
        final target = duration != null && resumePosition >= duration
            ? duration - const Duration(milliseconds: 500)
            : resumePosition;
        if (target > Duration.zero) await _player.seek(target);
      }
      _pendingStartPosition = null;
      if (requestId != _playRequestId) return;
      _streamInfoCache.remove(track.videoId);
      unawaited(
        _player.play().catchError(
          (Object error) => _handlePlaybackError(error, requestId),
        ),
      );
    } catch (error) {
      if (requestId != _playRequestId) return;
      _streamInfoCache.remove(track.videoId);
      await _handlePlaybackError(error, requestId);
    }
  }

  Future<AudioOnlyStreamInfo> _resolveStreamInfo(Track track) async {
    final cached = _streamInfoCache.putIfAbsent(track.videoId, () async {
      final manifest = await _youtube.videos.streams.getManifest(
        track.videoId,
        requireWatchPage: true,
      );
      if (manifest.audioOnly.isEmpty) {
        throw StateError('No audio-only stream is available for this video.');
      }
      final streams = manifest.audioOnly.toList();
      final networkTypes = await _connectivity.checkConnectivity().catchError(
        (Object _) => const <ConnectivityResult>[],
      );
      final hasUnconstrainedNetwork =
          networkTypes.contains(ConnectivityResult.wifi) ||
          networkTypes.contains(ConnectivityResult.ethernet);
      if (hasUnconstrainedNetwork) {
        return manifest.audioOnly.withHighestBitrate();
      }

      // On mobile or unknown networks favor a moderate stream around 64 kbps.
      const targetBitrate = 64 * 1024;
      const minimumBitrate = 48 * 1024;
      final candidates = streams
          .where((stream) => stream.bitrate.bitsPerSecond >= minimumBitrate)
          .toList();
      final selectionPool = candidates.isEmpty ? streams : candidates;
      selectionPool.sort(
        (a, b) => (a.bitrate.bitsPerSecond - targetBitrate).abs().compareTo(
          (b.bitrate.bitsPerSecond - targetBitrate).abs(),
        ),
      );
      return selectionPool.first;
    });
    try {
      return await cached;
    } catch (_) {
      if (identical(_streamInfoCache[track.videoId], cached)) {
        _streamInfoCache.remove(track.videoId);
      }
      rethrow;
    }
  }

  int? _nextQueueIndex() {
    if (_tracks.length < 2 || _repeatOne) return null;
    if (_index < _tracks.length - 1) return _index + 1;
    return _loopQueue ? 0 : null;
  }

  Future<void> _maybePreloadNext(int requestId) async {
    if (requestId != _playRequestId ||
        _tracks.isEmpty ||
        !_player.playing ||
        _player.audioSources.length != 1 ||
        _preparingQueueIndex != null ||
        _preloadedQueueIndex != null) {
      return;
    }

    final duration =
        _player.duration ??
        (currentTrack?.durationSeconds == null
            ? null
            : Duration(seconds: currentTrack!.durationSeconds!));
    final remaining = duration == null ? null : duration - _player.position;
    if (remaining == null || remaining > const Duration(seconds: 10)) return;

    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) return;
    final nextTrack = _tracks[nextIndex];
    if (nextTrack.videoId == currentTrack?.videoId) return;
    final currentVideoId = currentTrack?.videoId;
    _preparingQueueIndex = nextIndex;
    _PrimedAudioSource? source;

    try {
      final info = await _resolveStreamInfo(nextTrack);
      if (!_canFinishPreload(requestId, currentVideoId, nextIndex, nextTrack)) {
        return;
      }
      // DASH fragments do not support resuming at an arbitrary byte offset.
      if (info.fragments.isNotEmpty) return;

      final prefix = await _bufferPrefix(info);
      if (prefix.isEmpty ||
          !_canFinishPreload(requestId, currentVideoId, nextIndex, nextTrack)) {
        return;
      }

      source = _PrimedAudioSource(
        _youtube,
        info,
        prefix,
        tag: _toMediaItem(nextTrack),
      );
      _preloadedSource = source;
      _preloadedQueueIndex = nextIndex;
      await _player.addAudioSource(source);
      if (!_canFinishPreload(requestId, currentVideoId, nextIndex, nextTrack)) {
        if (identical(_preloadedSource, source)) {
          _preloadedSource = null;
          _preloadedQueueIndex = null;
        }
        final sourceIndex = _player.audioSources.indexOf(source);
        final isCurrentSource = sourceIndex == _player.currentIndex;
        if (!isCurrentSource) {
          source.cancel();
          if (sourceIndex >= 0) {
            await _player.removeAudioSourceAt(sourceIndex);
          }
        }
      }
    } catch (_) {
      if (identical(_preloadedSource, source)) {
        _preloadedSource = null;
        _preloadedQueueIndex = null;
      }
      final sourceIndex = source == null
          ? -1
          : _player.audioSources.indexOf(source);
      if (sourceIndex >= 0 && sourceIndex != _player.currentIndex) {
        source!.cancel();
        try {
          await _player.removeAudioSourceAt(sourceIndex);
        } catch (_) {
          // The track may have changed while the failed source was removed.
        }
      } else if (sourceIndex < 0) {
        source?.cancel();
      }
    } finally {
      if (requestId == _playRequestId && _preparingQueueIndex == nextIndex) {
        _preparingQueueIndex = null;
      }
    }
  }

  bool _canFinishPreload(
    int requestId,
    String? currentVideoId,
    int nextIndex,
    Track nextTrack,
  ) =>
      requestId == _playRequestId &&
      currentTrack?.videoId == currentVideoId &&
      _nextQueueIndex() == nextIndex &&
      _tracks[nextIndex].videoId == nextTrack.videoId &&
      _player.playing;

  Future<Uint8List> _bufferPrefix(AudioOnlyStreamInfo info) async {
    final targetBytes = math.min(
      info.size.totalBytes,
      math.max(1, info.bitrate.bitsPerSecond * 4 ~/ 8),
    );
    if (targetBytes <= 0) return Uint8List(0);

    final builder = BytesBuilder(copy: false);
    var bufferedBytes = 0;
    await for (final chunk in _youtube.videos.streams.get(info)) {
      final remaining = targetBytes - bufferedBytes;
      if (remaining <= 0) break;
      final take = math.min(chunk.length, remaining);
      builder.add(take == chunk.length ? chunk : chunk.sublist(0, take));
      bufferedBytes += take;
      if (bufferedBytes >= targetBytes) break;
    }
    return builder.takeBytes();
  }

  Future<void> _onPreloadedTrackStarted() async {
    final nextIndex = _preloadedQueueIndex;
    if (nextIndex == null ||
        nextIndex < 0 ||
        nextIndex >= _tracks.length ||
        _player.currentIndex != 1) {
      return;
    }

    final track = _tracks[nextIndex];
    final source = _preloadedSource;
    _index = nextIndex;
    _preloadedQueueIndex = null;
    _preloadedSource = null;
    _taskRemovedPosition = null;
    _pendingStartPosition = null;
    _playRequestId++;
    _lastHandledErrorRequest = -1;
    _retriesCurrentTrack = 0;
    _currentTrackFailed = false;
    _streamInfoCache.remove(track.videoId);
    mediaItem.add(_toMediaItem(track));
    source?.continueStream();
    _publishPlaybackState();

    try {
      await _player.removeAudioSourceAt(0);
    } catch (_) {
      // The new item is already playing; keep the queue usable if cleanup races.
    }
  }

  Future<void> _syncPreloadedTrack() async {
    if (_player.currentIndex == 1 && _preloadedQueueIndex != null) {
      await _onPreloadedTrackStarted();
    }
  }

  Future<void> _discardPreloadedSource() async {
    _preparingQueueIndex = null;
    if (_player.currentIndex == 1 && _preloadedQueueIndex != null) {
      await _onPreloadedTrackStarted();
    }

    final source = _preloadedSource;
    _preloadedSource = null;
    _preloadedQueueIndex = null;
    source?.cancel();
    if (_player.currentIndex == 0 && _player.audioSources.length > 1) {
      try {
        await _player.removeAudioSourceRange(1, _player.audioSources.length);
      } catch (_) {
        // A track change may already have replaced this source list.
      }
    }
  }

  Future<void> _handlePlaybackError(Object error, int requestId) async {
    if (requestId != _playRequestId || _lastHandledErrorRequest == requestId) {
      return;
    }
    _lastHandledErrorRequest = requestId;

    if (_retriesCurrentTrack < 2) {
      _retriesCurrentTrack++;
      try {
        await _player.stop();
      } catch (_) {
        // Continue with a fresh manifest if stopping the failed source errors.
      }
      await Future<void>.delayed(
        Duration(milliseconds: 350 * _retriesCurrentTrack),
      );
      await _playCurrent();
      return;
    }

    _publishPlaybackState(
      processingState: AudioProcessingState.error,
      errorMessage:
          'Could not play ${currentTrack?.title ?? 'this video'}: $error',
    );
    _currentTrackFailed = true;
  }

  Future<void> _onTrackCompleted() async {
    if (_tracks.isEmpty) return;
    if (_preloadedQueueIndex != null) {
      if (_player.currentIndex == 1) {
        await _onPreloadedTrackStarted();
        return;
      }
      if (_player.currentIndex == 0) {
        await _player.seek(Duration.zero, index: 1);
        return;
      }
    }
    _retriesCurrentTrack = 0;
    if (_repeatOne) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    if (_index == _tracks.length - 1 && !_loopQueue) {
      _publishPlaybackState(processingState: AudioProcessingState.completed);
    } else if (_tracks.length == 1) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
    } else {
      await skipToNext();
    }
  }

  @override
  Future<void> skipToNext() async {
    await _syncPreloadedTrack();
    if (_tracks.isEmpty) return;
    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) return;
    if (_preloadedQueueIndex == nextIndex && _player.currentIndex == 0) {
      _taskRemovedPosition = null;
      _pendingStartPosition = null;
      _retriesCurrentTrack = 0;
      _currentTrackFailed = false;
      await _player.seek(Duration.zero, index: 1);
      return;
    }
    _playRequestId++;
    await _discardPreloadedSource();
    _taskRemovedPosition = null;
    _pendingStartPosition = null;
    _index = nextIndex;
    _retriesCurrentTrack = 0;
    _currentTrackFailed = false;
    await _player.stop();
    await _playCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    await _syncPreloadedTrack();
    if (_tracks.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (!_loopQueue && _index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    _playRequestId++;
    await _discardPreloadedSource();
    _taskRemovedPosition = null;
    _pendingStartPosition = null;
    _index = _loopQueue
        ? (_index - 1 + _tracks.length) % _tracks.length
        : _index - 1;
    _retriesCurrentTrack = 0;
    _currentTrackFailed = false;
    await _player.stop();
    await _playCurrent();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _syncPreloadedTrack();
    if (index < 0 || index >= _tracks.length) return;
    if (_preloadedQueueIndex == index && _player.currentIndex == 0) {
      _taskRemovedPosition = null;
      _pendingStartPosition = null;
      _retriesCurrentTrack = 0;
      _currentTrackFailed = false;
      await _player.seek(Duration.zero, index: 1);
      return;
    }
    _playRequestId++;
    await _discardPreloadedSource();
    _taskRemovedPosition = null;
    _pendingStartPosition = null;
    _index = index;
    _retriesCurrentTrack = 0;
    _currentTrackFailed = false;
    await _player.stop();
    await _playCurrent();
  }

  @override
  Future<void> play() async {
    if (_tracks.isEmpty) return;
    if (_currentTrackFailed ||
        _player.processingState == ProcessingState.idle) {
      _retriesCurrentTrack = 0;
      _lastHandledErrorRequest = -1;
      _pendingStartPosition ??= _taskRemovedPosition;
      _taskRemovedPosition = null;
      await _playCurrent();
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    _repeatOne = repeatMode == AudioServiceRepeatMode.one;
    _loopQueue =
        repeatMode == AudioServiceRepeatMode.all ||
        repeatMode == AudioServiceRepeatMode.group;
    _playRequestId++;
    await _discardPreloadedSource();
    _publishPlaybackState();
    unawaited(_maybePreloadNext(_playRequestId));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    _publishPlaybackState();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    _playRequestId++;
    await _discardPreloadedSource();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    _taskRemovedPosition = _player.position;
    await stop();
  }

  void _publishPlaybackState({
    bool loading = false,
    AudioProcessingState? processingState,
    String? errorMessage,
  }) {
    final state =
        processingState ??
        (loading
            ? AudioProcessingState.loading
            : switch (_player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              });
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: state,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
        queueIndex: _index,
        errorMessage: errorMessage,
      ),
    );
  }
}

class _ExplodeAudioSource extends StreamAudioSource {
  _ExplodeAudioSource(this.youtube, this.info, {super.tag});

  final YoutubeExplode youtube;
  final AudioOnlyStreamInfo info;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final byteStart = (start ?? 0).clamp(0, info.size.totalBytes).toInt();
    final byteEnd = (end ?? info.size.totalBytes)
        .clamp(byteStart, info.size.totalBytes)
        .toInt();
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: info.size.totalBytes,
      contentLength: byteEnd - byteStart,
      offset: byteStart,
      contentType: info.codec.mimeType,
      stream: _range(byteStart, byteEnd),
    );
  }

  Stream<List<int>> _range(int start, int end) async* {
    if (start >= end) return;
    var cursor = start;
    await for (final bytes in youtube.videos.streams.get(info, start: start)) {
      if (cursor >= end) break;
      final take = math.min(bytes.length, end - cursor);
      if (take > 0) {
        yield take == bytes.length ? bytes : bytes.sublist(0, take);
        cursor += take;
      }
    }
  }
}

class _PrimedAudioSource extends StreamAudioSource {
  _PrimedAudioSource(this.youtube, this.info, this.prefix, {super.tag});

  final YoutubeExplode youtube;
  final AudioOnlyStreamInfo info;
  final Uint8List prefix;
  final Completer<void> _continuation = Completer<void>();
  bool _cancelled = false;

  void continueStream() {
    if (!_continuation.isCompleted) _continuation.complete();
  }

  void cancel() {
    _cancelled = true;
    continueStream();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final byteStart = (start ?? 0).clamp(0, info.size.totalBytes);
    final byteEnd = (end ?? info.size.totalBytes).clamp(
      byteStart,
      info.size.totalBytes,
    );
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: info.size.totalBytes,
      contentLength: byteEnd - byteStart,
      offset: byteStart,
      contentType: info.codec.mimeType,
      stream: _range(byteStart, byteEnd),
    );
  }

  Stream<List<int>> _range(int start, int end) async* {
    if (_cancelled || start >= end) return;

    final prefixEnd = math.min(prefix.length, end);
    if (start < prefixEnd) {
      yield prefix.sublist(start, prefixEnd);
    }
    if (end <= prefix.length) return;

    await _continuation.future;
    if (_cancelled) return;

    var cursor = math.max(start, prefix.length);
    await for (final bytes in youtube.videos.streams.get(info, start: cursor)) {
      if (_cancelled) return;
      final chunkEnd = cursor + bytes.length;
      if (chunkEnd > cursor && cursor < end) {
        final take = math.min(bytes.length, end - cursor);
        if (take > 0) {
          yield take == bytes.length ? bytes : bytes.sublist(0, take);
        }
      }
      cursor = chunkEnd;
      if (cursor >= end) return;
    }
  }
}
