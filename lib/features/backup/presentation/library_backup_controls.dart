import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../data/library_backup_service.dart';

class LibraryBackupControls extends ConsumerStatefulWidget {
  const LibraryBackupControls({super.key});

  @override
  ConsumerState<LibraryBackupControls> createState() =>
      _LibraryBackupControlsState();
}

class _LibraryBackupControlsState extends ConsumerState<LibraryBackupControls> {
  bool _busy = false;

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final content = await LibraryBackupService(
        ref.read(databaseProvider),
      ).exportJson();
      final now = DateTime.now();
      final fileName =
          'spothub-backup-${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}.json';
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
        dialogTitle: 'Save SpotHub backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (!mounted || saved == null) return;
      _showMessage(
        'Backup saved. Keep the file somewhere safe to restore it later.',
      );
    } catch (error) {
      if (mounted) _showMessage('Backup export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a SpotHub backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size == null || size == 0 || size > 50 * 1024 * 1024) {
        throw const FormatException(
          'Choose a non-empty SpotHub backup smaller than 50 MB.',
        );
      }
      final contents = utf8.decode(await file.readAsBytes());
      final result = await LibraryBackupService(
        ref.read(databaseProvider),
      ).restoreJson(contents);
      ref.invalidate(playlistsProvider);
      ref.invalidate(favoritesProvider);
      ref.invalidate(recentlyPlayedProvider);
      if (!mounted) return;
      final details = result.playlistsAlreadyPresent > 0
          ? ' ${result.playlistsAlreadyPresent} already restored.'
          : '';
      _showMessage(
        'Restored ${result.playlistsAdded} playlists, '
        '${result.favoritesRestored} liked tracks, and '
        '${result.recentTracksRestored} recent tracks.$details',
      );
    } catch (error) {
      if (mounted) _showMessage('Backup restore failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Keep a copy of your library',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        const Text(
          'Back up playlists, liked tracks, and listening history to a file. Restore that file after reinstalling SpotHub.',
          style: TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _exportBackup,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Export backup'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restoreBackup,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restore backup'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
