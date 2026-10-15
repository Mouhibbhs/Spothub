import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/track_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _textController;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: ref.read(searchControllerProvider).query,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final personal = ref.watch(personalFlavorProvider);
    final hasApiKey = personal
        ? true
        : ref.watch(youtubeApiKeyProvider).value?.trim().isNotEmpty ?? false;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Search',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  onChanged: ref
                      .read(searchControllerProvider.notifier)
                      .setQuery,
                  onSubmitted: (value) => ref
                      .read(searchControllerProvider.notifier)
                      .searchNow(value),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'What do you want to play?',
                    filled: true,
                    fillColor: AppTheme.elevated,
                    hintStyle: const TextStyle(color: AppTheme.secondaryText),
                    prefixIconColor: AppTheme.secondaryText,
                    prefixIcon: const Icon(Icons.search_rounded, size: 25),
                    suffixIcon: _textController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _textController.clear();
                              ref
                                  .read(searchControllerProvider.notifier)
                                  .setQuery('');
                              _focusNode.requestFocus();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
            ),
            if (search.query.trim().isEmpty) ...[
              if (!hasApiKey)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 0),
                  sliver: SliverToBoxAdapter(child: _ApiKeyNotice()),
                ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Browse categories',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _CategoryCard(
                      category: _categories[index],
                      onTap: () =>
                          _selectCategory(_categories[index].searchTerm),
                    ),
                    childCount: _categories.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 11,
                    crossAxisSpacing: 11,
                    mainAxisExtent: 103,
                  ),
                ),
              ),
            ] else ...[
              if (search.message != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 5),
                  sliver: SliverToBoxAdapter(
                    child: _SearchMessage(
                      message: search.message!,
                      fromCache: search.fromCache,
                      hasApiKey: hasApiKey,
                    ),
                  ),
                ),
              if (search.isLoading && search.tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  ),
                )
              else if (search.tracks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoResults(
                    hasMessage: search.message != null,
                    personal: personal,
                    onRetry: () => ref
                        .read(searchControllerProvider.notifier)
                        .searchNow(search.query),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 7),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            search.fromCache
                                ? 'Saved results'
                                : 'Songs and videos',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (search.isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 30),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => TrackTile(
                        track: search.tracks[index],
                        radioQuery: search.query,
                      ),
                      childCount: search.tracks.length,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _selectCategory(String term) {
    _textController.text = term;
    _textController.selection = TextSelection.collapsed(offset: term.length);
    ref.read(searchControllerProvider.notifier).searchNow(term);
    setState(() {});
  }
}

class _ApiKeyNotice extends StatelessWidget {
  const _ApiKeyNotice();

  @override
  Widget build(BuildContext context) => _NoticeCard(
    icon: Icons.key_rounded,
    title: 'Connect YouTube search',
    message:
        'Add your own YouTube Data API v3 key in Settings to search live videos.',
    action: 'Setup',
    onTap: () => context.go('/settings'),
  );
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.message,
    required this.fromCache,
    required this.hasApiKey,
  });
  final String message;
  final bool fromCache;
  final bool hasApiKey;

  @override
  Widget build(BuildContext context) => _NoticeCard(
    icon: fromCache ? Icons.history_rounded : Icons.info_outline_rounded,
    title: fromCache ? 'Saved results' : 'Search status',
    message: message,
    action: hasApiKey ? null : 'Setup',
    onTap: hasApiKey ? null : () => context.go('/settings'),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.accent, size: 19),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(action!),
          ),
      ],
    ),
  );
}

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.hasMessage,
    required this.personal,
    required this.onRetry,
  });
  final bool hasMessage;
  final bool personal;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasMessage ? Icons.search_off_rounded : Icons.music_note_rounded,
            color: AppTheme.secondaryText,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            hasMessage ? 'Search isnâ€™t available yet' : 'No videos found',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            hasMessage
                ? personal
                      ? 'Review the status above or check your connection.'
                      : 'Review the search status above or check your API key and connection.'
                : 'Try another title, artist, or channel.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (hasMessage) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

class _Genre {
  const _Genre(this.title, this.searchTerm, this.color, this.icon);
  final String title;
  final String searchTerm;
  final Color color;
  final IconData icon;
}

const _categories = [
  _Genre('Pop', 'pop music', Color(0xFF8B3D95), Icons.mic_rounded),
  _Genre(
    'Hip-hop',
    'hip-hop music',
    Color(0xFFB65A27),
    Icons.graphic_eq_rounded,
  ),
  _Genre('Rock', 'rock music', Color(0xFF315D9B), Icons.music_note_rounded),
  _Genre('Latin', 'latin music', Color(0xFFB54848), Icons.wb_sunny_rounded),
  _Genre(
    'Electronic',
    'electronic music',
    Color(0xFF3F7281),
    Icons.album_rounded,
  ),
  _Genre('Indie', 'indie music', Color(0xFF60853E), Icons.headphones_rounded),
  _Genre('Jazz', 'jazz music', Color(0xFF82632E), Icons.piano_rounded),
  _Genre('Focus', 'focus music', Color(0xFF365E57), Icons.spa_rounded),
];

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});
  final _Genre category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: category.color,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            right: -12,
            bottom: -16,
            child: Transform.rotate(
              angle: -0.22,
              child: Icon(
                category.icon,
                size: 78,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 13,
            child: Text(
              category.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
