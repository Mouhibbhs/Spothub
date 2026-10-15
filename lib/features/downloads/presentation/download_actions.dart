import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/download_notification_service.dart';
import '../../search/domain/track.dart';

Future<void> downloadTracks(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final downloadableTracks = tracks
      .where((track) => track.canPlayOnYouTube)
      .toList(growable: false);
  final skippedCount = tracks.length - downloadableTracks.length;
  if (downloadableTracks.isEmpty) {
    _showDownloadMessage(
      context,
      'This playlist has no supported tracks that can be saved by SpotHub.',
    );
    return;
  }

  final repository = ref.read(audioDownloadRepositoryProvider);
  final notifications = DownloadNotificationService.instance;
  final messenger = ScaffoldMessenger.of(context);
  var saved = 0;
  var failed = 0;
  try {
    await notifications.requestPermission();
  } catch (_) {
    // Downloads should still work when notifications are unavailable.
  }
  for (var index = 0; index < downloadableTracks.length; index++) {
    final track = downloadableTracks[index];
    var lastProgress = -1;
    DateTime? lastNotificationAt;
    Future<void> updateNotification(double progress) async {
      final overall =
          (((index + progress.clamp(0, 1)) / downloadableTracks.length) * 100)
              .round();
      final now = DateTime.now();
      if (overall == lastProgress ||
          (lastNotificationAt != null &&
              now.difference(lastNotificationAt!) <
                  const Duration(milliseconds: 700) &&
              overall != 100)) {
        return;
      }
      lastProgress = overall;
      lastNotificationAt = now;
      try {
        await notifications.showProgress(
          message:
              'Track ${index + 1} of ${downloadableTracks.length}: ${track.title}',
          progress: overall,
        );
      } catch (_) {
        // Keep the audio transfer running if Android cannot post a notification.
      }
    }

    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Saving ${index + 1} of ${downloadableTracks.length}: ${track.title}',
          ),
          duration: const Duration(minutes: 2),
        ),
      );
    }
    try {
      await updateNotification(0);
      await repository.downloadTrack(
        track,
        onProgress: (progress) => unawaited(updateNotification(progress)),
      );
      saved++;
      if (context.mounted) {
        ref.invalidate(downloadedTrackProvider(track.videoId));
      }
    } catch (_) {
      failed++;
    }
  }
  final summary =
      (failed == 0
          ? 'Saved $saved ${saved == 1 ? 'track' : 'tracks'} for offline playback.'
          : 'Saved $saved tracks. $failed could not be downloaded.') +
      (skippedCount == 0 ? '' : ' Skipped $skippedCount unsupported tracks.');
  if (messenger.mounted) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(summary)));
  }
  if (saved > 0) {
    try {
      await notifications.showComplete(
        failed == 0
            ? 'Saved $saved ${saved == 1 ? 'track' : 'tracks'} for offline playback.'
            : 'Saved $saved tracks; $failed could not be downloaded.',
      );
    } catch (_) {
      // A notification failure must not undo successfully saved files.
    }
    if (context.mounted) {
      ref.invalidate(downloadedTracksProvider);
      ref.invalidate(downloadedPlaylistsProvider);
    }
  } else {
    try {
      await notifications.cancel();
    } catch (_) {
      // Ignore notification service errors after failed downloads.
    }
  }
}

void _showDownloadMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
