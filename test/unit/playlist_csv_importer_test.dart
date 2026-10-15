import 'package:flutter_test/flutter_test.dart';
import 'package:spothub/features/integrations/csv/playlist_csv_importer.dart';

void main() {
  group('PlaylistCsvImporter', () {
    test('imports YouTube URLs and quoted values with commas', () {
      final result = PlaylistCsvImporter.parse(
        'youtubeUrl,title,artist\n'
        'https://youtu.be/abcdefghijk,"Blue, Monday",New Order\n'
        'lmnopqrstuv,Second song,Example Artist\n',
      );

      expect(result.tracks, hasLength(2));
      expect(result.tracks.first.videoId, 'abcdefghijk');
      expect(result.tracks.first.title, 'Blue, Monday');
      expect(result.tracks.first.channelName, 'New Order');
      expect(result.skippedRows, 0);
    });

    test('skips rows with invalid IDs and reports the count', () {
      final result = PlaylistCsvImporter.parse(
        'videoId,title\n'
        'abcdefghijk,Valid\n'
        'not-a-vide,Unavailable\n',
      );

      expect(result.tracks, hasLength(1));
      expect(result.skippedRows, 1);
    });

    test('rejects missing required headers and unclosed quoted fields', () {
      expect(
        () => PlaylistCsvImporter.parse('artist,title\nA,Song'),
        throwsFormatException,
      );
      expect(
        () => PlaylistCsvImporter.parse('videoId,title\nabcdefghijk,"Song'),
        throwsFormatException,
      );
    });
  });
}
