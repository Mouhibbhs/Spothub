import 'dart:io';

import 'package:sqflite/sqflite.dart';

class SpotDatabase {
  SpotDatabase._(this.database);

  static const schemaVersion = 3;
  final Database database;

  static Future<SpotDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final databaseFactoryToUse = factory ?? databaseFactory;
    final databasePath =
        path ??
        '${await getDatabasesPath()}${Platform.pathSeparator}spothub.db';
    final database = await databaseFactoryToUse.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: _upgrade,
      ),
    );
    return SpotDatabase._(database);
  }

  Future<void> close() => database.close();

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE tracks (
        videoId TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        channelName TEXT NOT NULL,
        thumbnailUrl TEXT,
        durationSeconds INTEGER,
        source TEXT NOT NULL DEFAULT 'youtube'
      )
    ''');
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        coverImage BLOB
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_tracks (
        playlistId INTEGER NOT NULL,
        videoId TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlistId, videoId),
        UNIQUE (playlistId, position),
        FOREIGN KEY (playlistId) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (videoId) REFERENCES tracks(videoId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        videoId TEXT PRIMARY KEY,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (videoId) REFERENCES tracks(videoId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE playback_history (
        videoId TEXT PRIMARY KEY,
        playedAt INTEGER NOT NULL,
        FOREIGN KEY (videoId) REFERENCES tracks(videoId) ON DELETE CASCADE
      )
    ''');
    await _createSearchCache(db);
  }

  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) await _createSearchCache(db);
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE playlists ADD COLUMN coverImage BLOB');
    }
  }

  static Future<void> _createSearchCache(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS search_cache (
      query TEXT PRIMARY KEY,
      resultsJson TEXT NOT NULL,
      updatedAt INTEGER NOT NULL
    )
  ''');
}
