import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/spot_database.dart';
import '../../search/domain/track.dart';

class TrackRepository {
  TrackRepository(this._store);

  final SpotDatabase _store;
  static const _cacheLifetime = Duration(days: 7);

  Future<void> saveTrack(Track track) async {
    await _store.database.transaction((txn) => upsertTrackRow(txn, track));
  }

  Future<bool> toggleFavorite(Track track) async {
    final db = _store.database;
    return db.transaction((txn) async {
      await upsertTrackRow(txn, track);
      final existing = await txn.query(
        'favorites',
        columns: ['videoId'],
        where: 'videoId = ?',
        whereArgs: [track.videoId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await txn.delete(
          'favorites',
          where: 'videoId = ?',
          whereArgs: [track.videoId],
        );
        return false;
      }
      await txn.insert('favorites', {
        'videoId': track.videoId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    });
  }

  Future<bool> isFavorite(String videoId) async {
    final rows = await _store.database.query(
      'favorites',
      columns: ['videoId'],
      where: 'videoId = ?',
      whereArgs: [videoId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Track>> getFavorites() async {
    final rows = await _store.database.rawQuery('''
      SELECT tracks.* FROM favorites
      INNER JOIN tracks ON tracks.videoId = favorites.videoId
      ORDER BY favorites.createdAt DESC
    ''');
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<List<Track>> getAllTracks() async {
    final rows = await _store.database.query(
      'tracks',
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<void> markPlayed(Track track) async {
    await _store.database.transaction((txn) async {
      await upsertTrackRow(txn, track);
      await txn.insert('playback_history', {
        'videoId': track.videoId,
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Track>> getRecentlyPlayed({int limit = 20}) async {
    final rows = await _store.database.rawQuery(
      '''
      SELECT tracks.* FROM playback_history
      INNER JOIN tracks ON tracks.videoId = playback_history.videoId
      ORDER BY playback_history.playedAt DESC
      LIMIT ?
    ''',
      [limit],
    );
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<List<Track>?> readCachedSearch(String query) async {
    final rows = await _store.database.query(
      'search_cache',
      columns: ['resultsJson', 'updatedAt'],
      where: 'query = ?',
      whereArgs: [query.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      rows.single['updatedAt']! as int,
    );
    if (DateTime.now().difference(updatedAt) > _cacheLifetime) return null;
    final decoded = jsonDecode(rows.single['resultsJson']! as String);
    if (decoded is! List) return null;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList(growable: false);
  }

  Future<void> cacheSearch(String query, List<Track> tracks) async {
    await _store.database.insert('search_cache', {
      'query': query.trim().toLowerCase(),
      'resultsJson': jsonEncode(tracks.map((track) => track.toJson()).toList()),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> upsertTrackRow(DatabaseExecutor executor, Track track) async {
  final values = track.toMap();
  await executor.insert(
    'tracks',
    values,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  await executor.update(
    'tracks',
    Map<String, Object?>.of(values)..remove('videoId'),
    where: 'videoId = ?',
    whereArgs: [track.videoId],
  );
}
