import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/spot_database.dart';
import '../features/player/application/playback_controller.dart';
import '../features/player/data/personal_youtube_audio_handler.dart';
import 'providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class SpotHubApp extends StatelessWidget {
  const SpotHubApp({
    required this.database,
    this.personal = false,
    this.personalAudioHandler,
    super.key,
  });
  final SpotDatabase database;
  final bool personal;
  final PersonalYouTubeAudioHandler? personalAudioHandler;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      personalFlavorProvider.overrideWithValue(personal),
      if (personalAudioHandler != null)
        personalAudioHandlerProvider.overrideWithValue(personalAudioHandler!),
    ],
    child: MaterialApp.router(
      title: 'SpotHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
    ),
  );
}

class StartupErrorApp extends StatefulWidget {
  const StartupErrorApp({
    required this.error,
    this.personal = false,
    this.personalAudioHandler,
    super.key,
  });
  final Object error;
  final bool personal;
  final PersonalYouTubeAudioHandler? personalAudioHandler;

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _retrying = false;
  String? _error;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      final database = await SpotDatabase.open();
      runApp(
        SpotHubApp(
          database: database,
          personal: widget.personal,
          personalAudioHandler: widget.personalAudioHandler,
        ),
      );
    } catch (error) {
      setState(() {
        _retrying = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.storage_rounded,
                color: AppTheme.accent,
                size: 45,
              ),
              const SizedBox(height: 16),
              const Text(
                'SpotHub could not open its library',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? widget.error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _retrying ? null : _retry,
                child: _retrying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
