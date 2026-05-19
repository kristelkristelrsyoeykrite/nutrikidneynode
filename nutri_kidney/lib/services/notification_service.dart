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
  static const String _schedulePayloadPrefix = 'scheduled_reminder_payload_';
  static const String _scheduledHashPrefix = 'scheduled_reminder_hash_';
  static const String _channelId = 'nutrikidney_exact_reminders';
  static const String _channelName = 'NutriKidney Exact Reminders';
  static const int _mealIdBase = 41000;
  static const int _hydrationIdBase = 42000;
  static const int _medicationIdBase = 43000;
  static const int _snoozeIdBase = 44000;
  static const int _streakIdBase = 44500;
  static const int _singleMedicationIdBase = 46000;
  static const int _testImmediateId = 45001;
  static const int _testScheduledId = 45002;
  static const int _maxMedicationNotifications = 160;
  static const int _maxSingleMedicationNotifications = 8;
  static const int _notificationProfileBlockSize = 1000;
  static const int _maxCaregiverProfilesToSchedule = 4;
  static const int _daysToScheduleAhead = 7;

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

  static Future<bool> prepareReminderScheduling() async {
    final notificationsAllowed = await requestPermissionsIfNeeded();
    final exactAllowed = await canScheduleExactAlarms();
    if (!notificationsAllowed) {
      debugPrint('[Notifications] Scheduling skipped: notification permission denied');
      return false;
    }
    if (!exactAllowed) {
      debugPrint(
        '[Notifications] Exact alarms are disabled; Android may delay reminders.',
      );
    }
    return true;
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
      await refreshReminderNotificationsFromDashboardResponse(response);
    } catch (error) {
      debugPrint('[Notifications] Unable to refresh reminders: $error');
    }
  }

  static Future<void> refreshReminderNotificationsFromDashboardResponse(
    Map<String, dynamic> response,
  ) async {
    try {
      await initialize();
      if (response['success'] != true) {
        debugPrint('[Notifications] Dashboard refresh skipped: $response');
        return;
      }
      final viewer = _asStringMap(response['viewer']);
      final caregiverState = _asStringMap(response['caregiverDashboardState']);
      if (_isCaregiver(viewer)) {
        final settings = _reminderSettingsFrom(viewer);
        await cacheReminderSettings(settings);

        final childIds = _managedChildIds(caregiverState);
        final loadedProfileUserId =
            (response['profileOwnerId'] ?? response['dashboardOwnerId'])
                ?.toString();
        for (var index = 0;
            index < childIds.length && index < _maxCaregiverProfilesToSchedule;
            index += 1) {
          final childResponse = loadedProfileUserId == childIds[index]
              ? response
              : await ApiService.getDashboardSummary(
                  profileUserId: childIds[index],
                );
          if (childResponse['success'] != true) continue;
          await syncReminderNotifications(
            user: {
              ..._asStringMap(childResponse['user']),
              'reminderSettings': settings,
            },
            medications: _asStringMapList(childResponse['medications']),
            intakeData: _nullableStringMap(childResponse['intakeData']),
            gamification: _nullableStringMap(childResponse['gamification']),
            profileIndex: index,
            profileUserId: childIds[index],
          );
        }
        debugPrint('[Notifications] Caregiver reminders checked');
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

  static Future<void> ensureScheduledFromCache() async {
    try {
      await initialize();
      await requestPermissionsIfNeeded();
      final userId = ApiService.userId;
      if (userId == null || userId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final prefix = '$_schedulePayloadPrefix$userId|';
      final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final payload = Map<String, dynamic>.from(decoded);
        await syncReminderNotifications(
          user: _asStringMap(payload['user']),
          medications: _asStringMapList(payload['medications']),
          intakeData: _nullableStringMap(payload['intakeData']),
          gamification: _nullableStringMap(payload['gamification']),
          profileIndex: _intValue(payload['profileIndex']),
          profileUserId: payload['profileUserId']?.toString(),
        );
      }
    } catch (error) {
      debugPrint('[Notifications] Cached reminder check failed: $error');
    }
  }

  static Future<void> syncFromBackendAndRescheduleIfChanged() {
    return refreshReminderNotificationsFromDashboard();
  }

  static Future<void> syncSingleMedicationReminder({
    required Map<String, dynamic> medication,
    Map<String, dynamic>? previousMedication,
    String? profileUserId,
    int profileIndex = 0,
    Map<String, dynamic>? user,
  }) async {
    try {
      await initialize();
      final idOffsetBase = profileIndex * _notificationProfileBlockSize;
      var settings = user == null
          ? await cachedReminderSettings()
          : _reminderSettingsFrom(user);
      if (settings.isEmpty) {
        final response = await ApiService.getReminderSettings(
          profileUserId: profileUserId,
        );
        final backendSettings = _asStringMap(response['reminderSettings']);
        if (backendSettings.isNotEmpty) {
          settings = backendSettings;
          await cacheReminderSettings(settings);
        }
      }
      await _cancelMedicationReminderRequests(
        medication: previousMedication,
        profileUserId: profileUserId,
        idOffsetBase: idOffsetBase,
      );
      await _cancelMedicationReminderRequests(
        medication: medication,
        profileUserId: profileUserId,
        idOffsetBase: idOffsetBase,
      );

      if (settings['medicationReminders'] != true ||
          !_isPendingMedication(medication) ||
          _medicationTimes(medication).isEmpty) {
        debugPrint('[Notifications] Single medication reminder cleared');
        return;
      }

      final canSchedule = await prepareReminderScheduling();
      if (!canSchedule) return;
      final detectedProfileId = profileUserId ??
          ApiService.selectedManagedChildProfileId ??
          ApiService.userId;
      final patientName = user == null ? null : _patientName(user);
      final payloadPrefix = _profilePayloadPrefix(detectedProfileId, patientName);
      await _scheduleSingleMedicationReminder(
        settings: settings,
        medication: medication,
        patientName: patientName,
        idOffsetBase: idOffsetBase,
        payloadPrefix: payloadPrefix,
      );
      debugPrint('[Notifications] Single medication reminder synced');
    } catch (error) {
      debugPrint('[Notifications] Single medication reminder sync failed: $error');
    }
  }

  static Future<void> syncReminderNotifications({
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> medications,
    Map<String, dynamic>? intakeData,
    Map<String, dynamic>? gamification,
    int profileIndex = 0,
    String? profileUserId,
    bool forceReschedule = false,
  }) async {
    await initialize();

    final settings = _reminderSettingsFrom(user);
    final patientName = _patientName(user);
    await cacheReminderSettings(settings);
    final idOffsetBase = profileIndex * _notificationProfileBlockSize;
    final detectedProfileId = profileUserId ??
        ApiService.selectedManagedChildProfileId ??
        ApiService.userId;
    final payloadPrefix = _profilePayloadPrefix(detectedProfileId, patientName);
    final activeProfileId = detectedProfileId ?? payloadPrefix;
    final scheduleHash = _reminderHash(
      settings: settings,
      medications: medications,
      profileUserId: activeProfileId,
    );
    final prefs = await SharedPreferences.getInstance();
    final hashKey = _scheduledHashKey(activeProfileId, profileIndex);
    final previousHash = prefs.getString(hashKey);
    final hasReminderWork = _hasReminderWork(
      settings: settings,
      medications: medications,
      gamification: gamification,
    );
    final hasPendingReminders = hasReminderWork
        ? await _hasPendingScheduledRemindersForProfile(idOffsetBase)
        : true;
    if (!forceReschedule && previousHash == scheduleHash && hasPendingReminders) {
      await _cacheSchedulePayload(
        user: user,
        medications: medications,
        intakeData: intakeData,
        gamification: gamification,
        profileIndex: profileIndex,
        profileUserId: activeProfileId,
      );
      debugPrint('[Notifications] Reminder schedule unchanged');
      return;
    }
    if (!forceReschedule && previousHash == scheduleHash && !hasPendingReminders) {
      debugPrint(
        '[Notifications] Reminder hash unchanged but no pending reminders were found; scheduling again',
      );
    }

    final canSchedule = await prepareReminderScheduling();
    if (!canSchedule) return;
    await _cleanupExpiredDismissals();
    await _cleanupScheduledRemindersForProfile(idOffsetBase);

    final today = DateTime.now();
    final foodLogs = _foodLogsFromIntakeData(intakeData);
    final todayMealTypes = foodLogs.isEmpty
        ? await _loggedMealTypesForToday(profileUserId: activeProfileId)
        : _loggedMealTypesFromLogs(foodLogs);

    try {
      await _scheduleMealReminders(
        settings: settings,
        today: today,
        loggedMealTypesToday: todayMealTypes,
        idOffsetBase: idOffsetBase,
        payloadPrefix: payloadPrefix,
      );
      await _scheduleHydrationReminders(
        settings,
        patientName: patientName,
        idOffsetBase: idOffsetBase,
        payloadPrefix: payloadPrefix,
      );
      await _scheduleMedicationReminders(
        settings: settings,
        medications: medications,
        patientName: patientName,
        idOffsetBase: idOffsetBase,
        payloadPrefix: payloadPrefix,
      );
      await _scheduleStreakEndingReminder(
        gamification,
        idOffsetBase: idOffsetBase,
        payloadPrefix: payloadPrefix,
      );
    } catch (error) {
      debugPrint('[Notifications] Reminder scheduling failed: $error');
    }

    await prefs.setString(hashKey, scheduleHash);
    await _cacheSchedulePayload(
      user: user,
      medications: medications,
      intakeData: intakeData,
      gamification: gamification,
      profileIndex: profileIndex,
      profileUserId: activeProfileId,
    );
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

  static Future<void> _cleanupScheduledRemindersForProfile(int offset) async {
    await _cancelRange(_mealIdBase + offset, 40);
    await _cancelRange(_hydrationIdBase + offset, 40);
    await _cancelRange(
      _medicationIdBase + offset,
      _maxMedicationNotifications,
    );
    await _cancelRange(_streakIdBase + offset, 4);
  }

  static Future<bool> _hasPendingScheduledRemindersForProfile(int offset) async {
    final pending = await _localNotifications.pendingNotificationRequests();
    return pending.any((request) {
      final id = request.id;
      return _idInRange(id, _mealIdBase + offset, 40) ||
          _idInRange(id, _hydrationIdBase + offset, 40) ||
          _idInRange(
            id,
            _medicationIdBase + offset,
            _maxMedicationNotifications,
          ) ||
          _idInRange(id, _streakIdBase + offset, 4);
    });
  }

  static bool _idInRange(int id, int startId, int count) {
    return id >= startId && id < startId + count;
  }

  static Future<void> _cancelMedicationReminderRequests({
    required Map<String, dynamic>? medication,
    required String? profileUserId,
    required int idOffsetBase,
  }) async {
    if (medication == null || medication.isEmpty) return;
    final medicationKeys = _medicationPayloadKeys(medication);
    if (medicationKeys.isEmpty) return;
    final pending = await _localNotifications.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload ?? '';
      final isMedicationReminder = payload.contains(':medication:');
      final isProfileMatch = profileUserId == null ||
          profileUserId.isEmpty ||
          payload.contains(_stableKey(profileUserId));
      final isMedicationMatch =
          medicationKeys.any((key) => payload.contains(':$key:'));
      final isLegacyMedicationId = _idInRange(
        request.id,
        _medicationIdBase + idOffsetBase,
        _maxMedicationNotifications,
      );
      final isSingleMedicationId = _idInRange(
        request.id,
        _singleMedicationIdBase + idOffsetBase,
        _maxMedicationNotifications,
      );
      if (isMedicationReminder &&
          isProfileMatch &&
          isMedicationMatch &&
          (isLegacyMedicationId || isSingleMedicationId)) {
        await _localNotifications.cancel(request.id);
      }
    }
  }

  static Set<String> _medicationPayloadKeys(Map<String, dynamic> medication) {
    final keys = <String>{_stableKey(_medicationName(medication))};
    final medicationId =
        (medication['medicationId'] ?? medication['id'])?.toString();
    if (medicationId != null && medicationId.isNotEmpty) {
      keys.add(_stableKey(medicationId));
    }
    return keys.where((key) => key.isNotEmpty).toSet();
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
    required int idOffsetBase,
    required String payloadPrefix,
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

        final payload =
            '$payloadPrefix:meal:${entry.key}:${_dateKey(scheduled)}';
        if (await _isDismissed(payload)) continue;

        await _scheduleExact(
          id: _mealIdBase + idOffsetBase + idOffset++,
          title: '${time.label} reminder',
          body: 'Have you logged your ${entry.key} yet?',
          scheduled: scheduled,
          payload: payload,
        );
      }
    }
  }

  static Future<void> _scheduleHydrationReminders(
    Map<String, dynamic> settings, {
    required String? patientName,
    required int idOffsetBase,
    required String payloadPrefix,
  }) async {
    if (settings['hydrationAlerts'] != true) return;

    var idOffset = 0;
    final now = DateTime.now();
    for (var dayOffset = 0; dayOffset < _daysToScheduleAhead; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      for (var hour = 9; hour <= 21; hour += 2) {
        final scheduled = DateTime(day.year, day.month, day.day, hour);
        if (!scheduled.isAfter(now)) continue;
        final payload =
            '$payloadPrefix:hydration:${_dateKey(scheduled)}:${hour.toString().padLeft(2, '0')}00';
        if (await _isDismissed(payload)) continue;
        final title = patientName == null
            ? 'Hydration reminder'
            : 'Hydration reminder for $patientName!';
        await _scheduleExact(
          id: _hydrationIdBase + idOffsetBase + idOffset++,
          title: title,
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
    required String? patientName,
    required int idOffsetBase,
    required String payloadPrefix,
  }) async {
    if (settings['medicationReminders'] != true) return;

    var idOffset = 0;
    final now = DateTime.now();
    for (var dayOffset = 0; dayOffset < _daysToScheduleAhead; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      for (final medication in medications) {
        final name = _medicationName(medication);
        final takenTimesToday = medication['takenTimesToday'] is List
            ? (medication['takenTimesToday'] as List)
                .map((t) => t.toString())
                .toSet()
            : <String>{};

        for (final clockTime in _medicationTimes(medication)) {
          if (idOffset >= _maxMedicationNotifications) return;
          if (dayOffset == 0 && takenTimesToday.contains(clockTime)) continue;
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
          final medicationId =
              (medication['medicationId'] ?? medication['id'])?.toString();
          final medicationKey =
              medicationId == null || medicationId.isEmpty
                  ? medKey
                  : _stableKey(medicationId);
          final payload =
              '$payloadPrefix:medication:$medicationKey:$medKey:${_dateKey(scheduled)}:${parts.hour.toString().padLeft(2, '0')}${parts.minute.toString().padLeft(2, '0')}';
          if (await _isDismissed(payload)) continue;
          final title = patientName == null
              ? '$name reminder'
              : 'Medication reminder for $patientName!';
          await _scheduleExact(
            id: _medicationIdBase + idOffsetBase + idOffset++,
            title: title,
            body: patientName == null
                ? 'It is time to take $name.'
                : 'It is time for $patientName to take $name.',
            scheduled: scheduled,
            payload: payload,
          );
        }
      }
    }
  }

  static Future<void> _scheduleSingleMedicationReminder({
    required Map<String, dynamic> settings,
    required Map<String, dynamic> medication,
    required String? patientName,
    required int idOffsetBase,
    required String payloadPrefix,
  }) async {
    if (settings['medicationReminders'] != true) return;

    final name = _medicationName(medication);
    final takenTimesToday = medication['takenTimesToday'] is List
        ? (medication['takenTimesToday'] as List)
            .map((t) => t.toString())
            .toSet()
        : <String>{};

    final medicationId =
        (medication['medicationId'] ?? medication['id'])?.toString();
    final medicationKey = medicationId == null || medicationId.isEmpty
        ? _stableKey(name)
        : _stableKey(medicationId);
    final medKey = _stableKey(name);
    final baseOffset = _stableNotificationOffset(medicationKey);
    var idOffset = baseOffset;
    final now = DateTime.now();
    for (var dayOffset = 0; dayOffset < _daysToScheduleAhead; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      for (final clockTime in _medicationTimes(medication)) {
        if (idOffset >= baseOffset + _maxSingleMedicationNotifications) {
          return;
        }
        if (dayOffset == 0 && takenTimesToday.contains(clockTime)) continue;
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
        final payload =
            '$payloadPrefix:medication:$medicationKey:$medKey:${_dateKey(scheduled)}:${parts.hour.toString().padLeft(2, '0')}${parts.minute.toString().padLeft(2, '0')}';
        if (await _isDismissed(payload)) continue;
        final title = patientName == null
            ? '$name reminder'
            : 'Medication reminder for $patientName!';
        await _scheduleExact(
          id: _singleMedicationIdBase + idOffsetBase + idOffset++,
          title: title,
          body: patientName == null
              ? 'It is time to take $name.'
              : 'It is time for $patientName to take $name.',
          scheduled: scheduled,
          payload: payload,
        );
      }
    }
  }

  static Future<void> _scheduleStreakEndingReminder(
    Map<String, dynamic>? gamification, {
    required int idOffsetBase,
    required String payloadPrefix,
  }) async {
    if (!_shouldScheduleStreakReminder(gamification)) return;

    final now = DateTime.now();
    final scheduled = _nextStreakReminderTime(now);
    if (scheduled == null) return;

    final status = _asStringMap(gamification?['status']);
    final streak = _intValue(
      status['displayStreak'] ?? status['currentStreak'],
    );
    final missingItems = _missingStreakItems(gamification);
    final missingText = missingItems.isEmpty
        ? 'meals and hydration'
        : _joinReminderItems(missingItems);
    final payload = '$payloadPrefix:streak:${_dateKey(scheduled)}';
    if (await _isDismissed(payload)) return;

    await _scheduleExact(
      id: _streakIdBase + idOffsetBase,
      title: 'Streak reminder',
      body: streak >= 2
          ? 'Your $streak-day streak ends tonight. Log $missingText to keep it going.'
          : 'Your streak ends tonight. Log $missingText to keep it going.',
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
  }

  static _ReminderCopy _copyForPayload(String payload) {
    final parts = payload.split(':');
    final kindIndex = parts.indexWhere(
      (part) =>
          part == 'meal' ||
          part == 'hydration' ||
          part == 'medication' ||
          part == 'streak',
    );
    final kind = kindIndex >= 0 ? parts[kindIndex] : parts.first;
    if (kind == 'meal' && parts.length > kindIndex + 1) {
      final meal = parts[kindIndex + 1];
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
      final label = parts.length > kindIndex + 2
          ? parts[kindIndex + 2].replaceAll('_', ' ')
          : 'Medication';
      return _ReminderCopy(
        '$label reminder',
        parts.contains('pending_followup')
            ? 'Have you taken your medication? Don\'t forget to change the status as taken!'
            : 'Scheduled medication time.',
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

  static bool _isCaregiver(Map<String, dynamic> user) {
    final role = (user['role'] ?? user['userRole'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'caregiver' || role == 'parent_caregiver';
  }

  static List<String> _managedChildIds(Map<String, dynamic> caregiverState) {
    final children = caregiverState['linkedChildren'];
    if (children is! List) return const [];

    final ids = <String>[];
    for (final child in children) {
      if (child is! Map) continue;
      final id = (child['userId'] ?? child['uid'] ?? child['id'])?.toString();
      if (id == null || id.isEmpty || ids.contains(id)) continue;
      ids.add(id);
    }
    return ids;
  }

  static String _profilePayloadPrefix(String? profileUserId, String? name) {
    final key = profileUserId != null && profileUserId.isNotEmpty
        ? profileUserId
        : (name ?? 'self');
    return 'profile:${_stableKey(key)}';
  }

  static String _scheduleProfileKey(String? profileUserId, int profileIndex) {
    final userId = ApiService.userId ?? 'unknown_user';
    final profileKey = profileUserId != null && profileUserId.isNotEmpty
        ? profileUserId
        : 'profile_$profileIndex';
    return '$userId|$profileKey';
  }

  static String _scheduledHashKey(String? profileUserId, int profileIndex) {
    return '$_scheduledHashPrefix${_scheduleProfileKey(profileUserId, profileIndex)}';
  }

  static String _schedulePayloadKey(String? profileUserId, int profileIndex) {
    return '$_schedulePayloadPrefix${_scheduleProfileKey(profileUserId, profileIndex)}';
  }

  static Future<void> _cacheSchedulePayload({
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> medications,
    Map<String, dynamic>? intakeData,
    Map<String, dynamic>? gamification,
    required int profileIndex,
    String? profileUserId,
  }) async {
    final userId = ApiService.userId;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _schedulePayloadKey(profileUserId, profileIndex),
      jsonEncode({
        'user': user,
        'medications': medications,
        'intakeData': intakeData,
        'gamification': gamification,
        'profileIndex': profileIndex,
        'profileUserId': profileUserId,
      }),
    );
  }

  static String _reminderHash({
    required Map<String, dynamic> settings,
    required List<Map<String, dynamic>> medications,
    required String profileUserId,
  }) {
    final normalizedMedications = medications.map((medication) {
      return {
        'name': _medicationName(medication),
        'dose': medication['dose'] ??
            medication['dosage'] ??
            medication['medicationDose'] ??
            medication['medication_dose'] ??
            '',
        'times': _medicationTimes(medication),
        'status': medication['status'] ??
            medication['medicationStatus'] ??
            medication['medication_status'] ??
            '',
      };
    }).toList(growable: false);

    final normalized = {
      'activeProfileId': profileUserId,
      'timezone': tz.local.name,
      'date': _dateKey(DateTime.now()),
      'mealReminderSettings': _asStringMap(settings['mealReminders']),
      'hydrationSettings': {
        'enabled': settings['hydrationAlerts'] == true,
      },
      'medicationReminders': settings['medicationReminders'] == true,
      'medicationSchedules': normalizedMedications,
    };

    return _fnv1a(jsonEncode(_stableJsonValue(normalized)));
  }

  static bool _hasReminderWork({
    required Map<String, dynamic> settings,
    required List<Map<String, dynamic>> medications,
    required Map<String, dynamic>? gamification,
  }) {
    final mealSettings = _asStringMap(settings['mealReminders']);
    final hasMealReminder = mealSettings.values.any((value) => value == true);
    final hasHydrationReminder = settings['hydrationAlerts'] == true;
    final hasMedicationReminder = settings['medicationReminders'] == true &&
        medications.any(
          (medication) =>
              _isPendingMedication(medication) &&
              _medicationTimes(medication).isNotEmpty,
        );
    return hasMealReminder ||
        hasHydrationReminder ||
        hasMedicationReminder ||
        _shouldScheduleStreakReminder(gamification);
  }

  static dynamic _stableJsonValue(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      return {
        for (final key in sortedKeys) key: _stableJsonValue(value[key]),
      };
    }
    if (value is List) {
      return value.map(_stableJsonValue).toList(growable: false);
    }
    return value;
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static int _stableNotificationOffset(String input) {
    return int.parse(_fnv1a(input).substring(0, 6), radix: 16)
        .remainder(_maxMedicationNotifications - _maxSingleMedicationNotifications);
  }

  static List<Map<String, dynamic>> _foodLogsFromIntakeData(
    Map<String, dynamic>? intakeData,
  ) {
    final logs = intakeData?['foodLogs'] ?? intakeData?['food_logs'];
    return _asStringMapList(logs);
  }

  static Future<Set<String>> _loggedMealTypesForToday({
    String? profileUserId,
  }) async {
    try {
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final response = await ApiService.getFoodLogs(
        profileUserId: profileUserId ?? ApiService.selectedManagedChildProfileId,
        date: today,
      );
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
    if (_missingStreakItems(gamification).isEmpty) return false;

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
    final preferred = DateTime(now.year, now.month, now.day, 21);
    if (preferred.isAfter(now)) return preferred;

    final fallback = now.add(const Duration(minutes: 5));
    final cutoff = DateTime(now.year, now.month, now.day, 23, 30);
    if (fallback.isAfter(cutoff)) return null;
    return fallback;
  }

  static List<String> _missingStreakItems(Map<String, dynamic>? gamification) {
    final todayStatus = _asStringMap(gamification?['today']);
    if (todayStatus.isEmpty) return const [];

    final missing = <String>[];
    if (todayStatus['hasMorningMeal'] != true) missing.add('breakfast');
    if (todayStatus['hasLunchMeal'] != true) missing.add('lunch');
    if (todayStatus['hasDinnerMeal'] != true) missing.add('dinner');
    if (todayStatus['hasHydrationLog'] != true) missing.add('hydration');
    return missing;
  }

  static String _joinReminderItems(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items.first} and ${items.last}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
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

  static bool _isPendingMedication(Map<String, dynamic> medication) {
    final status = (medication['status'] ??
            medication['medicationStatus'] ??
            medication['medication_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return status.isEmpty || status == 'pending';
  }

  static String? _patientName(Map<String, dynamic> user) {
    final name = (user['childFullName'] ??
            user['childName'] ??
            user['displayName'] ??
            user['child_name'] ??
            user['fullName'] ??
            user['name'] ??
            '')
        .toString()
        .trim();
    if (name.isEmpty || name.toLowerCase() == 'there') return null;
    return name;
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
