import 'package:flutter/foundation.dart';

@immutable
class Track {
  const Track({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.thumbnailUrl,
    this.durationSeconds,
    this.source = 'youtube',
  });

  final String videoId;
  final String title;
  final String channelName;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String source;

  bool get canPlayOnYouTube =>
      source == 'youtube' && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId);

  static Track? tryParseYouTubeSearchItem(Map<String, dynamic> item) {
    final id = item['id'];
    final snippet = item['snippet'];
    if (id is! Map<String, dynamic> || snippet is! Map<String, dynamic>) {
      return null;
    }
    final videoId = id['videoId'];
    final title = snippet['title'];
    final channel = snippet['channelTitle'];
    if (videoId is! String || videoId.isEmpty || title is! String) {
      return null;
    }

    final thumbnails = snippet['thumbnails'];
    String? thumbnailUrl;
    if (thumbnails is Map<String, dynamic>) {
      for (final size in ['maxres', 'high', 'medium', 'default']) {
        final thumbnail = thumbnails[size];
        if (thumbnail is Map<String, dynamic> && thumbnail['url'] is String) {
          thumbnailUrl = thumbnail['url'] as String;
          break;
        }
      }
    }

    return Track(
      videoId: videoId,
      title: title,
      channelName: channel is String ? channel : 'YouTube',
      thumbnailUrl: thumbnailUrl,
    );
  }

  factory Track.fromMap(Map<String, Object?> map) => Track(
    videoId: map['videoId']! as String,
    title: map['title']! as String,
    channelName: map['channelName']! as String,
    thumbnailUrl: map['thumbnailUrl'] as String?,
    durationSeconds: map['durationSeconds'] as int?,
    source: map['source'] as String? ?? 'youtube',
  );

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    videoId: json['videoId'] as String,
    title: json['title'] as String,
    channelName: json['channelName'] as String,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    durationSeconds: json['durationSeconds'] as int?,
    source: json['source'] as String? ?? 'youtube',
  );

  Map<String, Object?> toMap() => {
    'videoId': videoId,
    'title': title,
    'channelName': channelName,
    'thumbnailUrl': thumbnailUrl,
    'durationSeconds': durationSeconds,
    'source': source,
  };

  Map<String, Object?> toJson() => toMap();

  @override
  bool operator ==(Object other) => other is Track && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}
