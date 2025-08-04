import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/constants.dart';

class NotificationManager {
  late final FlutterLocalNotificationsPlugin _localNotifications;
  late final FirebaseMessaging _firebaseMessaging;
  
  bool _isInitialized = false;

  NotificationManager() {
    _localNotifications = FlutterLocalNotificationsPlugin();
    _firebaseMessaging = FirebaseMessaging.instance;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels (Android)
    await _createNotificationChannels();

    // Initialize Firebase messaging
    await _initializeFirebaseMessaging();

    _isInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    // Default channel
    const defaultChannel = AndroidNotificationChannel(
      NotificationChannels.defaultChannel,
      'PyAirtable Default',
      description: 'Default notifications from PyAirtable',
      importance: Importance.defaultImportance,
    );

    // Sync channel
    const syncChannel = AndroidNotificationChannel(
      NotificationChannels.sync,
      'PyAirtable Sync',
      description: 'Data synchronization notifications',
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    );

    // Updates channel
    const updatesChannel = AndroidNotificationChannel(
      NotificationChannels.updates,
      'PyAirtable Updates',
      description: 'Real-time data update notifications',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(defaultChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(syncChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(updatesChannel);
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      // Request permission
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted permission for notifications');
      } else {
        print('User declined or has not accepted permission for notifications');
      }

      // Get FCM token
      final token = await _firebaseMessaging.getToken();
      print('FCM Token: $token');

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Received a message while in the foreground!');
        
        if (message.notification != null) {
          _showLocalNotification(
            message.notification!.title ?? 'PyAirtable',
            message.notification!.body ?? '',
            data: message.data,
          );
        }
      });

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('A new onMessageOpenedApp event was published!');
        _handleNotificationTap(message.data);
      });
    } catch (error) {
      print('Failed to initialize Firebase messaging: $error');
    }
  }

  Future<void> showNotification(
    String title,
    String body, {
    Map<String, dynamic>? data,
    String? channelId,
  }) async {
    if (!_isInitialized) {
      throw Exception('NotificationManager not initialized');
    }

    await _showLocalNotification(title, body, data: data, channelId: channelId);
  }

  Future<void> _showLocalNotification(
    String title,
    String body, {
    Map<String, dynamic>? data,
    String? channelId,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId ?? NotificationChannels.defaultChannel,
      channelId == NotificationChannels.sync ? 'PyAirtable Sync' :
      channelId == NotificationChannels.updates ? 'PyAirtable Updates' :
      'PyAirtable Default',
      channelDescription: 'PyAirtable notifications',
      importance: _getImportance(channelId),
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: data != null ? data.toString() : null,
    );
  }

  Future<void> scheduleNotification(
    String title,
    String body,
    DateTime scheduledDate, {
    Map<String, dynamic>? data,
    String? channelId,
  }) async {
    if (!_isInitialized) {
      throw Exception('NotificationManager not initialized');
    }

    final androidDetails = AndroidNotificationDetails(
      channelId ?? NotificationChannels.defaultChannel,
      'PyAirtable Scheduled',
      channelDescription: 'Scheduled PyAirtable notifications',
      importance: _getImportance(channelId),
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.schedule(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      scheduledDate,
      notificationDetails,
      payload: data != null ? data.toString() : null,
    );
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  Importance _getImportance(String? channelId) {
    switch (channelId) {
      case NotificationChannels.updates:
        return Importance.high;
      case NotificationChannels.sync:
        return Importance.low;
      default:
        return Importance.defaultImportance;
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    if (response.payload != null) {
      // Parse payload and handle navigation
      _handleNotificationTap({});
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    print('Handling notification tap with data: $data');
    // TODO: Implement navigation logic based on notification data
  }

  Future<void> dispose() async {
    // Clean up resources
    _isInitialized = false;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
}