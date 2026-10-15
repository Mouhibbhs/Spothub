import '../../search/domain/track.dart';

class PlaylistCsvImportResult {
  const PlaylistCsvImportResult({
    required this.tracks,
    required this.skippedRows,
  });

  final List<Track> tracks;
  final int skippedRows;
}

class PlaylistCsvImporter {
  PlaylistCsvImporter._();

  static const maxTracks = 500;
  static final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Reads rows with a YouTube video ID or URL, a title, and an optional artist.
  /// Headers are case-insensitive: `videoId`/`youtubeUrl`, `title`, and
  /// `channelName`/`artist`/`channel`.
  static PlaylistCsvImportResult parse(String csv) {
    final rows = _parseRows(csv.replaceFirst('\uFEFF', ''));
    if (rows.isEmpty) {
      throw const FormatException('The CSV file is empty.');
    }
    final headers = rows.first
        .map((cell) => cell.trim().toLowerCase())
        .toList();
    final idColumn = _column(headers, const ['videoid', 'youtubeurl', 'url']);
    final titleColumn = _column(headers, const ['title', 'track', 'trackname']);
    final channelColumn = _column(headers, const [
      'channelname',
      'artist',
      'channel',
      'artistname',
    ]);
    if (idColumn == -1 || titleColumn == -1) {
      throw const FormatException(
        'CSV needs a videoId or youtubeUrl column and a title column.',
      );
    }

    final tracks = <Track>[];
    var skipped = 0;
    for (final row in rows.skip(1)) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final rawId = _cell(row, idColumn).trim();
      final title = _cell(row, titleColumn).trim();
      final videoId = _extractVideoId(rawId);
      if (title.isEmpty || videoId == null) {
        skipped++;
        continue;
      }
      final channelName = channelColumn == -1
          ? 'YouTube'
          : _cell(row, channelColumn).trim();
      tracks.add(
        Track(
          videoId: videoId,
          title: title,
          channelName: channelName.isEmpty ? 'YouTube' : channelName,
          thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        ),
      );
      if (tracks.length > maxTracks) {
        throw const FormatException(
          'A playlist import can contain up to 500 videos.',
        );
      }
    }
    return PlaylistCsvImportResult(
      tracks: List.unmodifiable(tracks),
      skippedRows: skipped,
    );
  }

  static int _column(List<String> headers, List<String> candidates) =>
      headers.indexWhere(candidates.contains);

  static String _cell(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index] : '';

  static String? _extractVideoId(String value) {
    if (_videoIdPattern.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    String? id;
    if (host == 'youtu.be' || host == 'www.youtu.be') {
      id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com') {
      if (uri.path == '/watch') {
        id = uri.queryParameters['v'];
      } else if (uri.pathSegments.length >= 2 &&
          const {'embed', 'shorts', 'live'}.contains(uri.pathSegments.first)) {
        id = uri.pathSegments[1];
      }
    }
    return id != null && _videoIdPattern.hasMatch(id) ? id : null;
  }

  static List<List<String>> _parseRows(String csv) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < csv.length; i++) {
      final char = csv[i];
      if (char == '"') {
        if (inQuotes && i + 1 < csv.length && csv[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') i++;
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
        row = <String>[];
        if (rows.length > maxTracks + 1) {
          throw const FormatException(
            'A playlist import can contain up to 500 videos.',
          );
        }
      } else {
        field.write(char);
      }
    }
    if (inQuotes) {
      throw const FormatException('A quoted CSV field was not closed.');
    }
    row.add(field.toString());
    if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
    if (rows.length > maxTracks + 1) {
      throw const FormatException(
        'A playlist import can contain up to 500 videos.',
      );
    }
    return rows;
  }
}
