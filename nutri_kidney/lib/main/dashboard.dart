import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nutri_kidney/create_account/profile_setup_intro.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:nutri_kidney/services/notification_service.dart';
import 'adolescent_dashboard.dart';
import 'caregiver_dashboard.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'health_metrics.dart';
import 'leaderboard_page.dart';
import 'profile.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentIndex = 0;
  bool _isLoadingDashboard = true;
  bool _dashboardRequestInFlight = false;
  String? _dashboardError;
  Map<String, dynamic> _viewer = {};
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _caregiverDashboardState = {};
  Map<String, dynamic> _nutritionTargets = {};
  Map<String, dynamic> _medicalProfile = {};
  Map<String, dynamic> _phase2DecisionSupport = {};
  Map<String, dynamic> _labResults = {};
  Map<String, dynamic> _anthropometrics = {};
  Map<String, dynamic>? _intakeData;
  Map<String, dynamic>? _medicationData;
  Map<String, dynamic> _gamification = {};
  List<Map<String, dynamic>> _medications = [];
  List<Map<String, dynamic>> _missedMedications = [];
  String? _selectedManagedChildId;
  static const Map<String, Map<String, int>> _mealReminderSchedule = {
    "breakfast": {"hour": 8, "minute": 0},
    "lunch": {"hour": 12, "minute": 0},
    "snack": {"hour": 15, "minute": 0},
    "dinner": {"hour": 18, "minute": 0},
  };

  static const double _defaultSodiumTargetMg = 1500;
  static const double _defaultPotassiumTargetMg = 2000;

  int get _medicationTotalCount {
    return _medications.length > 0
        ? _medications.length
        : (_numberFrom(
                  _medicationData?["totalActiveMedications"] ??
                      _medicationData?["count"],
                ) ??
                0)
            .toInt();
  }

  bool get _hasMedicationData => _medicationTotalCount > 0;
  bool get _hasNutritionData => _todayMealCount > 0;

  Map<String, dynamic> get _reminderSettings {
    if (_isCaregiverViewer) {
      final viewerSettings = _viewer["reminderSettings"];
      if (viewerSettings is Map<String, dynamic>) return viewerSettings;
      if (viewerSettings is Map) {
        return viewerSettings.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    final settings = _user["reminderSettings"];
    if (settings is Map<String, dynamic>) return settings;
    if (settings is Map) {
      return settings.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  Map<String, dynamic> get _mealReminderSettings {
    final settings = _reminderSettings["mealReminders"];
    if (settings is Map<String, dynamic>) return settings;
    if (settings is Map) {
      return settings.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardSummary(
      profileUserId: ApiService.selectedManagedChildProfileId,
    );
  }

  Future<void> _loadDashboardSummary({
    String? profileUserId,
    bool forceRefresh = false,
  }) async {
    if (_dashboardRequestInFlight) return;
    _dashboardRequestInFlight = true;
    try {
      final response = await ApiService.getDashboardSummary(
        profileUserId: profileUserId,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      if (response["success"] != true) {
        throw Exception(response["error"] ?? "Failed to load dashboard");
      }

      String? selectedManagedId;
      String? responseOwnerId;
      setState(() {
        _viewer = _asStringMap(response["viewer"]);
        _user = _asStringMap(response["user"]);
        _caregiverDashboardState = _asStringMap(
          response["caregiverDashboardState"],
        );
        _nutritionTargets = _asStringMap(response["nutritionTargets"]);
        _medicalProfile = _asStringMap(response["medicalProfile"]);
        _phase2DecisionSupport = _asStringMap(response["phase2DecisionSupport"]);
        _labResults = _asStringMap(response["labResults"]);
        _anthropometrics = _asStringMap(response["anthropometrics"]);
        _intakeData = _nullableStringMap(response["intakeData"]);
        _gamification = _asStringMap(response["gamification"]);
        _medicationData = _nullableStringMap(response["medicationData"]);
        _medications = _asStringMapList(response["medications"]);
        responseOwnerId = response["dashboardOwnerId"]?.toString();
        if (_isCaregiverViewer) {
          final children = _managedChildren;
          final childIds = children
              .map((child) => child["id"])
              .whereType<String>()
              .toSet();
          final activeDirectChildId =
              _caregiverDashboardState["activeDirectChildProfileId"]
                  ?.toString();
          final restoredId =
              profileUserId ?? ApiService.selectedManagedChildProfileId;
          final candidates = [
            restoredId,
            responseOwnerId,
            activeDirectChildId,
            if (children.isNotEmpty) children.first["id"],
          ];
          selectedManagedId = candidates.firstWhere(
            (id) => id != null && childIds.contains(id),
            orElse: () => null,
          );
          if (selectedManagedId != null) {
            _selectedManagedChildId = selectedManagedId;
            ApiService.setSelectedManagedChildProfileId(selectedManagedId);
          } else {
            _selectedManagedChildId = null;
            ApiService.setSelectedManagedChildProfileId(null);
          }
        }
        _isLoadingDashboard = false;
        _dashboardError = null;
      });
      if (_isCaregiverViewer &&
          profileUserId == null &&
          selectedManagedId != null &&
          selectedManagedId != responseOwnerId) {
        if (!mounted) return;
        setState(() {
          _isLoadingDashboard = true;
          _dashboardError = null;
        });
        _dashboardRequestInFlight = false;
        await _loadDashboardSummary(
          profileUserId: selectedManagedId,
          forceRefresh: true,
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingDashboard = false;
        _dashboardError = e.toString();
      });
    } finally {
      _dashboardRequestInFlight = false;
      // Load missed medication reminders
      await _loadMissedMedicationReminders();
    }
  }

  Future<void> _loadMissedMedicationReminders() async {
    try {
      final targetUserId =
          _selectedManagedProfileUserId ??
          _user["id"]?.toString() ??
          _user["uid"]?.toString() ??
          ApiService.userId;
      if (targetUserId == null || targetUserId.isEmpty) return;

      final response = await ApiService.getMissedMedicationReminders(
        profileUserId: targetUserId,
        limit: 20,
      );
      if (response["success"] != true) {
        throw Exception(
          response["error"] ?? "Failed to load missed medication reminders",
        );
      }

      if (!mounted) return;

      final reminders = response["reminders"];
      final missedMedications = (reminders is List ? reminders : const [])
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
          .toList()
        ..sort(
          (a, b) =>
              _dateTimeFrom(b["timestamp"]).compareTo(_dateTimeFrom(a["timestamp"])),
        );

      setState(() {
        _missedMedications = missedMedications.take(10).toList();
      });
    } catch (e) {
      debugPrint("Error loading missed medications: $e");
    }
  }

  Future<void> _selectManagedChild(String? childId) async {
    if (childId == null || childId == _selectedManagedChildId) return;
    setState(() {
      _selectedManagedChildId = childId;
      _isLoadingDashboard = true;
      _dashboardError = null;
    });
    ApiService.setSelectedManagedChildProfileId(childId);
    await _loadDashboardSummary(profileUserId: childId);
  }

  Future<void> _openFoodLogAndRefresh() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FoodLogPage(
          profileUserId: _selectedManagedProfileUserId,
          caregiverNoChildEmptyState:
              _isCaregiverViewer && _managedChildren.isEmpty,
        ),
      ),
    );
    if (!mounted) return;
    await _loadDashboardSummary(
      profileUserId: _selectedManagedProfileUserId,
    );
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  Map<String, dynamic>? _nullableStringMap(dynamic value) {
    final map = _asStringMap(value);
    return map.isEmpty ? null : map;
  }

  List<Map<String, dynamic>> _asStringMapList(dynamic value) {
    if (value is! List) return [];
    return value.map(_asStringMap).where((map) => map.isNotEmpty).toList();
  }

  double? _numberFrom(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  String _formatNumber(double value, {int decimals = 0}) {
    final rounded = value.toStringAsFixed(decimals);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }

  String _optionalText(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  String _normalizedText(dynamic value) {
    return _optionalText(value).toLowerCase().trim().replaceAll('_', ' ');
  }

  double? _sodiumTargetFromMedicalProfile() {
    final ckdType = _normalizedText(
      _medicalProfile["ckdType"] ??
          _medicalProfile["ckd_type"] ??
          _medicalProfile["kidneyDiseaseType"] ??
          _medicalProfile["kidney_disease_type"] ??
          _medicalProfile["kidneyType"],
    );
    final ckdStage = _normalizedText(
      _medicalProfile["ckdStage"] ?? _medicalProfile["ckd_stage"],
    );

    if (ckdType == "ckd dkd" || ckdType == "dkd") return 3000;
    if (ckdStage == "stage 5d" || ckdStage == "ckd 5d" || ckdStage == "5d") {
      return 2300;
    }
    return 2000;
  }

  DateTime _dateTimeFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  String _medicationName(Map<String, dynamic> medication) {
    final name = _optionalText(
      medication["name"] ??
          medication["medicationName"] ??
          medication["medication_name"],
    );
    return name.isEmpty ? "Medication" : name;
  }

  List<String> _medicationTimes(Map<String, dynamic> medication) {
    final scheduledTimes = medication["scheduled_times"];
    if (scheduledTimes is List && scheduledTimes.isNotEmpty) {
      return scheduledTimes
          .map((time) => time.toString().trim())
          .where((time) => time.isNotEmpty)
          .toList();
    }

    final startTime = _optionalText(medication["start_time"]);
    if (RegExp(r"^\d{1,2}:\d{2}$").hasMatch(startTime)) {
      return [startTime];
    }

    return [];
  }

  DateTime? _dateTimeForMedicationTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  String _formatDoseTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDoseTimeLabel(String time) {
    final scheduled = _dateTimeForMedicationTime(time);
    return scheduled == null ? time : _formatClockTime(scheduled);
  }

  String _missedMedicationMessage(Map<String, dynamic> missed) {
    final fallback = missed["body"] ?? "You missed your medication reminder.";
    final message = fallback.toString();
    final scheduledTime = missed["scheduledTime"]?.toString();
    if (scheduledTime == null || scheduledTime.trim().isEmpty) return message;

    final displayTime = _formatDoseTimeLabel(scheduledTime);
    return message.replaceAll(scheduledTime, displayTime);
  }

  int _missedMedicationCountFromSummary() {
    var count = 0;
    for (final medication in _medications) {
      final doseWindow =
          medication["doseWindow"] is Map ? Map<String, dynamic>.from(medication["doseWindow"]) : null;
      final windowStatus = doseWindow?["status"]?.toString().trim().toLowerCase();
      if (windowStatus == "missed") {
        count += 1;
        continue;
      }

      final missedCount =
          int.tryParse(medication["missedCountToday"]?.toString() ?? "") ?? 0;
      if (missedCount > 0) {
        count += missedCount;
        continue;
      }

      final status = _optionalText(medication["status"]).toLowerCase();
      if (medication["isMissed"] == true || status == "missed") {
        count += 1;
      }
    }
    return count;
  }

  List<Map<String, dynamic>> get _missedMedicationReminders {
    return _missedMedications
        .map((missed) => {
              "kind": "missed_medication",
              "id": missed["medicationId"] ?? missed["id"],
              "notificationId": missed["id"],
              "name": "Missed Medication",
              "message": _missedMedicationMessage(missed),
              "time": _dateTimeFrom(missed["dueTime"] ?? missed["timestamp"]),
              "scheduledTime": missed["scheduledTime"],
              "expectedDate": missed["day"] ?? missed["date"],
              "isMissed": true,
              "color": "red",
            })
        .toList();
  }

  Map<String, dynamic>? get _nextMedicationReminder {
    Map<String, dynamic>? nextReminder;
    DateTime? nextTime;

    for (final medication in _medications) {
      for (final time in _medicationTimes(medication)) {
        final scheduled = _dateTimeForMedicationTime(time);
        if (scheduled == null) continue;
        if (nextTime == null || scheduled.isBefore(nextTime)) {
          nextTime = scheduled;
          nextReminder = {
            "id": medication["id"]?.toString(),
            "name": _medicationName(medication),
            "time": scheduled,
          };
        }
      }
    }

    return nextReminder;
  }

  Future<void> _promptMarkMedicationTaken(Map<String, dynamic> reminder) async {
    final medicationId = reminder["id"]?.toString();
    final dateTime = reminder["time"] as DateTime?;
    final scheduledTime = reminder["scheduledTime"]?.toString();
    final expectedDate = reminder["expectedDate"]?.toString();
    if (medicationId == null || medicationId.isEmpty || dateTime == null) return;

    final doseTime = scheduledTime != null && scheduledTime.isNotEmpty
        ? scheduledTime
        : _formatDoseTime(dateTime);
    final doseTimeLabel = _formatDoseTimeLabel(doseTime);

    final didConfirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder["name"]?.toString() ?? "Medication",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF37474F),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Dose time: $doseTimeLabel',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF78909C),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Mark as taken'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (didConfirm != true) return;

    try {
      await ApiService.markMedicationTaken(
        medicationId,
        time: doseTime,
        expectedDate: expectedDate,
        profileUserId: _selectedManagedProfileUserId,
      );
      if (!mounted) return;
      await _loadDashboardSummary(profileUserId: _selectedManagedProfileUserId, forceRefresh: true);
    } catch (e) {
      debugPrint("Error marking medication taken: $e");
    }
  }

  DateTime _nextScheduledTime(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  List<Map<String, dynamic>> get _mealReminderItems {
    final items = <Map<String, dynamic>>[];
    final labels = {
      "breakfast": "Breakfast",
      "lunch": "Lunch",
      "snack": "Snack",
      "dinner": "Dinner",
    };

    for (final entry in _mealReminderSchedule.entries) {
      if (_mealReminderSettings[entry.key] != true) continue;
      final schedule = entry.value;
      items.add({
        "kind": "meal",
        "name": "${labels[entry.key]} reminder",
        "message": "Have you taken your ${entry.key} yet?",
        "time": _nextScheduledTime(
          schedule["hour"] ?? 0,
          schedule["minute"] ?? 0,
        ),
      });
    }

    return items;
  }

  Map<String, dynamic>? get _hydrationReminder {
    if (_reminderSettings["hydrationAlerts"] != true) return null;
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    return {
      "kind": "hydration",
      "name": "Hydration reminder",
      "message": "Drink water and stay within today\'s fluid goal.",
      "time": nextHour,
    };
  }

  Map<String, dynamic>? get _streakEndingReminder {
    if (!_isStreakAtRisk) return null;
    final scheduled = _nextStreakReminderTime(DateTime.now());
    if (scheduled == null) return null;
    final missingText = _joinReminderItems(_missingStreakItems);
    return {
      "kind": "streak",
      "name": "Streak reminder",
      "message":
          "Your $_currentLoggingStreak-day streak ends tonight. Log $missingText to keep it going.",
      "time": scheduled,
    };
  }

  List<Map<String, dynamic>> get _dashboardReminders {
    final items = <Map<String, dynamic>>[];
    
    // Add missed medication reminders first (highest priority)
    items.addAll(_missedMedicationReminders);
    
    items.addAll(_mealReminderItems);
    if (_reminderSettings["medicationReminders"] == true) {
      final medication = _nextMedicationReminder;
      if (medication != null) {
        items.add({
          "kind": "medication",
          "name": "${medication["name"]} reminder",
          "message":
              "Scheduled at ${_formatClockTime(medication["time"] as DateTime)}.",
          "time": medication["time"],
        });
      }
    }
    final hydration = _hydrationReminder;
    if (hydration != null) {
      items.add(hydration);
    }
    final streak = _streakEndingReminder;
    if (streak != null) {
      items.add(streak);
    }
    items.sort(
      (a, b) => (a["time"] as DateTime).compareTo(b["time"] as DateTime),
    );
    return items;
  }

  Map<String, dynamic>? get _nextDashboardReminder {
    final items = _dashboardReminders;
    return items.isEmpty ? null : items.first;
  }

  String _formatClockTime(DateTime dateTime) {
    final hour12 = dateTime.hour == 0
        ? 12
        : dateTime.hour > 12
            ? dateTime.hour - 12
            : dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  String _relativeReminderText(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    if (difference.isNegative) {
      final elapsed = now.difference(dateTime);
      if (elapsed.inDays >= 1) return 'Missed ${elapsed.inDays}d ago';
      if (elapsed.inHours >= 1) return 'Missed ${elapsed.inHours}h ago';
      return 'Missed';
    }
    if (difference.inDays >= 1) return 'Tomorrow';
    if (difference.inHours >= 1) return 'In ${difference.inHours} hours';
    final minutes = difference.inMinutes <= 0 ? 1 : difference.inMinutes;
    return 'In $minutes minutes';
  }

  String get _childName {
    return (_user["childFullName"] ??
            _user["child_name"] ??
            _nutritionTargets["child_name"] ??
            "there")
        .toString();
  }

  bool get _isCaregiverViewer {
    final role = (_viewer["role"] ?? _user["role"] ?? "").toString().toLowerCase();
    return role == "parent_caregiver" || role == "caregiver";
  }

  bool get _isPendingCaregiverLinkFlow {
    if (!_isCaregiverViewer) return false;
    if (_hasCaregiverManagedProfile) return false;
    return _caregiverDashboardState["linkedChildAccount"] != true;
  }

  bool get _hasCaregiverManagedProfile {
    if (!_isCaregiverViewer) return false;

    final linkedChildren = _caregiverDashboardState["linkedChildren"];
    if (linkedChildren is List && linkedChildren.isNotEmpty) return true;

    final childAgeGroup = _caregiverDashboardState["childAgeGroup"]?.toString();
    final hasDirectProfile = childAgeGroup == "5-12" ||
        childAgeGroup == "5-13" ||
        childAgeGroup == "13-18-direct";
    final hasLegacyLinkedChild =
        (_caregiverDashboardState["linkedChildUserId"]?.toString() ?? "")
            .isNotEmpty;

    return hasDirectProfile || hasLegacyLinkedChild;
  }

  String get _viewerRoleLabel {
    final role = (_viewer["role"] ?? _user["role"] ?? "").toString().toLowerCase();
    if (role == "caregiver" || role == "parent_caregiver") {
      return "Caregiver";
    }
    if (role == "adolescent") {
      return "Adolescent";
    }
    return "Account";
  }

  bool get _isAdolescentViewer {
    final role = (_viewer["role"] ?? _user["role"] ?? "").toString().toLowerCase();
    return role == "adolescent";
  }

  List<Map<String, String>> get _managedChildren {
    final linkedChildren = _caregiverDashboardState["linkedChildren"];
    if (linkedChildren is List) {
      final children = linkedChildren
          .whereType<Map>()
          .map((child) {
            final id = (child["id"] ?? child["uid"] ?? child["userId"])
                ?.toString();
            final name = (child["childFullName"] ??
                    child["fullName"] ??
                    child["name"])
                ?.toString();
            if (id == null || id.isEmpty || name == null || name.isEmpty) {
              return null;
            }
            return {"id": id, "name": name};
          })
          .whereType<Map<String, String>>()
          .toList(growable: false);
      if (children.isNotEmpty) return children;
    }

    if (_isCaregiverViewer && !_isPendingCaregiverLinkFlow && _childName != "there") {
      return [
        {
          "id": (_user["id"] ?? _user["uid"] ?? "current-child").toString(),
          "name": _childName,
        },
      ];
    }

    return const [];
  }

  String? get _selectedManagedProfileUserId {
    if (!_isCaregiverViewer) return null;
    final children = _managedChildren;
    if (children.isEmpty) return null;
    final selectedId = _selectedManagedChildId;
    if (selectedId != null &&
        children.any((child) => child["id"] == selectedId)) {
      return selectedId;
    }
    return children.first["id"];
  }

  Future<void> _generateCaregiverLinkCode() async {
    try {
      final response = await ApiService.generateCaregiverLinkCode();
      if (!mounted) return;

      if (response["success"] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ??
                  "Unable to generate a linking code right now.",
            ),
          ),
        );
        return;
      }

      final code = response["code"]?.toString() ?? "";
      final expiresAt = response["expiresAt"]?.toString() ?? "";

      await _loadDashboardSummary();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Caregiver Linking Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share this code with your child so they can link their adolescent account.',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2FBF7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD7ECE5)),
                  ),
                  child: Text(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Color(0xFF009688),
                    ),
                  ),
                ),
                if (expiresAt.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Expires: $expiresAt',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF78909C),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate a linking code: $error')),
      );
    }
  }

  Future<void> _showAddChildDialog() async {
    final managedChildren = _managedChildren;
    if (managedChildren.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A caregiver account can manage up to 3 profiles.'),
        ),
      );
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('How would you like to add another child?'),
          content: const Text(
            'You can add a younger child profile, link an adolescent account, or manage an adolescent directly in this caregiver account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('link_adolescent'),
              child: const Text('Link Existing Account'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('child_profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Child Profile'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;

    if (choice == 'link_adolescent') {
      await _generateCaregiverLinkCode();
      return;
    }

    await _startChildProfileSetup('5-12');
  }

  Future<void> _startChildProfileSetup(String childAgeGroup) async {
    try {
      final response = await ApiService.saveCaregiverChildAgeGroup(
        childAgeGroup: childAgeGroup,
      );
      if (!mounted) return;
      if (response["success"] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ??
                  'Unable to start profile setup right now.',
            ),
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ProfileSetupIntroScreen(
            isChildProfileSetup: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add child: $error')),
      );
    }
  }

  String get _childInitials {
    final parts = _childName
        .trim()
        .split(RegExp(r"\s+"))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty || _childName == "there") return "NK";
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return "${parts.first[0]}${parts.last[0]}".toUpperCase();
  }

  double get _sodiumTargetMg {
    return _numberFrom(
          _nutritionTargets["sodium_target_mg"] ??
              _nutritionTargets["sodiumTargetMg"],
        ) ??
        _sodiumTargetFromMedicalProfile() ??
        _defaultSodiumTargetMg;
  }

  double get _potassiumTargetMg {
    return _numberFrom(
          _nutritionTargets["potassium_target_mg"] ??
              _nutritionTargets["potassiumTargetMg"],
        ) ??
        _defaultPotassiumTargetMg;
  }

  double get _proteinTargetG {
    return _numberFrom(
          _nutritionTargets["protein_target_g"] ??
              _nutritionTargets["proteinTargetG"],
        ) ??
        0;
  }

  double get _phosphorusTargetMg {
    return _numberFrom(
          _nutritionTargets["phosphate_target_mg"] ??
              _nutritionTargets["phosphateTargetMg"] ??
              _nutritionTargets["phosphorus_target_mg"] ??
              _nutritionTargets["phosphorusTargetMg"],
        ) ??
        0;
  }

  Map<String, dynamic> get _todayNutritionTotals {
    final totals = _intakeData?["totals"];
    return _asStringMap(totals);
  }

  double get _todayCalories =>
      _numberFrom(_todayNutritionTotals["calories"]) ?? 0;
  double get _todaySodiumMg =>
      _numberFrom(_todayNutritionTotals["sodium"]) ?? 0;
  double get _todayPotassiumMg =>
      _numberFrom(_todayNutritionTotals["potassium"]) ?? 0;
  double get _todayProteinG =>
      _numberFrom(_todayNutritionTotals["protein"]) ?? 0;
  double get _todayPhosphorusMg =>
      _numberFrom(_todayNutritionTotals["phosphorus"]) ?? 0;

  int get _todayMealCount =>
      (_numberFrom(_intakeData?["mealCount"] ?? _intakeData?["meal_count"]) ??
              0)
          .toInt();

  double get _todayWaterMl {
    // First try to get water data from backend response
    final waterMl = _numberFrom(
      _intakeData?["waterMl"] ??
          _intakeData?["water_ml"] ??
          _intakeData?["fluid_ml"],
    );
    if (waterMl != null && waterMl > 0) {
      return waterMl;
    }
    
    // Fallback: calculate from food logs if available
    try {
      final foodLogs = _intakeData?["foodLogs"];
      if (foodLogs is List) {
        int totalWaterMl = 0;
        for (final log in foodLogs) {
          if (log is Map) {
            final name = log['name']?.toString().toLowerCase() ?? '';
            final portion = log['portion']?.toString() ?? '';
            
            if (name == 'water') {
              // Extract ML from portion string like "250 mL"
              final regex = RegExp(r'(\d+(?:\.\d+)?)');
              final match = regex.firstMatch(portion);
              if (match != null) {
                totalWaterMl += int.tryParse(match.group(1) ?? '0') ?? 0;
              }
            }
          }
        }
        return totalWaterMl.toDouble();
      }
    } catch (_) {
      // If parsing fails, just return 0
    }
    
    return waterMl ?? 0;
  }

  double get _todayWaterLiters => _todayWaterMl / 1000;

  bool get _hasHydrationLogged => _todayWaterMl > 0;

  Map<String, dynamic> get _gamificationStatus =>
      _asStringMap(_gamification["status"]);

  Map<String, dynamic> get _todayLogStatus =>
      _asStringMap(_gamification["today"]);

  int get _currentLoggingStreak =>
      (_numberFrom(_gamificationStatus["displayStreak"] ??
                  _gamificationStatus["currentStreak"]) ??
              0)
          .toInt();

  int get _longestLoggingStreak =>
      (_numberFrom(_gamificationStatus["longestStreak"]) ?? 0).toInt();

  bool _todayStatusFlag(String key) => _todayLogStatus[key] == true;

  bool get _isStreakAtRisk {
    if (_currentLoggingStreak < 2) return false;
    if (_todayLogStatus["isCompleteDay"] == true) return false;
    if (_missingStreakItems.isEmpty) return false;

    final lastCompleteLogDate =
        _gamificationStatus["lastCompleteLogDate"]?.toString() ?? "";
    if (lastCompleteLogDate.isEmpty) return false;

    final now = DateTime.now();
    return lastCompleteLogDate == _dateKey(now) ||
        lastCompleteLogDate == _dateKey(now.subtract(const Duration(days: 1)));
  }

  DateTime? _nextStreakReminderTime(DateTime now) {
    final preferred = DateTime(now.year, now.month, now.day, 21);
    if (preferred.isAfter(now)) return preferred;

    final fallback = now.add(const Duration(minutes: 5));
    final cutoff = DateTime(now.year, now.month, now.day, 23, 30);
    if (fallback.isAfter(cutoff)) return null;
    return fallback;
  }

  List<String> get _missingStreakItems {
    if (_todayLogStatus.isEmpty) return const [];

    final missing = <String>[];
    if (_todayStatusFlag("hasMorningMeal") != true) missing.add("breakfast");
    if (_todayStatusFlag("hasLunchMeal") != true) missing.add("lunch");
    if (_todayStatusFlag("hasDinnerMeal") != true) missing.add("dinner");
    if (_todayStatusFlag("hasHydrationLog") != true) missing.add("hydration");
    return missing;
  }

  String _joinReminderItems(List<String> items) {
    if (items.isEmpty) return "meals and hydration";
    if (items.length == 1) return items.first;
    if (items.length == 2) return "${items.first} and ${items.last}";
    return "${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}";
  }

  String _dateKey(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  double _progressFor(double value, double target) {
    if (target <= 0) return 0;
    return (value / target).clamp(0, 1).toDouble();
  }

  bool get _hasFluidRestriction {
    final status = (_medicalProfile["fluidRestrictionStatus"] ??
            _medicalProfile["fluid_restriction_status"] ??
            _nutritionTargets["fluidRestrictionStatus"] ??
            _nutritionTargets["fluid_restriction_status"] ??
            _phase2DecisionSupport["fluidRestrictionStatus"] ??
            _phase2DecisionSupport["fluid_restriction_status"])
        ?.toString()
        .trim()
        .toLowerCase();
    return status == "yes";
  }

  double? get _fluidLimitMl {
    return _numberFrom(
      _medicalProfile["fluidLimitMl"] ??
          _medicalProfile["fluid_limit_ml"] ??
          _nutritionTargets["fluidLimitMl"] ??
          _nutritionTargets["fluid_limit_ml"] ??
          _nutritionTargets["dailyFluidLimitMl"] ??
          _nutritionTargets["daily_fluid_limit_ml"] ??
          _phase2DecisionSupport["fluidLimitMl"] ??
          _phase2DecisionSupport["fluid_limit_ml"] ??
          _phase2DecisionSupport["dailyFluidLimitMl"] ??
          _phase2DecisionSupport["daily_fluid_limit_ml"],
    );
  }

  double? get _fluidTargetLiters {
    final limitMl = _fluidLimitMl;
    if (!_hasFluidRestriction || limitMl == null) return null;
    return limitMl / 1000;
  }

  // --- NEW: Notifications Pop-up Logic ---
  void _showNotificationsPanel() {
    final reminders = _dashboardReminders;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF9FBFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Color(0xFF90A4AE),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Notification Items
              if (reminders.isNotEmpty)
                ...reminders.take(5).map((reminder) {
                  final kind = reminder["kind"]?.toString() ?? "";
                  final reminderTime = reminder["time"] as DateTime;
                  return _buildNotificationItem(
                    icon: kind == "meal"
                        ? Icons.restaurant_outlined
                        : kind == "hydration"
                            ? Icons.water_drop_outlined
                            : kind == "streak"
                                ? Icons.local_fire_department_outlined
                                : kind == "missed_medication"
                                    ? Icons.warning_outlined
                                : Icons.medication_outlined,
                    color: kind == "meal"
                        ? const Color(0xFFFFB74D)
                        : kind == "hydration"
                            ? const Color(0xFF64B5F6)
                            : kind == "streak"
                                ? const Color(0xFFFF7043)
                                : kind == "missed_medication"
                                    ? const Color(0xFFD32F2F)
                                : const Color(0xFF9E86FF),
                    title: reminder["name"]?.toString() ?? "Reminder",
                    message: reminder["message"]?.toString() ?? "",
                    time: _relativeReminderText(reminderTime),
                  );
                })
              else
                _buildNotificationItem(
                  icon: Icons.notifications_none,
                  color: const Color(0xFF90A4AE),
                  title: 'No reminders enabled',
                  message:
                      'Turn on meal, medication, or hydration reminders from Profile settings.',
                  time: 'Today',
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: SafeArea(
        child: _isLoadingDashboard
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C874)),
              )
            : _isPendingCaregiverLinkFlow
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_dashboardError != null) ...[
                          _buildDashboardErrorCard(),
                          const SizedBox(height: 16),
                        ],
                        CaregiverPendingDashboard(
                          caregiverName: (_viewer["fullName"] ??
                                  _viewer["name"] ??
                                  "Caregiver")
                              .toString(),
                          roleLabel: _viewerRoleLabel,
                          onAddChildProfile: () =>
                              _startChildProfileSetup('5-12'),
                          onLinkExistingAccount: _generateCaregiverLinkCode,
                        ),
                      ],
                    ),
                  )
                : _isAdolescentViewer
                    ? AdolescentDashboardContent(
                        children: _buildStandardDashboardChildren(),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildStandardDashboardChildren(),
                        ),
                      ),
      ),
      // --- Bottom Navigation Bar ---
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => FoodLogPage(
                    profileUserId: _selectedManagedProfileUserId,
                    caregiverNoChildEmptyState:
                        _isCaregiverViewer && _managedChildren.isEmpty,
                  ),
                ),
              );
            } else if (index == 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AnalyticsPage(
                    profileUserId: _selectedManagedProfileUserId,
                    caregiverNoChildEmptyState:
                        _isCaregiverViewer && _managedChildren.isEmpty,
                  ),
                ),
              );
            } else if (index == 3) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => HealthMetricsPage(
                    profileUserId: _selectedManagedProfileUserId,
                    caregiverNoChildEmptyState:
                        _isCaregiverViewer && _managedChildren.isEmpty,
                  ),
                ),
              );
            } else if (index == 4) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfilePage(
                    profileUserId: _selectedManagedProfileUserId,
                    caregiverNoChildEmptyState:
                        _isCaregiverViewer && _managedChildren.isEmpty,
                  ),
                ),
              );
            } else {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF00C874),
          unselectedItemColor: const Color(0xFFB0BEC5),
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu),
              label: 'Food',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border),
              label: 'Health',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStandardDashboardChildren() {
    return [
      if (_dashboardError != null) ...[
        _buildDashboardErrorCard(),
        const SizedBox(height: 16),
      ],
      _buildHeader(),
      const SizedBox(height: 24),
      _buildStreakCard(),
      const SizedBox(height: 16),
      _buildMetricsRow(),
      const SizedBox(height: 16),
      _buildNutritionCard(),
      const SizedBox(height: 16),
      _buildAlertCard(),
      const SizedBox(height: 16),
      _buildQuickActionsCard(),
      const SizedBox(height: 16),
      _buildUpcomingCard(),
      const SizedBox(height: 40),
    ];
  }

  // --- 1. Header Area ---
  Widget _buildDashboardErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Text(
        "Dashboard data could not be loaded: $_dashboardError",
        style: const TextStyle(
          color: Color(0xFF78909C),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildManagedChildSelector() {
    final children = _managedChildren;
    if (!_isCaregiverViewer || children.isEmpty) {
      return const SizedBox.shrink();
    }

    return CaregiverManagedChildSelector(
      children: children,
      selectedChildId: _selectedManagedChildId,
      onChanged: _selectManagedChild,
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(
                  profileUserId: _selectedManagedProfileUserId,
                  caregiverNoChildEmptyState:
                      _isCaregiverViewer && _managedChildren.isEmpty,
                ),
              ),
            );
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFD5F5E3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _childInitials,
                style: const TextStyle(
                  color: Color(0xFF009688),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome!',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
              ),
              if (_isCaregiverViewer && _managedChildren.isNotEmpty)
                _buildManagedChildSelector()
              else
                Text(
                  _childName,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7F1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_viewerRoleLabel Dashboard',
                  style: const TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // --- UPDATED: Clickable Notifications Icon ---
        GestureDetector(
          onTap: _showNotificationsPanel,
          child: const Icon(
            Icons.notifications_none,
            color: Color(0xFF37474F),
            size: 28,
          ),
        ),
      ],
    );
  }

  // --- 2. Daily Logging Card ---
  Widget _buildStreakCard() {
    final hasMorning = _todayStatusFlag("hasMorningMeal");
    final hasLunch = _todayStatusFlag("hasLunchMeal");
    final hasDinner = _todayStatusFlag("hasDinnerMeal");
    final hasHydration = _todayStatusFlag("hasHydrationLog");
    final isComplete = _todayStatusFlag("isCompleteDay");
    final streakText = _currentLoggingStreak >= 2
        ? '$_currentLoggingStreak-day streak'
        : isComplete
            ? 'Complete today'
            : 'Build a streak';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF4DB6AC), Color(0xFF9E86FF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9E86FF).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_fire_department_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Logging Consistency',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      streakText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _longestLoggingStreak > 0
                          ? 'Longest streak: $_longestLoggingStreak days'
                          : 'Complete 2 days in a row to start a streak',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _openFoodLogAndRefresh,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF00C874),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
                child: const Text(
                  'Log',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDailyProgressChip('Morning', hasMorning),
              _buildDailyProgressChip('Lunch', hasLunch),
              _buildDailyProgressChip('Dinner', hasDinner),
              _buildDailyProgressChip('Hydration', hasHydration),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyProgressChip(String label, bool isDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isDone ? 0.24 : 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.cancel_outlined,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. Metrics Row ---
  Widget _buildMetricsRow() {
    final medicationTotal = _medicationTotalCount;
    final medicationTaken = (_numberFrom(_medicationData?["dosesTakenToday"]) ??
            _medications.where((medication) {
              final doseWindow = medication["doseWindow"] is Map
                  ? Map<String, dynamic>.from(medication["doseWindow"])
                  : null;
              final windowStatus =
                  doseWindow?["status"]?.toString().trim().toLowerCase();
              if (windowStatus != null && windowStatus.isNotEmpty) {
                return windowStatus == "taken";
              }
              return _optionalText(medication["status"]).toLowerCase() == "taken";
            }).length)
        .toInt();
    final medicationDueNow =
        (_numberFrom(_medicationData?["dosesDueNow"]) ?? 0).toInt();
    final nextReminder = _nextMedicationReminder;
    final nextReminderTime = nextReminder?["time"] as DateTime?;
    final missedCount = (_numberFrom(_medicationData?["missedDosesToday"]) ??
            (_missedMedications.isNotEmpty
                ? _missedMedications.length
                : _missedMedicationCountFromSummary()))
        .toInt();
    final missedLabel = missedCount == 1
        ? '1 missed medication'
        : missedCount > 1
            ? '$missedCount missed medications'
            : null;
    final medicationSubValue = missedLabel != null
        ? missedLabel
        : medicationDueNow > 0
            ? '$medicationDueNow due now'
            : nextReminderTime == null
                ? 'No medication logged yet'
                : 'Next: ${_formatClockTime(nextReminderTime)}';

    final fluidExceeded = _fluidTargetLiters != null &&
        _fluidTargetLiters! > 0 &&
        _todayWaterLiters > _fluidTargetLiters!;

    return Row(
      children: [
        Expanded(
          child: _buildSmallMetricCard(
            title: 'Hydration',
            icon: Icons.water_drop_outlined,
            iconColor: const Color(0xFF42A5F5),
            mainValue: _fluidTargetLiters == null
                ? 'No fluid restriction set'
                : '${_todayWaterLiters.toStringAsFixed(1)} L',
            subValue: _fluidTargetLiters == null
                ? 'Hydration logging not started'
                : fluidExceeded
                    ? 'Fluid intake exceeded'
                    : 'of ${_formatLiters(_fluidTargetLiters!)} goal',
            hintText: _hasHydrationLogged ? null : 'No hydration logged yet',
            progressColor:
                fluidExceeded ? const Color(0xFFD32F2F) : const Color(0xFF42A5F5),
            progressValue: _fluidTargetLiters != null && _fluidTargetLiters! > 0
                ? (_todayWaterLiters / _fluidTargetLiters!).clamp(0, 1)
                : 0,
            backgroundColor:
                fluidExceeded ? const Color(0xFFFFF1F2) : null,
            borderColor:
                fluidExceeded ? const Color(0xFFD32F2F) : null,
            shadowColor:
                fluidExceeded ? const Color(0x4DD32F2F) : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSmallMetricCard(
            title: 'Medication',
            icon: Icons.medication_outlined,
            iconColor: const Color(0xFFAB47BC),
            mainValue:
                _hasMedicationData ? '$medicationTaken taken' : 'Not set',
            subValue: medicationSubValue,
            hintText: _hasMedicationData ? null : 'No medication logged yet',
            progressColor: const Color(0xFFAB47BC),
            progressValue:
                medicationTotal == 0
                    ? 0
                    : (medicationTaken / medicationTotal).clamp(0, 1),
            backgroundColor:
                missedCount > 0 ? const Color(0xFFFFF1F2) : null,
            borderColor:
                missedCount > 0 ? const Color(0xFFD32F2F) : null,
            shadowColor:
                missedCount > 0 ? const Color(0x4DD32F2F) : null,
          ),
        ),
      ],
    );
  }

  String _formatLiters(double value) {
    final text = value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 1,
    );
    return '$text L';
  }

  Widget _buildSmallMetricCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String mainValue,
    required String subValue,
    required Color progressColor,
    required double progressValue,
    String? hintText,
    Color? backgroundColor,
    Color? borderColor,
    Color? shadowColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
        boxShadow: shadowColor == null
            ? null
            : [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            mainValue,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subValue,
            style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
          ),
          if (hintText != null) ...[
            const SizedBox(height: 6),
            Text(
              hintText,
              style: const TextStyle(
                color: Color(0xFFB0BEC5),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              backgroundColor: progressColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. Today's Nutrition Card ---
  Widget _buildNutritionCard() {
    final sodiumAlert =
        _sodiumTargetMg > 0 && _todaySodiumMg > _sodiumTargetMg;
    final potassiumAlert =
        _potassiumTargetMg > 0 && _todayPotassiumMg > _potassiumTargetMg;
    final phosphorusAlert =
        _phosphorusTargetMg > 0 && _todayPhosphorusMg > _phosphorusTargetMg;
    final anyAlert = sodiumAlert || potassiumAlert || phosphorusAlert;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: anyAlert ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: anyAlert ? const Color(0xFFD32F2F) : Colors.grey.shade200,
        ),
        boxShadow: anyAlert
            ? [
                BoxShadow(
                  color: const Color(0x4DD32F2F),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Nutrition",
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD5F5E3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _hasNutritionData ? 'Today' : 'No data',
                  style: const TextStyle(
                    color: Color(0xFF009688),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildNutritionBar(
            label: "Sodium",
            valueText:
                "${_formatNumber(_todaySodiumMg)} / ${_formatNumber(_sodiumTargetMg)} mg",
            progress: _progressFor(_todaySodiumMg, _sodiumTargetMg),
            color: const Color(0xFF00C874),
            isAlert: sodiumAlert,
          ),
          const SizedBox(height: 16),
          _buildNutritionBar(
            label: "Potassium",
            valueText:
                "${_formatNumber(_todayPotassiumMg)} / ${_formatNumber(_potassiumTargetMg)} mg",
            progress: _progressFor(_todayPotassiumMg, _potassiumTargetMg),
            color: const Color(0xFFFFCA28),
            isAlert: potassiumAlert,
          ),
          const SizedBox(height: 16),
          _buildNutritionBar(
            label: "Protein",
            valueText:
                "${_formatNumber(_todayProteinG, decimals: 1)} / ${_formatNumber(_proteinTargetG, decimals: 1)} g",
            progress: _progressFor(_todayProteinG, _proteinTargetG),
            color: const Color(0xFFEF5350),
          ),
          const SizedBox(height: 16),
          _buildNutritionBar(
            label: "Phosphorus",
            valueText:
                "${_formatNumber(_todayPhosphorusMg)} / ${_formatNumber(_phosphorusTargetMg)} mg",
            progress: _progressFor(_todayPhosphorusMg, _phosphorusTargetMg),
            color: const Color(0xFFFF7043),
            isAlert: phosphorusAlert,
          ),
          if (!_hasNutritionData) ...[
            const SizedBox(height: 18),
            const Text(
              "No nutrition data logged yet. Targets are based on your child's profile.",
              style: TextStyle(
                color: Color(0xFF78909C),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNutritionBar({
    required String label,
    required String valueText,
    required double progress,
    required Color color,
    bool isAlert = false,
  }) {
    final displayColor = isAlert ? const Color(0xFFD32F2F) : color;
    final labelColor =
        isAlert ? const Color(0xFFD32F2F) : const Color(0xFF78909C);
    final valueColor =
        isAlert ? const Color(0xFFD32F2F) : const Color(0xFF37474F);

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: displayColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 13,
                fontWeight: isAlert ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              valueText,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isAlert) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFD32F2F),
                size: 16,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: isAlert
                ? [
                    BoxShadow(
                      color: const Color(0xFFD32F2F).withOpacity(0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: displayColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(displayColor),
              minHeight: 8,
            ),
          ),
        ),
      ],
    );
  }

  // --- 5. Alert Card ---
  Widget _buildAlertCard() {
    final alerts = <String>[];
    if (_sodiumTargetMg > 0 && _todaySodiumMg > _sodiumTargetMg) {
      alerts.add('Sodium is above today\'s target.');
    }
    if (_potassiumTargetMg > 0 && _todayPotassiumMg > _potassiumTargetMg) {
      alerts.add('Potassium is above today\'s target.');
    }
    if (_phosphorusTargetMg > 0 && _todayPhosphorusMg > _phosphorusTargetMg) {
      alerts.add('Phosphorus is above today\'s target.');
    }

    if (!_hasNutritionData) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5FAF8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0F2ED)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              color: Color(0xFF00A86B),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'No nutrition data yet.',
                    style: TextStyle(
                      color: Color(0xFF37474F),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Log your meals to see insights and recommendations.',
                    style: TextStyle(
                      color: Color(0xFF78909C),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5FAF8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0F2ED)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.check_circle_outline, color: Color(0xFF00A86B), size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Today\'s logged meals are within the displayed nutrition targets.',
                style: TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF7043), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nutrition target alert',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alerts.join(' '),
                  style: const TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 6. Quick Actions Card ---
  Widget _buildQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              color: Color(0xFF78909C),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _buildQuickActionBtn(
            Icons.restaurant_menu,
            'Log Food',
            onTap: _openFoodLogAndRefresh,
          ),
          if (_isAdolescentViewer) ...[
            const SizedBox(height: 12),
            _buildQuickActionBtn(
              Icons.emoji_events_outlined,
              'Leaderboard',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LeaderboardPage(),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          _buildQuickActionBtn(
            Icons.calendar_today_outlined,
            'View Growth Chart',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AnalyticsPage(
                    initialCategory: 'Growth',
                    profileUserId: _selectedManagedProfileUserId,
                    caregiverNoChildEmptyState:
                        _isCaregiverViewer && _managedChildren.isEmpty,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildQuickActionBtn(
            Icons.trending_up,
            'Weekly Report',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AnalyticsPage(
                    initialCategory: 'Nutrients',
                    profileUserId: _selectedManagedProfileUserId,
                    caregiverNoChildEmptyState:
                        _isCaregiverViewer && _managedChildren.isEmpty,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn(
    IconData icon,
    String title, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF37474F), size: 20),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF37474F),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 7. Upcoming Card ---
  Widget _buildUpcomingCard() {
    final nextReminder = _nextDashboardReminder;
    final nextReminderName = nextReminder?["name"]?.toString() ?? "Reminder";
    final nextReminderTime = nextReminder?["time"] as DateTime?;
    final nextReminderMessage = nextReminder?["message"]?.toString() ?? "";
    final nextReminderKind = nextReminder?["kind"]?.toString() ?? "";
    final isMissed = nextReminder?["isMissed"] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upcoming',
            style: TextStyle(
              color: Color(0xFF78909C),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          if (nextReminderTime != null) ...[
            _buildUpcomingItem(
              icon: nextReminderKind == "meal"
                  ? Icons.restaurant_outlined
                  : nextReminderKind == "hydration"
                      ? Icons.water_drop_outlined
                      : nextReminderKind == "streak"
                          ? Icons.local_fire_department_outlined
                          : nextReminderKind == "missed_medication"
                              ? Icons.warning_outlined
                              : Icons.medication_outlined,
              iconColor: nextReminderKind == "meal"
                  ? const Color(0xFFEF6C00)
                  : nextReminderKind == "hydration"
                      ? const Color(0xFF1565C0)
                      : nextReminderKind == "streak"
                          ? const Color(0xFFD84315)
                          : nextReminderKind == "missed_medication"
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF9E86FF),
              bgColor: nextReminderKind == "meal"
                  ? const Color(0xFFFFF3E0)
                  : nextReminderKind == "hydration"
                      ? const Color(0xFFE3F2FD)
                      : nextReminderKind == "streak"
                          ? const Color(0xFFFBE9E7)
                          : nextReminderKind == "missed_medication"
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFF3E5F5),
              title: nextReminderName,
              subtitle: isMissed
                  ? '${_relativeReminderText(nextReminderTime)}${nextReminderMessage.isNotEmpty ? ' - $nextReminderMessage' : ''}'
                  : '${_formatClockTime(nextReminderTime)} - ${_relativeReminderText(nextReminderTime)}${nextReminderMessage.isNotEmpty ? ' - $nextReminderMessage' : ''}',
              onTap: nextReminderKind == "medication"
                  ? () => _promptMarkMedicationTaken(nextReminder ?? {})
                  : null,
            ),
            const SizedBox(height: 20),
          ],
          if (nextReminderTime == null)
            _buildUpcomingItem(
              icon: Icons.notifications_none_outlined,
              iconColor: const Color(0xFF78909C),
              bgColor: const Color(0xFFF5F7FA),
              title: 'No upcoming reminders',
              subtitle:
                  'Meal, hydration, and medication reminders will appear here.',
            ),
        ],
      ),
    );
  }

  Widget _buildUpcomingItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final content = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }

  // --- Helper to build individual notification items ---
  Widget _buildNotificationItem({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String time,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF37474F),
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB0BEC5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF78909C),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
