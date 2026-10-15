import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../features/search/domain/track.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _tab = 0;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(downloadedTracksProvider);
    final playlists = ref.watch(downloadedPlaylistsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh downloads',
            onPressed: () {
              ref.invalidate(downloadedTracksProvider);
              ref.invalidate(downloadedPlaylistsProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.music_note_rounded),
                    label: Text('Songs'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.queue_music_rounded),
                    label: Text('Playlists'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (selection) =>
                    setState(() => _tab = selection.first),
              ),
            ),
            Expanded(
              child: _tab == 0 ? _songsTab(tracks) : _playlistsTab(playlists),
            ),
          ],
        ),
      ),
    );
  }

  Widget _songsTab(AsyncValue<List<Track>> state) => state.when(
    loading: () =>
        const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    error: (error, stack) => _MessageState(
      icon: Icons.error_outline_rounded,
      title: 'Downloads could not be loaded',
      body: error.toString(),
    ),
    data: (tracks) {
      final selectedTracks = tracks
          .where((track) => _selected.contains(track.videoId))
          .toList(growable: false);
      if (tracks.isEmpty) {
        return const _MessageState(
          icon: Icons.download_for_offline_outlined,
          title: 'No songs saved yet',
          body:
              'Use a song menu or Download playlist to save music for offline playback.',
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(17, 0, 17, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} available offline',
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
              ),
              if (selectedTracks.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _createOfflinePlaylist(selectedTracks),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: Text('Create playlist (${selectedTracks.length})'),
                ),
            ],
          ),
          if (_selected.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 9),
              child: Text(
                'Select songs to make an offline playlist.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
              ),
            ),
          for (final track in tracks)
            TrackTile(
              track: track,
              queue: tracks,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _selected.contains(track.videoId),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(track.videoId);
                      } else {
                        _selected.remove(track.videoId);
                      }
                    }),
                    activeColor: AppTheme.accent,
                  ),
                  IconButton(
                    tooltip: 'Remove download',
                    onPressed: () => _removeDownload(track),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.secondaryText,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _playlistsTab(
    AsyncValue<List<DownloadedPlaylist>> state,
  ) => state.when(
    loading: () =>
        const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    error: (error, stack) => _MessageState(
      icon: Icons.error_outline_rounded,
      title: 'Offline playlists could not be loaded',
      body: error.toString(),
    ),
    data: (playlists) {
      if (playlists.isEmpty) {
        return const _MessageState(
          icon: Icons.library_music_outlined,
          title: 'No downloaded playlists yet',
          body:
              'Download songs from a playlist, or make a playlist from your saved songs.',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 25),
        itemCount: playlists.length,
        separatorBuilder: (context, index) => const SizedBox(height: 5),
        itemBuilder: (context, index) {
          final entry = playlists[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 3,
            ),
            leading: Artwork(
              url: entry.playlist.thumbnailUrl,
              imageBytes: entry.playlist.coverImageBytes,
              size: 55,
              icon: Icons.queue_music_rounded,
            ),
            title: Text(
              entry.playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry.downloadedTracks} of ${entry.tracks.length} songs saved offline',
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/playlist/${entry.playlist.id}'),
          );
        },
      );
    },
  );

  Future<void> _createOfflinePlaylist(List<Track> tracks) async {
    final name = await showCreatePlaylistDialog(context);
    if (name == null || !mounted) return;
    try {
      await ref.read(playlistRepositoryProvider).createWithTracks(name, tracks);
      ref.invalidate(playlistsProvider);
      ref.invalidate(downloadedPlaylistsProvider);
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created offline playlist "$name".')),
      );
      setState(() => _tab = 1);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist could not be created: $error')),
      );
    }
  }

  Future<void> _removeDownload(Track track) async {
    await ref
        .read(audioDownloadRepositoryProvider)
        .deleteDownload(track.videoId);
    if (!mounted) return;
    setState(() => _selected.remove(track.videoId));
    ref.invalidate(downloadedTracksProvider);
    ref.invalidate(downloadedPlaylistsProvider);
    ref.invalidate(downloadedTrackProvider(track.videoId));
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.accent, size: 46),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.secondaryText, height: 1.4),
          ),
        ],
      ),
    ),
  );
}
