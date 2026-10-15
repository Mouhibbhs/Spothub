import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spothub/core/database/spot_database.dart';
import 'package:spothub/features/library/data/track_repository.dart';
import 'package:spothub/features/search/data/youtube_search_repository.dart';
import 'package:spothub/features/search/domain/track.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'missing API key returns setup guidance without making a request',
    () async {
      final store = await SpotDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final repository = YouTubeSearchRepository(
        tracks: TrackRepository(store),
        dio: Dio(),
        apiKey: '',
      );

      final outcome = await repository.search('ambient music');

      expect(outcome.tracks, isEmpty);
      expect(outcome.message, contains('YouTube Data API key'));
      expect(outcome.fromCache, isFalse);
      await store.close();
    },
  );

  test(
    'missing API key can show genuine cached results with a clear label',
    () async {
      final store = await SpotDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      const track = Track(
        videoId: 'abcdefghijk',
        title: 'Ambient',
        channelName: 'Example channel',
        thumbnailUrl: null,
      );
      final trackRepository = TrackRepository(store);
      await trackRepository.cacheSearch('ambient music', [track]);
      final repository = YouTubeSearchRepository(
        tracks: trackRepository,
        dio: Dio(),
        apiKey: '',
      );

      final outcome = await repository.search('ambient music');

      expect(outcome.tracks, [track]);
      expect(outcome.fromCache, isTrue);
      expect(outcome.message, contains('Live search needs'));
      await store.close();
    },
  );
}
