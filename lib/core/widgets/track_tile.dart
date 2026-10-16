import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../features/player/application/playback_controller.dart';
import '../../features/downloads/presentation/download_actions.dart';
import '../../features/search/domain/track.dart';
import 'artwork.dart';
import 'music_motion.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    required this.track,
    this.queue = const [],
    this.radioQuery,
    this.trailing,
    this.onTap,
    this.compact = false,
    super.key,
  });

  final Track track;
  final List<Track> queue;
  final String? radioQuery;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personal = ref.watch(personalFlavorProvider);
    final isDownloadable = track.canPlayOnYouTube;
    final isDownloaded = personal && isDownloadable
        ? ref.watch(downloadedTrackProvider(track.videoId)).value ?? false
        : false;
    final favorite = ref.watch(isFavoriteProvider(track.videoId));
    final isFavorite = favorite.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );
    final playback = ref.watch(playbackControllerProvider);
    final isCurrent = playback.track?.videoId == track.videoId;

    return PressScale(
      pressedScale: 0.987,
      child: AnimatedContainer(
        duration: MusicMotion.icon,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isCurrent
              ? AppTheme.accent.withValues(
                  alpha: playback.isPlaying ? 0.10 : 0.055,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ?? () => _play(context, ref),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 7,
                vertical: compact ? 5 : 8,
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Artwork(
                        url: track.thumbnailUrl,
                        size: compact ? 46 : 52,
                        radius: 4,
                      ),
                      if (isCurrent && playback.isPlaying)
                        Container(
                          width: compact ? 46 : 52,
                          height: compact ? 46 : 52,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.graphic_eq_rounded,
                            color: AppTheme.accentPressed,
                            size: 24,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? AppTheme.accentPressed
                                : AppTheme.primaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                  PopupMenuButton<String>(
                    tooltip: 'More options',
                    icon: const Icon(
                      Icons.more_horiz,
                      color: AppTheme.secondaryText,
                    ),
                    onSelected: (value) async {
                      if (value == 'play') {
                        _play(context, ref);
                      } else if (value == 'favorite') {
                        final added = await ref
                            .read(trackRepositoryProvider)
                            .toggleFavorite(track);
                        if (!context.mounted) return;
                        ref.invalidate(favoritesProvider);
                        ref.invalidate(isFavoriteProvider(track.videoId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added
                                  ? 'Added to Liked Songs'
                                  : 'Removed from Liked Songs',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } else if (value == 'playlist') {
                        await _addToPlaylist(context, ref);
                      } else if (value == 'queue-next') {
                        final added = await ref
                            .read(playbackControllerProvider.notifier)
                            .addToQueueNext(track);
                        if (!context.mounted) return;
                        _showMessage(
                          context,
                          added
                              ? 'Added to play next.'
                              : 'This song is already playing.',
                        );
                      } else if (value == 'download') {
                        await downloadTracks(context, ref, [track]);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'play',
                        child: Text('Play now'),
                      ),
                      if (personal)
                        const PopupMenuItem(
                          value: 'queue-next',
                          child: Text('Add to queue'),
                        ),
                      if (personal && isDownloadable)
                        PopupMenuItem(
                          value: 'download',
                          enabled: !isDownloaded,
                          child: Text(
                            isDownloaded
                                ? 'Downloaded'
                                : 'Download for offline use',
                          ),
                        ),
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text(
                          isFavorite
                              ? 'Remove from Liked Songs'
                              : 'Add to Liked Songs',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'playlist',
                        child: Text('Add to playlist'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _play(BuildContext context, WidgetRef ref) {
    if (!track.canPlayOnYouTube) {
      _showMessage(context, 'This saved track is no longer playable.');
      return;
    }
    unawaited(
      ref
          .read(playbackControllerProvider.notifier)
          .playTrack(track, queue: queue, radioQuery: radioQuery),
    );
    context.push('/now-playing');
  }

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(playlistRepositoryProvider);
    final playlists = await repository.getAll();
    if (!context.mounted) return;
    if (playlists.isEmpty) {
      final create = await showCreatePlaylistDialog(context);
      if (create == null || !context.mounted) return;
      final id = await repository.create(create);
      await repository.addTrack(id, track);
      if (!context.mounted) return;
      ref.invalidate(playlistsProvider);
      _showMessage(context, 'Added to $create');
      return;
    }
    final selectedId = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text('Add to playlist', style: TextStyle(fontSize: 18)),
            ),
            for (final playlist in playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                onTap: () => Navigator.pop(context, playlist.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Create new playlist'),
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (selectedId == null || !context.mounted) return;
    if (selectedId == -1) {
      final name = await showCreatePlaylistDialog(context);
      if (name == null || !context.mounted) return;
      final id = await repository.create(name);
      await repository.addTrack(id, track);
      if (!context.mounted) return;
      ref.invalidate(playlistsProvider);
      _showMessage(context, 'Added to $name');
    } else {
      await repository.addTrack(selectedId, track);
      if (!context.mounted) return;
      ref.invalidate(playlistsProvider);
      _showMessage(context, 'Added to playlist');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

Future<String?> showCreatePlaylistDialog(
  BuildContext context, {
  String? initialName,
}) async {
  final controller = TextEditingController(text: initialName ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 50,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Name your playlist',
          filled: false,
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
