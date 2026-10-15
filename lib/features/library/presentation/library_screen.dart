import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import 'dart:convert';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../features/library/data/playlist_repository.dart';
import '../../../features/integrations/csv/playlist_csv_importer.dart';
import '../../../features/search/domain/track.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _filter = 'All';
  bool _grid = false;
  bool _alphabetical = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDisplayOptions());
  }

  Future<void> _restoreDisplayOptions() async {
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      final savedGrid = await preferences.getBool('library_grid') ?? false;
      final savedSort =
          await preferences.getBool('library_alphabetical') ?? false;
      if (mounted) {
        setState(() {
          _grid = savedGrid;
          _alphabetical = savedSort;
        });
      }
    } catch (_) {
      // Library display preferences are optional; the default layout still works.
    }
  }

  void _toggleGrid() {
    setState(() => _grid = !_grid);
    unawaited(
      ref.read(sharedPreferencesProvider).setBool('library_grid', _grid),
    );
  }

  void _toggleSort() {
    setState(() => _alphabetical = !_alphabetical);
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setBool('library_alphabetical', _alphabetical),
    );
  }

  @override
  Widget build(BuildContext context) {
    final personal = ref.watch(personalFlavorProvider);
    final playlists = ref.watch(playlistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final isLoading =
        playlists.isLoading || favorites.isLoading || recent.isLoading;
    final hasError =
        playlists.hasError || favorites.hasError || recent.hasError;
    final playlistItems = [...?playlists.asData?.value];
    final favoriteItems = [...?favorites.asData?.value];
    final recentItems = [...?recent.asData?.value];
    if (_alphabetical) {
      playlistItems.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      favoriteItems.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      recentItems.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 19, 18, 30),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Library',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (personal)
                  IconButton.filledTonal(
                    tooltip: 'Downloads',
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.elevated,
                      foregroundColor: AppTheme.accent,
                    ),
                    onPressed: () => context.push('/downloads'),
                    icon: const Icon(Icons.download_rounded),
                  ),
                IconButton(
                  tooltip: _alphabetical ? 'Sort by newest' : 'Sort A to Z',
                  onPressed: _toggleSort,
                  icon: Icon(
                    _alphabetical
                        ? Icons.sort_by_alpha_rounded
                        : Icons.swap_vert_rounded,
                  ),
                ),
                IconButton(
                  tooltip: _grid ? 'Show list' : 'Show grid',
                  onPressed: _toggleGrid,
                  icon: Icon(
                    _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Import CSV playlist',
                  onPressed: _importing ? null : _importPlaylist,
                  icon: _importing
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined),
                ),
                IconButton.filledTonal(
                  tooltip: 'Create playlist',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.elevated,
                    foregroundColor: AppTheme.accent,
                  ),
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (personal) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _importing ? null : _importYouTubePlaylist,
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Import YouTube playlist from link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: () => context.push('/spotify'),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Import Spotify playlist from link'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1ED760),
                side: BorderSide(
                  color: const Color(0xFF1ED760).withValues(alpha: 0.4),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final filter in const [
                    'All',
                    'Playlists',
                    'Liked Songs',
                    'Recently played',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                        labelStyle: TextStyle(
                          color: _filter == filter
                              ? const Color(0xFF111312)
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isLoading && playlistItems.isEmpty && favoriteItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                ),
              )
            else if (hasError && playlistItems.isEmpty && favoriteItems.isEmpty)
              _LibraryEmpty(
                title: 'Library unavailable',
                body:
                    'Your saved items couldnâ€™t be loaded. Please reopen the app.',
              )
            else
              ..._sections(playlistItems, favoriteItems, recentItems),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(
    List<PlaylistSummary> playlists,
    List<Track> favorites,
    List<Track> recent,
  ) {
    final sections = <Widget>[];
    if (_filter == 'All' || _filter == 'Playlists') {
      sections.add(
        SectionHeader('Playlists', action: 'Create', onAction: _createPlaylist),
      );
      if (playlists.isEmpty) {
        sections.add(
          _LibraryEmpty(
            title: 'Your playlists start here',
            body: 'Make a collection for the videos you want to come back to.',
            action: 'Create playlist',
            onAction: _createPlaylist,
          ),
        );
      } else if (_grid) {
        sections.add(
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: playlists.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 13,
              mainAxisSpacing: 16,
              mainAxisExtent: 224,
            ),
            itemBuilder: (context, index) =>
                _PlaylistGridCard(playlist: playlists[index]),
          ),
        );
      } else {
        for (final playlist in playlists) {
          sections.add(_PlaylistLibraryRow(playlist: playlist));
        }
      }
    }
    if (_filter == 'All' || _filter == 'Liked Songs') {
      sections.add(const SectionHeader('Liked Songs'));
      if (favorites.isEmpty) {
        sections.add(
          const _LibraryEmpty(
            title: 'Save the songs you love',
            body: 'Tap the menu on any video and add it to Liked Songs.',
            icon: Icons.favorite_border_rounded,
          ),
        );
      } else {
        for (final track in favorites.take(5)) {
          sections.add(TrackTile(track: track, compact: true));
        }
        if (favorites.length > 5) {
          sections.add(
            TextButton(
              onPressed: () => setState(() => _filter = 'Liked Songs'),
              child: Text('See all ${favorites.length} liked videos'),
            ),
          );
        }
      }
    }
    if (_filter == 'All' || _filter == 'Recently played') {
      sections.add(const SectionHeader('Recently played'));
      if (recent.isEmpty) {
        sections.add(
          const _LibraryEmpty(
            title: 'Nothing played yet',
            body: 'Play a video and itâ€™ll be saved here for quick access.',
            icon: Icons.history_rounded,
          ),
        );
      } else {
        for (final track in recent.take(_filter == 'All' ? 5 : recent.length)) {
          sections.add(TrackTile(track: track, compact: true));
        }
      }
    }
    return sections;
  }

  Future<void> _createPlaylist() async {
    final name = await showCreatePlaylistDialog(context);
    if (name == null) return;
    try {
      await ref.read(playlistRepositoryProvider).create(name);
      ref.invalidate(playlistsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist couldnâ€™t be created: $error')),
        );
      }
    }
  }

  Future<void> _importPlaylist() async {
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size == null || size > 2 * 1024 * 1024) {
        throw const FormatException('Choose a CSV file that is under 2 MB.');
      }
      final csv = utf8.decode(await file.readAsBytes());
      final imported = PlaylistCsvImporter.parse(csv);
      if (imported.tracks.isEmpty) {
        throw const FormatException(
          'No playable YouTube videos were found. Check the CSV columns and video IDs.',
        );
      }
      if (!mounted) return;
      final fileName = file.name.replaceFirst(
        RegExp(r'\.csv$', caseSensitive: false),
        '',
      );
      final name = await showCreatePlaylistDialog(
        context,
        initialName: fileName.isEmpty ? 'Imported playlist' : fileName,
      );
      if (name == null || !mounted) return;
      await ref
          .read(playlistRepositoryProvider)
          .createWithTracks(name, imported.tracks);
      if (!mounted) return;
      ref.invalidate(playlistsProvider);
      if (mounted) {
        final skipped = imported.skippedRows;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skipped == 0
                  ? 'Imported ${imported.tracks.length} videos to $name'
                  : 'Imported ${imported.tracks.length} videos; skipped $skipped invalid rows.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist import failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importYouTubePlaylist() async {
    setState(() => _importing = true);
    final urlController = TextEditingController();
    try {
      final playlistUrl = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import YouTube playlist'),
          content: TextField(
            controller: urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.elevated,
              prefixIcon: const Icon(Icons.link_rounded),
              labelText: 'Playlist link',
              hintText: 'youtube.com/playlist?list=â€¦',
              hintStyle: const TextStyle(color: AppTheme.secondaryText),
              labelStyle: const TextStyle(color: AppTheme.secondaryText),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: AppTheme.accent,
                  width: 1.5,
                ),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, urlController.text.trim()),
              child: const Text('Load playlist'),
            ),
          ],
        ),
      );
      if (!mounted || playlistUrl == null || playlistUrl.isEmpty) return;

      final imported = await ref
          .read(personalYouTubeCatalogProvider)
          .importPlaylist(playlistUrl);
      if (!mounted) return;
      final name = await showCreatePlaylistDialog(
        context,
        initialName: imported.title,
      );
      if (!mounted || name == null) return;

      await ref
          .read(playlistRepositoryProvider)
          .createWithTracks(name, imported.tracks);
      ref.invalidate(playlistsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${imported.tracks.length} videos to $name.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist import failed: $error')),
        );
      }
    } finally {
      urlController.dispose();
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _PlaylistLibraryRow extends StatelessWidget {
  const _PlaylistLibraryRow({required this.playlist});
  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Artwork(
      url: playlist.thumbnailUrl,
      imageBytes: playlist.coverImageBytes,
      size: 56,
      icon: Icons.queue_music_rounded,
    ),
    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      'Playlist Â· ${playlist.trackCount} videos',
      style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
    ),
    onTap: () => context.push('/playlist/${playlist.id}'),
  );
}

class _PlaylistGridCard extends StatelessWidget {
  const _PlaylistGridCard({required this.playlist});
  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/playlist/${playlist.id}'),
    borderRadius: BorderRadius.circular(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Artwork(
            url: playlist.thumbnailUrl,
            imageBytes: playlist.coverImageBytes,
            expand: true,
            radius: 12,
            icon: Icons.queue_music_rounded,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${playlist.trackCount} videos',
          style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
        ),
      ],
    ),
  );
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    this.icon = Icons.library_music_outlined,
  });
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppTheme.accent, size: 24),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(action!),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
