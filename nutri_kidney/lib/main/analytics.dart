import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/api_service.dart';
import '../widgets/chart_js_view.dart';
import 'dashboard.dart';
import 'food_log.dart';
import 'health_metrics.dart';
import 'profile.dart';

class AnalyticsPage extends StatefulWidget {
  final String initialCategory;
  final bool? allowDataExport;
  final String? profileUserId;
  final bool caregiverNoChildEmptyState;

  const AnalyticsPage({
    super.key,
    this.initialCategory = 'Nutrients',
    this.allowDataExport,
    this.profileUserId,
    this.caregiverNoChildEmptyState = false,
  });

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  int _currentIndex = 2;
  String _activeTimeRange = 'Week';
  late String _activeCategory;
  bool _isLoading = true;
  String? _error;
  late bool _allowDataExport;
  bool _isExporting = false;
  bool _resolvedCaregiverNoChildEmptyState = false;
  DateTime _historyDate = DateTime.now();
  List<Map<String, dynamic>> _historyLogsForSelectedDate = [];
  List<_DailyAnalyticsPoint> _dailyPoints = [];
  List<Map<String, dynamic>> _anthropometricHistory = [];
  List<Map<String, dynamic>> _labResultsHistory = [];
  Map<String, dynamic> _userProfile = {};
  Map<String, dynamic> _medicalProfile = {};

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _allowDataExport = widget.allowDataExport ?? false;
    _resolvedCaregiverNoChildEmptyState = widget.caregiverNoChildEmptyState;
    if (!widget.caregiverNoChildEmptyState) {
      _loadAnalytics();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadAnalytics() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (await _shouldShowCaregiverEmptyState()) {
        if (!mounted) return;
        setState(() {
          _resolvedCaregiverNoChildEmptyState = true;
          _isLoading = false;
        });
        return;
      }
      final now = DateTime.now();

      // Load health summary first to sync export preference immediately
      final healthSummaryResponse = await ApiService.getHealthSummary(
        profileUserId: widget.profileUserId,
      );
      if (healthSummaryResponse['success'] == true) {
        final viewer = healthSummaryResponse['viewer'] is Map
            ? Map<String, dynamic>.from(healthSummaryResponse['viewer'] as Map)
            : <String, dynamic>{};
        final user = healthSummaryResponse['user'] is Map
            ? Map<String, dynamic>.from(healthSummaryResponse['user'] as Map)
            : <String, dynamic>{};
        final medicalProfile = healthSummaryResponse['medicalProfile'] is Map
            ? Map<String, dynamic>.from(
                healthSummaryResponse['medicalProfile'] as Map,
              )
            : <String, dynamic>{};
        if (mounted) {
          setState(() {
            _userProfile = user;
            _medicalProfile = medicalProfile;
            final viewerRole = viewer['role']?.toString().toLowerCase() ?? '';
            final isCaregiverViewer =
                viewerRole == 'caregiver' || viewerRole == 'parent_caregiver';
            _allowDataExport = isCaregiverViewer
                ? viewer['allowDataExport'] == true
                : user['allowDataExport'] == true;
          });
        }
      }

      final range = _analyticsDateRange(_activeTimeRange, endDate: now);
      final analyticsSummaryResponse = await ApiService.getAnalyticsSummary(
        range: _analyticsRangeKey(_activeTimeRange),
        endDate: _dateKey(now),
        profileUserId: widget.profileUserId,
      );
      final rangeLogsResponse = await ApiService.getFoodLogs(
        dateFrom: _dateKey(range.start),
        dateTo: _dateKey(range.end),
        limit: 500,
        profileUserId: widget.profileUserId,
      );
      final selectedDateLogsResponse = await ApiService.getFoodLogs(
        date: _dateKey(_historyDate),
        limit: 200,
        profileUserId: widget.profileUserId,
      );

      final summary = _extractAnalyticsSummary(analyticsSummaryResponse);
      final rangeLogs = _extractLogs(rangeLogsResponse);
      final selectedDayLogs = _extractLogs(selectedDateLogsResponse);
      final healthHistory = _extractAnthropometricHistory(healthSummaryResponse);
      final labHistory = _extractLabResultsHistory(healthSummaryResponse);
      final dailyPoints = _mergeHydrationFallback(
        _dailyPointsFromSummary(summary),
        rangeLogs,
      );

      if (!mounted) return;
      setState(() {
        _dailyPoints = dailyPoints;
        _historyLogsForSelectedDate = selectedDayLogs;
        _anthropometricHistory = healthHistory;
        _labResultsHistory = labHistory;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedCaregiverNoChildEmptyState) {
      return _buildCaregiverNoChildScaffold();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C874)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      _buildErrorCard(),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        _buildTimeToggle('Week'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _buildCategoryToggle('Nutrients')),
                          Expanded(child: _buildCategoryToggle('Growth')),
                          Expanded(child: _buildCategoryToggle('Hydration')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDynamicContent(),
                    const SizedBox(height: 16),
                    _buildMealHistoryCard(),
                    const SizedBox(height: 16),
                    _buildLabResultsHistoryCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
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
            if (index == 0) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const DashboardPage()),
                (route) => false,
              );
            } else if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      FoodLogPage(
                        profileUserId: widget.profileUserId,
                        caregiverNoChildEmptyState:
                            _resolvedCaregiverNoChildEmptyState,
                      ),
                ),
              );
            } else if (index == 3) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      HealthMetricsPage(
                        profileUserId: widget.profileUserId,
                        caregiverNoChildEmptyState:
                            _resolvedCaregiverNoChildEmptyState,
                      ),
                ),
              );
            } else if (index == 4) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            } else {
              setState(() => _currentIndex = index);
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
              activeIcon: Icon(Icons.favorite),
              label: 'Health',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaregiverNoChildScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analytics',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Add or link a child profile from the dashboard before viewing analytics.',
                style: TextStyle(
                  color: Color(0xFF607D8B),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
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
          if (index == 0) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
              (route) => false,
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => FoodLogPage(
                  profileUserId: widget.profileUserId,
                  caregiverNoChildEmptyState:
                      _resolvedCaregiverNoChildEmptyState,
                ),
              ),
            );
          } else if (index == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HealthMetricsPage(
                  profileUserId: widget.profileUserId,
                  caregiverNoChildEmptyState:
                      _resolvedCaregiverNoChildEmptyState,
                ),
              ),
            );
          } else if (index == 4) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
          } else {
            setState(() => _currentIndex = index);
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
    );
  }

  Future<bool> _shouldShowCaregiverEmptyState() async {
    final response = await ApiService.getDashboardSummary();
    final viewer = response['viewer'];
    final role = viewer is Map
        ? (viewer['role'] ?? viewer['userRole'] ?? '').toString().toLowerCase()
        : '';
    if (role != 'caregiver' && role != 'parent_caregiver') return false;
    final state = response['caregiverDashboardState'];
    final children = state is Map ? state['linkedChildren'] : null;
    return children is! List || children.isEmpty;
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analytics',
          style: TextStyle(
            color: Color(0xFF37474F),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Historical meal trends and growth history',
          style: TextStyle(
            color: Color(0xFF90A4AE),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loadAnalytics,
              icon: const Icon(
                Icons.refresh,
                size: 16,
                color: Color(0xFF37474F),
              ),
              label: const Text(
                'Refresh',
                style: TextStyle(color: Color(0xFF37474F)),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            if (_allowDataExport) ...[
              OutlinedButton.icon(
                onPressed: _isExporting ? null : _exportAnalyticsPdf,
                icon: _isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 16,
                        color: Color(0xFF37474F),
                      ),
                label: Text(
                  _isExporting ? 'Exporting' : 'Export PDF',
                  style: const TextStyle(color: Color(0xFF37474F)),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4.0, left: 2.0, right: 2.0),
                child: Text(
                  'Export a PDF report of your health, nutrition, and hydration data to share with your doctor, dietitian, or caregiver.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF78909C)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Text(
        'Analytics could not be fully loaded: $_error',
        style: const TextStyle(
          color: Color(0xFF78909C),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildDynamicContent() {
    if (_activeCategory == 'Growth') {
      return _buildGrowthContent();
    }
    if (_activeCategory == 'Hydration') {
      return _buildHydrationContent();
    }
    return _buildNutrientsContent();
  }

  Widget _buildNutrientsContent() {
    final avgSodium = _averageFor((point) => point.sodium);
    final avgProtein = _averageFor((point) => point.protein);
    final totalCalories = _dailyPoints.fold<double>(
      0,
      (sum, point) => sum + point.calories,
    );
    final macroTotals = _macroTotals();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Avg. Sodium',
                '${avgSodium.round()} mg',
                '${_dailyPoints.length} days tracked',
                Icons.water_drop_outlined,
                const Color(0xFF42A5F5),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Avg. Protein',
                '${avgProtein.toStringAsFixed(1)} g',
                '${totalCalories.round()} kcal total',
                Icons.fitness_center,
                const Color(0xFF9E86FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSummaryCard(
          'Meal Log Coverage',
          '${_dailyPoints.fold<int>(0, (sum, p) => sum + p.mealCount)} meals',
          '${_daysWithMeals()} of ${_dailyPoints.length} days have meal logs',
          Icons.restaurant,
          const Color(0xFF00C874),
          fullWidth: true,
        ),
        const SizedBox(height: 24),
        _buildChartCard(
          title: 'Sodium & Potassium Trends',
          legends: [
            _buildLegend(const Color(0xFF42A5F5), 'Sodium (mg)'),
            _buildLegend(const Color(0xFF66BB6A), 'Potassium (mg)'),
          ],
          chart: ChartJsView(
            chartType: 'line',
            data: _buildNutrientTrendData(),
            options: _buildCartesianChartOptions(yAxisLabel: 'Milligrams'),
          ),
        ),
        const SizedBox(height: 16),
        _buildChartCard(
          title: 'Protein & Phosphorus by Day',
          legends: [
            _buildLegend(const Color(0xFF9E86FF), 'Protein (g)'),
            _buildLegend(const Color(0xFFFFB74D), 'Phosphorus (mg)'),
          ],
          chart: ChartJsView(
            chartType: 'bar',
            data: _buildProteinPhosphorusData(),
            options: _buildCartesianChartOptions(yAxisLabel: 'Amount'),
          ),
        ),
        const SizedBox(height: 16),
        _buildChartCard(
          title: 'Macro Distribution',
          legends: [
            _buildLegend(
              const Color(0xFF66BB6A),
              'Protein\n${macroTotals.proteinPercent}%',
            ),
            _buildLegend(
              const Color(0xFF42A5F5),
              'Carbs\n${macroTotals.carbPercent}%',
            ),
            _buildLegend(
              const Color(0xFFFFB74D),
              'Fat\n${macroTotals.fatPercent}%',
            ),
          ],
          chart: SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ChartJsView(
                  chartType: 'doughnut',
                  data: _buildMacroChartData(macroTotals),
                  options: _buildDoughnutOptions(),
                ),
                Text(
                  '${macroTotals.totalCalories.round()} kcal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthContent() {
    final growthPoints = _growthHistoryPoints();
    final latest = growthPoints.isNotEmpty ? growthPoints.last : null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Current Weight',
                latest?.weightLabel ?? 'No data',
                '${growthPoints.length} records',
                Icons.scale,
                const Color(0xFF00C874),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Current Height',
                latest?.heightLabel ?? 'No data',
                latest?.bmiLabel ?? 'BMI unavailable',
                Icons.straighten,
                const Color(0xFF42A5F5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildChartCard(
          title: 'Weight Trend',
          legends: [
            _buildLegend(const Color(0xFF9E86FF), 'Weight (kg)'),
          ],
          chart: ChartJsView(
            chartType: 'line',
            data: _buildGrowthTrendData(growthPoints),
            options: _buildCartesianChartOptions(
              yAxisLabel: 'kg',
              useDateLabels: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHydrationContent() {
    final avgWaterLiters = _averageFor((point) => point.waterMl) / 1000;
    final highestWaterLiters =
        _dailyPoints.fold<double>(0, (max, point) => point.waterMl > max ? point.waterMl : max) /
            1000;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Avg Daily Intake',
                '${avgWaterLiters.toStringAsFixed(1)} L',
                '${_daysWithWater()} days with water logs',
                Icons.local_drink_outlined,
                const Color(0xFF42A5F5),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Highest Logged Day',
                '${highestWaterLiters.toStringAsFixed(1)} L',
                '${_dailyPoints.length} days tracked',
                Icons.opacity,
                const Color(0xFF00C874),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildChartCard(
          title: 'Daily Intake vs Limit',
          legends: [
            _buildLegend(const Color(0xFF42A5F5), 'Fluid Intake (L)'),
            _buildLegend(const Color(0xFFEF5350), 'Guide Line (1.5L)'),
          ],
          chart: ChartJsView(
            chartType: 'bar',
            data: _buildHydrationChartData(),
            options: _buildHydrationChartOptions(),
          ),
        ),
      ],
    );
  }

  Widget _buildMealHistoryCard() {
    final formattedDate = DateFormat('MMM d, yyyy').format(_historyDate);
    return Container(
      width: double.infinity,
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
                'Meal Log History',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickHistoryDate,
                icon: const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: Color(0xFF37474F),
                ),
                label: Text(
                  formattedDate,
                  style: const TextStyle(color: Color(0xFF37474F)),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Review the foods logged on the selected date.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          if (_historyLogsForSelectedDate.isEmpty)
            const Text(
              'No meal logs found for this date.',
              style: TextStyle(color: Color(0xFF90A4AE)),
            )
          else
            ..._historyLogsForSelectedDate.map(_buildHistoryLogTile),
        ],
      ),
    );
  }

  Widget _buildLabResultsHistoryCard() {
    return Container(
      width: double.infinity,
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
            children: const [
              Icon(
                Icons.calendar_month_outlined,
                color: Color(0xFF42A5F5),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Previous Lab Results',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tap any result date to view the complete lab details.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          if (_labResultsHistory.isEmpty)
            const Text(
              'No lab results recorded yet.',
              style: TextStyle(color: Color(0xFF90A4AE)),
            )
          else
            ..._labResultsHistory.map(_buildLabHistoryTile),
        ],
      ),
    );
  }

  Widget _buildLabHistoryTile(Map<String, dynamic> lab) {
    final dateLabel = _formatLabDate(
      lab['date'] ?? lab['resultDate'] ?? lab['createdAt'],
    );
    final detailCount = _labDetailEntries(lab).length;

    return InkWell(
      onTap: () => _showLabResultDetails(lab),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0ECE8)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.science_outlined,
                color: Color(0xFF1E88E5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Color(0xFF37474F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$detailCount values recorded',
                    style: const TextStyle(
                      color: Color(0xFF78909C),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF90A4AE),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLabResultDetails(Map<String, dynamic> lab) {
    final entries = _labDetailEntries(lab);
    final dateLabel = _formatLabDate(
      lab['date'] ?? lab['resultDate'] ?? lab['createdAt'],
    );

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lab Result Details',
                          style: TextStyle(
                            color: Color(0xFF37474F),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            color: Color(0xFF90A4AE),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const Text(
                    'No lab details available.',
                    style: TextStyle(color: Color(0xFF90A4AE)),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      child: Column(
                        children: entries.map((entry) {
                          final status = entry.status;
                          final statusColor = status == null || status.isEmpty
                              ? const Color(0xFF90A4AE)
                              : (status.toLowerCase() == 'high' ||
                                      status.toLowerCase() == 'low'
                                  ? const Color(0xFFEF5350)
                                  : const Color(0xFF00A86B));
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE0ECE8),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.label,
                                      style: const TextStyle(
                                        color: Color(0xFF37474F),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (status != null && status.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        status,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '${entry.value} ${entry.unit}'.trim(),
                                  style: const TextStyle(
                                    color: Color(0xFF37474F),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryLogTile(Map<String, dynamic> log) {
    final name = log['name']?.toString() ?? 'Food';
    final mealType = log['mealType']?.toString() ?? 'Meal';
    final portion = log['portion']?.toString() ?? '1 serving';
    final calories = _toDouble(log['calories']).round();
    final time = _formatLogTime(log['loggedAt'] ?? log['createdAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0ECE8)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFDDF7EE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.restaurant_menu,
              color: Color(0xFF00A86B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$mealType - $portion - $calories kcal',
                  style: const TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickHistoryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _historyDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _historyDate = picked;
    });
    await _loadAnalytics();
  }

  Widget _buildTimeToggle(String title) {
    final isActive = _activeTimeRange == title;
    return GestureDetector(
      onTap: () {
        setState(() => _activeTimeRange = title);
        _loadAnalytics();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00C874) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF00C874) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF37474F),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryToggle(String title) {
    final isActive = _activeCategory == title;
    return GestureDetector(
      onTap: () => setState(() => _activeCategory = title),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00C874) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF78909C),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color accent, {
    bool fullWidth = false,
  }) {
    final card = Container(
      width: fullWidth ? double.infinity : null,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF90A4AE),
                  fontSize: 12,
                ),
              ),
              Icon(icon, color: accent, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return card;
  }

  Widget _buildChartCard({
    required String title,
    required List<Widget> legends,
    required Widget chart,
  }) {
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
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF78909C),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          chart,
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: legends,
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Map<String, dynamic> _buildNutrientTrendData() {
    return {
      'labels': _dailyPointLabels(useDateLabels: _dailyPoints.length > 7),
      'datasets': [
        {
          'label': 'Sodium',
          'data': _dailyPoints.map((point) => point.sodium.round()).toList(),
          'borderColor': '#42A5F5',
          'backgroundColor': 'rgba(66, 165, 245, 0.18)',
          'tension': 0.35,
          'fill': false,
        },
        {
          'label': 'Potassium',
          'data': _dailyPoints.map((point) => point.potassium.round()).toList(),
          'borderColor': '#66BB6A',
          'backgroundColor': 'rgba(102, 187, 106, 0.18)',
          'tension': 0.35,
          'fill': false,
        },
      ],
    };
  }

  Map<String, dynamic> _buildProteinPhosphorusData() {
    return {
      'labels': _dailyPointLabels(useDateLabels: _dailyPoints.length > 7),
      'datasets': [
        {
          'label': 'Protein',
          'data': _dailyPoints
              .map((point) => double.parse(point.protein.toStringAsFixed(1)))
              .toList(),
          'backgroundColor': '#9E86FF',
          'borderRadius': 6,
        },
        {
          'label': 'Phosphorus',
          'data': _dailyPoints.map((point) => point.phosphorus.round()).toList(),
          'backgroundColor': '#FFB74D',
          'borderRadius': 6,
        },
      ],
    };
  }

  Map<String, dynamic> _buildMacroChartData(_MacroTotals totals) {
    return {
      'labels': const ['Carbs', 'Protein', 'Fat'],
      'datasets': [
        {
          'data': [
            totals.carbCalories <= 0 ? 1 : totals.carbCalories,
            totals.proteinCalories <= 0 ? 1 : totals.proteinCalories,
            totals.fatCalories <= 0 ? 1 : totals.fatCalories,
          ],
          'backgroundColor': const ['#42A5F5', '#66BB6A', '#FFB74D'],
          'borderWidth': 0,
        },
      ],
    };
  }

  Map<String, dynamic> _buildGrowthTrendData(List<_GrowthPoint> points) {
    final safePoints = points.isEmpty
        ? [
            _GrowthPoint(
              date: DateTime.now(),
              weightKg: 0,
              heightCm: 0,
              bmi: null,
            ),
          ]
        : points;
    return {
      'labels': safePoints
          .map((point) => DateFormat('MMM d').format(point.date))
          .toList(),
      'datasets': [
        {
          'label': 'Weight',
          'data': safePoints
              .map((point) => double.parse(point.weightKg.toStringAsFixed(1)))
              .toList(),
          'borderColor': '#9E86FF',
          'backgroundColor': 'rgba(158, 134, 255, 0.14)',
          'tension': 0.35,
          'fill': true,
        },
      ],
    };
  }

  Map<String, dynamic> _buildHydrationChartData() {
    final waterLiters = _dailyPoints
        .map((point) => double.parse((point.waterMl / 1000).toStringAsFixed(2)))
        .toList();
    return {
      'labels': _dailyPointLabels(useDateLabels: _dailyPoints.length > 7),
      'datasets': [
        {
          'label': 'Fluid Intake',
          'data': waterLiters,
          'backgroundColor': waterLiters
              .map((value) => value > 1.5 ? '#EF5350' : '#42A5F5')
              .toList(),
          'borderRadius': 6,
        },
        {
          'type': 'line',
          'label': 'Guide Line',
          'data': List<double>.filled(_dailyPoints.length, 1.5),
          'borderColor': '#EF5350',
          'borderDash': const [6, 6],
          'borderWidth': 2,
          'pointRadius': 0,
          'fill': false,
        },
      ],
    };
  }

  Map<String, dynamic> _buildCartesianChartOptions({
    required String yAxisLabel,
    bool useDateLabels = false,
  }) {
    return {
      'responsive': true,
      'maintainAspectRatio': false,
      'interaction': {
        'mode': 'index',
        'intersect': false,
      },
      'plugins': {
        'legend': {'display': false},
      },
      'scales': {
        'x': {
          'grid': {'display': false},
          'ticks': {
            'color': '#90A4AE',
            'maxRotation': 0,
            'autoSkip': true,
          },
        },
        'y': {
          'beginAtZero': true,
          'title': {
            'display': true,
            'text': yAxisLabel,
            'color': '#90A4AE',
          },
          'ticks': {'color': '#90A4AE'},
          'grid': {'color': '#E6ECEF'},
        },
      },
    };
  }

  Map<String, dynamic> _buildHydrationChartOptions() {
    return {
      'responsive': true,
      'maintainAspectRatio': false,
      'interaction': {
        'mode': 'index',
        'intersect': false,
      },
      'plugins': {
        'legend': {'display': false},
      },
      'scales': {
        'x': {
          'grid': {'display': false},
          'ticks': {
            'color': '#90A4AE',
            'maxRotation': 0,
            'autoSkip': true,
          },
        },
        'y': {
          'beginAtZero': true,
          'suggestedMax': 4,
          'title': {
            'display': true,
            'text': 'Liters',
            'color': '#90A4AE',
          },
          'ticks': {'color': '#90A4AE'},
          'grid': {'color': '#E6ECEF'},
        },
      },
    };
  }

  Map<String, dynamic> _buildDoughnutOptions() {
    return {
      'responsive': true,
      'maintainAspectRatio': false,
      'cutout': '68%',
      'plugins': {
        'legend': {'display': false},
      },
    };
  }

  List<String> _dailyPointLabels({required bool useDateLabels}) {
    final format = DateFormat(useDateLabels ? 'MMM d' : 'E');
    return _dailyPoints.map((point) => format.format(point.date)).toList();
  }

  List<Map<String, dynamic>> _extractLogs(Map<String, dynamic> response) {
    final logs = response['logs'];
    if (logs is! List) return [];
    return logs
        .whereType<Map>()
        .map((log) => Map<String, dynamic>.from(log))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _extractAnthropometricHistory(
    Map<String, dynamic> response,
  ) {
    final history = response['anthropometricHistory'];
    if (history is! List) return [];
    final mapped = history
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    mapped.sort((a, b) => _timestampOf(a).compareTo(_timestampOf(b)));
    return mapped;
  }

  List<Map<String, dynamic>> _extractLabResultsHistory(
    Map<String, dynamic> response,
  ) {
    final history = response['labResultsHistory'];
    if (history is! List) return [];
    final mapped = history
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    mapped.sort((a, b) => _timestampOf(b).compareTo(_timestampOf(a)));
    return mapped;
  }

  Map<String, dynamic> _extractAnalyticsSummary(Map<String, dynamic> response) {
    final summary = response['summary'];
    if (summary is Map) {
      return Map<String, dynamic>.from(summary);
    }
    return <String, dynamic>{};
  }

  List<_DailyAnalyticsPoint> _dailyPointsFromSummary(Map<String, dynamic> summary) {
    final dailySummaries = summary['dailySummaries'];
    if (dailySummaries is! List) return [];
    return dailySummaries
        .whereType<Map>()
        .map((entry) => _DailyAnalyticsPoint.fromSummary(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  List<_DailyAnalyticsPoint> _mergeHydrationFallback(
    List<_DailyAnalyticsPoint> points,
    List<Map<String, dynamic>> logs,
  ) {
    if (points.isEmpty || logs.isEmpty) return points;

    final waterByDate = <String, double>{};
    for (final log in logs) {
      final dateKey = log['date']?.toString();
      if (dateKey == null || dateKey.isEmpty) continue;
      waterByDate.update(
        dateKey,
        (value) => value + _waterMlFromLog(log),
        ifAbsent: () => _waterMlFromLog(log),
      );
    }

    return points.map((point) {
      if (point.waterMl > 0) return point;
      final fallbackWater = waterByDate[_dateKey(point.date)] ?? 0;
      if (fallbackWater <= 0) return point;
      return point.copyWith(waterMl: fallbackWater);
    }).toList(growable: false);
  }

  List<_GrowthPoint> _growthHistoryPoints() {
    return _anthropometricHistory
        .map((entry) => _GrowthPoint.fromMap(entry))
        .where((point) => point.weightKg > 0 || point.heightCm > 0)
        .toList(growable: false);
  }

  _MacroTotals _macroTotals() {
    final proteinGrams = _dailyPoints.fold<double>(0, (sum, p) => sum + p.protein);
    final carbGrams =
        _dailyPoints.fold<double>(0, (sum, p) => sum + p.carbohydrate);
    final fatGrams = _dailyPoints.fold<double>(0, (sum, p) => sum + p.fat);
    return _MacroTotals.fromGrams(
      proteinGrams: proteinGrams,
      carbGrams: carbGrams,
      fatGrams: fatGrams,
    );
  }

  double _averageFor(double Function(_DailyAnalyticsPoint point) selector) {
    if (_dailyPoints.isEmpty) return 0;
    final total = _dailyPoints.fold<double>(0, (sum, point) => sum + selector(point));
    return total / _dailyPoints.length;
  }

  int _daysWithMeals() {
    return _dailyPoints.where((point) => point.mealCount > 0).length;
  }

  int _daysWithWater() {
    return _dailyPoints.where((point) => point.waterMl > 0).length;
  }

  String _analyticsRangeKey(String range) {
    switch (range) {
      case 'Week':
      default:
        return 'week';
    }
  }

  ({DateTime start, DateTime end}) _analyticsDateRange(
    String range, {
    DateTime? endDate,
  }) {
    final end = DateTime(
      (endDate ?? DateTime.now()).year,
      (endDate ?? DateTime.now()).month,
      (endDate ?? DateTime.now()).day,
    );
    final days = switch (range) {
      _ => 6,
    };
    return (start: end.subtract(Duration(days: days)), end: end);
  }

  String _dateKey(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value);
  }

  double _waterMlFromLog(Map<String, dynamic> log) {
    final explicitWater = _toDouble(
      log['waterMl'] ?? log['water_ml'] ?? log['fluid_ml'],
    );
    if (explicitWater > 0) return explicitWater;

    final name = (log['name'] ?? log['foodName'] ?? log['food_name'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (name == null || name.isEmpty) return 0;

    const hydrationKeywords = [
      'water',
      'juice',
      'milk',
      'tea',
      'coffee',
      'smoothie',
      'drink',
      'beverage',
      'liquid',
      'coconut water',
      'sports drink',
      'electrolyte',
    ];
    final isHydrationItem = hydrationKeywords.any(name.contains);
    if (!isHydrationItem) return 0;

    final portion = (log['portion'] ??
            log['selectedServingDescription'] ??
            log['selected_serving_description'])
        ?.toString()
        .toLowerCase() ??
        '';

    final mlMatch = RegExp(r'(\d+(?:\.\d+)?)\s*m\s*l\b').firstMatch(portion);
    if (mlMatch != null) {
      return double.tryParse(mlMatch.group(1) ?? '') ?? 0;
    }

    final cupMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:cup|c\b)').firstMatch(portion);
    if (cupMatch != null) {
      final cups = double.tryParse(cupMatch.group(1) ?? '');
      return cups == null ? 0 : cups * 240;
    }

    final ozMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:oz|fl\s*oz|fluid\s*oz)\b',
    ).firstMatch(portion);
    if (ozMatch != null) {
      final ounces = double.tryParse(ozMatch.group(1) ?? '');
      return ounces == null ? 0 : ounces * 30;
    }

    return 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _maxValue(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a > b ? a : b);
  }

  double _niceInterval(double maxY) {
    if (maxY <= 10) return 2;
    if (maxY <= 50) return 10;
    if (maxY <= 100) return 20;
    if (maxY <= 500) return 100;
    if (maxY <= 2000) return 250;
    return 500;
  }

  DateTime _timestampOf(Map<String, dynamic> map) {
    final candidates = [
      map['updatedAt'],
      map['createdAt'],
      map['date'],
    ];
    for (final candidate in candidates) {
      final parsed = DateTime.tryParse(candidate?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatLogTime(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    return DateFormat('h:mm a').format(parsed.toLocal());
  }

  String _firstTextValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  String _profileDisplayValue(
    Map<String, dynamic> source,
    List<String> keys, {
    String fallback = 'Not recorded',
  }) {
    final value = _firstTextValue(source, keys);
    return value.isEmpty ? fallback : value;
  }

  List<List<String>> _medicalProfileRows() {
    final name = _firstTextValue(_userProfile, [
      'childFullName',
      'fullName',
      'displayName',
      'name',
    ]);
    final rows = <List<String>>[
      ['Name', name.isEmpty ? 'Not recorded' : name],
      [
        'Age',
        _profileDisplayValue(_userProfile, ['age', 'childAge']),
      ],
      [
        'CKD Stage',
        _profileDisplayValue(_medicalProfile, ['ckdStage', 'ckd_stage', 'stage']),
      ],
      [
        'Kidney Disease Type',
        _profileDisplayValue(_medicalProfile, [
          'kidneyDiseaseType',
          'kidney_disease_type',
        ]),
      ],
      [
        'Dialysis Status',
        _profileDisplayValue(_medicalProfile, [
          'dialysisStatus',
          'dialysis_status',
          'onDialysis',
        ]),
      ],
      [
        'Treatment Frequency',
        _profileDisplayValue(_medicalProfile, [
          'treatmentFrequency',
          'treatment_frequency',
        ]),
      ],
      [
        'Fluid Restriction',
        _profileDisplayValue(_medicalProfile, [
          'fluidRestrictionStatus',
          'fluid_restriction_status',
        ]),
      ],
      [
        'Fluid Limit',
        _profileDisplayValue(_medicalProfile, [
          'fluidLimitMl',
          'fluid_limit_ml',
        ]),
      ],
      [
        'Diagnosis Date',
        _profileDisplayValue(_medicalProfile, [
          'dateOfDiagnosis',
          'date_of_diagnosis',
        ]),
      ],
    ];
    return rows.where((row) => row[1] != 'Not recorded').toList();
  }

  pw.Widget _pdfSummaryBarChart({
    required String title,
    required List<_PdfBarItem> items,
    required PdfColor accent,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE0ECE8)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
          ),
          pw.SizedBox(height: 8),
          if (items.isEmpty)
            pw.Text('No chart data available.')
          else
            ...items.map((item) {
              final width = (item.ratio.clamp(0.0, 1.0) * 180).toDouble();
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 7),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 88,
                      child: pw.Text(
                        item.label,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Container(
                      width: 180,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFEFF4F2),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Container(
                        width: width,
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: item.color ?? accent,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Text(
                        item.value,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  List<_PdfBarItem> _pdfNutrientBars() {
    final averages = [
      (
        label: 'Sodium',
        value: _averageFor((point) => point.sodium),
        unit: 'mg',
        color: const PdfColor.fromInt(0xFF42A5F5),
      ),
      (
        label: 'Potassium',
        value: _averageFor((point) => point.potassium),
        unit: 'mg',
        color: const PdfColor.fromInt(0xFF66BB6A),
      ),
      (
        label: 'Phosphorus',
        value: _averageFor((point) => point.phosphorus),
        unit: 'mg',
        color: const PdfColor.fromInt(0xFFFFB74D),
      ),
      (
        label: 'Protein',
        value: _averageFor((point) => point.protein),
        unit: 'g',
        color: const PdfColor.fromInt(0xFF9E86FF),
      ),
    ];
    final maxValue = _maxValue(averages.map((item) => item.value).toList());
    return averages
        .map(
          (item) => _PdfBarItem(
            label: item.label,
            value:
                '${item.value.toStringAsFixed(item.unit == 'g' ? 1 : 0)} ${item.unit}',
            ratio: maxValue <= 0 ? 0 : item.value / maxValue,
            color: item.color,
          ),
        )
        .toList(growable: false);
  }

  List<_PdfBarItem> _pdfGrowthBars(List<_GrowthPoint> growthPoints) {
    final latest = growthPoints.isNotEmpty ? growthPoints.last : null;
    if (latest == null) return [];
    return [
      _PdfBarItem(
        label: 'Weight',
        value: latest.weightLabel,
        ratio: latest.weightKg / 80,
        color: const PdfColor.fromInt(0xFF9E86FF),
      ),
      _PdfBarItem(
        label: 'Height',
        value: latest.heightLabel,
        ratio: latest.heightCm / 180,
        color: const PdfColor.fromInt(0xFF42A5F5),
      ),
      _PdfBarItem(
        label: 'BMI',
        value: latest.bmiLabel,
        ratio: (latest.bmi ?? 0) / 35,
        color: const PdfColor.fromInt(0xFF00C874),
      ),
    ];
  }

  List<_PdfBarItem> _pdfHydrationBars() {
    final points = _dailyPoints.length > 7
        ? _dailyPoints.sublist(_dailyPoints.length - 7)
        : _dailyPoints;
    return points
        .map(
          (point) => _PdfBarItem(
            label: DateFormat('MMM d').format(point.date),
            value: '${(point.waterMl / 1000).toStringAsFixed(1)} L',
            ratio: (point.waterMl / 1000) / 1.5,
            color: point.waterMl > 1500
                ? const PdfColor.fromInt(0xFFEF5350)
                : const PdfColor.fromInt(0xFF42A5F5),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _exportAnalyticsPdf() async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final bytes = await _buildAnalyticsPdf();
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'nutrikidney_analytics_$timestamp.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to export PDF: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<Uint8List> _buildAnalyticsPdf() async {
    final pdf = pw.Document();
    final exportDate = DateFormat('MMM d, yyyy h:mm a').format(DateTime.now());
    final growthPoints = _growthHistoryPoints();
    final latestGrowth = growthPoints.isNotEmpty ? growthPoints.last : null;
    final medicalRows = _medicalProfileRows();
    final mealRows = _historyLogsForSelectedDate.map((log) {
      final name = log['name']?.toString() ?? 'Food';
      final mealType = log['mealType']?.toString() ?? 'Meal';
      final portion = log['portion']?.toString() ?? '1 serving';
      final calories = _toDouble(log['calories']).round();
      return [name, mealType, portion, '$calories kcal'];
    }).toList(growable: false);
    final dailyRows = _dailyPoints.map((point) {
      return [
        DateFormat('MMM d, yyyy').format(point.date),
        point.mealCount.toString(),
        point.calories.round().toString(),
        point.protein.toStringAsFixed(1),
        point.sodium.round().toString(),
        (point.waterMl / 1000).toStringAsFixed(1),
      ];
    }).toList(growable: false);
    final labRows = _labResultsHistory.map((lab) {
      final values = _labDetailEntries(lab)
          .map((entry) => '${entry.label}: ${entry.value} ${entry.unit}'.trim())
          .join(', ');
      return [
        _formatLabDate(lab['date'] ?? lab['resultDate'] ?? lab['createdAt']),
        values.isEmpty ? 'No values' : values,
      ];
    }).toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'NutriKidney Analytics Report',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Exported: $exportDate'),
          pw.Text('Range: $_activeTimeRange'),
          pw.Text('Category view: $_activeCategory'),
          pw.SizedBox(height: 18),
          pw.Header(level: 1, text: 'Medical Profile'),
          if (medicalRows.isEmpty)
            pw.Text('No medical profile details available.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Field', 'Value'],
              data: medicalRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8F5F1),
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
              },
            ),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Summary'),
          pw.Bullet(text: 'Days tracked: ${_dailyPoints.length}'),
          pw.Bullet(text: 'Days with meals: ${_daysWithMeals()}'),
          pw.Bullet(
            text:
                'Average sodium: ${_averageFor((point) => point.sodium).round()} mg',
          ),
          pw.Bullet(
            text:
                'Average protein: ${_averageFor((point) => point.protein).toStringAsFixed(1)} g',
          ),
          pw.Bullet(
            text:
                'Average hydration: ${(_averageFor((point) => point.waterMl) / 1000).toStringAsFixed(1)} L',
          ),
          if (latestGrowth != null) ...[
            pw.Bullet(text: 'Latest weight: ${latestGrowth.weightLabel}'),
            pw.Bullet(text: 'Latest height: ${latestGrowth.heightLabel}'),
            pw.Bullet(text: latestGrowth.bmiLabel),
          ],
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Summarized Charts'),
          _pdfSummaryBarChart(
            title: 'Nutrients - Average Daily Intake',
            items: _pdfNutrientBars(),
            accent: const PdfColor.fromInt(0xFF00C874),
          ),
          pw.SizedBox(height: 8),
          _pdfSummaryBarChart(
            title: 'Growth - Latest Measurement Snapshot',
            items: _pdfGrowthBars(growthPoints),
            accent: const PdfColor.fromInt(0xFF9E86FF),
          ),
          pw.SizedBox(height: 8),
          _pdfSummaryBarChart(
            title: 'Hydration - Recent Daily Intake',
            items: _pdfHydrationBars(),
            accent: const PdfColor.fromInt(0xFF42A5F5),
          ),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Daily Analytics'),
          if (dailyRows.isEmpty)
            pw.Text('No daily analytics data available.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Date',
                'Meals',
                'Calories',
                'Protein (g)',
                'Sodium (mg)',
                'Water (L)',
              ],
              data: dailyRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8F5F1),
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Meal History (${DateFormat('MMM d, yyyy').format(_historyDate)})'),
          if (mealRows.isEmpty)
            pw.Text('No meal logs found for the selected date.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Food', 'Meal', 'Portion', 'Calories'],
              data: mealRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFEFF7FB),
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Previous Lab Results'),
          if (labRows.isEmpty)
            pw.Text('No lab history recorded yet.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Details'],
              data: labRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F0FF),
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
              },
            ),
        ],
      ),
    );

    return pdf.save();
  }

  String _formatLabDate(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed != null) {
      return DateFormat('MMM d, yyyy').format(parsed.toLocal());
    }
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? 'No date' : text;
  }

  List<_LabDetailEntry> _labDetailEntries(Map<String, dynamic> lab) {
    final entries = <_LabDetailEntry>[];

    void addEntry(
      String label,
      dynamic value,
      String unit, {
      String? status,
    }) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') return;
      entries.add(
        _LabDetailEntry(
          label: label,
          value: text,
          unit: unit,
          status: status?.trim().isEmpty == true ? null : status?.trim(),
        ),
      );
    }

    addEntry('Creatinine', lab['creatinine'], 'mg/dL');
    addEntry('eGFR', lab['egfr'] ?? lab['eGFR'], 'mL/min');
    addEntry('Potassium', lab['potassium'], 'mEq/L');
    addEntry(
      'Phosphorus',
      lab['phosphorus'],
      'mg/dL',
      status: lab['phosphorus_status']?.toString(),
    );
    addEntry('Calcium', lab['calcium'], 'mg/dL');
    addEntry(
      'Sodium',
      lab['sodium'],
      'mEq/L',
      status: lab['sodium_status']?.toString(),
    );

    return entries;
  }
}

class _DailyAnalyticsPoint {
  final DateTime date;
  final int mealCount;
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;
  final double sodium;
  final double potassium;
  final double phosphorus;
  final double waterMl;

  const _DailyAnalyticsPoint({
    required this.date,
    required this.mealCount,
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
    required this.sodium,
    required this.potassium,
    required this.phosphorus,
    required this.waterMl,
  });

  _DailyAnalyticsPoint copyWith({
    DateTime? date,
    int? mealCount,
    double? calories,
    double? protein,
    double? carbohydrate,
    double? fat,
    double? sodium,
    double? potassium,
    double? phosphorus,
    double? waterMl,
  }) {
    return _DailyAnalyticsPoint(
      date: date ?? this.date,
      mealCount: mealCount ?? this.mealCount,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbohydrate: carbohydrate ?? this.carbohydrate,
      fat: fat ?? this.fat,
      sodium: sodium ?? this.sodium,
      potassium: potassium ?? this.potassium,
      phosphorus: phosphorus ?? this.phosphorus,
      waterMl: waterMl ?? this.waterMl,
    );
  }

  factory _DailyAnalyticsPoint.fromSummary(Map<String, dynamic> summary) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final totals = summary['totals'] is Map
        ? Map<String, dynamic>.from(summary['totals'] as Map)
        : const <String, dynamic>{};

    return _DailyAnalyticsPoint(
      date: DateTime.tryParse(summary['date']?.toString() ?? '') ?? DateTime.now(),
      mealCount: asDouble(summary['mealCount'] ?? summary['meal_count']).round(),
      calories: asDouble(totals['calories']),
      protein: asDouble(totals['protein']),
      carbohydrate: asDouble(totals['carbohydrate']),
      fat: asDouble(totals['fat']),
      sodium: asDouble(totals['sodium']),
      potassium: asDouble(totals['potassium']),
      phosphorus: asDouble(totals['phosphorus']),
      waterMl: asDouble(summary['waterMl'] ?? summary['water_ml'] ?? summary['fluid_ml']),
    );
  }
}

class _GrowthPoint {
  final DateTime date;
  final double weightKg;
  final double heightCm;
  final double? bmi;

  const _GrowthPoint({
    required this.date,
    required this.weightKg,
    required this.heightCm,
    required this.bmi,
  });

  factory _GrowthPoint.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    DateTime parseDate(dynamic value) {
      return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    }

    return _GrowthPoint(
      date: parseDate(map['updatedAt'] ?? map['createdAt'] ?? map['date']),
      weightKg: asDouble(map['weight_kg'] ?? map['weight']),
      heightCm: asDouble(map['height_cm'] ?? map['height']),
      bmi: (() {
        final value = map['bmi'];
        if (value == null || value == '') return null;
        return asDouble(value);
      })(),
    );
  }

  String get weightLabel =>
      weightKg > 0 ? '${weightKg.toStringAsFixed(1)} kg' : 'No weight';
  String get heightLabel =>
      heightCm > 0 ? '${heightCm.toStringAsFixed(0)} cm' : 'No height';
  String get bmiLabel =>
      bmi != null && bmi! > 0 ? 'BMI ${bmi!.toStringAsFixed(1)}' : 'BMI unavailable';
}

class _MacroTotals {
  final double proteinCalories;
  final double carbCalories;
  final double fatCalories;
  final double totalCalories;
  final int proteinPercent;
  final int carbPercent;
  final int fatPercent;

  const _MacroTotals({
    required this.proteinCalories,
    required this.carbCalories,
    required this.fatCalories,
    required this.totalCalories,
    required this.proteinPercent,
    required this.carbPercent,
    required this.fatPercent,
  });

  factory _MacroTotals.fromGrams({
    required double proteinGrams,
    required double carbGrams,
    required double fatGrams,
  }) {
    final proteinCalories = proteinGrams * 4;
    final carbCalories = carbGrams * 4;
    final fatCalories = fatGrams * 9;
    final totalCalories = proteinCalories + carbCalories + fatCalories;

    int percent(double value) {
      if (totalCalories <= 0) return 0;
      return ((value / totalCalories) * 100).round();
    }

    return _MacroTotals(
      proteinCalories: proteinCalories,
      carbCalories: carbCalories,
      fatCalories: fatCalories,
      totalCalories: totalCalories,
      proteinPercent: percent(proteinCalories),
      carbPercent: percent(carbCalories),
      fatPercent: percent(fatCalories),
    );
  }
}

class _LabDetailEntry {
  final String label;
  final String value;
  final String unit;
  final String? status;

  const _LabDetailEntry({
    required this.label,
    required this.value,
    required this.unit,
    this.status,
  });
}

class _PdfBarItem {
  final String label;
  final String value;
  final double ratio;
  final PdfColor? color;

  const _PdfBarItem({
    required this.label,
    required this.value,
    required this.ratio,
    this.color,
  });
}
