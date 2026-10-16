import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/mini_player.dart';
import '../core/widgets/music_motion.dart';
import 'theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: AnimatedSize(
              alignment: Alignment.bottomCenter,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: const MiniPlayer(),
            ),
          ),
          _SpotNavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotNavigationBar extends StatelessWidget {
  const _SpotNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _destinations = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.search_rounded, Icons.search_rounded, 'Search'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Your Library'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppTheme.surface,
      border: Border(top: BorderSide(color: AppTheme.outline)),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        7,
        7,
        7,
        6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          for (var index = 0; index < _destinations.length; index++)
            Expanded(
              child: _NavigationDestination(
                selected: index == selectedIndex,
                destination: _destinations[index],
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    ),
  );
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.selected,
    required this.destination,
    required this.onTap,
  });

  final bool selected;
  final (IconData, IconData, String) destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    pressedScale: 0.93,
    child: Semantics(
      button: true,
      selected: selected,
      label: destination.$3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: MusicMotion.selection,
                curve: Curves.easeOutBack,
                width: selected ? 48 : 38,
                height: 29,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.accent.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AnimatedScale(
                  duration: MusicMotion.icon,
                  curve: Curves.easeOutBack,
                  scale: selected ? 1.08 : 0.94,
                  child: Icon(
                    selected ? destination.$2 : destination.$1,
                    color: selected
                        ? AppTheme.accentPressed
                        : AppTheme.secondaryText,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: MusicMotion.icon,
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: selected
                      ? AppTheme.accentPressed
                      : AppTheme.secondaryText,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
                child: Text(destination.$3),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
