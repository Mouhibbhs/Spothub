import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spothub/core/database/spot_database.dart';
import 'package:spothub/features/library/data/playlist_repository.dart';
import 'package:spothub/features/library/data/track_repository.dart';
import 'package:spothub/features/search/domain/track.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late SpotDatabase store;
  late PlaylistRepository playlists;
  late TrackRepository tracks;

  setUp(() async {
    store = await SpotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    playlists = PlaylistRepository(store);
    tracks = TrackRepository(store);
  });

  tearDown(() => store.close());

  const firstTrack = Track(
    videoId: 'abcdefghijk',
    title: 'First',
    channelName: 'Channel',
    thumbnailUrl: null,
  );
  const secondTrack = Track(
    videoId: 'lmnopqrstuv',
    title: 'Second',
    channelName: 'Channel',
    thumbnailUrl: null,
  );

  test('favorites persist once and toggle off by stable video ID', () async {
    expect(await tracks.toggleFavorite(firstTrack), isTrue);
    expect(await tracks.isFavorite(firstTrack.videoId), isTrue);
    expect(await tracks.getFavorites(), [firstTrack]);

    expect(await tracks.toggleFavorite(firstTrack), isFalse);
    expect(await tracks.isFavorite(firstTrack.videoId), isFalse);
    expect(await tracks.getFavorites(), isEmpty);
  });

  test('playlist import is ordered, deduplicated, and removable', () async {
    final playlistId = await playlists.createWithTracks('Road trip', [
      firstTrack,
      secondTrack,
      firstTrack,
    ]);

    expect(await playlists.getTracks(playlistId), [firstTrack, secondTrack]);
    expect((await playlists.getAll()).single.trackCount, 2);

    await playlists.removeTrack(playlistId, firstTrack.videoId);
    expect(await playlists.getTracks(playlistId), [secondTrack]);
    await playlists.delete(playlistId);
    expect(await playlists.getAll(), isEmpty);
  });

  test('search results round-trip through the local cache', () async {
    await tracks.cacheSearch('Night drive', [firstTrack]);
    expect(await tracks.readCachedSearch('night drive'), [firstTrack]);
  });
}
