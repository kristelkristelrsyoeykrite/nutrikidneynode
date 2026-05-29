import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'notification_service.dart';

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
  static const String _snoozeActionId = 'snooze_5_minutes';
  static const String _dontRemindActionId = 'dont_remind_again';
  static const String _channelId = 'nutrikidney_reminders';
  static const String _channelName = 'NutriKidney Reminders';
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      debugPrint('[Push] Skipping push notification service on web');
      return;
    }

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
      if (!_isForCurrentUser(message)) {
        debugPrint('[Push] Ignoring foreground notification for inactive user');
        return;
      }
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
          await NotificationService.handleNotificationResponse(details);
        },
        onDidReceiveBackgroundNotificationResponse:
            notificationActionBackgroundHandler,
      );
      await _createAndroidChannel();
      debugPrint('[Push] Local notifications initialized');
    } catch (error) {
      debugPrint('[Push] Failed to initialize local notifications: $error');
    }
  }

  static Future<void> _createAndroidChannel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Push reminders for meals, medications, and hydration',
      importance: Importance.max,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> _displayForegroundNotification(
    RemoteMessage message,
  ) async {
    if (!_isForCurrentUser(message)) {
      debugPrint('[Push] Skipping display for inactive user');
      return;
    }

    final title =
        message.notification?.title ?? message.data['title'] ?? 'Notification';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final payload = _payloadForMessage(message);

    debugPrint('[Push] Displaying foreground notification: $title');

    try {
      await _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Reminders for meals, medications, and hydration',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            icon: null, // Use default icon
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.reminder,
            timeoutAfter: 60 * 60 * 1000,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: 'Reminder',
            ),
            actions: _isReminderPayload(payload)
                ? const <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      _snoozeActionId,
                      'Remind me in 5 mins',
                      showsUserInterface: true,
                    ),
                    AndroidNotificationAction(
                      _dontRemindActionId,
                      'Don\'t remind me again',
                      showsUserInterface: true,
                    ),
                  ]
                : null,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
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
    if (kIsWeb) return false;
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
    if (kIsWeb) return;
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
    if (kIsWeb) return;
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
    if (kIsWeb) return;
    final userId = ApiService.userId;
    debugPrint('[Push] syncTokenIfPossible userId=$userId');
    if (userId == null || userId.isEmpty) {
      debugPrint('[Push] Skipping token sync because no userId is set');
      return;
    }
    await registerCurrentDeviceToken();
  }

  static Future<Map<String, dynamic>> sendTestPushNotification() async {
    if (kIsWeb) {
      return {
        'success': false,
        'message': 'Push notifications are not available on web.',
      };
    }
    debugPrint('[Push] Sending test push notification');
    await registerCurrentDeviceToken();
    final response = await ApiService.sendTestPushNotification();
    debugPrint('[Push] Test push response: $response');
    return response;
  }

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static bool _isForCurrentUser(RemoteMessage message) {
    final messageUserId = message.data['userId']?.toString();
    final currentUserId = ApiService.userId;
    if (messageUserId == null || messageUserId.isEmpty) {
      return currentUserId != null && currentUserId.isNotEmpty;
    }
    return currentUserId != null &&
        currentUserId.isNotEmpty &&
        messageUserId == currentUserId;
  }

  static String _payloadForMessage(RemoteMessage message) {
    final explicitPayload = message.data['payload']?.toString();
    if (explicitPayload != null && explicitPayload.isNotEmpty) {
      return explicitPayload;
    }

    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final type = message.data['type']?.toString() ?? '';
    if (type == 'meal_reminder') return 'meal:food_log:$date';
    if (type == 'hydration_reminder') return 'hydration:$date:push';
    if (type == 'medication_reminder') return 'medication:medication:$date:push';
    return message.data.toString();
  }

  static bool _isReminderPayload(String payload) {
    return payload.startsWith('meal:') ||
        payload.startsWith('hydration:') ||
        payload.startsWith('medication:');
  }

  static String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) return '<empty>';
    if (token.length <= 16) return token;
    return '${token.substring(0, 8)}...${token.substring(token.length - 8)}';
  }
}
