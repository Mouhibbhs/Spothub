import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/spot_database.dart';
import '../../library/data/track_repository.dart';
import '../../search/domain/track.dart';

class LibraryBackupService {
  LibraryBackupService(this._store);

  static const formatName = 'spothub-library-backup';
  static const formatVersion = 1;

  final SpotDatabase _store;

  Future<String> exportJson() async {
    final database = _store.database;
    final playlistRows = await database.query(
      'playlists',
      orderBy: 'createdAt ASC, id ASC',
    );
    final playlists = <Map<String, Object?>>[];
    for (final playlist in playlistRows) {
      final trackRows = await database.rawQuery(
        '''
        SELECT tracks.* FROM playlist_tracks
        INNER JOIN tracks ON tracks.videoId = playlist_tracks.videoId
        WHERE playlist_tracks.playlistId = ?
        ORDER BY playlist_tracks.position ASC
        ''',
        [playlist['id']],
      );
      final coverImage = playlist['coverImage'];
      playlists.add({
        'name': playlist['name'],
        'createdAt': playlist['createdAt'],
        'coverImageBase64': coverImage is Uint8List
            ? base64Encode(coverImage)
            : null,
        'tracks': trackRows
            .map((row) => Track.fromMap(row).toJson())
            .toList(growable: false),
      });
    }

    final favoriteRows = await database.rawQuery('''
      SELECT tracks.*, favorites.createdAt AS savedAt FROM favorites
      INNER JOIN tracks ON tracks.videoId = favorites.videoId
      ORDER BY favorites.createdAt ASC
    ''');
    final historyRows = await database.rawQuery('''
      SELECT tracks.*, playback_history.playedAt AS lastPlayedAt
      FROM playback_history
      INNER JOIN tracks ON tracks.videoId = playback_history.videoId
      ORDER BY playback_history.playedAt ASC
    ''');

    return const JsonEncoder.withIndent('  ').convert({
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'playlists': playlists,
      'favorites': favoriteRows
          .map(
            (row) => {
              'createdAt': row['savedAt'],
              'track': Track.fromMap(row).toJson(),
            },
          )
          .toList(growable: false),
      'recentlyPlayed': historyRows
          .map(
            (row) => {
              'playedAt': row['lastPlayedAt'],
              'track': Track.fromMap(row).toJson(),
            },
          )
          .toList(growable: false),
    });
  }

  Future<LibraryBackupRestoreResult> restoreJson(String contents) async {
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatName ||
        decoded['version'] != formatVersion) {
      throw const FormatException(
        'This is not a SpotHub backup file version this app can restore.',
      );
    }

    final rawPlaylists = _list(decoded['playlists'], 'playlists');
    final rawFavorites = _list(decoded['favorites'], 'favorites');
    final rawHistory = _list(decoded['recentlyPlayed'], 'recently played');
    if (rawPlaylists.length > 10000 ||
        rawFavorites.length > 100000 ||
        rawHistory.length > 100000) {
      throw const FormatException('This backup contains too much data.');
    }

    final playlists = rawPlaylists.map(_parsePlaylist).toList(growable: false);
    final favorites = rawFavorites
        .map((entry) => _parseSavedTrack(entry, 'createdAt'))
        .toList(growable: false);
    final history = rawHistory
        .map((entry) => _parseSavedTrack(entry, 'playedAt'))
        .toList(growable: false);

    return _store.database.transaction((transaction) async {
      var added = 0;
      var skipped = 0;
      for (final playlist in playlists) {
        final existingRows = await transaction.query(
          'playlists',
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [playlist.name],
        );
        int? alreadyPresentId;
        for (final existing in existingRows) {
          final currentRows = await transaction.query(
            'playlist_tracks',
            columns: ['videoId'],
            where: 'playlistId = ?',
            whereArgs: [existing['id']],
            orderBy: 'position ASC',
          );
          final currentIds = currentRows
              .map((row) => row['videoId'] as String)
              .toList(growable: false);
          final incomingIds = playlist.tracks
              .map((track) => track.videoId)
              .toList(growable: false);
          if (_sameIds(currentIds, incomingIds)) {
            alreadyPresentId = existing['id']! as int;
            break;
          }
        }
        if (alreadyPresentId != null) {
          if (playlist.coverImageIncluded) {
            await transaction.update(
              'playlists',
              {'coverImage': playlist.coverImageBytes},
              where: 'id = ?',
              whereArgs: [alreadyPresentId],
            );
          }
          skipped++;
          continue;
        }

        final playlistId = await transaction.insert('playlists', {
          'name': playlist.name,
          'createdAt': playlist.createdAt,
          'coverImage': playlist.coverImageBytes,
        });
        var position = 0;
        final seen = <String>{};
        for (final track in playlist.tracks) {
          if (!seen.add(track.videoId)) continue;
          await upsertTrackRow(transaction, track);
          await transaction.insert('playlist_tracks', {
            'playlistId': playlistId,
            'videoId': track.videoId,
            'position': position++,
          });
        }
        added++;
      }

      for (final saved in favorites) {
        await upsertTrackRow(transaction, saved.track);
        await transaction.insert('favorites', {
          'videoId': saved.track.videoId,
          'createdAt': saved.timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final saved in history) {
        await upsertTrackRow(transaction, saved.track);
        await transaction.insert('playback_history', {
          'videoId': saved.track.videoId,
          'playedAt': saved.timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      return LibraryBackupRestoreResult(
        playlistsAdded: added,
        playlistsAlreadyPresent: skipped,
        favoritesRestored: favorites.length,
        recentTracksRestored: history.length,
      );
    });
  }

  static _BackupPlaylist _parsePlaylist(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('A playlist entry in the backup is invalid.');
    }
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty || name.trim().length > 50) {
      throw const FormatException(
        'A playlist name in the backup is missing or too long.',
      );
    }
    final rawTracks = _list(raw['tracks'], 'playlist tracks');
    if (rawTracks.length > 10000) {
      throw const FormatException('A playlist in the backup is too large.');
    }
    final timestamp = _timestamp(raw['createdAt']);
    final coverImageIncluded = raw.containsKey('coverImageBase64');
    final rawCoverImage = raw['coverImageBase64'];
    Uint8List? coverImageBytes;
    if (rawCoverImage != null) {
      if (rawCoverImage is! String) {
        throw const FormatException(
          'A playlist cover in the backup is invalid.',
        );
      }
      try {
        coverImageBytes = base64Decode(rawCoverImage);
      } on FormatException {
        throw const FormatException(
          'A playlist cover in the backup is invalid.',
        );
      }
      if (coverImageBytes.length > 8 * 1024 * 1024) {
        throw const FormatException(
          'A playlist cover in the backup is too large.',
        );
      }
    }
    return _BackupPlaylist(
      name: name.trim(),
      createdAt: timestamp,
      tracks: rawTracks.map(_parseTrack).toList(growable: false),
      coverImageIncluded: coverImageIncluded,
      coverImageBytes: coverImageBytes,
    );
  }

  static _BackupSavedTrack _parseSavedTrack(Object? raw, String timeKey) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('A saved track in the backup is invalid.');
    }
    return _BackupSavedTrack(
      track: _parseTrack(raw['track']),
      timestamp: _timestamp(raw[timeKey]),
    );
  }

  static Track _parseTrack(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('A track entry in the backup is invalid.');
    }
    final videoId = raw['videoId'];
    final title = raw['title'];
    final channelName = raw['channelName'];
    final thumbnailUrl = raw['thumbnailUrl'];
    final duration = raw['durationSeconds'];
    final source = raw['source'];
    if (videoId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) ||
        title is! String ||
        title.trim().isEmpty ||
        channelName is! String ||
        (thumbnailUrl != null && thumbnailUrl is! String) ||
        (duration != null && duration is! int) ||
        (source != null && source is! String)) {
      throw const FormatException('A track entry in the backup is invalid.');
    }
    return Track(
      videoId: videoId,
      title: title,
      channelName: channelName,
      thumbnailUrl: thumbnailUrl as String?,
      durationSeconds: duration as int?,
      source: source as String? ?? 'youtube',
    );
  }

  static List<Object?> _list(Object? value, String label) {
    if (value is! List) {
      throw FormatException('The $label section in this backup is invalid.');
    }
    return value.cast<Object?>();
  }

  static int _timestamp(Object? value) {
    final timestamp = value is int ? value : int.tryParse('$value');
    if (timestamp == null || timestamp < 0) {
      throw const FormatException('A date in the backup is invalid.');
    }
    return timestamp;
  }

  static bool _sameIds(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

class LibraryBackupRestoreResult {
  const LibraryBackupRestoreResult({
    required this.playlistsAdded,
    required this.playlistsAlreadyPresent,
    required this.favoritesRestored,
    required this.recentTracksRestored,
  });

  final int playlistsAdded;
  final int playlistsAlreadyPresent;
  final int favoritesRestored;
  final int recentTracksRestored;
}

class _BackupPlaylist {
  const _BackupPlaylist({
    required this.name,
    required this.createdAt,
    required this.tracks,
    required this.coverImageIncluded,
    required this.coverImageBytes,
  });

  final String name;
  final int createdAt;
  final List<Track> tracks;
  final bool coverImageIncluded;
  final Uint8List? coverImageBytes;
}

class _BackupSavedTrack {
  const _BackupSavedTrack({required this.track, required this.timestamp});

  final Track track;
  final int timestamp;
}
