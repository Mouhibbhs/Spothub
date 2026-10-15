import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../features/downloads/presentation/download_actions.dart';
import '../data/playlist_repository.dart';
import '../../../features/player/application/playback_controller.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.playlistId, super.key});
  final int playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final tracks = ref.watch(playlistTracksProvider(widget.playlistId));
    final matching = playlists.asData?.value
        .where((item) => item.id == widget.playlistId)
        .toList(growable: false);
    final playlist = matching == null || matching.isEmpty
        ? null
        : matching.first;
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          if (playlist != null)
            IconButton(
              tooltip: 'Change playlist cover',
              onPressed: () => _editCover(context, ref, playlist),
              icon: const Icon(Icons.photo_outlined),
            ),
          IconButton(
            tooltip: 'Delete playlist',
            onPressed: playlist == null
                ? null
                : () => _deletePlaylist(context, ref, playlist.name),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: tracks.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (error, stack) =>
            const Center(child: Text('This playlist couldn’t be opened.')),
        data: (items) {
          final normalizedQuery = _query.trim().toLowerCase();
          final visibleItems = normalizedQuery.isEmpty
              ? items
              : items
                    .where(
                      (track) =>
                          track.title.toLowerCase().contains(normalizedQuery) ||
                          track.channelName.toLowerCase().contains(
                            normalizedQuery,
                          ),
                    )
                    .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(15, 9, 15, 25),
            children: [
              if (playlist != null) ...[
                _PlaylistHeader(
                  name: playlist.name,
                  count: playlist.trackCount,
                  thumbnailUrl: playlist.thumbnailUrl,
                  coverImageBytes: playlist.coverImageBytes,
                  onChangeCover: () => _editCover(context, ref, playlist),
                ),
                const SizedBox(height: 12),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Find a song in this playlist',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: AppTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: AppTheme.surface.withValues(alpha: 0.8),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
              ],
              if (items.isEmpty)
                _EmptyPlaylist(name: playlist?.name ?? 'this playlist')
              else if (visibleItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 38),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.search_off_rounded,
                        size: 38,
                        color: AppTheme.secondaryText,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No songs match “${_query.trim()}”.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        normalizedQuery.isEmpty
                            ? '${items.length} songs'
                            : '${visibleItems.length} of ${items.length} songs',
                        style: const TextStyle(
                          color: AppTheme.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (ref.read(personalFlavorProvider)) ...[
                      OutlinedButton.icon(
                        onPressed: () => downloadTracks(context, ref, items),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download playlist'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: () {
                        ref
                            .read(playbackControllerProvider.notifier)
                            .playTrack(visibleItems.first, queue: items);
                        context.push('/now-playing');
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              for (final track in visibleItems)
                TrackTile(
                  track: track,
                  queue: items,
                  trailing: IconButton(
                    tooltip: 'Remove from playlist',
                    onPressed: () async {
                      await ref
                          .read(playlistRepositoryProvider)
                          .removeTrack(widget.playlistId, track.videoId);
                      ref.invalidate(playlistTracksProvider(widget.playlistId));
                      ref.invalidate(playlistsProvider);
                    },
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      color: AppTheme.secondaryText,
                      size: 20,
                    ),
                  ),
                  compact: true,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCover(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
  ) async {
    final action = await showModalBottomSheet<_CoverAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from device'),
              onTap: () => Navigator.pop(sheetContext, _CoverAction.choose),
            ),
            if (playlist.coverImageBytes != null)
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Reset to playlist artwork'),
                onTap: () => Navigator.pop(sheetContext, _CoverAction.reset),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      if (action == _CoverAction.choose) {
        final pickedImage = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
          dialogTitle: 'Choose playlist cover',
        );
        if (pickedImage == null || !context.mounted) return;
        final imageSize = await pickedImage.length();
        if (!context.mounted) return;
        if (imageSize != null && imageSize > 8 * 1024 * 1024) {
          _showCoverMessage(context, 'Choose an image smaller than 8 MB.');
          return;
        }
        final imageBytes = await pickedImage.readAsBytes();
        if (!context.mounted) return;
        if (imageBytes.isEmpty) {
          _showCoverMessage(
            context,
            'Could not read that image. Try another file.',
          );
          return;
        }
        if (imageBytes.length > 8 * 1024 * 1024) {
          _showCoverMessage(context, 'Choose an image smaller than 8 MB.');
          return;
        }
        await ref
            .read(playlistRepositoryProvider)
            .setCoverImage(playlist.id, imageBytes);
      } else {
        await ref
            .read(playlistRepositoryProvider)
            .setCoverImage(playlist.id, null);
      }
      if (!context.mounted) return;
      ref.invalidate(playlistsProvider);
      if (context.mounted) {
        _showCoverMessage(
          context,
          action == _CoverAction.choose
              ? 'Playlist cover updated.'
              : 'Playlist cover reset.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showCoverMessage(context, 'Could not update playlist cover: $error');
      }
    }
  }

  void _showCoverMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('“$name” will be removed from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await ref.read(playlistRepositoryProvider).delete(widget.playlistId);
    ref.invalidate(playlistsProvider);
    if (context.mounted) context.pop();
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.name,
    required this.count,
    required this.thumbnailUrl,
    required this.coverImageBytes,
    required this.onChangeCover,
  });
  final String name;
  final int count;
  final String? thumbnailUrl;
  final Uint8List? coverImageBytes;
  final VoidCallback onChangeCover;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Stack(
        children: [
          Artwork(
            url: thumbnailUrl,
            imageBytes: coverImageBytes,
            size: 210,
            radius: 10,
            icon: Icons.queue_music_rounded,
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton.filledTonal(
              tooltip: 'Change playlist cover',
              onPressed: onChangeCover,
              icon: const Icon(Icons.edit_rounded),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      Text(
        'SpotHub playlist · $count videos',
        style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
      ),
    ],
  );
}

enum _CoverAction { choose, reset }

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.queue_music_rounded,
            color: AppTheme.accent,
            size: 44,
          ),
          const SizedBox(height: 13),
          Text(
            name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'This playlist is empty. Add videos from Search to start your collection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
