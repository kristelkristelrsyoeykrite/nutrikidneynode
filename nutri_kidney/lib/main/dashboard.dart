import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
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
  String? _dashboardError;
  Map<String, dynamic> _viewer = {};
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _caregiverDashboardState = {};
  Map<String, dynamic> _nutritionTargets = {};
  Map<String, dynamic> _medicalProfile = {};
  Map<String, dynamic> _labResults = {};
  Map<String, dynamic> _anthropometrics = {};
  Map<String, dynamic>? _intakeData;
  Map<String, dynamic>? _medicationData;
  Map<String, dynamic> _gamification = {};
  List<Map<String, dynamic>> _medications = [];
  static const Map<String, Map<String, int>> _mealReminderSchedule = {
    "breakfast": {"hour": 8, "minute": 0},
    "lunch": {"hour": 12, "minute": 0},
    "snack": {"hour": 15, "minute": 30},
    "dinner": {"hour": 18, "minute": 30},
  };

  static const double _defaultSodiumTargetMg = 1500;
  static const double _defaultPotassiumTargetMg = 2000;

  int get _medicationTotalCount {
    return _medications.length > 0
        ? _medications.length
        : (_numberFrom(_medicationData?["count"]) ?? 0).toInt();
  }

  bool get _hasMedicationData => _medicationTotalCount > 0;
  bool get _hasNutritionData => _todayMealCount > 0;

  Map<String, dynamic> get _reminderSettings {
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
    _loadDashboardSummary();
  }

  Future<void> _loadDashboardSummary() async {
    try {
      final response = await ApiService.getDashboardSummary();

      if (!mounted) return;

      if (response["success"] != true) {
        throw Exception(response["error"] ?? "Failed to load dashboard");
      }

      setState(() {
        _viewer = _asStringMap(response["viewer"]);
        _user = _asStringMap(response["user"]);
        _caregiverDashboardState = _asStringMap(
          response["caregiverDashboardState"],
        );
        _nutritionTargets = _asStringMap(response["nutritionTargets"]);
        _medicalProfile = _asStringMap(response["medicalProfile"]);
        Map<String, dynamic> _phase2DecisionSupport = {};
            _asStringMap(response["phase2DecisionSupport"]);
        _labResults = _asStringMap(response["labResults"]);
        _anthropometrics = _asStringMap(response["anthropometrics"]);
        _intakeData = _nullableStringMap(response["intakeData"]);
        _gamification = _asStringMap(response["gamification"]);
        _medicationData = _nullableStringMap(response["medicationData"]);
        _medications = _asStringMapList(response["medications"]);
        _isLoadingDashboard = false;
        _dashboardError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingDashboard = false;
        _dashboardError = e.toString();
      });
    }
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
            "name": _medicationName(medication),
            "time": scheduled,
          };
        }
      }
    }

    return nextReminder;
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

  List<Map<String, dynamic>> get _dashboardReminders {
    final items = <Map<String, dynamic>>[];
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
    return _isCaregiverViewer &&
        _caregiverDashboardState["childAgeGroup"] == "13-18" &&
        _caregiverDashboardState["linkedChildAccount"] != true;
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

  double _progressFor(double value, double target) {
    if (target <= 0) return 0;
    return (value / target).clamp(0, 1).toDouble();
  }

  bool get _hasFluidRestriction {
    final status = (_medicalProfile["fluidRestrictionStatus"] ??
            _medicalProfile["fluid_restriction_status"])
        ?.toString()
        .trim()
        .toLowerCase();
    return status == "yes";
  }

  double? get _fluidLimitMl {
    return _numberFrom(
      _medicalProfile["fluidLimitMl"] ?? _medicalProfile["fluid_limit_ml"],
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
                            : Icons.medication_outlined,
                    color: kind == "meal"
                        ? const Color(0xFFFFB74D)
                        : kind == "hydration"
                            ? const Color(0xFF64B5F6)
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
                        _buildPendingCaregiverHeader(),
                        const SizedBox(height: 24),
                        _buildPendingCaregiverCard(),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
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
                MaterialPageRoute(builder: (context) => const FoodLogPage()),
              );
            } else if (index == 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const AnalyticsPage()),
              );
            } else if (index == 3) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HealthMetricsPage(),
                ),
              );
            } else if (index == 4) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
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

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
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
                'Good morning,',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
              ),
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

  Widget _buildPendingCaregiverHeader() {
    final caregiverName =
        (_viewer["fullName"] ?? _viewer["name"] ?? "Caregiver").toString();

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFD5F5E3),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.volunteer_activism_outlined,
              color: Color(0xFF009688),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Caregiver dashboard',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
              ),
              Text(
                caregiverName,
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
      ],
    );
  }

  Widget _buildPendingCaregiverCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F2),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.link,
              color: Color(0xFF00A676),
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No linked adolescent account yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF37474F),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Please link your child’s account to view and support their health profile.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF78909C),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Please link your child’s account here.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF78909C),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _generateCaregiverLinkCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Generate Linking Code',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FoodLogPage()),
                  );
                },
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
    final medicationTaken = _medications
        .where(
          (medication) =>
              _optionalText(medication["status"]).toLowerCase() == "taken",
        )
        .length;
    final nextReminder = _nextMedicationReminder;
    final nextReminderTime = nextReminder?["time"] as DateTime?;

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
                : 'of ${_formatLiters(_fluidTargetLiters!)} goal',
            hintText: _hasHydrationLogged ? null : 'No hydration logged yet',
            progressColor: const Color(0xFF42A5F5),
            progressValue: _fluidTargetLiters != null && _fluidTargetLiters! > 0
                ? (_todayWaterLiters / _fluidTargetLiters!).clamp(0, 1)
                : 0,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSmallMetricCard(
            title: 'Medication',
            icon: Icons.medication_outlined,
            iconColor: const Color(0xFFAB47BC),
            mainValue:
                _hasMedicationData ? '$medicationTaken/$medicationTotal' : 'Not set',
            subValue: nextReminderTime == null
                ? 'No medication logged yet'
                : 'Next: ${_formatClockTime(nextReminderTime)}',
            hintText: _hasMedicationData ? null : 'No medication logged yet',
            progressColor: const Color(0xFFAB47BC),
            progressValue:
                medicationTotal == 0 ? 0 : medicationTaken / medicationTotal,
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
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
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF78909C),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              valueText,
              style: TextStyle(
                color: isAlert ? color : const Color(0xFF37474F),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isAlert) ...[
              const SizedBox(width: 4),
              Icon(Icons.warning_amber_rounded, color: color, size: 16),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FoodLogPage()),
              );
            },
          ),
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
          const SizedBox(height: 12),
          _buildQuickActionBtn(
            Icons.calendar_today_outlined,
            'View Growth Chart',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const AnalyticsPage(initialCategory: 'Growth'),
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
                  builder: (context) =>
                      const AnalyticsPage(initialCategory: 'Nutrients'),
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
                      : Icons.medication_outlined,
              iconColor: nextReminderKind == "meal"
                  ? const Color(0xFFEF6C00)
                  : nextReminderKind == "hydration"
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF9E86FF),
              bgColor: nextReminderKind == "meal"
                  ? const Color(0xFFFFF3E0)
                  : nextReminderKind == "hydration"
                      ? const Color(0xFFE3F2FD)
                      : const Color(0xFFF3E5F5),
              title: nextReminderName,
              subtitle:
                  '${_formatClockTime(nextReminderTime)} - ${_relativeReminderText(nextReminderTime)}${nextReminderMessage.isNotEmpty ? ' - $nextReminderMessage' : ''}',
            ),
            const SizedBox(height: 20),
          ],
          _buildUpcomingItem(
            icon: Icons.event_available_outlined,
            iconColor: const Color(0xFF009688),
            bgColor: const Color(0xFFE0F2F1),
            title: nextReminderTime == null
                ? 'No upcoming items set'
                : 'No appointments set',
            subtitle: nextReminderTime == null
                ? 'Meal, hydration, medication reminders, and appointments will appear here.'
                : 'Appointments will appear here.',
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
  }) {
    return Row(
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
