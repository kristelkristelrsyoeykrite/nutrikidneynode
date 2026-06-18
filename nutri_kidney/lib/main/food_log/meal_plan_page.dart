import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../food_log.dart';

/// A full-page view for displaying generated meal plans.
/// Not added to the nav bar — only navigated to when a meal plan is generated.
class MealPlanPage extends StatefulWidget {
  final Map<String, dynamic> mealPlan;
  final String? profileUserId;
  final String selectedDate;
  final Future<void> Function(Map<String, dynamic>) onAddMealPlan;

  const MealPlanPage({
    super.key,
    required this.mealPlan,
    this.profileUserId,
    required this.selectedDate,
    required this.onAddMealPlan,
  });

  @override
  State<MealPlanPage> createState() => _MealPlanPageState();
}

class _MealPlanPageState extends State<MealPlanPage> {
  int _selectedDayIndex = 0;
  String? _expandedComponentKey;
  bool _isAddingPlan = false;

  List<Map<String, dynamic>> get _days => _mealPlanDays(widget.mealPlan);
  List<Map<String, dynamic>> get _meals => _mealPlanMeals(widget.mealPlan);

  Map<String, dynamic> get _profile => widget.mealPlan['nutritionProfile'] is Map
      ? Map<String, dynamic>.from(widget.mealPlan['nutritionProfile'] as Map)
      : const <String, dynamic>{};

  Map<String, dynamic> get _restrictions => widget.mealPlan['restrictions'] is Map
      ? Map<String, dynamic>.from(widget.mealPlan['restrictions'] as Map)
      : const <String, dynamic>{};

  String _nutrientDisplay(dynamic value) {
    final parsed = _doubleValue(value);
    if (parsed == null || parsed <= 0) return '—';
    if (parsed == parsed.roundToDouble()) return parsed.toInt().toString();
    return parsed.toStringAsFixed(1);
  }

  String _nutrientWithUnit(dynamic value, String unit) {
    final display = _nutrientDisplay(value);
    return display == '—' ? '—' : '$display $unit';
  }

  double? _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _mealPlanDayLabel(String? date, int index) {
    if (date == widget.selectedDate) return 'Today';
    final parsed = DateTime.tryParse(date ?? '');
    if (parsed != null) {
      final tomorrow = DateFormat('yyyy-MM-dd').format(
        DateTime.now().add(const Duration(days: 1)),
      );
      if (date == tomorrow) return 'Tomorrow';
      return DateFormat('MMM d').format(parsed);
    }
    return 'Day ${index + 1}';
  }

  String _mealPlanDateSubtitle(String? date) {
    if (date == null) return '';
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateFormat('EEEE, MMM d, yyyy').format(parsed);
  }

  List<Map<String, dynamic>> _mealPlanMeals(Map<String, dynamic> mealPlan) {
    final days = mealPlan['days'];
    if (days is List && days.isNotEmpty) {
      return days
          .whereType<Map>()
          .expand((rawDay) {
            final day = Map<String, dynamic>.from(rawDay);
            final date = day['date']?.toString();
            final meals = day['meals'];
            if (meals is! List) return const <Map<String, dynamic>>[];
            return meals.whereType<Map>().map((rawMeal) {
              return {
                if (date != null) 'date': date,
                ...Map<String, dynamic>.from(rawMeal),
              };
            });
          })
          .toList(growable: false);
    }
    final meals = mealPlan['meals'];
    if (meals is! List) return const <Map<String, dynamic>>[];
    return meals
        .whereType<Map>()
        .map((meal) => Map<String, dynamic>.from(meal))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _mealPlanDays(Map<String, dynamic> mealPlan) {
    final rawDays = mealPlan['days'];
    if (rawDays is List && rawDays.isNotEmpty) {
      return rawDays
          .whereType<Map>()
          .map((day) => Map<String, dynamic>.from(day))
          .toList(growable: false);
    }
    return [
      {
        'date': mealPlan['planDate'] ?? widget.selectedDate,
        'meals': mealPlan['meals'] ?? const [],
        'totals': mealPlan['totals'] ?? const <String, dynamic>{},
      }
    ];
  }

  String _avoidList() {
    final avoid = _restrictions['avoid'];
    if (avoid is List) return avoid.take(8).join(', ');
    return '';
  }

  String _recommendationLine() {
    final history = widget.mealPlan['historyRecommendations'];
    if (history is! Map) return '';
    final messages = history['messages'];
    if (messages is List && messages.isNotEmpty) {
      return messages.take(2).join(' ');
    }
    return '';
  }

  String _profileLine() {
    final parts = <String>[
      if (_profile['stage'] != null) 'CKD ${_profile['stage']}',
      if (_profile['egfr'] != null) 'eGFR ${_profile['egfr']}',
      'K ${_profile['potassiumStatus'] ?? 'Unknown'}',
      'Phos ${_profile['phosphorusStatus'] ?? 'Unknown'}',
      if (_profile['diabetesRisk'] == true) 'diabetes risk',
      'BMI ${_profile['bmiCategory'] ?? 'Unknown'}',
    ];
    return parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    final planDays = _intValue(
      widget.mealPlan['planDays'] ?? _days.length,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF37474F)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '$planDays-Day Meal Plan',
          style: const TextStyle(
            color: Color(0xFF37474F),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isAddingPlan
                ? null
                : () async {
                    setState(() => _isAddingPlan = true);
                    try {
                      await widget.onAddMealPlan(widget.mealPlan);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Meals added to food log!'),
                          ),
                        );
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isAddingPlan = false);
                    }
                  },
            child: _isAddingPlan
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Add All to Log',
                    style: TextStyle(
                      color: Color(0xFF00BFA5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Profile summary + restrictions bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileLine(),
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_avoidList().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Avoid or limit: ${_avoidList()}',
                    style: const TextStyle(
                      color: Color(0xFF78909C),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Day selector tabs
          Container(
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: _days.asMap().entries.map((entry) {
                  final day = entry.value;
                  final isSelected = entry.key == _selectedDayIndex;
                  final date = day['date']?.toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selectedDayIndex = entry.key;
                        _expandedComponentKey = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00BFA5)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _mealPlanDayLabel(date, entry.key),
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF37474F),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (date != null)
                              Text(
                                DateFormat('MMM d').format(
                                  DateTime.tryParse(date) ?? DateTime.now(),
                                ),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white70
                                      : const Color(0xFF90A4AE),
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Main content
          Expanded(
            child: _days.isEmpty
                ? const Center(child: Text('No meal plan data'))
                : _buildDayContent(_days[_selectedDayIndex]),
          ),
        ],
      ),
    );
  }

  Widget _buildDayContent(Map<String, dynamic> day) {
    final dayMeals = day['meals'] is List
        ? (day['meals'] as List)
            .whereType<Map>()
            .map((meal) => Map<String, dynamic>.from(meal))
            .toList(growable: false)
        : <Map<String, dynamic>>[];
    final dayTotals = day['totals'] is Map
        ? Map<String, dynamic>.from(day['totals'] as Map)
        : <String, dynamic>{};
    final date = day['date']?.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date subtitle
          if (date != null) ...[
            Text(
              _mealPlanDateSubtitle(date),
              style: const TextStyle(
                color: Color(0xFF00695C),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Meals
          if (dayMeals.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Column(
                children: [
                  Icon(Icons.restaurant_outlined,
                      color: Color(0xFFB0BEC5), size: 48),
                  SizedBox(height: 12),
                  Text(
                    'No meals planned for this day yet.',
                    style: TextStyle(color: Color(0xFF78909C), fontSize: 14),
                  ),
                ],
              ),
            )
          else
            ...dayMeals.map((meal) => _buildMealCard(meal, date)),
          // Day totals
          if (dayTotals.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildTotalsCard(dayTotals, 'Day Totals'),
          ],
          // Weekly totals at bottom of last day
          if (_selectedDayIndex == _days.length - 1) ...[
            const SizedBox(height: 12),
            _buildTotalsCard(
              widget.mealPlan['weeklyTotals'] is Map
                  ? Map<String, dynamic>.from(
                      widget.mealPlan['weeklyTotals'] as Map)
                  : <String, dynamic>{},
              'Weekly Averages',
              isWeekly: true,
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal, String? plannedDate) {
    final mealType = meal['mealType']?.toString() ?? 'Meal';
    final name = meal['name']?.toString() ?? 'Food';
    final portion = meal['portion']?.toString() ?? '1 serving';
    final matchConfidence = meal['matchConfidence']?.toString() ?? '';
    final source = meal['source']?.toString() ?? '';
    final needsReview = meal['needsManualReview'] == true;
    final isUnresolved = matchConfidence == 'unresolved' || source == 'unresolved_guide_meal_plan';
    final calories = _doubleValue(meal['calories']);
    final protein = _doubleValue(meal['protein']);
    final sodium = _doubleValue(meal['sodium']);
    final potassium = _doubleValue(meal['potassium']);
    final phosphorus = _doubleValue(meal['phosphorus']);
    final components = meal['componentBreakdown'] is List
        ? (meal['componentBreakdown'] as List)
            .whereType<Map>()
            .map((c) => Map<String, dynamic>.from(c))
            .toList(growable: false)
        : <Map<String, dynamic>>[];
    final validation = meal['recipeValidation'] is Map
        ? Map<String, dynamic>.from(meal['recipeValidation'] as Map)
        : null;
    final validationPassed = validation?['isAllowed'] == true;

    // Card color based on status
    Color cardBg = Colors.white;
    Color borderColor = const Color(0xFFE0F2F1);
    if (isUnresolved) {
      borderColor = const Color(0xFFFFE082);
      cardBg = const Color(0xFFFFFDF5);
    } else if (needsReview) {
      borderColor = const Color(0xFFFFCC80);
      cardBg = const Color(0xFFFFF8E1);
    } else if (validationPassed) {
      borderColor = const Color(0xFFC8E6C9);
      cardBg = const Color(0xFFF1F8E9);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: meal type + status pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  mealType,
                  style: const TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isUnresolved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Guide only',
                    style: TextStyle(
                      color: Color(0xFFE65100),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (needsReview && !isUnresolved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Review',
                    style: TextStyle(
                      color: Color(0xFFF57F17),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (validationPassed && !isUnresolved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Validated',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Name
          Text(
            name,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          // Portion + calories
          Row(
            children: [
              if (!isUnresolved && calories != null && calories > 0) ...[
                Text(
                  '$portion',
                  style: const TextStyle(
                    color: Color(0xFF607D8B),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  isUnresolved
                      ? 'No exact database match — use as a meal idea'
                      : '${_nutrientDisplay(calories)} kcal',
                  style: TextStyle(
                    color: isUnresolved
                        ? const Color(0xFFBF360C)
                        : const Color(0xFF78909C),
                    fontSize: 12,
                    fontStyle: isUnresolved ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
          // Nutrition row (only show if not unresolved and has data)
          if (!isUnresolved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMiniNutrientPill('Protein', _nutrientDisplay(protein), 'g'),
                const SizedBox(width: 6),
                _buildMiniNutrientPill('Sodium', _nutrientDisplay(sodium), 'mg'),
                const SizedBox(width: 6),
                _buildMiniNutrientPill('K', _nutrientDisplay(potassium), 'mg'),
                const SizedBox(width: 6),
                _buildMiniNutrientPill('Phos', _nutrientDisplay(phosphorus), 'mg'),
              ],
            ),
          ],
          // Match info
          if (matchConfidence.isNotEmpty && !isUnresolved) ...[
            const SizedBox(height: 8),
            Text(
              _matchLine(meal),
              style: const TextStyle(
                color: Color(0xFF78909C),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
          // Component breakdown expandable
          if (components.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                setState(() {
                  _expandedComponentKey = _expandedComponentKey == name ? null : name;
                });
              },
              child: Row(
                children: [
                  const Icon(
                    Icons.list_alt_outlined,
                    size: 16,
                    color: Color(0xFF00897B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${components.length} ingredients',
                    style: const TextStyle(
                      color: Color(0xFF00897B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expandedComponentKey == name
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: const Color(0xFF00897B),
                  ),
                ],
              ),
            ),
            if (_expandedComponentKey == name) ...[
              const SizedBox(height: 8),
              ...components.map((component) {
                final compNutrients = component['nutrients'] is Map
                    ? Map<String, dynamic>.from(component['nutrients'] as Map)
                    : <String, dynamic>{};
                final compName = component['matchedName']?.toString() ??
                    component['component']?.toString() ??
                    'Food';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.circle,
                        size: 6,
                        color: Color(0xFFB0BEC5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          compName,
                          style: const TextStyle(
                            color: Color(0xFF546E7A),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '${_nutrientDisplay(compNutrients['calories'])} kcal',
                        style: const TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
          // Add to food log button inline
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isAddingPlan
                  ? null
                  : () async {
                      setState(() => _isAddingPlan = true);
                      try {
                        final dayDate = plannedDate ?? widget.selectedDate;
                        final dayMeals = [meal];
                        await widget.onAddMealPlan({
                          'planDate': dayDate,
                          'planDays': 1,
                          'days': [
                            {
                              'date': dayDate,
                              'meals': dayMeals,
                              'totals': meal['nutrientPreview'] ?? {},
                            }
                          ],
                          'meals': dayMeals,
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$name added to food log!'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Unable to add: $e'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isAddingPlan = false);
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00897B),
                side: const BorderSide(color: Color(0xFF80CBC4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: const Text(
                'Add to Log',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _matchLine(Map<String, dynamic> meal) {
    final confidence = meal['matchConfidence']?.toString() ?? '';
    if (confidence == 'partial') {
      return 'Partial recipe match — nutrition may be estimated.';
    }
    if ((meal['recipeValidation'] is Map) &&
        Map<String, dynamic>.from(meal['recipeValidation'] as Map)['isAllowed'] == true) {
      return 'Recipe passed ingredient validation.';
    }
    if ((meal['componentBreakdown'] is List) &&
        (meal['componentBreakdown'] as List).isNotEmpty) {
      return 'Nutrition estimated from ingredient breakdown.';
    }
    if (meal['needsManualReview'] == true) {
      return 'Review before logging.';
    }
    return '';
  }

  Widget _buildMiniNutrientPill(String label, String value, String unit) {
    final hasValue = value != '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasValue
            ? const Color(0xFFFAFAFA)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasValue
              ? const Color(0xFFE0E0E0)
              : const Color(0xFFEEEEEE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: hasValue
                  ? const Color(0xFF90A4AE)
                  : const Color(0xFFB0BEC5),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hasValue ? '$value $unit' : '—',
            style: TextStyle(
              color: hasValue
                  ? const Color(0xFF37474F)
                  : const Color(0xFFBDBDBD),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(Map<String, dynamic> totals, String title,
      {bool isWeekly = false}) {
    final hasCalories = _doubleValue(totals['calories']) != null &&
        (_doubleValue(totals['calories']) ?? 0) > 0;
    final hasProtein = _doubleValue(totals['protein']) != null &&
        (_doubleValue(totals['protein']) ?? 0) > 0;
    final hasSodium = _doubleValue(totals['sodium']) != null &&
        (_doubleValue(totals['sodium']) ?? 0) > 0;
    final hasPotassium = _doubleValue(totals['potassium']) != null &&
        (_doubleValue(totals['potassium']) ?? 0) > 0;
    final hasPhosphorus = _doubleValue(totals['phosphorus']) != null &&
        (_doubleValue(totals['phosphorus']) ?? 0) > 0;
    final anyNutrient =
        hasCalories || hasProtein || hasSodium || hasPotassium || hasPhosphorus;
    final prefix = isWeekly ? 'Avg ' : '';

    if (!anyNutrient) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isWeekly
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWeekly
              ? const Color(0xFFC8E6C9)
              : const Color(0xFFDCEDC8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isWeekly ? Icons.date_range : Icons.today,
                size: 18,
                color: isWeekly
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF558B2F),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isWeekly
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF33691E),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasCalories)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${prefix}Calories: ${_nutrientDisplay(totals['calories'])} kcal',
                style: const TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 13,
                ),
              ),
            ),
          if (hasProtein)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${prefix}Protein: ${_nutrientDisplay(totals['protein'])} g',
                style: const TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 13,
                ),
              ),
            ),
          if (hasSodium)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${prefix}Sodium: ${_nutrientDisplay(totals['sodium'])} mg',
                style: const TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 13,
                ),
              ),
            ),
          if (hasPotassium)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${prefix}Potassium: ${_nutrientDisplay(totals['potassium'])} mg',
                style: const TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 13,
                ),
              ),
            ),
          if (hasPhosphorus)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${prefix}Phosphorus: ${_nutrientDisplay(totals['phosphorus'])} mg',
                style: const TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
