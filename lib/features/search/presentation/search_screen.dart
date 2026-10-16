import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/music_motion.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _textController;
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: ref.read(searchControllerProvider).query,
    );
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final personal = ref.watch(personalFlavorProvider);
    final hasApiKey = personal
        ? true
        : ref.watch(youtubeApiKeyProvider).value?.trim().isNotEmpty ?? false;

    if (_textController.text != search.query) {
      _textController.value = TextEditingValue(
        text: search.query,
        selection: TextSelection.collapsed(offset: search.query.length),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: BrandHeader(
                title: 'Search',
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
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Search',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 13),
                    AnimatedContainer(
                      duration: MusicMotion.selection,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: _isFocused
                            ? AppTheme.pressedSurface
                            : AppTheme.elevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isFocused
                              ? AppTheme.accent.withValues(alpha: 0.82)
                              : Colors.transparent,
                          width: 1.1,
                        ),
                      ),
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
                          color: AppTheme.primaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'What do you want to play?',
                          filled: false,
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 23,
                          ),
                          suffixIcon: _textController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SearchPresets(
                      selectedQuery: search.query,
                      onSelected: _selectPreset,
                    ),
                    const SizedBox(height: 18),
                    AnimatedSize(
                      duration: MusicMotion.track,
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: MusicMotion.track,
                        reverseDuration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) =>
                            coordinatedSwitchTransition(
                              child,
                              animation,
                              begin: const Offset(0, 0.035),
                            ),
                        child: search.query.trim().isEmpty
                            ? _BrowseSearch(
                                key: const ValueKey('browse-search'),
                                recent: recent,
                                hasApiKey: hasApiKey,
                                onCategorySelected: _selectCategory,
                              )
                            : _SearchResults(
                                key: ValueKey('search-${search.query}'),
                                state: search,
                                personal: personal,
                                hasApiKey: hasApiKey,
                                onRetry: () => ref
                                    .read(searchControllerProvider.notifier)
                                    .searchNow(search.query),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearSearch() {
    _textController.clear();
    ref.read(searchControllerProvider.notifier).setQuery('');
    _focusNode.requestFocus();
    setState(() {});
  }

  void _selectPreset(String query) {
    _focusNode.unfocus();
    _textController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    if (query.isEmpty) {
      ref.read(searchControllerProvider.notifier).setQuery('');
    } else {
      ref.read(searchControllerProvider.notifier).searchNow(query);
    }
  }

  void _selectCategory(String term) {
    _textController.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    _focusNode.unfocus();
    ref.read(searchControllerProvider.notifier).searchNow(term);
  }
}

class _SearchPresets extends StatelessWidget {
  const _SearchPresets({required this.selectedQuery, required this.onSelected});

  final String selectedQuery;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const presets = <(String, String)>[
      ('All', ''),
      ('Music', 'music'),
      ('Podcasts', 'podcast'),
      ('Live events', 'live music'),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PressScale(
                child: ChoiceChip(
                  label: Text(preset.$1),
                  selected: selectedQuery.trim().toLowerCase() == preset.$2,
                  onSelected: (_) => onSelected(preset.$2),
                  showCheckmark: false,
                  backgroundColor: AppTheme.elevated,
                  selectedColor: AppTheme.accent,
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    color: selectedQuery.trim().toLowerCase() == preset.$2
                        ? const Color(0xFF001F0B)
                        : AppTheme.primaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrowseSearch extends StatelessWidget {
  const _BrowseSearch({
    required this.recent,
    required this.hasApiKey,
    required this.onCategorySelected,
    super.key,
  });

  final AsyncValue<List<dynamic>> recent;
  final bool hasApiKey;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!hasApiKey) ...[_ApiKeyNotice(), const SizedBox(height: 18)],
      recent.when(
        loading: () => const SizedBox.shrink(),
        error: (error, stack) => const SizedBox.shrink(),
        data: (items) => items.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader('Recently played'),
                  for (final track in items.take(2))
                    TrackTile(track: track, compact: true),
                  const SizedBox(height: 10),
                ],
              ),
      ),
      const SectionHeader('Explore your genres'),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 96,
        ),
        itemBuilder: (context, index) => _CategoryCard(
          key: ValueKey(_categories[index].title),
          category: _categories[index],
          onTap: () => onCategorySelected(_categories[index].searchTerm),
        ),
      ),
    ],
  );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.state,
    required this.personal,
    required this.hasApiKey,
    required this.onRetry,
    super.key,
  });

  final SearchState state;
  final bool personal;
  final bool hasApiKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.tracks.isEmpty) {
      return const SizedBox(
        key: ValueKey('search-loading'),
        height: 180,
        child: Center(
          child: SizedBox.square(
            dimension: 27,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.accent,
            ),
          ),
        ),
      );
    }
    if (state.tracks.isEmpty) {
      return _NoResults(
        key: const ValueKey('search-empty'),
        hasMessage: state.message != null,
        personal: personal,
        onRetry: onRetry,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.message != null) ...[
          _SearchMessage(
            message: state.message!,
            fromCache: state.fromCache,
            hasApiKey: hasApiKey,
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                state.fromCache ? 'Saved results' : 'Songs and videos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (state.isLoading)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accent,
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        for (final track in state.tracks)
          TrackTile(
            key: ValueKey(track.videoId),
            track: track,
            radioQuery: state.query,
          ),
      ],
    );
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
      borderRadius: BorderRadius.circular(8),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
    super.key,
  });

  final bool hasMessage;
  final bool personal;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 30, 22, 42),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hasMessage ? Icons.search_off_rounded : Icons.music_note_rounded,
          color: AppTheme.secondaryText,
          size: 34,
        ),
        const SizedBox(height: 12),
        Text(
          hasMessage ? 'Search is unavailable' : 'No videos found',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          hasMessage
              ? personal
                    ? 'Review the status above or check your connection.'
                    : 'Review the status above or check your API key and connection.'
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
  );
}

class _Genre {
  const _Genre(this.title, this.searchTerm, this.icon);
  final String title;
  final String searchTerm;
  final IconData icon;
}

const _categories = [
  _Genre('Hip-hop', 'hip-hop music', Icons.graphic_eq_rounded),
  _Genre('Rap', 'rap music', Icons.mic_rounded),
  _Genre('Pop', 'pop music', Icons.music_note_rounded),
  _Genre('Electronic', 'electronic music', Icons.album_rounded),
  _Genre('Rock', 'rock music', Icons.queue_music_rounded),
  _Genre('Chill', 'chill music', Icons.spa_rounded),
  _Genre('Gaming', 'gaming music', Icons.headphones_rounded),
  _Genre('Discover', 'new music', Icons.graphic_eq_rounded),
];

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap, super.key});

  final _Genre category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppTheme.elevated,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -5,
              bottom: -17,
              child: Transform.rotate(
                angle: -0.2,
                child: Icon(
                  category.icon,
                  size: 82,
                  color: AppTheme.accent.withValues(alpha: 0.2),
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 13,
              child: Text(
                category.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
