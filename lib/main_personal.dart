import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/database/spot_database.dart';
import 'features/player/data/personal_youtube_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PersonalYouTubeAudioHandler? personalAudioHandler;
  try {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
    final audioHandler = await AudioService.init(
      builder: PersonalYouTubeAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.spothub.personal.audio',
        androidNotificationChannelName: 'SpotHub Personal playback',
        androidNotificationOngoing: true,
      ),
    );
    personalAudioHandler = audioHandler;
    final database = await SpotDatabase.open();
    runApp(
      SpotHubApp(
        database: database,
        personal: true,
        personalAudioHandler: personalAudioHandler,
      ),
    );
  } catch (error) {
    runApp(
      StartupErrorApp(
        error: error,
        personal: true,
        personalAudioHandler: personalAudioHandler,
      ),
    );
  }
}
