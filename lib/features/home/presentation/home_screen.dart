import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
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
    final recent = ref.watch(recentlyPlayedProvider);
    final playlistSection = playlists.when(
      loading: () {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      error: (error, stack) =>
          _InlineMessage(message: 'Your playlists couldnâ€™t be opened.'),
      data: (items) {
        return items.isEmpty
            ? _CreateFirstPlaylist(
                onCreate: () => _createPlaylist(context, ref),
              )
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length > 4 ? 4 : items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 65,
                ),
                itemBuilder: (context, index) =>
                    _PlaylistQuickCard(playlist: items[index]),
              );
      },
    );
    final recentSection = recent.when(
      loading: () {
        return const SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      error: (error, stack) => _InlineMessage(
        message: 'Your listening history couldnâ€™t be opened.',
      ),
      data: (tracks) {
        return tracks.isEmpty
            ? _InlineMessage(
                message:
                    'Videos you play will show up here. Find something new in Search.',
                action: 'Explore music',
                onAction: () => context.go('/search'),
              )
            : SizedBox(
                height: 178,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tracks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 13),
                  itemBuilder: (context, index) =>
                      _RecentCard(track: tracks[index]),
                ),
              );
      },
    );
    final screen = Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 30),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(),
                              style: const TextStyle(
                                color: AppTheme.secondaryText,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'SpotHub',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Settings',
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.elevated,
                          foregroundColor: AppTheme.accent,
                        ),
                        onPressed: () => context.go('/settings'),
                        icon: const Icon(Icons.person_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 19),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final genre in const [
                          'All',
                          'Pop',
                          'Hip-hop',
                          'Rock',
                          'Latin',
                          'Electronic',
                          'Jazz',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(genre),
                              onPressed: () => _search(context, ref, genre),
                              backgroundColor: genre == 'All'
                                  ? AppTheme.accent
                                  : AppTheme.elevated,
                              labelStyle: TextStyle(
                                color: genre == 'All'
                                    ? const Color(0xFF082512)
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SectionHeader('Your playlists'),
                  playlistSection,
                  SectionHeader(
                    'Recently played',
                    action: 'See all',
                    onAction: () => context.go('/library'),
                  ),
                  recentSection,
                  const SectionHeader('Start a new discovery'),
                  _DiscoveryBanner(onTap: () => context.go('/search')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return screen;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _search(BuildContext context, WidgetRef ref, String genre) {
    final query = genre == 'All' ? '' : '$genre music';
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
          SnackBar(content: Text('Playlist couldnâ€™t be created: $error')),
        );
      }
    }
  }
}

class _PlaylistQuickCard extends StatelessWidget {
  const _PlaylistQuickCard({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Row(
        children: [
          Artwork(
            url: playlist.thumbnailUrl,
            imageBytes: playlist.coverImageBytes,
            size: 65,
            radius: 0,
            icon: Icons.queue_music_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.trackCount} videos',
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    ),
  );
}

class _CreateFirstPlaylist extends StatelessWidget {
  const _CreateFirstPlaylist({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onCreate,
      borderRadius: BorderRadius.circular(16),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppTheme.accent, size: 25),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create your first playlist',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Save videos together in your own collection.',
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
  );
}

class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 138,
    child: InkWell(
      onTap: () {
        ref.read(playbackControllerProvider.notifier).playTrack(track);
        context.push('/now-playing');
      },
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Artwork(url: track.thumbnailUrl, size: 138, radius: 12),
          const SizedBox(height: 9),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            track.channelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
          ),
        ],
      ),
    ),
  );
}

class _DiscoveryBanner extends StatelessWidget {
  const _DiscoveryBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF1A4030),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: const Padding(
        padding: EdgeInsets.all(17),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hear something new',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Search music videos from across YouTube.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: AppTheme.accent),
          ],
        ),
      ),
    ),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, this.action, this.onAction});
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
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
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}
