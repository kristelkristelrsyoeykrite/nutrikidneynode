import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'api_service.dart';

@pragma('vm:entry-point')
void notificationActionBackgroundHandler(NotificationResponse details) {
  NotificationService.handleNotificationResponse(details).catchError((error) {
    debugPrint('[Notifications] Background action failed: $error');
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String _snoozeActionId = 'snooze_5_minutes';
  static const String _dontRemindActionId = 'dont_remind_again';
  static const String _settingsPrefix = 'notification_preferences_';
  static const String _dismissedPrefix = 'dismissed_reminders_';
  static const String _channelId = 'nutrikidney_exact_reminders';
  static const String _channelName = 'NutriKidney Exact Reminders';
  static const int _mealIdBase = 41000;
  static const int _hydrationIdBase = 42000;
  static const int _medicationIdBase = 43000;
  static const int _snoozeIdBase = 44000;
  static const int _streakIdBase = 44500;
  static const int _testImmediateId = 45001;
  static const int _testScheduledId = 45002;
  static const int _maxMedicationNotifications = 80;
  static const int _daysToScheduleAhead = 2;

  static bool _initialized = false;
  static bool _timeZoneInitialized = false;
  static bool _exactAlarmsAllowed = true;

  static const Map<String, _ReminderTime> _mealSchedule = {
    'breakfast': _ReminderTime(8, 0, 'Breakfast'),
    'lunch': _ReminderTime(12, 0, 'Lunch'),
    'snack': _ReminderTime(15, 0, 'Snack'),
    'dinner': _ReminderTime(18, 0, 'Dinner'),
  };

  static Future<void> initialize() async {
    if (_initialized) return;

    _initializeTimeZone();

    const androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInitializationSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('[Notifications] tapped payload=${details.payload}');
        handleNotificationResponse(details);
      },
      onDidReceiveBackgroundNotificationResponse:
          notificationActionBackgroundHandler,
    );

    await _createAndroidChannel();
    _initialized = true;
    debugPrint('[Notifications] Exact local notification service initialized');
  }

  static Future<bool> requestPermissionsIfNeeded() async {
    await initialize();

    bool localGranted = true;
    if (!kIsWeb && Platform.isAndroid) {
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      localGranted =
          await android?.requestNotificationsPermission() ?? localGranted;
      _exactAlarmsAllowed =
          await android?.canScheduleExactNotifications() ?? true;
    } else if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      final ios = _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      localGranted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          localGranted;
    }

    return localGranted;
  }

  static Future<bool> canScheduleExactAlarms() async {
    await initialize();
    if (kIsWeb || !Platform.isAndroid) return true;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    _exactAlarmsAllowed =
        await android?.canScheduleExactNotifications() ?? true;
    return _exactAlarmsAllowed;
  }

  static Future<bool> openExactAlarmSettings() async {
    await initialize();
    if (kIsWeb || !Platform.isAndroid) return true;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    _exactAlarmsAllowed =
        await android?.canScheduleExactNotifications() ?? false;
    return _exactAlarmsAllowed;
  }

  static Future<bool> showTestNotification() async {
    final granted = await requestPermissionsIfNeeded();
    if (!granted) {
      debugPrint('[Notifications] Test skipped because permission is denied');
      return false;
    }

    final title = 'Welcome!';
    final body = 'Notifications are ready.';
    final payload = 'test:${_dateKey(DateTime.now())}:immediate';

    await _localNotifications.show(
      _testImmediateId,
      title,
      body,
      _notificationDetails(title: title, body: body),
      payload: payload,
    );

    await _localNotifications.cancel(_testScheduledId);
    await _scheduleExact(
      id: _testScheduledId,
      title: 'Scheduled reminder test',
      body: 'This reminder was scheduled 10 seconds ago.',
      scheduled: DateTime.now().add(const Duration(seconds: 10)),
      payload: 'test:${_dateKey(DateTime.now())}:scheduled',
    );
    return true;
  }

  static Future<void> handleNotificationResponse(
    NotificationResponse details,
  ) async {
    await initialize();
    final actionId = details.actionId;
    final payload = details.payload;
    if (payload == null || payload.isEmpty) return;

    if (actionId == _snoozeActionId) {
      await _snoozeReminder(payload);
    } else if (actionId == _dontRemindActionId) {
      await _disableReminderFromPayload(payload);
    }
  }

  static Future<void> refreshReminderNotificationsFromDashboard() async {
    try {
      await initialize();
      final response = await ApiService.getDashboardSummary();
      if (response['success'] != true) {
        debugPrint('[Notifications] Dashboard refresh skipped: $response');
        return;
      }
      await syncReminderNotifications(
        user: _asStringMap(response['user']),
        medications: _asStringMapList(response['medications']),
        intakeData: _nullableStringMap(response['intakeData']),
        gamification: _nullableStringMap(response['gamification']),
      );
    } catch (error) {
      debugPrint('[Notifications] Unable to refresh reminders: $error');
    }
  }

  static Future<void> syncReminderNotifications({
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> medications,
    Map<String, dynamic>? intakeData,
    Map<String, dynamic>? gamification,
  }) async {
    await initialize();

    final settings = _reminderSettingsFrom(user);
    await cacheReminderSettings(settings);
    await _cleanupExpiredDismissals();
    await _cleanupScheduledReminders();

    final today = DateTime.now();
    final foodLogs = _foodLogsFromIntakeData(intakeData);
    final todayMealTypes = foodLogs.isEmpty
        ? await _loggedMealTypesForToday()
        : _loggedMealTypesFromLogs(foodLogs);

    try {
      await _scheduleMealReminders(
        settings: settings,
        today: today,
        loggedMealTypesToday: todayMealTypes,
      );
      await _scheduleHydrationReminders(settings);
      await _scheduleMedicationReminders(
        settings: settings,
        medications: medications,
      );
      await _scheduleStreakEndingReminder(gamification);
    } catch (error) {
      debugPrint('[Notifications] Reminder scheduling failed: $error');
    }

    debugPrint('[Notifications] Reminders rescheduled');
  }

  static Future<Map<String, dynamic>> cachedReminderSettings() async {
    final userId = ApiService.userId;
    if (userId == null || userId.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_settingsPrefix$userId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> cacheReminderSettings(Map<String, dynamic> settings) async {
    final userId = ApiService.userId;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_settingsPrefix$userId', jsonEncode(settings));
  }

  static Future<void> replaceCachedReminderSettings({
    required bool medicationReminders,
    required bool hydrationAlerts,
    required bool breakfastReminder,
    required bool lunchReminder,
    required bool snackReminder,
    required bool dinnerReminder,
  }) async {
    await cacheReminderSettings({
      'medicationReminders': medicationReminders,
      'hydrationAlerts': hydrationAlerts,
      'mealReminders': {
        'breakfast': breakfastReminder,
        'lunch': lunchReminder,
        'snack': snackReminder,
        'dinner': dinnerReminder,
      },
    });
  }

  static void _initializeTimeZone() {
    if (_timeZoneInitialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    _timeZoneInitialized = true;
  }

  static Future<void> _createAndroidChannel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Exact reminders for meals, medications, and hydration',
      importance: Importance.max,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> _cleanupScheduledReminders() async {
    await _cancelRange(_mealIdBase, 40);
    await _cancelRange(_hydrationIdBase, 40);
    await _cancelRange(_medicationIdBase, _maxMedicationNotifications);
    await _cancelRange(_streakIdBase, 4);
  }

  static Future<void> _cancelRange(int startId, int count) async {
    for (var id = startId; id < startId + count; id++) {
      await _localNotifications.cancel(id);
    }
  }

  static Future<void> _scheduleMealReminders({
    required Map<String, dynamic> settings,
    required DateTime today,
    required Set<String> loggedMealTypesToday,
  }) async {
    final mealSettings = _asStringMap(settings['mealReminders']);
    var idOffset = 0;

    for (var dayOffset = 0; dayOffset < _daysToScheduleAhead; dayOffset++) {
      for (final entry in _mealSchedule.entries) {
        if (mealSettings[entry.key] != true) continue;
        if (dayOffset == 0 && loggedMealTypesToday.contains(entry.key)) {
          continue;
        }

        final time = entry.value;
        final scheduled = _nextDateAt(
          baseDate: today.add(Duration(days: dayOffset)),
          hour: time.hour,
          minute: time.minute,
        );
        if (!scheduled.isAfter(DateTime.now())) continue;

        final payload = 'meal:${entry.key}:${_dateKey(scheduled)}';
        if (await _isDismissed(payload)) continue;

        await _scheduleExact(
          id: _mealIdBase + idOffset++,
          title: '${time.label} reminder',
          body: 'Have you logged your ${entry.key} yet?',
          scheduled: scheduled,
          payload: payload,
        );
      }
    }
  }

  static Future<void> _scheduleHydrationReminders(
    Map<String, dynamic> settings,
  ) async {
    if (settings['hydrationAlerts'] != true) return;

    var idOffset = 0;
    final now = DateTime.now();
    for (var dayOffset = 0; dayOffset < _daysToScheduleAhead; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      for (var hour = 9; hour <= 21; hour++) {
        final scheduled = DateTime(day.year, day.month, day.day, hour);
        if (!scheduled.isAfter(now)) continue;
        final payload = 'hydration:${_dateKey(scheduled)}:${hour.toString().padLeft(2, '0')}00';
        if (await _isDismissed(payload)) continue;
        await _scheduleExact(
          id: _hydrationIdBase + idOffset++,
          title: 'Hydration reminder',
          body: 'Drink water and stay within today\'s fluid goal.',
          scheduled: scheduled,
          payload: payload,
        );
      }
    }
  }

  static Future<void> _scheduleMedicationReminders({
    required Map<String, dynamic> settings,
    required List<Map<String, dynamic>> medications,
  }) async {
    if (settings['medicationReminders'] != true) return;

    var idOffset = 0;
    final now = DateTime.now();
    for (var dayOffset = 0; dayOffset < _daysToScheduleAhead; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      for (final medication in medications) {
        final name = _medicationName(medication);
        for (final clockTime in _medicationTimes(medication)) {
          if (idOffset >= _maxMedicationNotifications) return;
          final parts = _parseClockTime(clockTime);
          if (parts == null) continue;
          final scheduled = DateTime(
            day.year,
            day.month,
            day.day,
            parts.hour,
            parts.minute,
          );
          if (!scheduled.isAfter(now)) continue;
          final medKey = _stableKey(name);
          final payload =
              'medication:$medKey:${_dateKey(scheduled)}:${parts.hour.toString().padLeft(2, '0')}${parts.minute.toString().padLeft(2, '0')}';
          if (await _isDismissed(payload)) continue;
          await _scheduleExact(
            id: _medicationIdBase + idOffset++,
            title: '$name reminder',
            body: 'Scheduled medication time.',
            scheduled: scheduled,
            payload: payload,
          );
        }
      }
    }
  }

  static Future<void> _scheduleStreakEndingReminder(
    Map<String, dynamic>? gamification,
  ) async {
    if (!_shouldScheduleStreakReminder(gamification)) return;

    final now = DateTime.now();
    final scheduled = _nextStreakReminderTime(now);
    if (scheduled == null) return;

    final status = _asStringMap(gamification?['status']);
    final streak = _intValue(
      status['displayStreak'] ?? status['currentStreak'],
    );
    final payload = 'streak:${_dateKey(scheduled)}';
    if (await _isDismissed(payload)) return;

    await _scheduleExact(
      id: _streakIdBase,
      title: 'Streak reminder',
      body: streak >= 2
          ? 'Your $streak-day streak ends tonight. Log meals and hydration to keep it going.'
          : 'Your streak ends tonight. Log meals and hydration to keep it going.',
      scheduled: scheduled,
      payload: payload,
    );
  }

  static Future<void> _scheduleExact({
    required int id,
    required String title,
    required String body,
    required DateTime scheduled,
    required String payload,
  }) async {
    final scheduleMode = _exactAlarmsAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduled, tz.local),
        _notificationDetails(title: title, body: body),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (error) {
      final message = error.toString();
      if (message.contains('EXACT_ALARMS_NOT_PERMITTED') ||
          message.contains('exact alarms are not permitted')) {
        _exactAlarmsAllowed = false;
        await _localNotifications.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduled, tz.local),
          _notificationDetails(title: title, body: body),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        return;
      }
      debugPrint('[Notifications] Skipping reminder $id: $error');
    }
  }

  static Future<void> _snoozeReminder(String payload) async {
    final copy = _copyForPayload(payload);
    final scheduled = DateTime.now().add(const Duration(minutes: 5));
    await _scheduleExact(
      id: _snoozeIdBase +
          DateTime.now().millisecondsSinceEpoch.remainder(10000),
      title: copy.title,
      body: copy.body,
      scheduled: scheduled,
      payload: payload,
    );
  }

  static Future<void> _disableReminderFromPayload(String payload) async {
    await _markDismissed(payload);
    await _cleanupScheduledReminders();
    await refreshReminderNotificationsFromDashboard();
  }

  static _ReminderCopy _copyForPayload(String payload) {
    final parts = payload.split(':');
    final kind = parts.first;
    if (kind == 'meal' && parts.length > 1) {
      final meal = parts[1];
      final label = _mealSchedule[meal]?.label ?? 'Meal';
      return _ReminderCopy(
        '$label reminder',
        'Have you logged your $meal yet?',
      );
    }
    if (kind == 'hydration') {
      return const _ReminderCopy(
        'Hydration reminder',
        'Drink water and stay within today\'s fluid goal.',
      );
    }
    if (kind == 'medication') {
      final label = parts.length > 1
          ? parts[1].replaceAll('_', ' ')
          : 'Medication';
      return _ReminderCopy(
        '$label reminder',
        'Scheduled medication time.',
      );
    }
    if (kind == 'streak') {
      return const _ReminderCopy(
        'Streak reminder',
        'Your streak ends tonight. Log meals and hydration to keep it going.',
      );
    }
    return const _ReminderCopy('Reminder', 'It is time for your reminder.');
  }

  static NotificationDetails _notificationDetails({
    bool includeActions = true,
    String? title,
    String? body,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Exact reminders for meals, medications, and hydration',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
        timeoutAfter: 60 * 60 * 1000,
        styleInformation: BigTextStyleInformation(
          body ?? '',
          contentTitle: title,
          summaryText: 'Reminder',
        ),
        actions: includeActions
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
    );
  }

  static DateTime _nextDateAt({
    required DateTime baseDate,
    required int hour,
    required int minute,
  }) {
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }

  static Map<String, dynamic> _reminderSettingsFrom(
    Map<String, dynamic> user,
  ) {
    final settings = _asStringMap(user['reminderSettings']);
    return settings.isNotEmpty
        ? settings
        : {
            'medicationReminders': false,
            'hydrationAlerts': false,
            'mealReminders': {
              'breakfast': false,
              'lunch': false,
              'snack': false,
              'dinner': false,
            },
          };
  }

  static List<Map<String, dynamic>> _foodLogsFromIntakeData(
    Map<String, dynamic>? intakeData,
  ) {
    final logs = intakeData?['foodLogs'] ?? intakeData?['food_logs'];
    return _asStringMapList(logs);
  }

  static Future<Set<String>> _loggedMealTypesForToday() async {
    try {
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final response = await ApiService.getFoodLogs(date: today);
      return _loggedMealTypesFromLogs(_asStringMapList(response['logs']));
    } catch (error) {
      debugPrint('[Notifications] Meal log lookup failed: $error');
      return {};
    }
  }

  static Set<String> _loggedMealTypesFromLogs(List<Map<String, dynamic>> logs) {
    return logs
        .map((log) => _normalizeMealKey(log['mealType'] ?? log['meal_type']))
        .where((meal) => meal.isNotEmpty)
        .toSet();
  }

  static String _normalizeMealKey(dynamic value) {
    final meal = value?.toString().trim().toLowerCase() ?? '';
    if (meal == 'snacks') return 'snack';
    return meal;
  }

  static Future<bool> _isDismissed(String payload) async {
    final dismissed = await _dismissedPayloads();
    return dismissed.contains(payload);
  }

  static Future<void> _markDismissed(String payload) async {
    final userId = ApiService.userId;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = await _dismissedPayloads();
    dismissed.add(payload);
    await prefs.setStringList('$_dismissedPrefix$userId', dismissed.toList());
  }

  static Future<Set<String>> _dismissedPayloads() async {
    final userId = ApiService.userId;
    if (userId == null || userId.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('$_dismissedPrefix$userId') ?? const <String>[])
        .toSet();
  }

  static Future<void> _cleanupExpiredDismissals() async {
    final userId = ApiService.userId;
    if (userId == null || userId.isEmpty) return;
    final today = _dateKey(DateTime.now());
    final dismissed = await _dismissedPayloads();
    dismissed.removeWhere((payload) => !payload.contains(today));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_dismissedPrefix$userId', dismissed.toList());
  }

  static String _dateKey(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  static bool _shouldScheduleStreakReminder(
    Map<String, dynamic>? gamification,
  ) {
    if (gamification == null || gamification.isEmpty) return false;

    final status = _asStringMap(gamification['status']);
    final todayStatus = _asStringMap(gamification['today']);
    final streak = _intValue(status['displayStreak'] ?? status['currentStreak']);
    if (streak < 2) return false;
    if (todayStatus['isCompleteDay'] == true) return false;

    final lastCompleteLogDate = status['lastCompleteLogDate']?.toString();
    if (lastCompleteLogDate == null || lastCompleteLogDate.isEmpty) {
      return false;
    }

    final now = DateTime.now();
    final today = _dateKey(now);
    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));
    return lastCompleteLogDate == yesterday || lastCompleteLogDate == today;
  }

  static DateTime? _nextStreakReminderTime(DateTime now) {
    final preferred = DateTime(now.year, now.month, now.day, 20, 30);
    if (preferred.isAfter(now)) return preferred;

    final fallback = now.add(const Duration(minutes: 5));
    final cutoff = DateTime(now.year, now.month, now.day, 23, 30);
    if (fallback.isAfter(cutoff)) return null;
    return fallback;
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _stableKey(String value) {
    final key = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return key.isEmpty ? 'medication' : key;
  }

  static String _medicationName(Map<String, dynamic> medication) {
    final name = (medication['name'] ??
            medication['medicationName'] ??
            medication['medication_name'] ??
            'Medication')
        .toString()
        .trim();
    return name.isEmpty ? 'Medication' : name;
  }

  static List<String> _medicationTimes(Map<String, dynamic> medication) {
    final scheduledTimes = medication['scheduled_times'];
    if (scheduledTimes is List) {
      final parsedTimes = scheduledTimes
          .expand((time) => _extractClockTimes(time.toString()))
          .toList(growable: false);
      if (parsedTimes.isNotEmpty) return parsedTimes;
    }

    final raw = (medication['start_time'] ??
            medication['time'] ??
            medication['schedule'] ??
            medication['display_times'] ??
            '')
        .toString();
    return _extractClockTimes(raw);
  }

  static _ReminderTime? _parseClockTime(String raw) {
    final trimmed = raw.trim().toUpperCase();
    final twentyFourHour = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
    if (twentyFourHour != null) {
      final hour = int.tryParse(twentyFourHour.group(1)!);
      final minute = int.tryParse(twentyFourHour.group(2)!);
      if (hour != null && minute != null && hour <= 23 && minute <= 59) {
        return _ReminderTime(hour, minute, '');
      }
    }

    final twelveHour =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([AP]M)$', caseSensitive: false)
            .firstMatch(trimmed);
    if (twelveHour == null) return null;
    var hour = int.tryParse(twelveHour.group(1)!);
    final minute = int.tryParse(twelveHour.group(2) ?? '0');
    final period = twelveHour.group(3)!.toUpperCase();
    if (hour == null || minute == null || hour < 1 || hour > 12 || minute > 59) {
      return null;
    }
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return _ReminderTime(hour, minute, '');
  }

  static List<String> _extractClockTimes(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return const [];

    final matches = RegExp(
      r'\b\d{1,2}:\d{2}\s*(?:[AP]M)?\b|\b\d{1,2}\s*[AP]M\b',
      caseSensitive: false,
    ).allMatches(normalized);
    final times = matches
        .map((match) => match.group(0)?.trim() ?? '')
        .where((time) => time.isNotEmpty)
        .toList(growable: false);
    if (times.isNotEmpty) return times;

    return normalized
        .split(',')
        .map((time) => time.trim())
        .where((time) => time.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  static Map<String, dynamic>? _nullableStringMap(dynamic value) {
    final map = _asStringMap(value);
    return map.isEmpty ? null : map;
  }

  static List<Map<String, dynamic>> _asStringMapList(dynamic value) {
    if (value is! List) return [];
    return value.map(_asStringMap).where((map) => map.isNotEmpty).toList();
  }
}

class _ReminderTime {
  final int hour;
  final int minute;
  final String label;

  const _ReminderTime(this.hour, this.minute, this.label);
}

class _ReminderCopy {
  final String title;
  final String body;

  const _ReminderCopy(this.title, this.body);
}
