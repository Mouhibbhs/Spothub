import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    required this.url,
    this.size = 52,
    this.expand = false,
    this.radius = 6,
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF194A3A), Color(0xFF18251F)],
            ),
          ),
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
            errorBuilder: (context, error, stackTrace) => const SizedBox(),
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              final loaded = frame != null || wasSynchronouslyLoaded;
              return AnimatedOpacity(
                opacity: loaded ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: AnimatedScale(
                  scale: loaded ? 1 : 1.06,
                  duration: const Duration(milliseconds: 420),
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
