import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DownloadNotificationService {
  DownloadNotificationService._();

  static final instance = DownloadNotificationService._();
  static const _notificationId = 4821;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  Future<void> _initialize() async {
    _initializing ??= _plugin
        .initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        )
        .then<void>((_) {});
    await _initializing;
  }

  Future<void> requestPermission() async {
    await _initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> showProgress({
    required String message,
    required int progress,
  }) async {
    await _initialize();
    await _plugin.show(
      id: _notificationId,
      title: 'Saving music for offline use',
      body: message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'spothub_downloads',
          'Downloads',
          channelDescription: 'Progress for offline music downloads',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: progress,
          ongoing: true,
        ),
      ),
    );
  }

  Future<void> showComplete(String message) async {
    await _initialize();
    await _plugin.show(
      id: _notificationId,
      title: 'Downloads ready offline',
      body: message,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'spothub_downloads',
          'Downloads',
          channelDescription: 'Progress for offline music downloads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
        ),
      ),
    );
  }

  Future<void> cancel() async {
    await _initialize();
    await _plugin.cancel(id: _notificationId);
  }
}
