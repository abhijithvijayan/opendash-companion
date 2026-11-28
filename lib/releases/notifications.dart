import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'updates';
const _channelName = 'Updates';

final _plugin = FlutterLocalNotificationsPlugin();

/// Sets up the plugin and the single Android channel. Safe to call from the
/// background isolate too.
Future<void> initNotifications() async {
  await _plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'New S1 Dash and Companion releases',
          importance: Importance.defaultImportance,
        ),
      );
}

/// Android 13+ POST_NOTIFICATIONS prompt. A denial just means no notices.
Future<void> requestNotificationPermission() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<void> showUpdateNotification(String title, String body) {
  return _plugin.show(
    id: title.hashCode & 0x7fffffff,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(_channelId, _channelName, importance: Importance.defaultImportance),
    ),
  );
}
