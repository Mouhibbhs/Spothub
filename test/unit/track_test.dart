import 'package:flutter_test/flutter_test.dart';
import 'package:spothub/features/search/domain/track.dart';

void main() {
  group('YouTube search parsing', () {
    test('parses an embeddable result and prefers its largest thumbnail', () {
      final track = Track.tryParseYouTubeSearchItem({
        'id': {'videoId': 'abcdefghijk'},
        'snippet': {
          'title': 'Night drive',
          'channelTitle': 'Example channel',
          'thumbnails': {
            'default': {'url': 'https://img.example/small.jpg'},
            'high': {'url': 'https://img.example/high.jpg'},
          },
        },
      });

      expect(track, isNotNull);
      expect(track!.videoId, 'abcdefghijk');
      expect(track.title, 'Night drive');
      expect(track.channelName, 'Example channel');
      expect(track.thumbnailUrl, 'https://img.example/high.jpg');
    });

    test('ignores items that do not contain a stable video ID', () {
      expect(
        Track.tryParseYouTubeSearchItem({
          'id': {'channelId': 'channel-id'},
          'snippet': {'title': 'A channel'},
        }),
        isNull,
      );
    });

    test('uses the stable video ID as track identity', () {
      const first = Track(
        videoId: 'abcdefghijk',
        title: 'First title',
        channelName: 'Channel',
        thumbnailUrl: null,
      );
      const renamed = Track(
        videoId: 'abcdefghijk',
        title: 'Updated title',
        channelName: 'Channel',
        thumbnailUrl: null,
      );
      expect(first, renamed);
      expect({first, renamed}, hasLength(1));
    });
  });
}
