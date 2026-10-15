import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../search/domain/track.dart';
import '../data/personal_youtube_audio_handler.dart';
import '../data/personal_youtube_playback_repository.dart';
import '../data/youtube_playback_repository.dart';
import '../domain/playback_repository.dart';

final personalAudioHandlerProvider = Provider<PersonalYouTubeAudioHandler>(
  (ref) => throw StateError('Personal audio handler is not initialized.'),
);

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  if (ref.watch(personalFlavorProvider)) {
    return PersonalYouTubePlaybackRepository(
      ref.watch(personalAudioHandlerProvider),
    );
  }
  return YouTubePlaybackRepository();
});

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

enum PlaybackRepeatMode { off, all, one }

class PlaybackState {
  const PlaybackState({
    this.track,
    this.queue = const [],
    this.queueIndex = 0,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.hasError = false,
    this.loopsQueue = false,
    this.isRadio = false,
    this.isShuffling = false,
    this.repeatMode = PlaybackRepeatMode.off,
  });

  final Track? track;
  final List<Track> queue;
  final int queueIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool hasError;
  final bool loopsQueue;
  final bool isRadio;
  final bool isShuffling;
  final PlaybackRepeatMode repeatMode;

  bool get canGoPrevious =>
      track != null && (loopsQueue ? queue.isNotEmpty : queueIndex > 0);
  bool get canGoNext =>
      track != null &&
      (loopsQueue ? queue.isNotEmpty : queueIndex < queue.length - 1);

  PlaybackState copyWith({
    Track? track,
    List<Track>? queue,
    int? queueIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? hasError,
    bool? loopsQueue,
    bool? isRadio,
    bool? isShuffling,
    PlaybackRepeatMode? repeatMode,
  }) => PlaybackState(
    track: track ?? this.track,
    queue: queue ?? this.queue,
    queueIndex: queueIndex ?? this.queueIndex,
    isPlaying: isPlaying ?? this.isPlaying,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    hasError: hasError ?? this.hasError,
    loopsQueue: loopsQueue ?? this.loopsQueue,
    isRadio: isRadio ?? this.isRadio,
    isShuffling: isShuffling ?? this.isShuffling,
    repeatMode: repeatMode ?? this.repeatMode,
  );
}

class PlaybackController extends Notifier<PlaybackState> {
  static const _maxRadioQueueSize = 30;
  static const _radioHistoryToKeep = 5;

  PlaybackSession? _session;
  StreamSubscription<PlaybackProgress>? _progressSubscription;
  Future<void>? _opening;
  String? _openingVideoId;
  int _generation = 0;
  List<Track> _unshuffledQueue = const [];
  Timer? _saveTimer;
  Future<void> _saveChain = Future<void>.value();
  bool _restoreCancelled = false;

  PlaybackSession? get currentSession => _session;
  Widget? get playerSurface => _session?.playerSurface;

  @override
  PlaybackState build() {
    ref.onDispose(() {
      _saveTimer?.cancel();
      unawaited(_progressSubscription?.cancel());
      unawaited(_session?.dispose());
    });
    if (ref.read(personalFlavorProvider)) {
      unawaited(_restoreSavedPlayback());
    }
    return const PlaybackState();
  }

  Future<void> playTrack(
    Track track, {
    List<Track> queue = const [],
    bool? isRadio,
    String? radioQuery,
  }) async {
    _restoreCancelled = true;
    final uniqueQueue = <Track>[];
    for (final item in [...queue, track]) {
      if (!uniqueQueue.contains(item)) uniqueQueue.add(item);
    }
    _unshuffledQueue = List.unmodifiable(uniqueQueue);
    var playableQueue = uniqueQueue;
    var index = playableQueue.indexOf(track);
    final radio =
        isRadio ??
        (ref.read(personalFlavorProvider) &&
            queue.isEmpty &&
            track.source == 'youtube');
    if (ref.read(personalFlavorProvider) && state.isShuffling) {
      final before = playableQueue.sublist(0, index);
      final after = playableQueue.sublist(index + 1)..shuffle(math.Random());
      playableQueue = [...before, track, ...after];
      index = before.length;
    }
    await _open(
      track,
      queue: playableQueue,
      queueIndex: index,
      isRadio: radio,
      radioQuery: radioQuery,
    );
  }

  Future<void> toggleShuffle() async {
    if (!ref.read(personalFlavorProvider)) return;
    final enabled = !state.isShuffling;
    final track = state.track;
    var nextQueue = state.queue;
    var nextIndex = state.queueIndex;
    if (track != null && state.queue.isNotEmpty) {
      if (enabled) {
        final played = state.queue.take(state.queueIndex + 1).toList();
        final upcoming = state.queue.skip(state.queueIndex + 1).toList()
          ..shuffle(math.Random());
        nextQueue = [...played, ...upcoming];
        nextIndex = played.length - 1;
      } else {
        final restored = _unshuffledQueue.isEmpty
            ? state.queue
            : _unshuffledQueue;
        final restoredIndex = restored.indexWhere(
          (item) => item.videoId == track.videoId,
        );
        if (restoredIndex >= 0) {
          nextQueue = restored;
          nextIndex = restoredIndex;
        }
      }
    }
    state = state.copyWith(
      queue: List.unmodifiable(nextQueue),
      queueIndex: nextIndex,
      isShuffling: enabled,
    );
    _schedulePlaybackSave(immediate: true);
    final handler = ref.read(personalAudioHandlerProvider);
    await handler.setShuffleMode(
      enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    if (track != null && nextQueue.isNotEmpty) {
      await handler.setQueueOrder(nextQueue, nextIndex);
    }
  }

  Future<void> cycleRepeatMode() async {
    if (!ref.read(personalFlavorProvider)) return;
    final nextMode = switch (state.repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    state = state.copyWith(
      repeatMode: nextMode,
      loopsQueue: nextMode == PlaybackRepeatMode.all,
    );
    _schedulePlaybackSave(immediate: true);
    final handler = ref.read(personalAudioHandlerProvider);
    await handler.setRepeatMode(switch (nextMode) {
      PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
      PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
      PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
    });
  }

  Future<void> togglePlayback() async {
    final session = _session;
    if (session == null) return;
    if (state.isPlaying) {
      await session.pause();
      _schedulePlaybackSave(immediate: true);
    } else {
      await session.play();
      _schedulePlaybackSave(immediate: true);
    }
  }

  Future<void> pauseForBackground() async {
    final session = _session;
    if (session == null || session is BackgroundPlaybackSession) return;
    await session.pause();
    if (identical(_session, session)) {
      state = state.copyWith(isPlaying: false);
    }
  }

  Future<void> resumeSelectedTrack() async {
    if (state.track == null) return;
    if (_session != null) {
      await _session!.play();
      return;
    }
    await _open(
      state.track!,
      queue: state.queue,
      queueIndex: state.queueIndex,
      isRadio: state.isRadio,
      initialPosition: state.position,
    );
  }

  Future<void> releaseSession() async {
    if (_session is BackgroundPlaybackSession) return;
    _generation++;
    await _opening;
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    await _session?.pause();
    await _session?.dispose();
    _session = null;
    if (state.track != null) {
      state = state.copyWith(
        isPlaying: false,
        position: Duration.zero,
        duration: Duration.zero,
      );
    }
  }

  Future<void> seek(Duration position) async {
    await _session?.seek(position);
    state = state.copyWith(position: position);
    _schedulePlaybackSave(immediate: true);
  }

  Future<void> next() async {
    if (!state.canGoNext) return;
    final nextIndex = state.loopsQueue
        ? (state.queueIndex + 1) % state.queue.length
        : state.queueIndex + 1;
    await _open(
      state.queue[nextIndex],
      queue: state.queue,
      queueIndex: nextIndex,
      isRadio: state.isRadio,
    );
  }

  Future<void> previous() async {
    if (!state.canGoPrevious) return;
    final previousIndex = state.loopsQueue
        ? (state.queueIndex - 1 + state.queue.length) % state.queue.length
        : state.queueIndex - 1;
    await _open(
      state.queue[previousIndex],
      queue: state.queue,
      queueIndex: previousIndex,
      isRadio: state.isRadio,
    );
  }

  Future<bool> addToQueueNext(Track track) async {
    if (state.track == null || state.queue.isEmpty) {
      await playTrack(track, queue: [track], isRadio: false);
      return true;
    }
    final currentTrack = state.track!;
    if (currentTrack.videoId == track.videoId) return false;

    final nextQueue = [...state.queue]
      ..removeWhere((item) => item.videoId == track.videoId);
    final currentIndex = nextQueue.indexWhere(
      (item) => item.videoId == currentTrack.videoId,
    );
    if (currentIndex < 0) return false;
    nextQueue.insert(currentIndex + 1, track);
    final canonical = _unshuffledQueue.isEmpty ? state.queue : _unshuffledQueue;
    final nextCanonical = [...canonical]
      ..removeWhere((item) => item.videoId == track.videoId);
    final canonicalIndex = nextCanonical.indexWhere(
      (item) => item.videoId == currentTrack.videoId,
    );
    if (canonicalIndex >= 0) {
      nextCanonical.insert(canonicalIndex + 1, track);
    } else {
      nextCanonical
        ..clear()
        ..addAll(nextQueue);
    }
    _unshuffledQueue = List.unmodifiable(nextCanonical);
    state = state.copyWith(
      queue: List.unmodifiable(nextQueue),
      queueIndex: currentIndex,
    );
    _schedulePlaybackSave(immediate: true);

    if (ref.read(personalFlavorProvider)) {
      await ref
          .read(personalAudioHandlerProvider)
          .setQueueOrder(nextQueue, currentIndex);
    }
    return true;
  }

  Future<void> _open(
    Track track, {
    required List<Track> queue,
    required int queueIndex,
    required bool isRadio,
    String? radioQuery,
    Duration initialPosition = Duration.zero,
  }) {
    if (_opening != null && _openingVideoId == track.videoId) return _opening!;
    final operation = _openInternal(
      track,
      queue: queue,
      queueIndex: queueIndex,
      isRadio: isRadio,
      radioQuery: radioQuery,
      initialPosition: initialPosition,
    );
    _openingVideoId = track.videoId;
    _opening = operation;
    return operation.whenComplete(() {
      if (identical(_opening, operation)) {
        _opening = null;
        _openingVideoId = null;
      }
    });
  }

  Future<void> _openInternal(
    Track track, {
    required List<Track> queue,
    required int queueIndex,
    required bool isRadio,
    String? radioQuery,
    required Duration initialPosition,
  }) async {
    final generation = ++_generation;
    final repeatMode = state.repeatMode;
    final isShuffling = state.isShuffling;
    final oldSubscription = _progressSubscription;
    final oldSession = _session;
    _progressSubscription = null;
    _session = null;
    state = PlaybackState(
      track: track,
      queue: List.unmodifiable(queue),
      queueIndex: queueIndex,
      position: initialPosition,
      loopsQueue: repeatMode == PlaybackRepeatMode.all,
      isRadio: isRadio,
      isShuffling: isShuffling,
      repeatMode: repeatMode,
    );
    await oldSubscription?.cancel();
    await oldSession?.dispose();
    if (generation != _generation) return;

    final session = ref
        .read(playbackRepositoryProvider)
        .open(
          track,
          queue: queue,
          queueIndex: queueIndex,
          loopQueue: repeatMode == PlaybackRepeatMode.all,
          initialPosition: initialPosition,
        );
    _session = session;
    state = PlaybackState(
      track: track,
      queue: List.unmodifiable(queue),
      queueIndex: queueIndex,
      position: initialPosition,
      loopsQueue: repeatMode == PlaybackRepeatMode.all,
      isRadio: isRadio,
      isShuffling: isShuffling,
      repeatMode: repeatMode,
    );
    _progressSubscription = session.progress.listen((progress) {
      if (!identical(_session, session)) return;
      final wasPlaying = state.isPlaying;
      state = state.copyWith(
        isPlaying: progress.isPlaying,
        position: progress.position,
        duration: progress.duration,
        hasError: progress.hasError,
        track: progress.track,
        queueIndex: progress.queueIndex,
      );
      if (progress.isPlaying) {
        _schedulePlaybackSave();
      } else if (wasPlaying) {
        _schedulePlaybackSave(immediate: true);
      }
    });
    _schedulePlaybackSave(immediate: true);
    try {
      if (ref.read(personalFlavorProvider)) {
        final handler = ref.read(personalAudioHandlerProvider);
        await handler.setRepeatMode(switch (repeatMode) {
          PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
          PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
          PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
        });
        await handler.setShuffleMode(
          isShuffling
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        );
      }
      await session.play();
    } catch (_) {
      state = state.copyWith(isPlaying: false, hasError: true);
    }
    try {
      await ref.read(trackRepositoryProvider).markPlayed(track);
    } catch (_) {
      // Playback remains available if local history cannot be written.
    }
    if (isRadio && ref.read(personalFlavorProvider)) {
      unawaited(_appendSimilarTracks(track, generation, radioQuery));
    }
  }

  Future<void> _appendSimilarTracks(
    Track track,
    int generation,
    String? radioQuery,
  ) async {
    try {
      final recommendations = await ref
          .read(personalYouTubeCatalogProvider)
          .similarTracks(track, searchContext: radioQuery);
      if (recommendations.isEmpty || generation != _generation) return;
      final current = state;
      if (!current.isRadio || current.track?.videoId != track.videoId) return;
      final existingIds = current.queue.map((item) => item.videoId).toSet();
      final candidates = recommendations
          .where((item) => existingIds.add(item.videoId))
          .toList(growable: false);

      final queueStart = math
          .max(0, current.queueIndex - _radioHistoryToKeep)
          .toInt();
      final retainedQueue = current.queue
          .skip(queueStart)
          .take(current.queueIndex - queueStart + 1)
          .toList(growable: false);
      final existingUpcoming = current.queue
          .skip(current.queueIndex + 1)
          .toList(growable: false);

      final canonical = _unshuffledQueue.isEmpty
          ? current.queue
          : _unshuffledQueue;
      final canonicalIndex = canonical.indexWhere(
        (item) => item.videoId == track.videoId,
      );
      final canonicalQueueBase = canonicalIndex < 0 ? current.queue : canonical;
      final currentCanonicalIndex = canonicalIndex < 0
          ? current.queueIndex
          : canonicalIndex;
      final canonicalStart = canonicalIndex < 0
          ? 0
          : math.max(0, canonicalIndex - _radioHistoryToKeep).toInt();
      final retainedCanonical = canonicalQueueBase
          .skip(canonicalStart)
          .take(currentCanonicalIndex - canonicalStart + 1)
          .toList(growable: false);
      final canonicalUpcoming = canonicalQueueBase
          .skip(currentCanonicalIndex + 1)
          .toList(growable: false);
      final availableSlots = math
          .max(
            0,
            math.min(
              _maxRadioQueueSize -
                  retainedQueue.length -
                  existingUpcoming.length,
              _maxRadioQueueSize -
                  retainedCanonical.length -
                  canonicalUpcoming.length,
            ),
          )
          .toInt();
      final added = candidates.take(availableSlots).toList(growable: false);
      final canonicalQueue = [
        ...retainedCanonical,
        ...canonicalUpcoming,
        ...added,
      ];
      _unshuffledQueue = List.unmodifiable(canonicalQueue);
      final playableAdded = [...added];
      if (current.isShuffling) playableAdded.shuffle(math.Random());
      final nextQueue = [
        ...retainedQueue,
        ...existingUpcoming,
        ...playableAdded,
      ];
      final nextIndex = retainedQueue.length - 1;
      state = current.copyWith(
        queue: List.unmodifiable(nextQueue),
        queueIndex: nextIndex,
      );
      _schedulePlaybackSave(immediate: true);
      await ref
          .read(personalAudioHandlerProvider)
          .setQueueOrder(nextQueue, nextIndex);
    } catch (_) {
      // Keep the current song available when recommendations cannot load.
    }
  }

  Future<void> _restoreSavedPlayback() async {
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      final saved = await preferences.getString(
        personalPlaybackResumePreferenceKey,
      );
      if (saved == null || _restoreCancelled || state.track != null) return;
      final decoded = jsonDecode(saved);
      if (decoded is! Map<String, dynamic>) return;
      final trackData = decoded['track'];
      if (trackData is! Map) return;
      final track = Track.fromJson(Map<String, dynamic>.from(trackData));

      List<Track> decodeTracks(Object? raw) {
        if (raw is! List) return const [];
        final result = <Track>[];
        for (final item in raw) {
          if (item is! Map) continue;
          try {
            result.add(Track.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // Skip malformed queue entries and keep the saved current track.
          }
        }
        return result;
      }

      var restoredQueue = decodeTracks(decoded['queue']);
      if (!restoredQueue.any((item) => item.videoId == track.videoId)) {
        restoredQueue = [...restoredQueue, track];
      }
      if (restoredQueue.isEmpty) restoredQueue = [track];
      final requestedIndex = decoded['queueIndex'] is int
          ? decoded['queueIndex'] as int
          : -1;
      final queueIndex =
          requestedIndex >= 0 &&
              requestedIndex < restoredQueue.length &&
              restoredQueue[requestedIndex].videoId == track.videoId
          ? requestedIndex
          : restoredQueue.indexWhere((item) => item.videoId == track.videoId);
      final isRadio = decoded['isRadio'] == true;
      var restoredIndex = queueIndex;
      if (isRadio && restoredQueue.length > _maxRadioQueueSize) {
        final start = math.max(0, restoredIndex - _radioHistoryToKeep).toInt();
        restoredQueue = restoredQueue
            .skip(start)
            .take(_maxRadioQueueSize)
            .toList(growable: false);
        restoredIndex -= start;
      }
      final positionMs = decoded['positionMs'] is int
          ? (decoded['positionMs'] as int).clamp(0, 1 << 62).toInt()
          : 0;
      final rawRepeatMode = decoded['repeatMode'];
      final repeatMode = PlaybackRepeatMode.values.firstWhere(
        (mode) => mode.name == rawRepeatMode,
        orElse: () => PlaybackRepeatMode.off,
      );
      final canonicalQueue = decodeTracks(decoded['unshuffledQueue']);
      var restoredCanonicalQueue = canonicalQueue.isEmpty
          ? restoredQueue
          : canonicalQueue;
      if (isRadio && restoredCanonicalQueue.length > _maxRadioQueueSize) {
        final canonicalTrackIndex = restoredCanonicalQueue.indexWhere(
          (item) => item.videoId == track.videoId,
        );
        final start = math
            .max(0, canonicalTrackIndex - _radioHistoryToKeep)
            .toInt();
        restoredCanonicalQueue = restoredCanonicalQueue
            .skip(start)
            .take(_maxRadioQueueSize)
            .toList(growable: false);
      }
      _unshuffledQueue = List.unmodifiable(restoredCanonicalQueue);
      if (_restoreCancelled || state.track != null) return;
      state = PlaybackState(
        track: track,
        queue: List.unmodifiable(restoredQueue),
        queueIndex: restoredIndex,
        position: Duration(milliseconds: positionMs),
        duration: Duration(seconds: track.durationSeconds ?? 0),
        loopsQueue: repeatMode == PlaybackRepeatMode.all,
        isRadio: isRadio,
        isShuffling: decoded['isShuffling'] == true,
        repeatMode: repeatMode,
      );
    } catch (_) {
      // Ignore invalid local resume data and let playback start normally.
    }
  }

  void _schedulePlaybackSave({bool immediate = false}) {
    if (!ref.read(personalFlavorProvider) || state.track == null) return;
    if (!immediate) {
      if (_saveTimer?.isActive ?? false) return;
      _saveTimer = Timer(const Duration(seconds: 3), () {
        _saveTimer = null;
        _schedulePlaybackSave(immediate: true);
      });
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    final snapshot = state;
    final unshuffledQueue = List<Track>.unmodifiable(_unshuffledQueue);
    final preferences = ref.read(sharedPreferencesProvider);
    final saved = jsonEncode({
      'track': snapshot.track!.toJson(),
      'queue': snapshot.queue.map((item) => item.toJson()).toList(),
      'unshuffledQueue': unshuffledQueue.map((item) => item.toJson()).toList(),
      'queueIndex': snapshot.queueIndex,
      'positionMs': snapshot.position.inMilliseconds,
      'isShuffling': snapshot.isShuffling,
      'repeatMode': snapshot.repeatMode.name,
      'isRadio': snapshot.isRadio,
    });
    _saveChain = _saveChain
        .catchError((_) {})
        .then(
          (_) =>
              preferences.setString(personalPlaybackResumePreferenceKey, saved),
        )
        .catchError((_) {});
  }
}
