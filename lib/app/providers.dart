import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/database/spot_database.dart';
import '../features/downloads/data/audio_download_repository.dart';
import '../features/library/data/playlist_repository.dart';
import '../features/library/data/track_repository.dart';
import '../features/personal/data/personal_youtube_catalog.dart';
import '../features/search/data/youtube_search_repository.dart';
import '../features/search/domain/track.dart';
import '../features/spotify/data/spotify_playlist_importer.dart';

final databaseProvider = Provider<SpotDatabase>(
  (ref) => throw StateError('SpotDatabase must be initialized before runApp.'),
);

final personalFlavorProvider = Provider<bool>((ref) => false);

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (ref) => SharedPreferencesAsync(),
);

const youtubeApiKeyPreferenceKey = 'youtube_api_key';
const personalPlaybackResumePreferenceKey = 'personal_playback_resume';

final youtubeApiKeyProvider = FutureProvider<String>((ref) async {
  final preferences = ref.watch(sharedPreferencesProvider);
  return (await preferences.getString(youtubeApiKeyPreferenceKey))?.trim() ??
      '';
});

final trackRepositoryProvider = Provider<TrackRepository>(
  (ref) => TrackRepository(ref.watch(databaseProvider)),
);

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(ref.watch(databaseProvider)),
);

final audioDownloadRepositoryProvider = Provider<AudioDownloadRepository>((
  ref,
) {
  final youtube = YoutubeExplode();
  ref.onDispose(youtube.close);
  return AudioDownloadRepository(youtube: youtube);
});

final downloadedTrackProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, trackId) =>
      ref.watch(audioDownloadRepositoryProvider).isDownloaded(trackId),
);

final downloadedTracksProvider = FutureProvider.autoDispose((ref) async {
  final knownTracks = await ref.watch(trackRepositoryProvider).getAllTracks();
  return ref
      .watch(audioDownloadRepositoryProvider)
      .listDownloadedTracks(knownTracks: knownTracks);
});

final downloadedPlaylistsProvider = FutureProvider.autoDispose((ref) async {
  final playlistRepository = ref.watch(playlistRepositoryProvider);
  final downloadRepository = ref.watch(audioDownloadRepositoryProvider);
  final playlists = await playlistRepository.getAll();
  final offline = <DownloadedPlaylist>[];
  for (final playlist in playlists) {
    final tracks = await playlistRepository.getTracks(playlist.id);
    final savedTracks = <Track>[];
    for (final track in tracks) {
      if (await downloadRepository.isDownloaded(track.videoId)) {
        savedTracks.add(track);
      }
    }
    if (savedTracks.isNotEmpty) {
      offline.add(
        DownloadedPlaylist(
          playlist: playlist,
          tracks: tracks,
          downloadedTracks: savedTracks.length,
        ),
      );
    }
  }
  return offline;
});

class DownloadedPlaylist {
  const DownloadedPlaylist({
    required this.playlist,
    required this.tracks,
    required this.downloadedTracks,
  });

  final PlaylistSummary playlist;
  final List<Track> tracks;
  final int downloadedTracks;
}

final youtubeSearchRepositoryProvider = Provider<YouTubeSearchRepository>((
  ref,
) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 12),
      responseType: ResponseType.json,
    ),
  );
  ref.onDispose(dio.close);
  final preferences = ref.watch(sharedPreferencesProvider);
  return YouTubeSearchRepository(
    tracks: ref.watch(trackRepositoryProvider),
    dio: dio,
    apiKeyReader: () async =>
        (await preferences.getString(youtubeApiKeyPreferenceKey)) ?? '',
  );
});

final personalYouTubeCatalogProvider = Provider<PersonalYouTubeCatalog>((ref) {
  final youtube = YoutubeExplode();
  ref.onDispose(youtube.close);
  return PersonalYouTubeCatalog(
    youtube: youtube,
    tracks: ref.watch(trackRepositoryProvider),
  );
});

final spotifyPlaylistImporterProvider = Provider<SpotifyPlaylistImporter>((
  ref,
) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
    ),
  );
  ref.onDispose(dio.close);
  return SpotifyPlaylistImporter(dio: dio);
});

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

final playlistsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(playlistRepositoryProvider).getAll(),
);

final playlistTracksProvider = FutureProvider.autoDispose.family(
  (ref, int playlistId) =>
      ref.watch(playlistRepositoryProvider).getTracks(playlistId),
);

final favoritesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(trackRepositoryProvider).getFavorites(),
);

final recentlyPlayedProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(trackRepositoryProvider).getRecentlyPlayed(),
);

final isFavoriteProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, videoId) => ref.watch(trackRepositoryProvider).isFavorite(videoId),
);

class SearchState {
  const SearchState({
    this.query = '',
    this.tracks = const [],
    this.isLoading = false,
    this.message,
    this.fromCache = false,
  });

  final String query;
  final List<Track> tracks;
  final bool isLoading;
  final String? message;
  final bool fromCache;

  SearchState copyWith({
    String? query,
    List<Track>? tracks,
    bool? isLoading,
    String? message,
    bool clearMessage = false,
    bool? fromCache,
  }) => SearchState(
    query: query ?? this.query,
    tracks: tracks ?? this.tracks,
    isLoading: isLoading ?? this.isLoading,
    message: clearMessage ? null : message ?? this.message,
    fromCache: fromCache ?? this.fromCache,
  );
}

class SearchController extends Notifier<SearchState> {
  Timer? _debounce;
  CancelToken? _cancelToken;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancelToken?.cancel('Search screen disposed');
    });
    return const SearchState();
  }

  void setQuery(String query) {
    _debounce?.cancel();
    _cancelToken?.cancel('A newer search was entered');
    final cleaned = query.trim();
    if (cleaned.isEmpty) {
      state = const SearchState();
      return;
    }
    state = state.copyWith(
      query: query,
      isLoading: true,
      clearMessage: true,
      tracks: const [],
      fromCache: false,
    );
    _debounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(_runSearch(cleaned));
    });
  }

  Future<void> searchNow(String query) async {
    _debounce?.cancel();
    _cancelToken?.cancel('A newer search was entered');
    final cleaned = query.trim();
    if (cleaned.isEmpty) {
      state = const SearchState();
      return;
    }
    state = state.copyWith(
      query: query,
      isLoading: true,
      clearMessage: true,
      tracks: const [],
      fromCache: false,
    );
    await _runSearch(cleaned);
  }

  Future<void> _runSearch(String query) async {
    final token = CancelToken();
    _cancelToken = token;
    try {
      final outcome = ref.read(personalFlavorProvider)
          ? await ref.read(personalYouTubeCatalogProvider).search(query)
          : await ref
                .read(youtubeSearchRepositoryProvider)
                .search(query, cancelToken: token);
      if (state.query.trim() != query || token.isCancelled) {
        return;
      }
      state = state.copyWith(
        tracks: outcome.tracks,
        isLoading: false,
        message: outcome.message,
        clearMessage: outcome.message == null,
        fromCache: outcome.fromCache,
      );
    } on SearchException catch (error) {
      if (state.query.trim() != query || token.isCancelled) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        tracks: const [],
        message: error.message,
        fromCache: false,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || state.query.trim() != query) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        tracks: const [],
        message: 'Search couldn’t finish. Check your connection and try again.',
      );
    } catch (_) {
      if (state.query.trim() != query || token.isCancelled) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        tracks: const [],
        message: 'Search couldn’t finish. Please try again.',
      );
    }
  }
}
