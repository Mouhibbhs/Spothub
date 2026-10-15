import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../backup/presentation/library_backup_controls.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personal = ref.watch(personalFlavorProvider);
    final savedKey = personal
        ? ''
        : ref.watch(youtubeApiKeyProvider).value?.trim() ?? '';
    final hasApiKey = savedKey.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 22),
            if (personal) ...[
              const _SectionLabel('PERSONAL BUILD'),
              const _SettingsCard(
                icon: Icons.headphones_rounded,
                title: 'SpotHub Personal',
                body:
                    'Uses YouTube page data for search, playlist imports, and native background audio. It does not read or send a YouTube Data API key. Android app ID: com.spothub.personal.',
                color: AppTheme.accent,
              ),
              const SizedBox(height: 11),
              const _InfoCard(
                title: 'Personal playback',
                body:
                    'Audio plays through the Android media session. Use the notification or lock-screen controls to pause, skip, or resume playback.',
              ),
            ] else ...[
              const _SectionLabel('SEARCH'),
              _SettingsCard(
                icon: hasApiKey
                    ? Icons.check_circle_outline_rounded
                    : Icons.key_rounded,
                title: hasApiKey
                    ? 'YouTube search is connected'
                    : 'Add your YouTube API key',
                body: hasApiKey
                    ? 'SpotHub uses your key to find embeddable music videos.'
                    : 'Enter your own YouTube Data API v3 key below. It is saved on this device and used for your searches.',
                color: hasApiKey ? AppTheme.accent : Colors.orangeAccent,
              ),
              const SizedBox(height: 11),
              const _YouTubeApiKeyEditor(),
              const SizedBox(height: 11),
              const _InfoCard(
                title: 'Create and restrict your key',
                body:
                    'In Google Cloud Console, enable YouTube Data API v3 and create an API key. Restrict it to YouTube Data API v3 and the Android package com.spothub.spothub plus the APK signing certificate SHA-1. Monitor quota usage. The key is stored in this app on this device and is sent to Google when you search.',
              ),
              const SizedBox(height: 23),
              const _SectionLabel('PLAYBACK'),
              const _SettingsCard(
                icon: Icons.ondemand_video_rounded,
                title: 'Official YouTube player',
                body:
                    'Videos play in YouTubeâ€™s embedded player, including its controls and advertising. Background audio and lock-screen playback are not supported.',
                color: AppTheme.accent,
              ),
              const SizedBox(height: 11),
              const _InfoCard(
                title: 'Playback follows YouTube requirements',
                body:
                    'SpotHub does not extract audio or video, bypass ads, or use hidden playback. Android foreground services cannot override YouTube player restrictions.',
              ),
            ],
            const SizedBox(height: 23),
            const _SectionLabel('SPOTIFY'),
            const _SettingsCard(
              icon: Icons.graphic_eq_rounded,
              title: 'Import a Spotify playlist',
              body:
                  'Paste a public Spotify playlist link, match its songs on YouTube, and save them as a SpotHub playlist. No sign-in or Client ID is needed.',
              color: Color(0xFF1ED760),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => context.push('/spotify'),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Import Spotify playlist from link'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1ED760),
                foregroundColor: const Color(0xFF07200F),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 23),
            const _SectionLabel('BACKUP AND RESTORE'),
            const LibraryBackupControls(),
            const SizedBox(height: 23),
            const _SectionLabel('ABOUT SPOTHUB'),
            const _SettingsCard(
              icon: Icons.library_music_rounded,
              title: 'Your music, your collections',
              body:
                  'Playlists, favorites, recent videos, and recent search results are stored on this device.',
              color: AppTheme.accent,
            ),
            const SizedBox(height: 11),
            const _InfoCard(
              title: 'Spotify songs are matched on YouTube',
              body:
                  'SpotHub searches YouTube for each Spotify song and saves the matching videos in your library. YouTube remains SpotHubâ€™s only in-app playback source.',
            ),
            const SizedBox(height: 22),
            const Center(
              child: Text(
                'SpotHub Â· Music discovery',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YouTubeApiKeyEditor extends ConsumerStatefulWidget {
  const _YouTubeApiKeyEditor();

  @override
  ConsumerState<_YouTubeApiKeyEditor> createState() =>
      _YouTubeApiKeyEditorState();
}

class _YouTubeApiKeyEditorState extends ConsumerState<_YouTubeApiKeyEditor> {
  late final TextEditingController _controller;
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    Future<void>(() async {
      try {
        final key = await ref.read(youtubeApiKeyProvider.future);
        if (mounted) setState(() => _controller.text = key);
      } catch (_) {
        // Keep the field available if loading the saved value fails.
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _controller.text.trim();
    if (key.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setString(youtubeApiKeyPreferenceKey, key);
      ref.invalidate(youtubeApiKeyProvider);
      final search = ref.read(searchControllerProvider);
      if (search.query.trim().isNotEmpty &&
          search.message?.contains('API key') == true) {
        unawaited(
          ref.read(searchControllerProvider.notifier).searchNow(search.query),
        );
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube API key saved on this device.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the API key. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(sharedPreferencesProvider)
          .remove(youtubeApiKeyPreferenceKey);
      _controller.clear();
      ref.invalidate(youtubeApiKeyProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('YouTube API key removed.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove the API key. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyState = ref.watch(youtubeApiKeyProvider);
    final hasSavedKey = keyState.value?.trim().isNotEmpty ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveKey(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              letterSpacing: 0.2,
            ),
            decoration: InputDecoration(
              labelText: 'YouTube Data API v3 key',
              hintText: 'Paste your API key',
              filled: true,
              fillColor: AppTheme.elevated,
              labelStyle: const TextStyle(color: AppTheme.secondaryText),
              floatingLabelStyle: const TextStyle(color: AppTheme.accent),
              hintStyle: const TextStyle(color: AppTheme.secondaryText),
              prefixIcon: const Icon(Icons.key_rounded),
              prefixIconColor: AppTheme.secondaryText,
              suffixIconColor: AppTheme.secondaryText,
              suffixIcon: IconButton(
                tooltip: _obscureKey ? 'Show API key' : 'Hide API key',
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppTheme.accent,
                  width: 1.4,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 17,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || _controller.text.trim().isEmpty
                      ? null
                      : _saveKey,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(hasSavedKey ? 'Update key' : 'Save key'),
                ),
              ),
              if (hasSavedKey) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _saving ? null : _removeKey,
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 2),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.secondaryText,
        fontSize: 11,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(
                body,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF141516),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Text(
          body,
          style: const TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}
