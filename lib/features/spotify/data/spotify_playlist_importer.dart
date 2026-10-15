import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

class SpotifyPlaylistImporter {
  SpotifyPlaylistImporter({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<SpotifyPlaylistImport> importPlaylist(String input) async {
    final playlistId = _playlistIdFromLink(input);
    final playlistUrl = 'https://open.spotify.com/playlist/$playlistId';
    final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';

    try {
      final responses = await Future.wait<dynamic>([
        _dio.get<String>(
          embedUrl,
          options: Options(responseType: ResponseType.plain, headers: _headers),
        ),
        _dio
            .get<Map<String, dynamic>>(
              'https://open.spotify.com/oembed',
              queryParameters: {'url': playlistUrl},
              options: Options(
                responseType: ResponseType.json,
                headers: _headers,
              ),
            )
            .catchError(
              (_) => Response<Map<String, dynamic>>(
                requestOptions: RequestOptions(path: ''),
                data: const <String, dynamic>{},
              ),
            ),
      ]);

      final page = (responses[0] as Response<String>).data ?? '';
      final oembed =
          (responses[1] as Response<Map<String, dynamic>>).data ??
          const <String, dynamic>{};
      if (page.isEmpty) {
        throw const SpotifyPlaylistImportException(
          'Spotify returned an empty playlist page. Try again in a moment.',
        );
      }

      final items = _parseItems(page, playlistUrl);
      if (items.isEmpty) {
        throw const SpotifyPlaylistImportException(
          'No tracks were found. Check that the playlist is public and the link is correct.',
        );
      }

      final document = html_parser.parse(page);
      final title =
          _nonEmpty(oembed['title']?.toString()) ??
          _nonEmpty(
            document
                .querySelector('meta[property="og:title"]')
                ?.attributes['content'],
          ) ??
          'Spotify playlist';
      final imageUrl =
          _nonEmpty(oembed['thumbnail_url']?.toString()) ??
          _nonEmpty(
            document
                .querySelector('meta[property="og:image"]')
                ?.attributes['content'],
          );

      return SpotifyPlaylistImport(
        playlist: SpotifyPlaylist(
          id: playlistId,
          name: title,
          spotifyUrl: playlistUrl,
          itemCount: items.length,
          ownerName: 'Spotify',
          imageUrl: imageUrl,
        ),
        items: items,
      );
    } on SpotifyPlaylistImportException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 404 || status == 400) {
        throw const SpotifyPlaylistImportException(
          'Spotify could not find that playlist. Check the link and try again.',
        );
      }
      if (status == 403 || status == 401) {
        throw const SpotifyPlaylistImportException(
          'Spotify did not provide this playlist. It may be private or unavailable in your region.',
        );
      }
      if (status == 429) {
        throw const SpotifyPlaylistImportException(
          'Spotify is receiving too many requests. Wait a moment and retry.',
        );
      }
      throw const SpotifyPlaylistImportException(
        'Could not reach Spotify. Check your connection and try again.',
      );
    } on FormatException {
      throw const SpotifyPlaylistImportException(
        'Spotify returned playlist data in an unreadable format. Try again later.',
      );
    }
  }

  static const _headers = <String, String>{
    'Accept': 'text/html,application/json',
    'User-Agent': 'SpotHub/1.0 (Android; Spotify playlist importer)',
  };

  static String _playlistIdFromLink(String input) {
    final cleaned = input.trim();
    final uri = Uri.tryParse(
      cleaned.contains('://') ? cleaned : 'https://$cleaned',
    );
    const allowedHosts = {'spotify.com', 'www.spotify.com', 'open.spotify.com'};
    if (uri == null || !allowedHosts.contains(uri.host.toLowerCase())) {
      throw const SpotifyPlaylistImportException(
        'Paste a Spotify playlist link, such as open.spotify.com/playlist/…',
      );
    }
    final segments = uri.pathSegments;
    final playlistSegment = segments.indexOf('playlist');
    if (playlistSegment < 0 || playlistSegment + 1 >= segments.length) {
      throw const SpotifyPlaylistImportException(
        'That link is not a Spotify playlist. Paste a playlist link and try again.',
      );
    }
    final id = segments[playlistSegment + 1];
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) {
      throw const SpotifyPlaylistImportException(
        'The Spotify playlist link looks incomplete. Check it and try again.',
      );
    }
    return id;
  }

  static List<SpotifyPlaylistItem> _parseItems(
    String page,
    String playlistUrl,
  ) {
    final arrayStartMarker = RegExp(r'"trackList"\s*:\s*\[').firstMatch(page);
    if (arrayStartMarker != null) {
      final arrayStart = page.indexOf('[', arrayStartMarker.start);
      final arrayEnd = _matchingArrayEnd(page, arrayStart);
      if (arrayEnd != -1) {
        final decoded = jsonDecode(page.substring(arrayStart, arrayEnd + 1));
        if (decoded is List) {
          final items = decoded
              .whereType<Map>()
              .map(SpotifyPlaylistItem.tryParse)
              .whereType<SpotifyPlaylistItem>()
              .toList(growable: false);
          if (items.isNotEmpty) return items;
        }
      }
    }

    // Spotify's embedded page also renders accessible rows. Keep this fallback
    // for page variants that omit the serialized trackList data.
    final document = html_parser.parse(page);
    final rows = document.querySelectorAll('li[data-testid^="tracklist-row-"]');
    return rows
        .map((row) {
          final title = _nonEmpty(row.querySelector('h3')?.text);
          final artist = _nonEmpty(row.querySelector('h4')?.text);
          final duration = _nonEmpty(
            row.querySelector('[data-testid="duration-cell"]')?.text,
          );
          if (title == null) return null;
          return SpotifyPlaylistItem(
            title: title,
            artistNames: artist ?? '',
            spotifyUrl: playlistUrl,
            duration: duration ?? '',
          );
        })
        .whereType<SpotifyPlaylistItem>()
        .toList(growable: false);
  }

  static int _matchingArrayEnd(String text, int start) {
    if (start < 0 || start >= text.length || text[start] != '[') return -1;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '[') {
        depth++;
      } else if (char == ']') {
        depth--;
        if (depth == 0) return index;
      }
    }
    return -1;
  }

  static String? _nonEmpty(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}

class SpotifyPlaylistImport {
  const SpotifyPlaylistImport({required this.playlist, required this.items});

  final SpotifyPlaylist playlist;
  final List<SpotifyPlaylistItem> items;
}

class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.spotifyUrl,
    required this.itemCount,
    required this.ownerName,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String spotifyUrl;
  final int itemCount;
  final String ownerName;
  final String? imageUrl;
}

class SpotifyPlaylistItem {
  const SpotifyPlaylistItem({
    required this.title,
    required this.artistNames,
    required this.spotifyUrl,
    this.duration = '',
  });

  final String title;
  final String artistNames;
  final String spotifyUrl;
  final String duration;

  static SpotifyPlaylistItem? tryParse(Map<dynamic, dynamic> json) {
    final uri = json['uri']?.toString() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    if (title.isEmpty || !uri.startsWith('spotify:track:')) return null;
    final id = uri.substring('spotify:track:'.length);
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) return null;
    final durationMilliseconds = int.tryParse(
      json['duration']?.toString() ?? '',
    );
    final duration = durationMilliseconds == null
        ? ''
        : _formatDuration(durationMilliseconds);
    return SpotifyPlaylistItem(
      title: title,
      artistNames: json['subtitle']?.toString().trim() ?? '',
      spotifyUrl: 'https://open.spotify.com/track/$id',
      duration: duration,
    );
  }

  static String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class SpotifyPlaylistImportException implements Exception {
  const SpotifyPlaylistImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
