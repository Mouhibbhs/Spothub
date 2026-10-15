import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../search/data/youtube_search_repository.dart';
import '../../search/domain/track.dart';
import '../data/spotify_playlist_importer.dart';

class SpotifyPlaylistsScreen extends ConsumerStatefulWidget {
  const SpotifyPlaylistsScreen({super.key});

  @override
  ConsumerState<SpotifyPlaylistsScreen> createState() =>
      _SpotifyPlaylistsScreenState();
}

class _SpotifyPlaylistsScreenState
    extends ConsumerState<SpotifyPlaylistsScreen> {
  static const _matchConcurrency = 2;
  static const _searchStartInterval = Duration(milliseconds: 850);
  static const _rateLimitCooldown = Duration(seconds: 20);

  Future<void> _searchStartQueue = Future<void>.value();
  DateTime _nextSearchStartAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _searchPauseUntil = DateTime.fromMillisecondsSinceEpoch(0);

  late final TextEditingController _linkController;
  SpotifyPlaylistImport? _imported;
  String? _error;
  String? _searchStatus;
  bool _loading = false;
  bool _resolvingTracks = false;
  int _resolvedCount = 0;
  int? _savedPlaylistId;
  final Map<SpotifyPlaylistItem, Track> _resolvedTracks = {};
  List<SpotifyPlaylistItem> _unmatchedItems = [];

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _importFromLink() async {
    if (_loading || _resolvingTracks) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _imported = null;
      _savedPlaylistId = null;
    });
    try {
      final imported = await ref
          .read(spotifyPlaylistImporterProvider)
          .importPlaylist(_linkController.text);
      if (!mounted) return;
      setState(() {
        _imported = imported;
        _resolvedTracks.clear();
        _unmatchedItems = imported.items;
      });
      setState(() => _loading = false);
      await _addToYourPlaylists();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToYourPlaylists() async {
    final imported = _imported;
    if (imported == null ||
        _resolvingTracks ||
        (_savedPlaylistId != null && _unmatchedItems.isEmpty)) {
      return;
    }
    if (imported.items.length > 500) {
      setState(() {
        _error = 'A playlist can contain up to 500 tracks in SpotHub.';
      });
      return;
    }

    setState(() {
      _resolvingTracks = true;
      _resolvedCount = _resolvedTracks.length;
      _error = null;
    });
    try {
      final pendingItems = _unmatchedItems.isEmpty
          ? imported.items
          : List<SpotifyPlaylistItem>.of(_unmatchedItems);
      final batch = await _findYouTubeTracks(
        pendingItems,
        progressOffset: _resolvedTracks.length,
      );
      _resolvedTracks.addAll(batch.matches);
      final orderedTracks = <Track>[];
      final seenVideoIds = <String>{};
      for (final item in imported.items) {
        final track = _resolvedTracks[item];
        if (track != null && seenVideoIds.add(track.videoId)) {
          orderedTracks.add(track);
        }
      }
      final uniqueTracks = orderedTracks;
      if (uniqueTracks.isEmpty) {
        throw SearchException(
          batch.issue ??
              'No matching YouTube videos were found. Check your connection and try again.',
        );
      }

      final playlistName = _playlistName(imported.playlist.name);
      final repository = ref.read(playlistRepositoryProvider);
      final existingPlaylists = await repository.getAll();
      var targetPlaylistId = _savedPlaylistId;
      var previousTracks = <Track>[];
      if (targetPlaylistId != null) {
        previousTracks = await repository.getTracks(targetPlaylistId);
      } else {
        final incomingIds = uniqueTracks.map((track) => track.videoId).toSet();
        for (final existing in existingPlaylists) {
          if (existing.name != playlistName) continue;
          final existingTracks = await repository.getTracks(existing.id);
          if (existingTracks.every(
            (track) => incomingIds.contains(track.videoId),
          )) {
            targetPlaylistId = existing.id;
            previousTracks = existingTracks;
            break;
          }
        }
      }

      final previousIds = previousTracks.map((track) => track.videoId).toSet();
      final newlyAdded = uniqueTracks
          .where((track) => !previousIds.contains(track.videoId))
          .length;
      final id =
          targetPlaylistId ??
          await repository.createWithTracks(playlistName, uniqueTracks);
      if (targetPlaylistId != null) {
        await repository.mergeTracksInSourceOrder(id, uniqueTracks);
      }
      if (!mounted) return;
      ref.invalidate(playlistsProvider);
      _unmatchedItems = batch.unmatchedItems;
      setState(() => _savedPlaylistId = id);
      final messageParts = <String>[
        newlyAdded == 0
            ? 'This playlist is up to date in Your Playlists.'
            : 'Added $newlyAdded tracks to Your Playlists.',
      ];
      final repeatedMatches = _resolvedTracks.length - uniqueTracks.length;
      if (repeatedMatches > 0) {
        messageParts.add(
          '$repeatedMatches Spotify entries matched videos already used in this playlist.',
        );
      }
      if (_unmatchedItems.isNotEmpty) {
        messageParts.add(
          '${_unmatchedItems.length} Spotify tracks still need a YouTube match. You can retry them here.',
        );
        if (batch.issue != null) messageParts.add(batch.issue!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messageParts.join(' ')),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () => context.push('/playlist/$id'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _resolvingTracks = false;
          _searchStatus = null;
        });
      }
    }
  }

  Future<_YouTubeMatchBatch> _findYouTubeTracks(
    List<SpotifyPlaylistItem> items, {
    required int progressOffset,
  }) async {
    final matches = List<Track?>.filled(items.length, null);
    final queryCache = <String, Future<SearchOutcome>>{};
    Object? firstSearchError;
    String? fatalSearchIssue;
    final usedVideoIds = _resolvedTracks.values
        .map((track) => track.videoId)
        .toSet();
    final matchesBySpotifyUrl = <String, Track>{
      for (final entry in _resolvedTracks.entries)
        _spotifyTrackKey(entry.key): entry.value,
    };
    var nextIndex = 0;
    var completed = 0;

    Future<Track?> resolveItem(SpotifyPlaylistItem item) async {
      final itemKey = _spotifyTrackKey(item);
      final existingMatch = matchesBySpotifyUrl[itemKey];
      if (existingMatch != null) return existingMatch;
      final title = item.title.trim();
      final artist = item.artistNames.trim();
      final queries = <String>{
        '$title $artist official audio'.trim(),
        '$title $artist'.trim(),
        '$title official audio'.trim(),
      }.where((query) => query.isNotEmpty);
      for (final query in queries) {
        final cacheKey = query.toLowerCase();
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            final outcome = await queryCache.putIfAbsent(
              cacheKey,
              () => _searchYouTubePaced(query),
            );
            final concurrentMatch = matchesBySpotifyUrl[itemKey];
            if (concurrentMatch != null) return concurrentMatch;
            if (outcome.tracks.isNotEmpty) {
              final fresh = outcome.tracks.where(
                (track) => !usedVideoIds.contains(track.videoId),
              );
              if (fresh.isNotEmpty) {
                final track = fresh.first;
                usedVideoIds.add(track.videoId);
                matchesBySpotifyUrl[itemKey] = track;
                return track;
              }
              break;
            }
            if (_isQuotaIssue(outcome.message)) {
              fatalSearchIssue = outcome.message;
              return null;
            }
            break;
          } catch (error) {
            firstSearchError ??= error;
            if (_isRateLimitIssue(error.toString())) {
              queryCache.remove(cacheKey);
              if (fatalSearchIssue != null) return null;
              if (attempt == 0) continue;
              fatalSearchIssue =
                  'YouTube temporarily limited playlist searches. Matches found so far were saved; wait a little, then retry the remaining tracks.';
              return null;
            }
            if (_isQuotaIssue(error.toString())) {
              fatalSearchIssue =
                  'YouTube rejected the search request. Check your connection or API settings, then retry the remaining tracks.';
              return null;
            }
            queryCache.remove(cacheKey);
            if (attempt == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 650));
            }
          }
        }
        if (fatalSearchIssue != null) return null;
      }
      return null;
    }

    Future<void> worker() async {
      while (true) {
        if (fatalSearchIssue != null) return;
        final index = nextIndex++;
        if (index >= items.length) return;
        final item = items[index];
        matches[index] = await resolveItem(item);
        completed++;
        if (mounted) {
          setState(() => _resolvedCount = progressOffset + completed);
        }
      }
    }

    await Future.wait(List.generate(_matchConcurrency, (_) => worker()));
    final found = <SpotifyPlaylistItem, Track>{};
    final unmatched = <SpotifyPlaylistItem>[];
    for (var index = 0; index < items.length; index++) {
      final track = matches[index];
      if (track == null) {
        unmatched.add(items[index]);
      } else {
        found[items[index]] = track;
      }
    }
    if (found.isEmpty && firstSearchError != null) {
      throw SearchException(fatalSearchIssue ?? firstSearchError.toString());
    }
    if (fatalSearchIssue != null && firstSearchError == null) {
      firstSearchError = fatalSearchIssue;
    }
    final issue =
        fatalSearchIssue ??
        (unmatched.isNotEmpty && firstSearchError != null
            ? 'Some YouTube searches failed. Check the connection or API quota, then retry.'
            : null);
    return _YouTubeMatchBatch(
      matches: found,
      unmatchedItems: unmatched,
      issue: issue,
    );
  }

  bool _isQuotaIssue(String? message) {
    final normalized = message?.toLowerCase() ?? '';
    return normalized.contains('quota') ||
        normalized.contains('daily limit') ||
        normalized.contains('api key is invalid') ||
        normalized.contains('youtube denied');
  }

  bool _isRateLimitIssue(String? message) {
    final normalized = message?.toLowerCase() ?? '';
    return normalized.contains('429') ||
        normalized.contains('rate limit') ||
        normalized.contains('too many requests') ||
        normalized.contains('suspicious');
  }

  String _spotifyTrackKey(SpotifyPlaylistItem item) {
    final segments = Uri.tryParse(item.spotifyUrl)?.pathSegments ?? const [];
    final trackSegment = segments.indexOf('track');
    if (trackSegment >= 0 && trackSegment + 1 < segments.length) {
      return 'id:${segments[trackSegment + 1]}';
    }
    return '${item.title.trim().toLowerCase()}|${item.artistNames.trim().toLowerCase()}';
  }

  Future<SearchOutcome> _searchYouTubePaced(String query) async {
    if (ref.read(personalFlavorProvider)) {
      final cached = await ref
          .read(trackRepositoryProvider)
          .readCachedSearch(query);
      if (cached != null) {
        return SearchOutcome(tracks: cached, fromCache: true);
      }
    }

    await _waitForSearchSlot();
    try {
      final outcome = await _searchYouTube(query);
      if (mounted && _searchStatus != null) {
        setState(() => _searchStatus = null);
      }
      return outcome;
    } catch (error) {
      if (_isRateLimitIssue(error.toString())) {
        final retryAt = DateTime.now().add(_rateLimitCooldown);
        if (retryAt.isAfter(_searchPauseUntil)) {
          _searchPauseUntil = retryAt;
        }
        if (mounted) {
          setState(
            () => _searchStatus = 'YouTube is slowing searches; waiting…',
          );
        }
      }
      rethrow;
    }
  }

  Future<void> _waitForSearchSlot() async {
    final previous = _searchStartQueue;
    final release = Completer<void>();
    _searchStartQueue = release.future;
    await previous;
    try {
      while (true) {
        final now = DateTime.now();
        var startAt = _nextSearchStartAt;
        if (_searchPauseUntil.isAfter(startAt)) {
          startAt = _searchPauseUntil;
        }
        if (startAt.isAfter(now)) {
          await Future<void>.delayed(startAt.difference(now));
        }

        final start = DateTime.now();
        if (_searchPauseUntil.isAfter(start) ||
            _nextSearchStartAt.isAfter(start)) {
          continue;
        }
        _nextSearchStartAt = start.add(_searchStartInterval);
        return;
      }
    } finally {
      release.complete();
    }
  }

  Future<SearchOutcome> _searchYouTube(String query) {
    if (ref.read(personalFlavorProvider)) {
      return ref.read(personalYouTubeCatalogProvider).search(query);
    }
    return ref.read(youtubeSearchRepositoryProvider).search(query);
  }

  String _playlistName(String name) {
    final runes = name.trim().runes;
    return String.fromCharCodes(runes.take(50));
  }

  Future<void> _openSpotify(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Spotify on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Spotify playlists'),
      leading: const BackButton(),
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          const _SpotifyAttributionHeader(),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Import a Spotify playlist',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                Text(
                  'Paste a public Spotify playlist link. SpotHub finds YouTube matches and adds them to Your Playlists automatically.',
                  style: TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _linkController,
                  enabled: !_resolvingTracks,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _importFromLink(),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.elevated,
                    prefixIcon: const Icon(Icons.link_rounded),
                    prefixIconColor: AppTheme.secondaryText,
                    labelText: 'Playlist link',
                    hintText: 'open.spotify.com/playlist/…',
                    hintStyle: const TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 12,
                    ),
                    labelStyle: const TextStyle(color: AppTheme.secondaryText),
                    floatingLabelStyle: const TextStyle(
                      color: Color(0xFF1ED760),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(
                        color: Color(0xFF1ED760),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading || _resolvingTracks
                      ? null
                      : _importFromLink,
                  icon: _loading || _resolvingTracks
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_rounded, size: 19),
                  label: Text(
                    _loading
                        ? 'Loading playlist…'
                        : _resolvingTracks
                        ? 'Matching songs on YouTube…'
                        : 'Load playlist',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1ED760),
                    foregroundColor: const Color(0xFF07200F),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _StatusCard(message: _error!, isError: true),
          ],
          if (_imported case final imported?) ...[
            const SizedBox(height: 22),
            _playlistHeader(imported.playlist),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _resolvingTracks ||
                      (_savedPlaylistId != null && _unmatchedItems.isEmpty)
                  ? null
                  : _addToYourPlaylists,
              icon: _resolvingTracks
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _savedPlaylistId == null
                          ? Icons.library_add_rounded
                          : _unmatchedItems.isEmpty
                          ? Icons.check_circle_rounded
                          : Icons.refresh_rounded,
                      size: 19,
                    ),
              label: Text(
                _savedPlaylistId != null &&
                        !_resolvingTracks &&
                        _unmatchedItems.isEmpty
                    ? 'Added to Your Playlists'
                    : _savedPlaylistId != null && !_resolvingTracks
                    ? 'Retry ${_unmatchedItems.length} unmatched tracks'
                    : _resolvingTracks
                    ? '${_searchStatus ?? 'Finding YouTube songs'} ($_resolvedCount/${imported.items.length})…'
                    : 'Add to Your Playlists',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1ED760),
                foregroundColor: const Color(0xFF07200F),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            ...imported.items.asMap().entries.map((entry) {
              final item = entry.value;
              final hasMatch = _resolvedTracks.containsKey(item);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(
                    0xFF1ED760,
                  ).withValues(alpha: 0.12),
                  child: Text(
                    '${entry.key + 1}',
                    style: const TextStyle(
                      color: Color(0xFF1ED760),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  item.artistNames.isEmpty
                      ? 'Spotify'
                      : '${item.artistNames} · Spotify',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_savedPlaylistId != null)
                      Tooltip(
                        message: hasMatch
                            ? 'YouTube match found'
                            : 'No YouTube match yet',
                        child: Icon(
                          hasMatch
                              ? Icons.check_circle_rounded
                              : Icons.search_off_rounded,
                          color: hasMatch
                              ? AppTheme.accent
                              : AppTheme.secondaryText,
                          size: 18,
                        ),
                      ),
                    if (item.duration.isNotEmpty)
                      Text(
                        item.duration,
                        style: const TextStyle(
                          color: AppTheme.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Open in Spotify',
                      onPressed: () => _openSpotify(item.spotifyUrl),
                      icon: const Icon(
                        Icons.open_in_new_rounded,
                        color: Color(0xFF1ED760),
                      ),
                    ),
                  ],
                ),
                onTap: () => _openSpotify(item.spotifyUrl),
              );
            }),
          ],
        ],
      ),
    ),
  );

  Widget _playlistHeader(SpotifyPlaylist playlist) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        if (playlist.imageUrl case final imageUrl?)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const _SpotifyMark(),
            ),
          )
        else
          const _SpotifyMark(),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playlist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${playlist.itemCount} tracks · Spotify',
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open playlist in Spotify',
          onPressed: () => _openSpotify(playlist.spotifyUrl),
          icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF1ED760)),
        ),
      ],
    ),
  );
}

class _YouTubeMatchBatch {
  const _YouTubeMatchBatch({
    required this.matches,
    required this.unmatchedItems,
    this.issue,
  });

  final Map<SpotifyPlaylistItem, Track> matches;
  final List<SpotifyPlaylistItem> unmatchedItems;
  final String? issue;
}

class _SpotifyAttributionHeader extends StatelessWidget {
  const _SpotifyAttributionHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.graphic_eq_rounded, color: Color(0xFF1ED760), size: 24),
      SizedBox(width: 8),
      Text(
        'Spotify',
        style: TextStyle(
          color: Color(0xFF1ED760),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(width: 7),
      Text(
        'playlist importer',
        style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
      ),
    ],
  );
}

class _SpotifyMark extends StatelessWidget {
  const _SpotifyMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 60,
    height: 60,
    decoration: BoxDecoration(
      color: const Color(0xFF1ED760).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(
      Icons.graphic_eq_rounded,
      color: Color(0xFF1ED760),
      size: 30,
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: (isError ? Colors.redAccent : Colors.white).withValues(
          alpha: 0.12,
        ),
      ),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: isError ? Colors.redAccent.shade100 : AppTheme.secondaryText,
        fontSize: 13,
        height: 1.4,
      ),
    ),
  );
}
