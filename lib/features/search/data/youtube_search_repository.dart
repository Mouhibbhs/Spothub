import 'package:dio/dio.dart';

import '../../library/data/track_repository.dart';
import '../domain/track.dart';

class SearchOutcome {
  const SearchOutcome({
    required this.tracks,
    this.message,
    this.fromCache = false,
  });

  final List<Track> tracks;
  final String? message;
  final bool fromCache;
}

class YouTubeSearchRepository {
  YouTubeSearchRepository({
    required TrackRepository tracks,
    required Dio dio,
    String apiKey = '',
    Future<String> Function()? apiKeyReader,
  }) : _tracks = tracks,
       _dio = dio,
       _apiKey = apiKey.trim(),
       _apiKeyReader = apiKeyReader;

  final TrackRepository _tracks;
  final Dio _dio;
  final String _apiKey;
  final Future<String> Function()? _apiKeyReader;

  Future<SearchOutcome> search(String query, {CancelToken? cancelToken}) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return const SearchOutcome(tracks: []);

    final cached = await _tracks.readCachedSearch(cleaned);
    final apiKey = (_apiKeyReader == null ? _apiKey : await _apiKeyReader())
        .trim();
    if (apiKey.isEmpty) {
      return SearchOutcome(
        tracks: cached ?? const [],
        fromCache: cached != null,
        message:
            'Live search needs a YouTube Data API key. Add your key in Settings to search videos.',
      );
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://www.googleapis.com/youtube/v3/search',
        queryParameters: {
          'part': 'snippet',
          'type': 'video',
          'videoEmbeddable': 'true',
          'maxResults': 20,
          'q': cleaned,
          'fields':
              'items(id/videoId,snippet(title,channelTitle,thumbnails(default/url,medium/url,high/url,maxres/url)))',
          'key': apiKey,
        },
        cancelToken: cancelToken,
      );
      final rawItems = response.data?['items'];
      final tracks = rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(Track.tryParseYouTubeSearchItem)
                .whereType<Track>()
                .toList(growable: false)
          : const <Track>[];
      await _tracks.cacheSearch(cleaned, tracks);
      return SearchOutcome(tracks: tracks);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      final message = _describeError(error);
      if (cached != null) {
        return SearchOutcome(
          tracks: cached,
          message: '$message Showing saved results from your last search.',
          fromCache: true,
        );
      }
      throw SearchException(message);
    } on FormatException {
      throw const SearchException(
        'YouTube returned an unreadable response. Try again in a moment.',
      );
    }
  }

  String _describeError(DioException error) {
    final data = error.response?.data;
    final errors = data is Map<String, dynamic> ? data['error'] : null;
    final items = errors is Map<String, dynamic> ? errors['errors'] : null;
    final reason = items is List && items.isNotEmpty && items.first is Map
        ? (items.first as Map)['reason']?.toString()
        : null;
    if (reason == 'quotaExceeded' || reason == 'dailyLimitExceeded') {
      return 'The YouTube API quota is exhausted for today. Check quota usage in Google Cloud Console.';
    }
    if (reason == 'keyInvalid' || reason == 'API_KEY_INVALID') {
      return 'The YouTube API key is invalid. Check the key and its Google Cloud API restrictions.';
    }
    if (error.response?.statusCode == 403) {
      return 'YouTube denied this search. Check that the Data API v3 is enabled and the key is allowed to use it.';
    }
    if (error.response?.statusCode == 400) {
      return 'YouTube could not understand that search. Try a shorter query.';
    }
    if (error.response != null) {
      return 'YouTube search failed (HTTP ${error.response?.statusCode}). Please try again.';
    }
    return 'You’re offline or YouTube couldn’t be reached. Check your connection and try again.';
  }
}

class SearchException implements Exception {
  const SearchException(this.message);
  final String message;

  @override
  String toString() => message;
}
