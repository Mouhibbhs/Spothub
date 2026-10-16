import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

abstract final class MusicMotion {
  static const button = Duration(milliseconds: 120);
  static const icon = Duration(milliseconds: 190);
  static const selection = Duration(milliseconds: 220);
  static const track = Duration(milliseconds: 320);
  static const artwork = Duration(milliseconds: 380);
  static const sheet = Duration(milliseconds: 340);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

class PressScale extends StatefulWidget {
  const PressScale({required this.child, this.pressedScale = 0.975, super.key});

  final Widget child;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _setPressed(true),
    onPointerUp: (_) => _setPressed(false),
    onPointerCancel: (_) => _setPressed(false),
    child: AnimatedScale(
      scale: !MusicMotion.reduced(context) && _pressed
          ? widget.pressedScale
          : 1,
      duration: MusicMotion.button,
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class AnimatedPlayPauseIcon extends StatefulWidget {
  const AnimatedPlayPauseIcon({
    required this.isPlaying,
    this.size = 26,
    this.color,
    super.key,
  });

  final bool isPlaying;
  final double size;
  final Color? color;

  @override
  State<AnimatedPlayPauseIcon> createState() => _AnimatedPlayPauseIconState();
}

class _AnimatedPlayPauseIconState extends State<AnimatedPlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MusicMotion.icon,
    value: widget.isPlaying ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant AnimatedPlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (MusicMotion.reduced(context)) {
        _controller.value = widget.isPlaying ? 1 : 0;
      } else {
        _controller.animateTo(
          widget.isPlaying ? 1 : 0,
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
    icon: AnimatedIcons.play_pause,
    progress: _controller,
    size: widget.size,
    color: widget.color,
  );
}

class AnimatedFavoriteButton extends StatelessWidget {
  const AnimatedFavoriteButton({
    required this.selected,
    required this.onPressed,
    this.size = 22,
    this.tooltip,
    super.key,
  });

  final bool selected;
  final VoidCallback onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => PressScale(
    pressedScale: 0.88,
    child: IconButton(
      tooltip:
          tooltip ??
          (selected ? 'Remove from Liked Songs' : 'Add to Liked Songs'),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: AnimatedSwitcher(
        duration: MusicMotion.icon,
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.55, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: RotationTransition(
            turns: Tween<double>(begin: -0.06, end: 0).animate(animation),
            child: child,
          ),
        ),
        child: Icon(
          key: ValueKey(selected),
          selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: selected ? AppTheme.accent : AppTheme.secondaryText,
          size: size,
        ),
      ),
    ),
  );
}

Widget coordinatedSwitchTransition(
  Widget child,
  Animation<double> animation, {
  Offset begin = const Offset(0.045, 0),
}) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.965, end: 1).animate(curved),
        child: child,
      ),
    ),
  );
}

class AnimatedModeButton extends StatelessWidget {
  const AnimatedModeButton({
    required this.active,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.activeIcon,
    this.size = 22,
    super.key,
  });

  final bool active;
  final IconData icon;
  final IconData? activeIcon;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) => PressScale(
    pressedScale: 0.88,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      color: active ? AppTheme.accent : AppTheme.secondaryText,
      icon: AnimatedRotation(
        turns: active ? 0.035 : 0,
        duration: MusicMotion.icon,
        curve: Curves.easeOutCubic,
        child: AnimatedSwitcher(
          duration: MusicMotion.icon,
          transitionBuilder: coordinatedSwitchTransition,
          child: Icon(
            key: ValueKey(active),
            active && activeIcon != null ? activeIcon : icon,
            size: size,
          ),
        ),
      ),
    ),
  );
}
