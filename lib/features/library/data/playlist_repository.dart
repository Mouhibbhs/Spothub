import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/spot_database.dart';
import 'track_repository.dart';
import '../../search/domain/track.dart';

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackCount,
    this.thumbnailUrl,
    this.coverImageBytes,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int trackCount;
  final String? thumbnailUrl;
  final Uint8List? coverImageBytes;

  factory PlaylistSummary.fromMap(Map<String, Object?> row) => PlaylistSummary(
    id: row['id']! as int,
    name: row['name']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt']! as int),
    trackCount: row['trackCount']! as int,
    thumbnailUrl: row['thumbnailUrl'] as String?,
    coverImageBytes: row['coverImage'] as Uint8List?,
  );
}

class PlaylistRepository {
  PlaylistRepository(this._store);

  final SpotDatabase _store;

  Future<int> create(String name) async {
    final cleaned = _validateName(name);
    return _store.database.insert('playlists', {
      'name': cleaned,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> createWithTracks(String name, List<Track> tracks) async {
    final cleaned = _validateName(name);
    return _store.database.transaction((txn) async {
      final id = await txn.insert('playlists', {
        'name': cleaned,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await _appendTracks(txn, id, tracks);
      return id;
    });
  }

  String _validateName(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) throw ArgumentError('Playlist name can’t be empty.');
    if (cleaned.length > 50) {
      throw ArgumentError('Playlist names must be 50 characters or fewer.');
    }
    return cleaned;
  }

  Future<List<PlaylistSummary>> getAll() async {
    final rows = await _store.database.rawQuery('''
      SELECT playlists.id, playlists.name, playlists.createdAt,
        playlists.coverImage,
        COUNT(playlist_tracks.videoId) AS trackCount,
        (SELECT tracks.thumbnailUrl FROM playlist_tracks AS cover_items
          INNER JOIN tracks ON tracks.videoId = cover_items.videoId
          WHERE cover_items.playlistId = playlists.id
          ORDER BY cover_items.position ASC LIMIT 1) AS thumbnailUrl
      FROM playlists
      LEFT JOIN playlist_tracks ON playlists.id = playlist_tracks.playlistId
      GROUP BY playlists.id
      ORDER BY playlists.createdAt DESC
    ''');
    return rows.map(PlaylistSummary.fromMap).toList(growable: false);
  }

  Future<List<Track>> getTracks(int playlistId) async {
    final rows = await _store.database.rawQuery(
      '''
      SELECT tracks.* FROM playlist_tracks
      INNER JOIN tracks ON tracks.videoId = playlist_tracks.videoId
      WHERE playlist_tracks.playlistId = ?
      ORDER BY playlist_tracks.position ASC
    ''',
      [playlistId],
    );
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<void> addTrack(int playlistId, Track track) async {
    await addTracks(playlistId, [track]);
  }

  Future<void> addTracks(int playlistId, List<Track> tracks) async {
    await _store.database.transaction((txn) async {
      final exists = await txn.query(
        'playlists',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [playlistId],
        limit: 1,
      );
      if (exists.isEmpty) throw StateError('This playlist no longer exists.');
      await _appendTracks(txn, playlistId, tracks);
    });
  }

  Future<void> mergeTracksInSourceOrder(
    int playlistId,
    List<Track> sourceTracks,
  ) async {
    await _store.database.transaction((txn) async {
      final exists = await txn.query(
        'playlists',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [playlistId],
        limit: 1,
      );
      if (exists.isEmpty) throw StateError('This playlist no longer exists.');

      final rows = await txn.rawQuery(
        '''
        SELECT tracks.* FROM playlist_tracks
        INNER JOIN tracks ON tracks.videoId = playlist_tracks.videoId
        WHERE playlist_tracks.playlistId = ?
        ORDER BY playlist_tracks.position ASC
        ''',
        [playlistId],
      );
      final existingTracks = rows.map(Track.fromMap);
      final orderedTracks = <Track>[];
      final seenVideoIds = <String>{};
      for (final track in [...sourceTracks, ...existingTracks]) {
        if (seenVideoIds.add(track.videoId)) orderedTracks.add(track);
      }

      await txn.delete(
        'playlist_tracks',
        where: 'playlistId = ?',
        whereArgs: [playlistId],
      );
      await _appendTracks(txn, playlistId, orderedTracks);
    });
  }

  Future<void> _appendTracks(
    DatabaseExecutor txn,
    int playlistId,
    List<Track> tracks,
  ) async {
    final current = await txn.rawQuery(
      'SELECT COALESCE(MAX(position), -1) AS lastPosition FROM playlist_tracks WHERE playlistId = ?',
      [playlistId],
    );
    var position = (current.single['lastPosition']! as int) + 1;
    for (final track in tracks) {
      await upsertTrackRow(txn, track);
      final duplicate = await txn.query(
        'playlist_tracks',
        columns: ['videoId'],
        where: 'playlistId = ? AND videoId = ?',
        whereArgs: [playlistId, track.videoId],
        limit: 1,
      );
      if (duplicate.isNotEmpty) continue;
      await txn.insert('playlist_tracks', {
        'playlistId': playlistId,
        'videoId': track.videoId,
        'position': position++,
      });
    }
  }

  Future<void> removeTrack(int playlistId, String videoId) async {
    await _store.database.delete(
      'playlist_tracks',
      where: 'playlistId = ? AND videoId = ?',
      whereArgs: [playlistId, videoId],
    );
  }

  Future<void> delete(int playlistId) async {
    await _store.database.delete(
      'playlists',
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> setCoverImage(int playlistId, Uint8List? imageBytes) async {
    final updated = await _store.database.update(
      'playlists',
      {'coverImage': imageBytes},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    if (updated == 0) throw StateError('This playlist no longer exists.');
  }
}
