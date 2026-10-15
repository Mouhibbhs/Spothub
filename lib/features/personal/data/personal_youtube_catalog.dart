import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../features/library/data/track_repository.dart';
import '../../../features/search/data/youtube_search_repository.dart';
import '../../../features/search/domain/track.dart';

class PersonalPlaylistImport {
  const PersonalPlaylistImport({
    required this.title,
    required this.tracks,
    this.thumbnailUrl,
  });

  final String title;
  final String? thumbnailUrl;
  final List<Track> tracks;
}

class PersonalYouTubeCatalog {
  const PersonalYouTubeCatalog({required this.youtube, required this.tracks});

  final YoutubeExplode youtube;
  final TrackRepository tracks;

  Future<SearchOutcome> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return const SearchOutcome(tracks: []);

    final cached = (await tracks.readCachedSearch(
      cleaned,
    ))?.where((track) => track.canPlayOnYouTube).toList(growable: false);
    try {
      final results = await youtube.search.search(cleaned);
      final found = results.take(20).map(_fromVideo).toList(growable: false);
      await tracks.cacheSearch(cleaned, found);
      return SearchOutcome(tracks: found);
    } on RequestLimitExceededException {
      if (cached != null) {
        return SearchOutcome(
          tracks: cached,
          fromCache: true,
          message:
              'YouTube temporarily limited searches. Showing saved results.',
        );
      }
      rethrow;
    } catch (_) {
      if (cached != null) {
        return SearchOutcome(
          tracks: cached,
          fromCache: true,
          message: 'YouTube search failed. Showing your saved results.',
        );
      }
      throw const SearchException(
        'YouTube search could not finish. Check your connection and try again.',
      );
    }
  }

  Future<PersonalPlaylistImport> importPlaylist(String playlistUrl) async {
    final cleanedUrl = playlistUrl.trim();
    if (cleanedUrl.isEmpty) {
      throw const FormatException('Paste a YouTube playlist link first.');
    }
    final playlistId = PlaylistId.parsePlaylistId(cleanedUrl);
    if (playlistId == null) {
      throw const FormatException(
        'That link does not contain a valid YouTube playlist ID.',
      );
    }
    final playlist = await youtube.playlists.get(playlistId);
    final imported = <Track>[];
    await for (final video
        in youtube.playlists.getVideos(playlist.id).take(500)) {
      final title = video.title.trim();
      if (title == 'Private video' || title == 'Deleted video') continue;
      imported.add(_fromVideo(video));
    }
    if (imported.isEmpty) {
      throw const FormatException(
        'YouTube returned no importable entries. Check that this playlist is public or unlisted and that its videos are available.',
      );
    }
    return PersonalPlaylistImport(
      title: playlist.title,
      thumbnailUrl: playlist.thumbnails.highResUrl,
      tracks: List.unmodifiable(imported),
    );
  }

  Future<List<Track>> similarTracks(
    Track track, {
    int limit = 15,
    String? searchContext,
  }) async {
    if (limit <= 0) return const [];

    final recommendations = <Track>[];
    final seenIds = <String>{track.videoId};
    final normalizedTitle = _normalizeTitle(track.title);

    void addCandidates(Iterable<Track> candidates) {
      for (final candidate in candidates) {
        if (recommendations.length >= limit) break;
        if (!candidate.canPlayOnYouTube ||
            candidate.durationSeconds == 0 ||
            _normalizeTitle(candidate.title) == normalizedTitle ||
            !seenIds.add(candidate.videoId)) {
          continue;
        }
        recommendations.add(candidate);
      }
    }

    Future<List<Track>> cachedOrSearch(String query) async {
      final cached = await tracks.readCachedSearch(query);
      if (cached != null) return cached;
      return (await search(query)).tracks;
    }

    // Use the search term as the radio seed: category searches stay in that
    // category, and artist searches keep the next songs with that artist.
    final context = searchContext?.trim();
    if (context != null && context.isNotEmpty) {
      try {
        addCandidates(await cachedOrSearch(context));
      } catch (_) {
        // Continue with the artist and YouTube's related-video results.
      }
    }

    final artist = track.channelName.trim();
    final artistQuery = artist.isEmpty || artist.toLowerCase() == 'youtube'
        ? null
        : '$artist songs';
    if (recommendations.length < 5 && artistQuery != null) {
      try {
        addCandidates(await cachedOrSearch(artistQuery));
      } catch (_) {
        // Related videos below can still provide a queue.
      }
    }

    if (recommendations.length < 5) {
      try {
        final video = await youtube.videos.get(track.videoId);
        final related = await youtube.videos.getRelatedVideos(video);
        addCandidates(
          related
                  ?.where(
                    (candidate) =>
                        !candidate.isLive &&
                        candidate.duration != null &&
                        candidate.duration!.inSeconds > 0,
                  )
                  .map(_fromVideo) ??
              const <Track>[],
        );
      } catch (_) {
        // Search results already added above remain useful if recommendations
        // are unavailable for this video.
      }
    }

    if (recommendations.isEmpty) {
      try {
        addCandidates(
          await cachedOrSearch(
            '${track.title} ${track.channelName} official audio',
          ),
        );
      } catch (_) {
        // Keep playback working even when recommendations cannot be loaded.
      }
    }
    return List.unmodifiable(recommendations);
  }

  String _normalizeTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  Track _fromVideo(Video video) => Track(
    videoId: video.id.value,
    title: video.title,
    channelName: video.author.trim().isEmpty ? 'YouTube' : video.author,
    thumbnailUrl: video.thumbnails.maxResUrl,
    durationSeconds: video.duration?.inSeconds,
  );
}
