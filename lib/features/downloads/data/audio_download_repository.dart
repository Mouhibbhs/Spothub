import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../search/domain/track.dart';

class AudioDownloadRepository {
  const AudioDownloadRepository({required YoutubeExplode youtube})
    : _youtube = youtube;

  final YoutubeExplode _youtube;

  Future<String?> localPathFor(String trackId) => findDownloadedFile(trackId);

  static Future<String?> findDownloadedFile(String trackId) async {
    final directory = await _downloadDirectory();
    final prefix = _filePrefixFor(trackId);
    for (final extension in _supportedExtensions) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$prefix.$extension',
      );
      if (await file.exists() && await file.length() > 0) return file.path;
    }
    return null;
  }

  Future<bool> isDownloaded(String trackId) async =>
      await localPathFor(trackId) != null;

  Future<void> deleteDownload(String trackId) async {
    final path = await localPathFor(trackId);
    if (path == null) return;
    final media = File(path);
    if (await media.exists()) await media.delete();
    final metadata = File('$path.json');
    if (await metadata.exists()) await metadata.delete();
  }

  Future<List<Track>> listDownloadedTracks({
    Iterable<Track> knownTracks = const [],
  }) async {
    final directory = await _downloadDirectory();
    final knownByPrefix = <String, Track>{
      for (final track in knownTracks) _filePrefixFor(track.videoId): track,
    };
    final downloads = <Track>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          entity.path.endsWith('.json') ||
          entity.path.endsWith('.part')) {
        continue;
      }
      final fileName = entity.uri.pathSegments.last;
      final extension = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
          : '';
      if (!_supportedExtensions.contains(extension) ||
          await entity.length() == 0) {
        continue;
      }
      Track? track;
      final metadata = File('${entity.path}.json');
      if (await metadata.exists()) {
        try {
          final decoded = jsonDecode(await metadata.readAsString());
          if (decoded is Map<String, dynamic>) track = Track.fromJson(decoded);
        } catch (_) {
          // Fall back to the library's metadata for downloads from older builds.
        }
      }
      track ??= knownByPrefix[fileName.substring(0, fileName.lastIndexOf('.'))];
      if (track != null && track.canPlayOnYouTube) downloads.add(track);
    }
    downloads.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return downloads;
  }

  Future<String> downloadTrack(
    Track track, {
    void Function(double progress)? onProgress,
  }) async {
    if (!track.canPlayOnYouTube) {
      throw ArgumentError('This track source cannot be saved by SpotHub.');
    }
    final existingPath = await localPathFor(track.videoId);
    if (existingPath != null) return existingPath;

    final manifest = await _youtube.videos.streams.getManifest(
      track.videoId,
      requireWatchPage: true,
    );
    final info = manifest.audioOnly.isNotEmpty
        ? manifest.audioOnly.withHighestBitrate()
        : manifest.muxed.isNotEmpty
        ? manifest.muxed.withHighestBitrate()
        : throw StateError('YouTube returned no downloadable audio stream.');
    return _saveStream(
      track: track,
      extension: info.container.name,
      stream: _youtube.videos.streams.get(info),
      expectedLength: info.size.totalBytes,
      onProgress: onProgress,
    );
  }

  Future<String> _saveStream({
    required Track track,
    required String extension,
    required Stream<List<int>> stream,
    required int? expectedLength,
    void Function(double progress)? onProgress,
  }) async {
    final directory = await _downloadDirectory();
    final prefix = _filePrefixFor(track.videoId);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$prefix.$extension',
    );
    final temporary = File('${destination.path}.part');
    if (await temporary.exists()) await temporary.delete();

    final sink = temporary.openWrite();
    var sinkClosed = false;
    var bytesWritten = 0;
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
        bytesWritten += chunk.length;
        if (expectedLength != null && expectedLength > 0) {
          onProgress?.call(
            (bytesWritten / expectedLength).clamp(0, 1).toDouble(),
          );
        }
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;
      if (bytesWritten == 0) throw StateError('The audio download was empty.');
      if (expectedLength != null &&
          expectedLength > 0 &&
          bytesWritten < expectedLength) {
        throw StateError('The download ended before the full track arrived.');
      }
      if (await destination.exists()) await destination.delete();
      final saved = await temporary.rename(destination.path);
      await File(
        '${saved.path}.json',
      ).writeAsString(jsonEncode(track.toJson()));
      onProgress?.call(1);
      return saved.path;
    } catch (_) {
      if (!sinkClosed) await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static Future<Directory> _downloadDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}audio_downloads',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String _filePrefixFor(String trackId) =>
      trackId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static const _supportedExtensions = [
    'mp3',
    'm4a',
    'wav',
    'flac',
    'ogg',
    'webm',
    'mp4',
    '3gpp',
  ];
}
