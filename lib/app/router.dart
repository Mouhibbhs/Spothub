import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/music_motion.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/downloads/presentation/downloads_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/playlist_screen.dart';
import '../features/player/presentation/now_playing_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/spotify/presentation/spotify_playlists_screen.dart';
import 'app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      navigatorContainerBuilder: (context, navigationShell, children) =>
          _AnimatedBranchStack(
            currentIndex: navigationShell.currentIndex,
            children: children,
          ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => _motionPage(
                state,
                const HomeScreen(),
                begin: const Offset(0, 0.025),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) => _motionPage(
                state,
                const SearchScreen(),
                begin: const Offset(0, 0.025),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              pageBuilder: (context, state) => _motionPage(
                state,
                const LibraryScreen(),
                begin: const Offset(0, 0.025),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => _motionPage(
                state,
                const SettingsScreen(),
                begin: const Offset(0, 0.025),
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/now-playing',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _motionPage(
        state,
        const NowPlayingScreen(),
        begin: const Offset(0, 0.12),
        scale: 0.975,
      ),
    ),
    GoRoute(
      path: '/downloads',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _motionPage(
        state,
        const DownloadsScreen(),
        begin: const Offset(0, 0.05),
      ),
    ),
    GoRoute(
      path: '/spotify',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _motionPage(
        state,
        const SpotifyPlaylistsScreen(),
        begin: const Offset(0.035, 0),
      ),
    ),
    GoRoute(
      path: '/playlist/:playlistId',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _motionPage(
        state,
        PlaylistScreen(
          playlistId:
              int.tryParse(state.pathParameters['playlistId'] ?? '') ?? -1,
        ),
        begin: const Offset(0.04, 0),
      ),
    ),
  ],
);

CustomTransitionPage<void> _motionPage(
  GoRouterState state,
  Widget child, {
  Offset begin = const Offset(0.025, 0),
  double scale = 1,
}) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: const Duration(milliseconds: 420),
  reverseTransitionDuration: const Duration(milliseconds: 300),
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
    if (MusicMotion.reduced(context)) return pageChild;
    final entrance = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final spring = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: entrance,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(entrance),
        child: ScaleTransition(
          scale: Tween<double>(begin: scale, end: 1).animate(spring),
          child: RepaintBoundary(child: pageChild),
        ),
      ),
    );
  },
);

class _AnimatedBranchStack extends StatelessWidget {
  const _AnimatedBranchStack({
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = MusicMotion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final slideDuration = MusicMotion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    return Stack(
      children: [
        for (var index = 0; index < children.length; index++)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: index == currentIndex ? 1 : 0,
              duration: duration,
              curve: Curves.easeInOutCubic,
              child: AnimatedSlide(
                offset: index == currentIndex
                    ? Offset.zero
                    : const Offset(0, 0.025),
                duration: slideDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: index == currentIndex ? 1 : 0.985,
                  duration: slideDuration,
                  curve: Curves.easeOutBack,
                  child: TickerMode(
                    enabled: index == currentIndex,
                    child: IgnorePointer(
                      ignoring: index != currentIndex,
                      child: ExcludeSemantics(
                        excluding: index != currentIndex,
                        child: children[index],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
