import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[Push] Background message received: id=${message.messageId}, '
    'title=${message.notification?.title ?? message.data['title']}',
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('[Push] Initializing push notification service');

    // Initialize local notifications
    await _initializeLocalNotifications();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _messaging.setAutoInitEnabled(true);
    debugPrint('[Push] Firebase Messaging auto-init enabled');
    await _requestPermission();

    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint(
        '[Push] Foreground message received: id=${message.messageId}, '
        'title=${message.notification?.title ?? message.data['title']}, '
        'data=${message.data}',
      );
      // Display foreground notification
      await _displayForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint(
        '[Push] Notification opened from tray: id=${message.messageId}, '
        'data=${message.data}',
      );
    });

    _messaging.onTokenRefresh.listen((token) async {
      debugPrint('[Push] FCM token refreshed: ${_tokenPreview(token)}');
      try {
        await registerCurrentDeviceToken(token: token);
      } catch (error) {
        debugPrint('[Push] Failed to handle token refresh: $error');
      }
    });

    final startupToken = await _messaging.getToken();
    debugPrint('[Push] Startup FCM token: ${_tokenPreview(startupToken)}');
    _initialized = true;
    debugPrint('[Push] Push notification service initialized');
  }

  static Future<void> _initializeLocalNotifications() async {
    debugPrint('[Push] Initializing local notifications');

     final androidInitializationSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher', // Uses app launcher icon as default
    );
    
    final iosInitializationSettings = DarwinInitializationSettings(
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        debugPrint('[Push] iOS received local notification: $title');
      },
    );

    final initSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    try {
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) async {
          debugPrint('[Push] Local notification tapped: ${details.payload}');
        },
      );
      debugPrint('[Push] Local notifications initialized');
    } catch (error) {
      debugPrint('[Push] Failed to initialize local notifications: $error');
    }
  }

  static Future<void> _displayForegroundNotification(
    RemoteMessage message,
  ) async {
    final title = message.notification?.title ?? message.data['title'] ?? 'Notification';
    final body = message.notification?.body ?? message.data['body'] ?? '';

    debugPrint('[Push] Displaying foreground notification: $title');

    try {
      await _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'nutrikidney_reminders',
            'NutriKidney Reminders',
            channelDescription: 'Reminders for meals, medications, and hydration',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            icon: null, // Use default icon
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data.toString(),
      );
      debugPrint('[Push] Foreground notification displayed successfully');
    } catch (error) {
      debugPrint('[Push] Failed to display foreground notification: $error');
    }
  }

  static Future<void> _requestPermission() async {
    debugPrint('[Push] Requesting notification permission');
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    debugPrint(
      '[Push] Permission status: ${settings.authorizationStatus}, '
      'alert=${settings.alert}, badge=${settings.badge}, sound=${settings.sound}',
    );
  }

  static Future<bool> requestPermissionsIfNeeded() async {
    await initialize();
    debugPrint('[Push] Re-checking notification permission');
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    final status = settings.authorizationStatus;
    debugPrint('[Push] Re-check permission result: $status');
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  static Future<void> registerCurrentDeviceToken({String? token}) async {
    await initialize();
    final currentToken = token ?? await _messaging.getToken();
    debugPrint('[Push] registerCurrentDeviceToken token=${_tokenPreview(currentToken)}');
    if (currentToken == null || currentToken.isEmpty) {
      debugPrint('[Push] No FCM token available to register');
      return;
    }

    try {
      final response = await ApiService.registerDeviceToken(
        token: currentToken,
        platform: _platformLabel,
      );
      debugPrint('[Push] Device token register response: $response');
    } catch (error) {
      debugPrint('[Push] Failed to register FCM token: $error');
    }
  }

  static Future<void> unregisterCurrentDeviceToken() async {
    await initialize();
    final token = await _messaging.getToken();
    debugPrint('[Push] unregisterCurrentDeviceToken token=${_tokenPreview(token)}');
    if (token == null || token.isEmpty) {
      debugPrint('[Push] No FCM token available to unregister');
      return;
    }

    try {
      final response = await ApiService.unregisterDeviceToken(token: token);
      debugPrint('[Push] Device token unregister response: $response');
    } catch (error) {
      debugPrint('[Push] Failed to unregister FCM token: $error');
    }
  }

  static Future<void> syncTokenIfPossible() async {
    final userId = ApiService.userId;
    debugPrint('[Push] syncTokenIfPossible userId=$userId');
    if (userId == null || userId.isEmpty) {
      debugPrint('[Push] Skipping token sync because no userId is set');
      return;
    }
    await registerCurrentDeviceToken();
  }

  static Future<Map<String, dynamic>> sendTestPushNotification() async {
    debugPrint('[Push] Sending test push notification');
    await registerCurrentDeviceToken();
    final response = await ApiService.sendTestPushNotification();
    debugPrint('[Push] Test push response: $response');
    return response;
  }

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) return '<empty>';
    if (token.length <= 16) return token;
    return '${token.substring(0, 8)}...${token.substring(token.length - 8)}';
  }
}
