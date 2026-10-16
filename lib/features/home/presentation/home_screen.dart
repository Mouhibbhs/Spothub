import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/music_motion.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../features/library/data/playlist_repository.dart';
import '../../../features/player/application/playback_controller.dart';
import '../../../features/search/domain/track.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final favoriteTracks = favorites.asData?.value ?? const <Track>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BrandHeader(
                title: 'Home',
                actions: [
                  IconButton(
                    tooltip: 'Listening history',
                    onPressed: () => context.go('/library'),
                    icon: const Icon(Icons.history_rounded),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => context.go('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _greeting(),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _HomeFilterChip(
                          label: 'All',
                          selected: true,
                          onTap: () {
                            ref
                                .read(searchControllerProvider.notifier)
                                .setQuery('');
                            context.go('/search');
                          },
                        ),
                        for (final item in const [
                          ('Music', 'music'),
                          ('Podcasts', 'podcast'),
                          ('Audiobooks', 'audiobook'),
                        ])
                          _HomeFilterChip(
                            label: item.$1,
                            onTap: () => _search(context, ref, item.$2),
                          ),
                      ],
                    ),
                  ),
                  SectionHeader(
                    'Your playlists',
                    action: 'See all',
                    onAction: () => context.go('/library'),
                  ),
                  _QuickAccessSection(
                    playlists: playlists,
                    favorites: favoriteTracks,
                    onCreatePlaylist: () => _createPlaylist(context, ref),
                  ),
                  SectionHeader(
                    'Recently played',
                    action: 'See all',
                    onAction: () => context.go('/library'),
                  ),
                  _RecentlyPlayedSection(recent: recent),
                  const SectionHeader('Keep discovering'),
                  _DiscoveryBanner(onTap: () => context.go('/search')),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _search(BuildContext context, WidgetRef ref, String query) {
    ref.read(searchControllerProvider.notifier).searchNow(query);
    context.go('/search');
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final name = await showCreatePlaylistDialog(context);
    if (name == null) return;
    try {
      await ref.read(playlistRepositoryProvider).create(name);
      ref.invalidate(playlistsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist could not be created: $error')),
        );
      }
    }
  }
}

class _HomeFilterChip extends StatelessWidget {
  const _HomeFilterChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: PressScale(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF001F0B) : AppTheme.primaryText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        backgroundColor: AppTheme.elevated,
        selectedColor: AppTheme.accent,
        side: BorderSide.none,
      ),
    ),
  );
}

class _QuickAccessSection extends StatelessWidget {
  const _QuickAccessSection({
    required this.playlists,
    required this.favorites,
    required this.onCreatePlaylist,
  });

  final AsyncValue<List<PlaylistSummary>> playlists;
  final List<Track> favorites;
  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MusicMotion.track,
    transitionBuilder: coordinatedSwitchTransition,
    child: playlists.when(
      loading: () => const SizedBox(
        key: ValueKey('quick-access-loading'),
        height: 92,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
        ),
      ),
      error: (error, stack) => _InlineMessage(
        key: const ValueKey('quick-access-error'),
        message: 'Your playlists could not be opened.',
      ),
      data: (items) {
        final visiblePlaylists = items.take(favorites.isEmpty ? 6 : 5).toList();
        final count = visiblePlaylists.length + (favorites.isEmpty ? 0 : 1);
        if (count == 0) {
          return _CreateFirstPlaylist(
            key: const ValueKey('quick-access-empty'),
            onCreate: onCreatePlaylist,
          );
        }
        return GridView.builder(
          key: ValueKey(
            'quick-access-$count-${items.length}-${favorites.length}',
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 58,
          ),
          itemBuilder: (context, index) {
            if (favorites.isNotEmpty && index == 0) {
              return _QuickAccessTile.likedSongs(count: favorites.length);
            }
            final playlistIndex = favorites.isNotEmpty ? index - 1 : index;
            return _QuickAccessTile.playlist(
              playlist: visiblePlaylists[playlistIndex],
            );
          },
        );
      },
    ),
  );
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile._({
    this.playlist,
    this.count = 0,
    this.likedSongs = false,
  });

  factory _QuickAccessTile.playlist({required PlaylistSummary playlist}) =>
      _QuickAccessTile._(playlist: playlist);

  factory _QuickAccessTile.likedSongs({required int count}) =>
      _QuickAccessTile._(count: count, likedSongs: true);

  final PlaylistSummary? playlist;
  final int count;
  final bool likedSongs;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppTheme.elevated,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => likedSongs
            ? context.go('/library')
            : context.push('/playlist/${playlist!.id}'),
        child: Row(
          children: [
            if (likedSongs)
              Container(
                width: 58,
                height: 58,
                color: AppTheme.accent,
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF001F0B),
                  size: 25,
                ),
              )
            else
              Artwork(
                url: playlist!.thumbnailUrl,
                imageBytes: playlist!.coverImageBytes,
                size: 58,
                radius: 0,
                icon: Icons.queue_music_rounded,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                likedSongs ? 'Liked Songs' : playlist!.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.primaryText,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
        ),
      ),
    ),
  );
}

class _CreateFirstPlaylist extends StatelessWidget {
  const _CreateFirstPlaylist({required this.onCreate, super.key});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppTheme.elevated,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onCreate,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: AppTheme.accent, size: 25),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Create your first playlist',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Save videos in a collection of your own.',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.secondaryText),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RecentlyPlayedSection extends StatelessWidget {
  const _RecentlyPlayedSection({required this.recent});
  final AsyncValue<List<Track>> recent;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MusicMotion.track,
    transitionBuilder: coordinatedSwitchTransition,
    child: recent.when(
      loading: () => const SizedBox(
        key: ValueKey('recent-loading'),
        height: 96,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
        ),
      ),
      error: (error, stack) => const _InlineMessage(
        key: ValueKey('recent-error'),
        message: 'Your listening history could not be opened.',
      ),
      data: (tracks) => tracks.isEmpty
          ? const _InlineMessage(
              key: ValueKey('recent-empty'),
              message: 'Play something from Search to start your history.',
            )
          : SizedBox(
              key: ValueKey('recent-${tracks.first.videoId}'),
              height: 174,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _RecentCard(track: tracks[index]),
              ),
            ),
    ),
  );
}

class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 132,
    child: PressScale(
      child: InkWell(
        onTap: () {
          unawaited(
            ref.read(playbackControllerProvider.notifier).playTrack(track),
          );
          context.push('/now-playing');
        },
        borderRadius: BorderRadius.circular(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(url: track.thumbnailUrl, size: 132, radius: 4),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              track.channelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DiscoveryBanner extends StatelessWidget {
  const _DiscoveryBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hear something new',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Search tracks and playlists from YouTube.',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: AppTheme.accent),
            ],
          ),
        ),
      ),
    ),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
