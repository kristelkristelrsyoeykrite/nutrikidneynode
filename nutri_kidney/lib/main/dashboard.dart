import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'health_metrics.dart';
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
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _nutritionTargets = {};
  Map<String, dynamic> _medicalProfile = {};
  Map<String, dynamic> _phase2DecisionSupport = {};
  Map<String, dynamic> _labResults = {};
  Map<String, dynamic> _anthropometrics = {};
  Map<String, dynamic>? _intakeData;
  Map<String, dynamic>? _medicationData;
  List<Map<String, dynamic>> _medications = [];

  static const double _defaultSodiumTargetMg = 1500;
  static const double _defaultPotassiumTargetMg = 2000;

  bool get _hasHydrationLogged => false;
  int get _medicationTotalCount {
    return _medications.length > 0
        ? _medications.length
        : (_numberFrom(_medicationData?["count"]) ?? 0).toInt();
  }

  bool get _hasMedicationData => _medicationTotalCount > 0;
  bool get _hasNutritionData => _intakeData != null;

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
        _user = _asStringMap(response["user"]);
        _nutritionTargets = _asStringMap(response["nutritionTargets"]);
        _medicalProfile = _asStringMap(response["medicalProfile"]);
        _phase2DecisionSupport =
            _asStringMap(response["phase2DecisionSupport"]);
        _labResults = _asStringMap(response["labResults"]);
        _anthropometrics = _asStringMap(response["anthropometrics"]);
        _intakeData = _nullableStringMap(response["intakeData"]);
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
    final nextReminder = _nextMedicationReminder;
    final nextReminderTime = nextReminder?["time"] as DateTime?;
    final nextReminderName = nextReminder?["name"]?.toString() ?? "Medication";

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
              if (nextReminderTime != null)
                _buildNotificationItem(
                  icon: Icons.medication_outlined,
                  color: const Color(0xFF9E86FF),
                  title: '$nextReminderName reminder',
                  message: 'Scheduled at ${_formatClockTime(nextReminderTime)}.',
                  time: _relativeReminderText(nextReminderTime),
                )
              else
                _buildNotificationItem(
                  icon: Icons.medication_outlined,
                  color: const Color(0xFF9E86FF),
                  title: 'No medication reminders',
                  message: 'Add medication details to enable reminders.',
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_outlined,
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
                  'Daily Progress',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: const [
                    Text(
                      'No logs yet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 0,
            ),
            child: const Text(
              'Log Food',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                : '0 L',
            subValue: _fluidTargetLiters == null
                ? 'Hydration logging not started'
                : 'of ${_formatLiters(_fluidTargetLiters!)} goal',
            hintText: _hasHydrationLogged ? null : 'No hydration logged yet',
            progressColor: const Color(0xFF42A5F5),
            progressValue: 0,
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
                child: const Text(
                  'No data',
                  style: TextStyle(
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
            valueText: "0 / ${_formatNumber(_sodiumTargetMg)} mg",
            progress: 0,
            color: const Color(0xFF00C874),
          ),
          const SizedBox(height: 16),
          _buildNutritionBar(
            label: "Potassium",
            valueText: "0 / ${_formatNumber(_potassiumTargetMg)} mg",
            progress: 0,
            color: const Color(0xFFFFCA28),
          ),
          const SizedBox(height: 16),
          _buildNutritionBar(
            label: "Protein",
            valueText: "0 / ${_formatNumber(_proteinTargetG, decimals: 1)} g",
            progress: 0,
            color: const Color(0xFFEF5350),
          ),
          const SizedBox(height: 16),
          _buildNutritionBar(
            label: "Phosphorus",
            valueText: "0 / ${_formatNumber(_phosphorusTargetMg)} mg",
            progress: 0,
            color: const Color(0xFFFF7043),
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
    final nextReminder = _nextMedicationReminder;
    final nextReminderName = nextReminder?["name"]?.toString() ?? "Medication";
    final nextReminderTime = nextReminder?["time"] as DateTime?;

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
              icon: Icons.medication_outlined,
              iconColor: const Color(0xFF9E86FF),
              bgColor: const Color(0xFFF3E5F5),
              title: '$nextReminderName reminder',
              subtitle:
                  '${_formatClockTime(nextReminderTime)} - ${_relativeReminderText(nextReminderTime)}',
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
                ? 'Medication reminders and appointments will appear here.'
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
