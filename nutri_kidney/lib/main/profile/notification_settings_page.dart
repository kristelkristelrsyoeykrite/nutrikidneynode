import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  final String? profileUserId;
  final String? reminderSettingsProfileUserId;
  final bool canManageReminderSettings;
  final String reminderSettingsLockReason;
  final bool initialMedicationReminders;
  final bool initialHydrationAlerts;
  final bool initialBreakfastReminders;
  final bool initialLunchReminders;
  final bool initialSnackReminders;
  final bool initialDinnerReminders;
  final List<Map<String, dynamic>> medications;

  const NotificationSettingsPage({
    super.key,
    required this.profileUserId,
    this.reminderSettingsProfileUserId,
    required this.canManageReminderSettings,
    required this.reminderSettingsLockReason,
    required this.initialMedicationReminders,
    required this.initialHydrationAlerts,
    required this.initialBreakfastReminders,
    required this.initialLunchReminders,
    required this.initialSnackReminders,
    required this.initialDinnerReminders,
    required this.medications,
  });

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late bool _medicationReminders;
  late bool _hydrationAlerts;
  late bool _breakfastReminders;
  late bool _lunchReminders;
  late bool _snackReminders;
  late bool _dinnerReminders;
  bool _isSaving = false;
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    _medicationReminders = widget.initialMedicationReminders;
    _hydrationAlerts = widget.initialHydrationAlerts;
    _breakfastReminders = widget.initialBreakfastReminders;
    _lunchReminders = widget.initialLunchReminders;
    _snackReminders = widget.initialSnackReminders;
    _dinnerReminders = widget.initialDinnerReminders;
    _loadCachedReminderSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNotificationPermission();
    });
  }

  Future<void> _loadCachedReminderSettings() async {
    final cached = await NotificationService.cachedReminderSettings();
    if (!mounted || cached.isEmpty) return;
    final mealSettings = cached['mealReminders'];
    final meals = mealSettings is Map
        ? Map<String, dynamic>.from(mealSettings)
        : <String, dynamic>{};
    setState(() {
      if (cached.containsKey('medicationReminders')) {
        _medicationReminders = cached['medicationReminders'] == true;
      }
      if (cached.containsKey('hydrationAlerts')) {
        _hydrationAlerts = cached['hydrationAlerts'] == true;
      }
      if (meals.containsKey('breakfast')) {
        _breakfastReminders = meals['breakfast'] == true;
      }
      if (meals.containsKey('lunch')) {
        _lunchReminders = meals['lunch'] == true;
      }
      if (meals.containsKey('snack')) {
        _snackReminders = meals['snack'] == true;
      }
      if (meals.containsKey('dinner')) {
        _dinnerReminders = meals['dinner'] == true;
      }
    });
  }

  Future<void> _ensureNotificationPermission() async {
    if (_permissionChecked) return;
    _permissionChecked = true;

    final granted = await NotificationService.requestPermissionsIfNeeded();
    if (!mounted) return;

    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission was not granted. Phone notifications will stay off until permission is allowed.',
          ),
        ),
      );
    }

    await _promptForExactAlarmPermissionIfNeeded();
  }

  Future<void> _promptForExactAlarmPermissionIfNeeded() async {
    final exactAllowed = await NotificationService.canScheduleExactAlarms();
    if (!mounted || exactAllowed) return;

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Allow exact reminders?'),
          content: const Text(
            'Android needs a separate alarm permission so meal, hydration, and medication reminders can arrive on time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
              ),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await NotificationService.openExactAlarmSettings();
    }
  }

  Future<void> _syncVisibleReminderSettings() async {
    var medications = widget.medications;
    Map<String, dynamic>? responseUser;
    Map<String, dynamic>? intakeData;
    Map<String, dynamic>? gamification;

    try {
      final response = await ApiService.getDashboardSummary(
        profileUserId: widget.profileUserId,
      );
      if (response['success'] == true) {
        final dashboardMedications = response['medications'];
        final dashboardUser = response['user'];
        responseUser =
            dashboardUser is Map ? Map<String, dynamic>.from(dashboardUser) : null;
        if (_medicationReminders && dashboardMedications is List) {
          medications = dashboardMedications
              .whereType<Map>()
              .map((medication) => Map<String, dynamic>.from(medication))
              .toList(growable: false);
        }
        final dashboardIntakeData = response['intakeData'];
        final dashboardGamification = response['gamification'];
        intakeData = dashboardIntakeData is Map
            ? Map<String, dynamic>.from(dashboardIntakeData)
            : null;
        gamification = dashboardGamification is Map
            ? Map<String, dynamic>.from(dashboardGamification)
            : null;
      }
    } catch (error) {
      debugPrint('Unable to refresh dashboard data for reminders: $error');
    }

    return NotificationService.syncReminderNotifications(
      user: {
        if (responseUser != null) ...responseUser,
        'reminderSettings': {
          'medicationReminders': _medicationReminders,
          'hydrationAlerts': _hydrationAlerts,
          'mealReminders': {
            'breakfast': _breakfastReminders,
            'lunch': _lunchReminders,
            'snack': _snackReminders,
            'dinner': _dinnerReminders,
          },
        },
      },
      medications: medications,
      intakeData: intakeData,
      gamification: gamification,
    );
  }

  Future<void> _saveReminderSettings({
    required bool medicationReminders,
    required bool hydrationAlerts,
    required bool breakfastReminder,
    required bool lunchReminder,
    required bool snackReminder,
    required bool dinnerReminder,
  }) async {
    setState(() {
      _medicationReminders = medicationReminders;
      _hydrationAlerts = hydrationAlerts;
      _breakfastReminders = breakfastReminder;
      _lunchReminders = lunchReminder;
      _snackReminders = snackReminder;
      _dinnerReminders = dinnerReminder;
      _isSaving = true;
    });

    try {
      await NotificationService.replaceCachedReminderSettings(
        medicationReminders: medicationReminders,
        hydrationAlerts: hydrationAlerts,
        breakfastReminder: breakfastReminder,
        lunchReminder: lunchReminder,
        snackReminder: snackReminder,
        dinnerReminder: dinnerReminder,
      );

      final response = await ApiService.updateReminderSettings(
        profileUserId: widget.reminderSettingsProfileUserId,
        medicationReminders: medicationReminders,
        hydrationAlerts: hydrationAlerts,
        breakfastReminder: breakfastReminder,
        lunchReminder: lunchReminder,
        snackReminder: snackReminder,
        dinnerReminder: dinnerReminder,
      );

      if (!mounted) return;
      if (response["success"] != true) {
        throw Exception(
          response["error"]?.toString() ??
              'Unable to update reminder settings.',
        );
      }
      final savedSettings = response["reminderSettings"];
      if (savedSettings is Map) {
        await NotificationService.cacheReminderSettings(
          Map<String, dynamic>.from(savedSettings),
        );
      }
      await _syncVisibleReminderSettings();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminder setting saved on this device. Server sync failed: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showLockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.reminderSettingsLockReason)),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1ECE8)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF546E7A)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF37474F),
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                ),
              ),
        trailing: CupertinoSwitch(
          value: value,
          activeColor: const Color(0xFF00C874),
          onChanged: !widget.canManageReminderSettings || _isSaving
              ? null
              : onChanged,
        ),
        onTap: !widget.canManageReminderSettings ? _showLockedMessage : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.canManageReminderSettings)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Text(
                    widget.reminderSettingsLockReason,
                    style: const TextStyle(
                      color: Color(0xFF7A5C00),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              _buildSwitchTile(
                icon: Icons.free_breakfast_outlined,
                title: 'Breakfast Reminder',
                subtitle: 'Have you taken your breakfast?',
                value: _breakfastReminders,
                onChanged: (value) {
                  _saveReminderSettings(
                    medicationReminders: _medicationReminders,
                    hydrationAlerts: _hydrationAlerts,
                    breakfastReminder: value,
                    lunchReminder: _lunchReminders,
                    snackReminder: _snackReminders,
                    dinnerReminder: _dinnerReminders,
                  );
                },
              ),
              _buildSwitchTile(
                icon: Icons.lunch_dining_outlined,
                title: 'Lunch Reminder',
                subtitle: 'Have you taken your lunch?',
                value: _lunchReminders,
                onChanged: (value) {
                  _saveReminderSettings(
                    medicationReminders: _medicationReminders,
                    hydrationAlerts: _hydrationAlerts,
                    breakfastReminder: _breakfastReminders,
                    lunchReminder: value,
                    snackReminder: _snackReminders,
                    dinnerReminder: _dinnerReminders,
                  );
                },
              ),
              _buildSwitchTile(
                icon: Icons.icecream_outlined,
                title: 'Snack Reminder',
                subtitle: 'Have you taken your snack?',
                value: _snackReminders,
                onChanged: (value) {
                  _saveReminderSettings(
                    medicationReminders: _medicationReminders,
                    hydrationAlerts: _hydrationAlerts,
                    breakfastReminder: _breakfastReminders,
                    lunchReminder: _lunchReminders,
                    snackReminder: value,
                    dinnerReminder: _dinnerReminders,
                  );
                },
              ),
              _buildSwitchTile(
                icon: Icons.dinner_dining_outlined,
                title: 'Dinner Reminder',
                subtitle: 'Have you taken your dinner?',
                value: _dinnerReminders,
                onChanged: (value) {
                  _saveReminderSettings(
                    medicationReminders: _medicationReminders,
                    hydrationAlerts: _hydrationAlerts,
                    breakfastReminder: _breakfastReminders,
                    lunchReminder: _lunchReminders,
                    snackReminder: _snackReminders,
                    dinnerReminder: value,
                  );
                },
              ),
              _buildSwitchTile(
                icon: Icons.notifications_active_outlined,
                title: 'Medication Reminders',
                subtitle: 'Send reminders for scheduled medication times.',
                value: _medicationReminders,
                onChanged: (value) {
                  _saveReminderSettings(
                    medicationReminders: value,
                    hydrationAlerts: _hydrationAlerts,
                    breakfastReminder: _breakfastReminders,
                    lunchReminder: _lunchReminders,
                    snackReminder: _snackReminders,
                    dinnerReminder: _dinnerReminders,
                  );
                },
              ),
              _buildSwitchTile(
                icon: Icons.water_drop_outlined,
                title: 'Hydration Alerts',
                subtitle: 'Send hydration reminders during the day.',
                value: _hydrationAlerts,
                onChanged: (value) {
                  _saveReminderSettings(
                    medicationReminders: _medicationReminders,
                    hydrationAlerts: value,
                    breakfastReminder: _breakfastReminders,
                    lunchReminder: _lunchReminders,
                    snackReminder: _snackReminders,
                    dinnerReminder: _dinnerReminders,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
