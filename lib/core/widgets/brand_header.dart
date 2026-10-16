import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    required this.title,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 8, 8),
    child: SizedBox(
      height: 46,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'final-icon.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              semanticLabel: 'SpotHub',
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.25,
                color: AppTheme.primaryText,
              ),
            ),
          ),
          for (final action in actions) action,
        ],
      ),
    ),
  );
}
