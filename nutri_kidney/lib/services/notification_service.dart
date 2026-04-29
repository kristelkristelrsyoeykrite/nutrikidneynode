import 'package:flutter/foundation.dart';

import 'push_notification_service.dart';

class NotificationService {
  static Future<void> initialize() async {
    debugPrint('[NotificationShim] initialize() called');
  }

  static Future<void> refreshReminderNotificationsFromDashboard() async {
    debugPrint(
      '[NotificationShim] refreshReminderNotificationsFromDashboard() called',
    );
  }

  static Future<void> syncReminderNotifications({
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> medications,
    Map<String, dynamic>? intakeData,
  }) async {
    debugPrint(
      '[NotificationShim] syncReminderNotifications() called with '
      'medications=${medications.length}',
    );
  }

  static Future<bool> requestPermissionsIfNeeded() async {
    debugPrint('[NotificationShim] requestPermissionsIfNeeded() called');
    return PushNotificationService.requestPermissionsIfNeeded();
  }

  static Future<void> showTestNotification() async {
    debugPrint('[NotificationShim] showTestNotification() called');
    await PushNotificationService.sendTestPushNotification();
  }
}
