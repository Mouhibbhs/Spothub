import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    required this.url,
    this.size = 52,
    this.expand = false,
    this.radius = 4,
    this.imageBytes,
    this.icon = Icons.music_note_rounded,
    super.key,
  });

  final String? url;
  final double size;
  final bool expand;
  final double radius;
  final Uint8List? imageBytes;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? imageProvider =
        imageBytes != null && imageBytes!.isNotEmpty
        ? MemoryImage(imageBytes!)
        : url != null && url!.startsWith('https://')
        ? NetworkImage(url!)
        : null;
    final image = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(color: AppTheme.elevated),
          child: Icon(
            icon,
            color: AppTheme.accent,
            size: expand ? 48 : size * 0.42,
          ),
        ),
        if (imageProvider != null)
          Image(
            image: imageProvider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => const SizedBox(),
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              final loaded = frame != null || wasSynchronouslyLoaded;
              return AnimatedOpacity(
                opacity: loaded ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: AnimatedScale(
                  scale: loaded ? 1 : 1.035,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: child,
                ),
              );
            },
          ),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: expand
          ? SizedBox.expand(child: image)
          : SizedBox.square(dimension: size, child: image),
    );
  }
}
