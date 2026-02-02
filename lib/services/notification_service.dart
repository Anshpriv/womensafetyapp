import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart'; 
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ✅ Initialize notifications
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
    _initialized = true;
  }

  // ✅ Show overspeed notification
  static Future<void> showOverspeedAlert({
    required double speed,
    required double limit,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'overspeed_channel',
      'Overspeed Alerts',
      channelDescription: 'Notifications for speed violations',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF0000),
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0,
      '⚠️ OVERSPEED ALERT!',
      'Current speed: ${speed.toStringAsFixed(0)} km/h (Limit: ${limit.toStringAsFixed(0)} km/h)',
      details,
    );
  }

  // ✅ Show trip completed notification
  static Future<void> showTripCompleted({
    required double distance,
    required int overspeedCount,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'trip_channel',
      'Trip Notifications',
      channelDescription: 'Notifications for trip events',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      1,
      '🚛 Trip Completed',
      'Distance: ${distance.toStringAsFixed(1)} km | Overspeeds: $overspeedCount',
      details,
    );
  }

  // ✅ Show SOS sent notification
  static Future<void> showSOSSent(int contactsCount) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'sos_channel',
      'SOS Alerts',
      channelDescription: 'Emergency SOS notifications',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF0000),
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      2,
      '🚨 SOS SENT!',
      'Emergency alert sent to $contactsCount contacts',
      details,
    );
  }
}
