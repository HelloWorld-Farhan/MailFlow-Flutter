import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(settings: initSettings);
    _isInitialized = true;
  }

  /// Sends a local notification with system default sound & vibration
  static Future<void> showUpdateNotification({
    required String newVersion,
    String? body,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'mailflow_updates',
      'Software Updates',
      channelDescription: 'Notifications for new MailFlow versions and updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: 1001,
      title: '🎉 MailFlow Update Available (v$newVersion)',
      body: body ?? 'A new update is ready! Tap to download and install.',
      notificationDetails: notificationDetails,
    );
  }
}
