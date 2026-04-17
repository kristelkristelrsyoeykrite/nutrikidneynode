import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dashboard.dart';
import 'food_log.dart';
import 'health_metrics.dart';
import 'profile.dart'; // Added Profile Import

class AnalyticsPage extends StatefulWidget {
  final String initialCategory;

  const AnalyticsPage({super.key, this.initialCategory = 'Nutrients'});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  int _currentIndex = 2;
  String _activeTimeRange = 'Week';
  late String _activeCategory;

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Analytics',
                        style: TextStyle(
                          color: Color(0xFF37474F),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Track progress and trends',
                        style: TextStyle(
                          color: Color(0xFF90A4AE),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.download,
                      size: 16,
                      color: Color(0xFF37474F),
                    ),
                    label: const Text(
                      'Export',
                      style: TextStyle(color: Color(0xFF37474F)),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- Time Range Toggle ---
              Row(
                children: [
                  _buildTimeToggle('Week'),
                  const SizedBox(width: 8),
                  _buildTimeToggle('Month'),
                  const SizedBox(width: 8),
                  _buildTimeToggle('3 Months'),
                ],
              ),
              const SizedBox(height: 24),

              // --- Category Toggle ---
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

              // --- DYNAMIC CONTENT ---
              _buildDynamicContent(),

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
            if (index == 0) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const DashboardPage()),
                (route) => false,
              );
            } else if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const FoodLogPage()),
              );
            } else if (index == 3) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HealthMetricsPage(),
                ),
              );
            } else if (index == 4) {
              // --- NEW PROFILE NAVIGATION ---
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

  // ==========================================
  // DYNAMIC CONTENT BUILDERS
  // ==========================================

  Widget _buildDynamicContent() {
    if (_activeCategory == 'Growth') {
      return _buildGrowthContent();
    } else if (_activeCategory == 'Hydration') {
      return _buildHydrationContent();
    } else {
      return _buildNutrientsContent();
    }
  }

  Widget _buildNutrientsContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Avg.Sodium',
                '1,215 mg',
                '-8% vs last week',
                Icons.trending_down,
                const Color(0xFF00C874),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Avg.Protein',
                '47 g',
                '+5% vs last week',
                Icons.trending_up,
                const Color(0xFF00C874),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildChartCard(
          title: 'Sodium & Potassium Trends',
          legends: [
            _buildLegend(const Color(0xFF42A5F5), 'Sodium (mg)'),
            _buildLegend(const Color(0xFF66BB6A), 'Potassium (mg)'),
          ],
          chart: SizedBox(height: 200, child: LineChart(_buildLineChartData())),
        ),
        const SizedBox(height: 16),
        _buildChartCard(
          title: 'Protein & Phosphorus',
          legends: [
            _buildLegend(const Color(0xFF9E86FF), 'Protein (g)'),
            _buildLegend(const Color(0xFFFFB74D), 'Phosphorus (mg)'),
          ],
          chart: SizedBox(height: 200, child: BarChart(_buildBarChartData())),
        ),
        const SizedBox(height: 16),
        _buildChartCard(
          title: 'Macro Distribution',
          legends: [
            _buildLegend(const Color(0xFF66BB6A), 'Protein\n25%'),
            _buildLegend(const Color(0xFF42A5F5), 'Carbs\n50%'),
            _buildLegend(const Color(0xFFFFB74D), 'Fat\n25%'),
          ],
          chart: SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(_buildPieChartData()),
                const Text(
                  '100%',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 26,
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Current Weight',
                '28.5 kg',
                '+0.5kg this month',
                Icons.trending_up,
                const Color(0xFF00C874),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Current Height',
                '132 cm',
                '+1cm this month',
                Icons.trending_up,
                const Color(0xFF00C874),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildChartCard(
          title: 'Weight Trend (Last 6 Months)',
          legends: [_buildLegend(const Color(0xFF9E86FF), 'Weight (kg)')],
          chart: SizedBox(
            height: 200,
            child: LineChart(_buildWeightLineChartData()),
          ),
        ),
      ],
    );
  }

  Widget _buildHydrationContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Avg Daily Intake',
                '1.1 L',
                'Under 1.5L Limit',
                Icons.check_circle,
                const Color(0xFF00C874),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Adherence',
                '92%',
                '+2% vs last week',
                Icons.trending_up,
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
            _buildLegend(const Color(0xFFEF5350), 'Daily Limit (1.5L)'),
          ],
          chart: SizedBox(
            height: 200,
            child: BarChart(_buildHydrationBarChartData()),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // UI WIDGET HELPERS
  // ==========================================

  Widget _buildTimeToggle(String title) {
    bool isActive = _activeTimeRange == title;
    return GestureDetector(
      onTap: () => setState(() => _activeTimeRange = title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFC040FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFFC040FF) : Colors.grey.shade300,
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
    bool isActive = _activeCategory == title;
    return GestureDetector(
      onTap: () => setState(() => _activeCategory = title),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFC040FF) : Colors.transparent,
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
    String changeText,
    IconData icon,
    Color changeColor,
  ) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
              ),
              Icon(icon, color: changeColor, size: 16),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: changeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              changeText,
              style: TextStyle(
                color: changeColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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
          Row(mainAxisAlignment: MainAxisAlignment.center, children: legends),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
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
      ),
    );
  }

  // ==========================================
  // FL CHART CONFIGURATIONS
  // ==========================================

  LineChartData _buildLineChartData() {
    return LineChartData(
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => Colors.white,
          tooltipPadding: const EdgeInsets.all(12),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final isSodium = spot.barIndex == 0;
              final color = isSodium
                  ? const Color(0xFF42A5F5)
                  : const Color(0xFF66BB6A);
              final label = isSodium ? 'Sodium' : 'Potassium';
              return LineTooltipItem(
                '$label: ${spot.y.toInt()} mg',
                TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 550,
        getDrawingHorizontalLine: (double value) => FlLine(
          color: Colors.grey.shade200,
          strokeWidth: 1,
          dashArray: const [5, 5],
        ),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (double value, TitleMeta meta) {
              const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              if (value.toInt() < 0 || value.toInt() >= days.length) {
                return const Text('');
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  days[value.toInt()],
                  style: const TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 550,
            getTitlesWidget: (double value, TitleMeta meta) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
          left: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      minX: 0,
      maxX: 6,
      minY: 0,
      maxY: 2200,
      lineBarsData: [
        LineChartBarData(
          spots: const [
            FlSpot(0, 1150),
            FlSpot(1, 1050),
            FlSpot(2, 1250),
            FlSpot(3, 1200),
            FlSpot(4, 1100),
            FlSpot(5, 1350),
            FlSpot(6, 1150),
          ],
          isCurved: true,
          color: const Color(0xFF42A5F5),
          barWidth: 2,
          dotData: const FlDotData(show: true),
        ),
        LineChartBarData(
          spots: const [
            FlSpot(0, 1800),
            FlSpot(1, 1900),
            FlSpot(2, 1650),
            FlSpot(3, 2000),
            FlSpot(4, 1850),
            FlSpot(5, 2150),
            FlSpot(6, 1800),
          ],
          isCurved: true,
          color: const Color(0xFF66BB6A),
          barWidth: 2,
          dotData: const FlDotData(show: true),
        ),
      ],
    );
  }

  BarChartData _buildBarChartData() {
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: 1000,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (BarChartGroupData group) => Colors.white,
          tooltipPadding: const EdgeInsets.all(16),
          tooltipMargin: 8,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            if (rodIndex == 0) return null; // Avoid duplicate bubbles
            const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            String day = days[group.x.toInt()];
            double protein = group.barRods[0].toY;
            double phosphorus = group.barRods[1].toY;

            return BarTooltipItem(
              '$day\n',
              const TextStyle(
                color: Color(0xFF37474F),
                fontWeight: FontWeight.normal,
                fontSize: 16,
              ),
              children: [
                TextSpan(
                  text: 'phosphorus:${phosphorus.toInt()}\n',
                  style: const TextStyle(
                    color: Color(0xFFD6B26A),
                    fontWeight: FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
                TextSpan(
                  text: 'protein:${protein.toInt()}',
                  style: const TextStyle(
                    color: Color(0xFF9E86FF),
                    fontWeight: FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (double value, TitleMeta meta) {
              const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              if (value.toInt() < 0 || value.toInt() >= days.length) {
                return const Text('');
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  days[value.toInt()],
                  style: const TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 250,
            getTitlesWidget: (double value, TitleMeta meta) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 250,
        getDrawingHorizontalLine: (double value) => FlLine(
          color: Colors.grey.shade200,
          strokeWidth: 1,
          dashArray: const [5, 5],
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
          left: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      barGroups: [
        _makeBarGroup(0, 40, 250),
        _makeBarGroup(1, 45, 250),
        _makeBarGroup(2, 40, 250),
        _makeBarGroup(3, 50, 250),
        _makeBarGroup(4, 46, 790, isHighlight: true),
        _makeBarGroup(5, 45, 900),
        _makeBarGroup(6, 45, 950),
      ],
    );
  }

  BarChartGroupData _makeBarGroup(
    int x,
    double protein,
    double phosphorus, {
    bool isHighlight = false,
  }) {
    return BarChartGroupData(
      x: x,
      barsSpace: 4,
      barRods: [
        BarChartRodData(
          toY: protein,
          color: const Color(0xFF9E86FF),
          width: 8,
          borderRadius: BorderRadius.circular(2),
        ),
        BarChartRodData(
          toY: phosphorus,
          color: const Color(0xFFFFB74D),
          width: 8,
          borderRadius: BorderRadius.circular(2),
          backDrawRodData: BackgroundBarChartRodData(
            show: isHighlight,
            toY: 1000,
            color: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }

  PieChartData _buildPieChartData() {
    return PieChartData(
      sectionsSpace: 4,
      centerSpaceRadius: 60,
      sections: [
        PieChartSectionData(
          color: const Color(0xFF42A5F5),
          value: 50,
          radius: 25,
          showTitle: false,
        ),
        PieChartSectionData(
          color: const Color(0xFF66BB6A),
          value: 25,
          radius: 25,
          showTitle: false,
        ),
        PieChartSectionData(
          color: const Color(0xFFFFB74D),
          value: 25,
          radius: 25,
          showTitle: false,
        ),
      ],
    );
  }

  LineChartData _buildWeightLineChartData() {
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => Colors.white,
          getTooltipItems: (spots) => spots
              .map(
                (s) => LineTooltipItem(
                  '${s.y} kg',
                  const TextStyle(
                    color: Color(0xFF9E86FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
              .toList(),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (double value) => FlLine(
          color: Colors.grey.shade200,
          strokeWidth: 1,
          dashArray: const [5, 5],
        ),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (double value, TitleMeta meta) {
              const months = ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'];
              if (value.toInt() < 0 || value.toInt() >= months.length) {
                return const Text('');
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  months[value.toInt()],
                  style: const TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 1,
            getTitlesWidget: (double value, TitleMeta meta) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
          left: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      minX: 0,
      maxX: 5,
      minY: 26,
      maxY: 30,
      lineBarsData: [
        LineChartBarData(
          spots: const [
            FlSpot(0, 26.5),
            FlSpot(1, 27.0),
            FlSpot(2, 27.2),
            FlSpot(3, 27.8),
            FlSpot(4, 28.0),
            FlSpot(5, 28.5),
          ],
          isCurved: true,
          color: const Color(0xFF9E86FF),
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF9E86FF).withOpacity(0.1),
          ),
        ),
      ],
    );
  }

  BarChartData _buildHydrationBarChartData() {
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: 2.0,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) => Colors.white,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return BarTooltipItem(
              '${days[group.x.toInt()]}\n',
              const TextStyle(
                color: Color(0xFF37474F),
                fontWeight: FontWeight.bold,
              ),
              children: [
                TextSpan(
                  text: '${rod.toY} L',
                  style: const TextStyle(
                    color: Color(0xFF42A5F5),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (double value, TitleMeta meta) {
              const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              if (value.toInt() < 0 || value.toInt() >= days.length) {
                return const Text('');
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  days[value.toInt()],
                  style: const TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 0.5,
            getTitlesWidget: (double value, TitleMeta meta) {
              return Text(
                '${value.toStringAsFixed(1)}L',
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 0.5,
        getDrawingHorizontalLine: (double value) {
          if (value == 1.5) {
            return const FlLine(
              color: Color(0xFFEF5350),
              strokeWidth: 2,
              dashArray: [4, 4],
            );
          }
          return FlLine(
            color: Colors.grey.shade200,
            strokeWidth: 1,
            dashArray: const [5, 5],
          );
        },
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
          left: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      barGroups: [
        BarChartGroupData(
          x: 0,
          barRods: [
            BarChartRodData(
              toY: 1.2,
              color: const Color(0xFF42A5F5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        BarChartGroupData(
          x: 1,
          barRods: [
            BarChartRodData(
              toY: 1.4,
              color: const Color(0xFF42A5F5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        BarChartGroupData(
          x: 2,
          barRods: [
            BarChartRodData(
              toY: 1.1,
              color: const Color(0xFF42A5F5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        BarChartGroupData(
          x: 3,
          barRods: [
            BarChartRodData(
              toY: 1.6,
              color: const Color(0xFFEF5350),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        BarChartGroupData(
          x: 4,
          barRods: [
            BarChartRodData(
              toY: 1.3,
              color: const Color(0xFF42A5F5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        BarChartGroupData(
          x: 5,
          barRods: [
            BarChartRodData(
              toY: 1.0,
              color: const Color(0xFF42A5F5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        BarChartGroupData(
          x: 6,
          barRods: [
            BarChartRodData(
              toY: 1.2,
              color: const Color(0xFF42A5F5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ],
    );
  }
}
