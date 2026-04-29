import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  final String? profileUserId;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNotificationPermission();
    });
  }

  Future<void> _ensureNotificationPermission() async {
    if (_permissionChecked) return;
    _permissionChecked = true;

    final granted = await PushNotificationService.requestPermissionsIfNeeded();
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
  }

  Future<void> _saveReminderSettings({
    required bool medicationReminders,
    required bool hydrationAlerts,
    required bool breakfastReminder,
    required bool lunchReminder,
    required bool snackReminder,
    required bool dinnerReminder,
  }) async {
    final previousMedication = _medicationReminders;
    final previousHydration = _hydrationAlerts;
    final previousBreakfast = _breakfastReminders;
    final previousLunch = _lunchReminders;
    final previousSnack = _snackReminders;
    final previousDinner = _dinnerReminders;

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
      final response = await ApiService.updateReminderSettings(
        profileUserId: widget.profileUserId,
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _medicationReminders = previousMedication;
        _hydrationAlerts = previousHydration;
        _breakfastReminders = previousBreakfast;
        _lunchReminders = previousLunch;
        _snackReminders = previousSnack;
        _dinnerReminders = previousDinner;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update reminders: $error')),
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
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          final response =
                              await PushNotificationService
                                  .sendTestPushNotification();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                response['success'] == true
                                    ? 'Push test sent. Check your phone notification tray.'
                                    : (response['error']?.toString() ??
                                        'Unable to send push test.'),
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Send Test Notification'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00C874),
                    side: const BorderSide(color: Color(0xFF00C874)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
