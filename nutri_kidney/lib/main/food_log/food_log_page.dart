part of '../food_log.dart';

class FoodLogPage extends StatefulWidget {
  const FoodLogPage({super.key});

  @override
  State<FoodLogPage> createState() => _FoodLogPageState();
}

class _FoodLogPageState extends State<FoodLogPage> {
  int _currentIndex = 1; // 1 corresponds to 'Food'
  String _selectedMealType = 'Breakfast';

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isLoadingLogs = false;
  String? _foodLogError;
  int _currentLoggingStreak = 0;
  final Set<String> _unlockedAwardIds = {};
  final Set<String> _savingLogKeys = {};
  final ImagePicker _imagePicker = ImagePicker();
  Map<String, dynamic>? _imageReviewFoodDetails;
  Map<String, dynamic>? _imageReviewSelectedServing;
  bool _isSavingImageReview = false;
  String? _quickAddLoadingName;
  final TextEditingController _imageReviewQuantityController =
      TextEditingController(text: '1');

  final List<Map<String, String>> _allQuickAdds = [
    {'emoji': '\u{1F34E}', 'name': 'Apple'},
    {'emoji': '\u{1F34C}', 'name': 'Banana'},
    {'emoji': '\u{1F4A7}', 'name': 'Water'},
    {'emoji': '\u{1F95A}', 'name': 'Egg'},
  ];

  final Map<String, List<FoodItem>> _loggedMeals = {
    'Breakfast': [
      FoodItem(
        emoji: '\u{1F963}',
        name: 'Oatmeal with Berries',
        portion: '1 bowl (250g  )',
        calories: 280,
        time: '8:30 AM',
      ),
    ],
    'Lunch': [],
    'Dinner': [],
    'Snacks': [],
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadFoodLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _imageReviewQuantityController.dispose();
    super.dispose();
  }

  String get _selectedDate => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _loadFoodLogs() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLogs = true;
      _foodLogError = null;
      for (final key in _loggedMeals.keys) {
        _loggedMeals[key] = [];
      }
    });

    try {
      final response = await ApiService.getFoodLogs(date: _selectedDate);
      if (!mounted) return;
      final logs = response['logs'];
      if (logs is List) {
        setState(() {
          for (final log in logs) {
            if (log is! Map) continue;
            final data = Map<String, dynamic>.from(log);
            final mealType = data['mealType']?.toString() ?? 'Breakfast';
            final food = FoodItem.fromLog(data);
            _loggedMeals.putIfAbsent(mealType, () => []);
            _loggedMeals[mealType]!.add(food);
          }
        });
      }
      await _loadGamificationSummary();
      await _refreshReminderNotifications();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _foodLogError = e.toString();
        _currentLoggingStreak = 0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLogs = false;
        });
      }
    }
  }

  Future<void> _loadGamificationSummary({
    bool showAchievementPopup = false,
  }) async {
    try {
      final previousAwards = Set<String>.from(_unlockedAwardIds);
      final response = await ApiService.getGamificationSummary();
      if (!mounted) return;
      final gamification = response['gamification'];
      final status = gamification is Map ? gamification['status'] : null;
      final statusMap = status is Map
          ? Map<String, dynamic>.from(status)
          : <String, dynamic>{};
      final streak = _intValue(
        statusMap['displayStreak'] ?? statusMap['currentStreak'],
      );
      final currentAwards = _awardIdsFromStatus(statusMap);
      setState(() {
        _currentLoggingStreak = streak >= 2 ? streak : 0;
        _unlockedAwardIds
          ..clear()
          ..addAll(currentAwards);
      });
      if (showAchievementPopup) {
        final newAwards = currentAwards.difference(previousAwards);
        if (newAwards.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showAchievementPopup(newAwards.first);
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentLoggingStreak = 0;
      });
    }
  }

  Future<void> _refreshReminderNotifications() async {
    await NotificationService.refreshReminderNotificationsFromDashboard();
  }

  Set<String> _awardIdsFromStatus(Map<String, dynamic> statusMap) {
    final unlockedAwards = statusMap['unlockedAwards'];
    if (unlockedAwards is! List) return {};
    return unlockedAwards
        .map((award) => award.toString())
        .where((award) => award.isNotEmpty)
        .toSet();
  }

  _AchievementDetails _achievementDetails(String awardId) {
    switch (awardId) {
      case 'seven_day_streak':
        return const _AchievementDetails(
          title: '7 Day Streak',
          message: 'Congratulations! You logged consistently for 7 days.',
          icon: Icons.local_fire_department,
          color: Color(0xFFFF8A65),
        );
      case 'fourteen_day_streak':
        return const _AchievementDetails(
          title: '14 Day Streak',
          message: 'Amazing work! Two full weeks of steady tracking.',
          icon: Icons.whatshot,
          color: Color(0xFFFF7043),
        );
      case 'rainbow_eater':
        return const _AchievementDetails(
          title: 'Rainbow Eater',
          message: 'Congratulations! You logged foods from 5 color groups.',
          icon: Icons.palette_outlined,
          color: Color(0xFF7E57C2),
        );
      case 'hydration_hero':
        return const _AchievementDetails(
          title: 'Hydration Hero',
          message: 'Great job meeting your hydration goal again and again.',
          icon: Icons.water_drop,
          color: Color(0xFF64B5F6),
        );
      case 'balanced_week':
        return const _AchievementDetails(
          title: 'Balanced Week',
          message: 'Congratulations! Your week stayed within nutrition ranges.',
          icon: Icons.star_rounded,
          color: Color(0xFFFFD54F),
        );
      default:
        return const _AchievementDetails(
          title: 'Achievement Unlocked',
          message: 'Congratulations! You unlocked a new badge.',
          icon: Icons.emoji_events,
          color: Color(0xFF00C874),
        );
    }
  }

  void _showAchievementPopup(String awardId) {
    final details = _achievementDetails(awardId);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Achievement unlocked',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.82,
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: details.color.withOpacity(0.14),
                          border: Border.all(
                            color: details.color.withOpacity(0.35),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          details.icon,
                          color: details.color,
                          size: 52,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Achievement Unlocked',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF00C874),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        details.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF37474F),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        details.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C874),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Nice!',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizeFoodSearchQuery(String query) {
    final trimmed = query.trim();
    final compact = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const joinedFoodNames = {
      'friedchicken': 'fried chicken',
      'chickenbreast': 'chicken breast',
      'chickenwings': 'chicken wings',
      'frenchfries': 'french fries',
      'icecream': 'ice cream',
      'hotdog': 'hot dog',
      'friedrice': 'fried rice',
      'boiledegg': 'boiled egg',
      'scrambledegg': 'scrambled egg',
      'whiterice': 'white rice',
      'brownrice': 'brown rice',
    };

    return joinedFoodNames[compact] ?? trimmed;
  }

  FoodItem _foodWithEmoji(FoodItem food, String emoji) {
    return FoodItem(
      id: food.id,
      foodId: food.foodId,
      servingId: food.servingId,
      emoji: emoji,
      name: food.name,
      portion: food.portion,
      quantity: food.quantity,
      calories: food.calories,
      time: food.time,
      protein: food.protein,
      carbohydrate: food.carbohydrate,
      fat: food.fat,
      sodium: food.sodium,
      potassium: food.potassium,
      phosphorus: food.phosphorus,
      source: food.source,
      needsManualReview: food.needsManualReview,
      raw: food.raw,
    );
  }

  Future<void> _handleQuickAdd(String emoji, String name) async {
    if (_quickAddLoadingName != null) return;

    // Handle water specially - just ask for ML amount
    if (name.toLowerCase() == 'water') {
      await _showWaterDialog(emoji);
      return;
    }

    setState(() {
      _quickAddLoadingName = name;
    });

    try {
      final response = await ApiService.searchFoods(_normalizeFoodSearchQuery(name));
      if (!mounted) return;
      final foods = response['foods'];
      final suggestions = foods is List
          ? foods
              .whereType<Map>()
              .map(
                (food) => _foodWithEmoji(
                  FoodItem.fromCatalog(Map<String, dynamic>.from(food)),
                  emoji,
                ),
              )
              .toList(growable: false)
          : <FoodItem>[];

      if (suggestions.isEmpty) {
        throw Exception('No FatSecret matches found for $name.');
      }

      final exactName = name.trim().toLowerCase();
      final selected = suggestions.firstWhere(
        (food) => food.name.toLowerCase() == exactName,
        orElse: () => suggestions.first,
      );

      if (!mounted) return;
      await _showFoodServingDialog(selected);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to quick add $name: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _quickAddLoadingName = null;
        });
      }
    }
  }

  Future<void> _showWaterDialog(String emoji) async {
    final mlController = TextEditingController(text: '250');
    bool isSavingWater = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  const Text('Log Water'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How much water did you drink?',
                    style: TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mlController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: false,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. 250, 500, 1000',
                      suffixText: 'mL',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSavingWater ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSavingWater
                      ? null
                      : () async {
                          final mlAmount = int.tryParse(mlController.text.trim());
                          if (mlAmount == null || mlAmount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid amount'),
                              ),
                            );
                            return;
                          }

                          setStateDialog(() {
                            isSavingWater = true;
                          });

                          try {
                            final waterItem = FoodItem(
                              emoji: emoji,
                              name: 'Water',
                              portion: '$mlAmount mL',
                              quantity: 1,
                              calories: 0,
                              protein: 0,
                              carbohydrate: 0,
                              fat: 0,
                              sodium: 0,
                              potassium: 0,
                              phosphorus: 0,
                              time: DateFormat('h:mm a')
                                  .format(DateTime.now()),
                              source: 'manual_entry',
                              needsManualReview: false,
                            );

                            if (mounted) {
                              final response =
                                  await _submitFoodLogWithAllergyCheck({
                                'mealType': _selectedMealType,
                                'date': _selectedDate,
                                'name': 'Water',
                                'portion': '$mlAmount mL',
                                'quantity': 1.0,
                                'calories': 0,
                                'protein': 0.0,
                                'carbohydrate': 0.0,
                                'fat': 0.0,
                                'sodium': 0.0,
                                'potassium': 0.0,
                                'phosphorus': 0.0,
                                'source': 'manual_entry',
                                'waterMl': mlAmount.toDouble(),
                              });
                              if (response == null) {
                                return;
                              }
                              final log = response['log'];
                              final savedFood = log is Map
                                  ? FoodItem.fromLog(
                                      Map<String, dynamic>.from(log),
                                    )
                                  : waterItem;
                              setState(() {
                                _loggedMeals[_selectedMealType]?.add(savedFood);
                              });
                              await _loadGamificationSummary(
                                showAchievementPopup: true,
                              );
                              await _refreshReminderNotifications();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text('Error logging water: $e')),
                              );
                            }
                          } finally {
                            if (mounted && context.mounted) {
                              setStateDialog(() {
                                isSavingWater = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA5),
                  ),
                  child: isSavingWater
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Log Water',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _logKeyFor({
    required String mealType,
    required String name,
    required String portion,
    required String date,
  }) {
    return [
      mealType.trim().toLowerCase(),
      name.trim().toLowerCase(),
      portion.trim().toLowerCase(),
      date,
    ].join('|');
  }

  bool _hasDuplicateLog(FoodItem food, {String? exceptId}) {
    final key = _logKeyFor(
      mealType: _selectedMealType,
      name: food.name,
      portion: food.portion,
      date: _selectedDate,
    );
    return (_loggedMeals[_selectedMealType] ?? []).any((existing) {
      if (exceptId != null && existing.id == exceptId) return false;
      return _logKeyFor(
            mealType: _selectedMealType,
            name: existing.name,
            portion: existing.portion,
            date: _selectedDate,
          ) ==
          key;
    });
  }

  Future<bool> _confirmAllergyWarning(Map<String, dynamic> response) async {
    final matchedAllergens = response['matchedAllergens'] is List
        ? (response['matchedAllergens'] as List)
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final profileAllergies = response['profileAllergies'] is List
        ? (response['profileAllergies'] as List)
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final message = response['message']?.toString().trim().isNotEmpty == true
        ? response['message'].toString().trim()
        : 'This meal may contain an allergen listed in the child profile.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Allergy Warning'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (matchedAllergens.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Matched allergens: ${matchedAllergens.join(', ')}',
                style: const TextStyle(
                  color: Color(0xFFB71C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (profileAllergies.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Profile allergies: ${profileAllergies.join(', ')}',
                style: const TextStyle(
                  color: Color(0xFF546E7A),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD84315),
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Anyway'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<Map<String, dynamic>?> _submitFoodLogWithAllergyCheck(
    Map<String, dynamic> request,
  ) async {
    Future<Map<String, dynamic>> submit({required bool confirmed}) {
      return ApiService.addFoodLog(
        mealType: request['mealType'] as String,
        date: request['date']?.toString(),
        foodId: request['foodId']?.toString(),
        servingId: request['servingId']?.toString(),
        quantity: request['quantity'] as double?,
        name: request['name'] as String,
        portion: request['portion'] as String,
        calories: request['calories'] as int,
        protein: request['protein'] as double?,
        carbohydrate: request['carbohydrate'] as double?,
        fat: request['fat'] as double?,
        sodium: request['sodium'] as double?,
        potassium: request['potassium'] as double?,
        phosphorus: request['phosphorus'] as double?,
        source: request['source']?.toString() ?? 'manual_entry',
        needsManualReview: request['needsManualReview'] == true,
        raw: request['raw'] as Map<String, dynamic>?,
        waterMl: request['waterMl'] as double?,
        userConfirmedAllergyWarning: confirmed,
      );
    }

    final initialResponse = await submit(confirmed: false);
    if (initialResponse['requiresAllergyConfirmation'] == true) {
      final shouldContinue = await _confirmAllergyWarning(initialResponse);
      if (!shouldContinue) {
        return null;
      }
      return submit(confirmed: true);
    }
    return initialResponse;
  }

  Future<void> _saveFoodItem(FoodItem food) async {
    final logKey = _logKeyFor(
      mealType: _selectedMealType,
      name: food.name,
      portion: food.portion,
      date: _selectedDate,
    );
    if (_savingLogKeys.contains(logKey) || _hasDuplicateLog(food)) {
      throw Exception('This food is already logged for $_selectedMealType.');
    }

    if (!mounted) return;
    setState(() {
      _savingLogKeys.add(logKey);
    });

    try {
      final response = await _submitFoodLogWithAllergyCheck({
        'mealType': _selectedMealType,
        'date': _selectedDate,
        'foodId': food.foodId,
        'servingId': food.servingId,
        'quantity': food.quantity,
        'name': food.name,
        'portion': food.portion,
        'calories': food.calories,
        'protein': food.protein,
        'carbohydrate': food.carbohydrate,
        'fat': food.fat,
        'sodium': food.sodium,
        'potassium': food.potassium,
        'phosphorus': food.phosphorus,
        'source': food.source,
        'needsManualReview': food.needsManualReview,
        'raw': food.raw,
      });

      if (response == null) {
        return;
      }

      if (response['success'] == false) {
        throw Exception(response['error'] ?? 'Database save failed.');
      }

      final log = response['log'];
      final savedFood = log is Map
          ? FoodItem.fromLog(Map<String, dynamic>.from(log))
          : food;

      if (mounted) {
        setState(() {
          _loggedMeals[_selectedMealType]?.add(savedFood);
        });
        await _loadGamificationSummary(showAchievementPopup: true);
        await _refreshReminderNotifications();
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingLogKeys.remove(logKey);
        });
      }
    }
  }

  Future<void> _updateFoodItem(FoodItem original, FoodItem updated) async {
    if (original.id == null || original.id!.isEmpty) {
      throw Exception('This food log cannot be edited yet.');
    }

    if (_hasDuplicateLog(updated, exceptId: original.id)) {
      throw Exception('This food is already logged for $_selectedMealType.');
    }

    final response = await ApiService.updateFoodLog(
      foodLogId: original.id!,
      mealType: _selectedMealType,
      date: _selectedDate,
      name: updated.name,
      portion: updated.portion,
      calories: updated.calories,
      servingId: updated.servingId,
      quantity: updated.quantity,
      protein: updated.protein,
      carbohydrate: updated.carbohydrate,
      fat: updated.fat,
      sodium: updated.sodium,
      potassium: updated.potassium,
      phosphorus: updated.phosphorus,
      raw: updated.raw,
    );

    if (response['success'] == false) {
      throw Exception(response['error'] ?? 'Database update failed.');
    }

    final log = response['log'];
    final savedFood = log is Map
        ? FoodItem.fromLog(Map<String, dynamic>.from(log))
        : updated;

    if (mounted) {
      setState(() {
        final foods = _loggedMeals[_selectedMealType] ?? [];
        final index = foods.indexWhere((item) => item.id == original.id);
        if (index >= 0) {
          foods[index] = savedFood;
        }
      });
      await _loadGamificationSummary(showAchievementPopup: true);
      await _refreshReminderNotifications();
    }
  }

  Future<void> _deleteFoodItem(FoodItem food) async {
    if (food.id == null || food.id!.isEmpty) {
      if (mounted) {
        setState(() {
          _loggedMeals[_selectedMealType]?.remove(food);
        });
      }
      await _refreshReminderNotifications();
      return;
    }

    final response = await ApiService.deleteFoodLog(food.id!);
    if (response['success'] == false) {
      throw Exception(response['error'] ?? 'Database delete failed.');
    }

    if (mounted) {
      setState(() {
        _loggedMeals[_selectedMealType]
            ?.removeWhere((item) => item.id == food.id);
      });
      await _loadGamificationSummary();
      await _refreshReminderNotifications();
    }
  }

  Future<void> _confirmDeleteFoodItem(FoodItem food) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete food log?'),
        content: Text('Remove ${food.name} from $_selectedMealType?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await _deleteFoodItem(food);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food log deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to delete food: $e')),
        );
      }
    }
  }

  Future<void> _editFoodItem(FoodItem food) async {
    final rawDetails = food.raw;
    if (food.foodId != null &&
        food.foodId!.isNotEmpty &&
        rawDetails != null &&
        rawDetails['servings'] is List) {
      await _showFoodServingDialog(
        food,
        preloadedDetails: {'food': rawDetails},
        existingLog: food,
      );
      return;
    }

    if (food.foodId != null && food.foodId!.isNotEmpty) {
      await _showFoodServingDialog(food, existingLog: food);
      return;
    }

    _showAddFoodDialog(food.emoji, food.name, food: food);
  }

  Future<void> _showImageInputOptions() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Food Image',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFF00BFA5),
                ),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(dialogContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_outlined,
                  color: Color(0xFF00BFA5),
                ),
                title: const Text('Upload File'),
                onTap: () => Navigator.pop(dialogContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final pickedImage = await _pickImageSafely(source);
    if (pickedImage == null) return;

    if (!mounted) return;
    bool processingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          margin: EdgeInsets.symmetric(horizontal: 28),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF00C874)),
                SizedBox(height: 16),
                Text(
                  'Scanning food image...',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'If the scanning service is starting up, please wait at least 15 seconds.',
                  style: TextStyle(color: Color(0xFF78909C), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final response = await ApiService.recognizeFoodImage(
        imagePath: pickedImage.path,
        contentType: _contentTypeForImage(pickedImage.path),
      );
      if (!mounted) return;
      if (processingDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        processingDialogOpen = false;
      }

      if (response['success'] == false) {
        throw Exception(
          response['error'] ?? 'The image could not be identified as food.',
        );
      }

      final recognizedOptions = _extractRecognizedFoodOptions(response);
      final foodDetails = recognizedOptions.length > 1
          ? await _selectRecognizedFoodOption(recognizedOptions)
          : (recognizedOptions.isNotEmpty
                ? recognizedOptions.first
                : _extractRecognizedFoodDetails(response));
      final recognizedName =
          foodDetails['food_name'] ?? foodDetails['foodName'] ?? 'unknown';
      final recognizedServingCount = foodDetails['servings'] is List
          ? (foodDetails['servings'] as List).length
          : 0;
      debugPrint(
        'IMAGE_RECOGNITION_NODE_RESULT food=$recognizedName servings=$recognizedServingCount',
      );

      if (foodDetails.isEmpty) {
        throw Exception('No FatSecret nutrition match was returned.');
      }
      if (foodDetails['servings'] is! List) {
        throw Exception('Recognized food has no serving options to review.');
      }

      final food = FoodItem.fromCatalog({
        'foodId': foodDetails['food_id'] ?? foodDetails['foodId'],
        'name': foodDetails['food_name'] ?? foodDetails['foodName'],
        'brandName': foodDetails['brand_name'] ?? foodDetails['brandName'],
        'foodType': foodDetails['food_type'] ?? foodDetails['foodType'],
        'servingDescription': 'Select serving',
        'source': response['source'] ?? 'image_recognition',
        'raw': foodDetails,
      });
      if (mounted) {
        final rawServings = foodDetails['servings'] is List
            ? List<dynamic>.from(foodDetails['servings'] as List)
            : <dynamic>[];
        final firstServing = rawServings.whereType<Map>().isNotEmpty
            ? Map<String, dynamic>.from(rawServings.whereType<Map>().first)
            : <String, dynamic>{};
        setState(() {
          _imageReviewFoodDetails = {
            ...foodDetails,
            'display_food_name': food.name,
            'display_food_id': food.foodId,
          };
          _imageReviewSelectedServing = firstServing;
          _imageReviewQuantityController.text = '1';
        });
        debugPrint('IMAGE_RECOGNITION_INLINE_REVIEW_READY');
      }
    } catch (e) {
      if (processingDialogOpen) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        processingDialogOpen = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to recognize food image: $e')),
        );
      }
    }
  }

  Future<XFile?> _pickImageSafely(
    ImageSource source, {
    bool hasRetried = false,
  }) async {
    try {
      return await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
    } on PlatformException catch (error) {
      if (!mounted) return null;

      final normalizedCode = error.code.toLowerCase();
      final normalizedMessage = (error.message ?? '').toLowerCase();
      final fromCamera = source == ImageSource.camera;
      final sourceLabel = fromCamera ? 'camera' : 'gallery';
      final permissionDenied = normalizedCode.contains('denied') ||
          normalizedMessage.contains('denied') ||
          normalizedCode.contains('access_denied') ||
          normalizedMessage.contains('access denied') ||
          normalizedMessage.contains('permission');
      final cancelled = normalizedCode.contains('cancel') ||
          normalizedMessage.contains('cancel');

      if (cancelled) {
        return null;
      }

      if (permissionDenied) {
        if (hasRetried) {
          await _showImagePermissionSettingsDialog(sourceLabel);
          return null;
        }
        final retry = await _showImagePermissionRetryDialog(sourceLabel);
        if (retry != true || !mounted) {
          return null;
        }
        return _pickImageSafely(source, hasRetried: true);
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to open the $sourceLabel.')));
      return null;
    } catch (_) {
      if (!mounted) return null;
      final sourceLabel = source == ImageSource.camera ? 'camera' : 'gallery';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open the $sourceLabel.')),
      );
      return null;
    }
  }

  Future<bool?> _showImagePermissionRetryDialog(String sourceLabel) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Permission Needed'),
        content: Text(
          'NutriKidney needs access to your $sourceLabel to continue. Would you like to try again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
            ),
            child: const Text(
              'Try Again',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showImagePermissionSettingsDialog(String sourceLabel) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Permission Still Blocked'),
        content: Text(
          'NutriKidney still cannot access your $sourceLabel. Please enable $sourceLabel permission in your device settings, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _openDeviceSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeviceSettings() async {
    try {
      await AppSettings.openAppSettings();
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Settings shortcut is not available yet. Rebuild the app, then try again.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open device settings.'),
        ),
      );
    }
  }


  Map<String, dynamic> _extractRecognizedFoodDetails(
    Map<String, dynamic> response,
  ) {
    final directFood = response['food'];
    if (directFood is Map) {
      return Map<String, dynamic>.from(directFood);
    }

    final recognizedFood = response['recognizedFood'];
    if (recognizedFood is Map) {
      return Map<String, dynamic>.from(recognizedFood);
    }

    final result = response['result'];
    if (result is Map && result['food'] is Map) {
      return Map<String, dynamic>.from(result['food'] as Map);
    }

    final data = response['data'];
    if (data is Map && data['food'] is Map) {
      return Map<String, dynamic>.from(data['food'] as Map);
    }

    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _extractRecognizedFoodOptions(
    Map<String, dynamic> response,
  ) {
    final recognizedFoods = response['recognizedFoods'];
    if (recognizedFoods is List) {
      return recognizedFoods
          .whereType<Map>()
          .map((food) => Map<String, dynamic>.from(food))
          .where((food) => food['servings'] is List)
          .toList(growable: false);
    }

    final single = _extractRecognizedFoodDetails(response);
    return single.isEmpty ? const <Map<String, dynamic>>[] : [single];
  }

  Future<Map<String, dynamic>> _selectRecognizedFoodOption(
    List<Map<String, dynamic>> options,
  ) async {
    if (options.isEmpty) return <String, dynamic>{};
    if (options.length == 1) return options.first;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (dialogContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recognized foods',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Multiple foods or ingredients were recognized. Choose one to review.',
                style: TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final name = option['food_name']?.toString() ??
                        option['foodName']?.toString() ??
                        'Food';
                    final servings = option['servings'] is List
                        ? (option['servings'] as List).length
                        : 0;
                    return ListTile(
                      leading: const Icon(
                        Icons.restaurant_menu,
                        color: Color(0xFF00BFA5),
                      ),
                      title: Text(name),
                      subtitle: Text(
                        servings > 0
                            ? '$servings serving options'
                            : 'Tap to review',
                      ),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        Map<String, dynamic>.from(option),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    return selected ?? options.first;
  }

  String _contentTypeForImage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  void _showAddFoodDialog(String emoji, String defaultName, {FoodItem? food}) {
    final TextEditingController nameController = TextEditingController(
      text: food?.name ?? defaultName,
    );
    final TextEditingController portionController = TextEditingController(
      text: food?.portion ?? '1 serving',
    );
    List<FoodItem> dialogSuggestions = [];
    bool isSearchingDialogSuggestions = false;
    bool isSavingDialogFood = false;
    String latestDialogQuery = '';
    Timer? suggestionDebounce;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isFormValid =
                nameController.text.trim().isNotEmpty &&
                portionController.text.trim().isNotEmpty;
            void onFieldChanged(String _) {
              setStateDialog(() {});
            }
            void searchDialogSuggestions(String value) {
              final requestedQuery = value.trim();
              latestDialogQuery = requestedQuery;
              suggestionDebounce?.cancel();

              if (requestedQuery.length < 2) {
                setStateDialog(() {
                  dialogSuggestions = [];
                  isSearchingDialogSuggestions = false;
                });
                return;
              }

              setStateDialog(() {
                isSearchingDialogSuggestions = true;
              });

              suggestionDebounce = Timer(
                const Duration(milliseconds: 650),
                () async {
                  try {
                    final response = await ApiService.searchFoods(
                      _normalizeFoodSearchQuery(requestedQuery),
                    );
                    if (!context.mounted ||
                        latestDialogQuery != requestedQuery) {
                      return;
                    }
                    final foods = response['foods'];
                    setStateDialog(() {
                      dialogSuggestions = foods is List
                          ? foods
                              .whereType<Map>()
                              .map(
                                (food) => FoodItem.fromCatalog(
                                  Map<String, dynamic>.from(food),
                                ),
                              )
                              .toList()
                          : [];
                    });
                  } catch (_) {
                    if (!context.mounted ||
                        latestDialogQuery != requestedQuery) {
                      return;
                    }
                    setStateDialog(() {
                      dialogSuggestions = [];
                    });
                  } finally {
                    if (!context.mounted ||
                        latestDialogQuery != requestedQuery) {
                      return;
                    }
                    setStateDialog(() {
                      isSearchingDialogSuggestions = false;
                    });
                  }
                },
              );
            }

            void closeDialog() {
              suggestionDebounce?.cancel();
              Navigator.pop(context);
            }

            Future<void> openSuggestion(FoodItem suggestion) async {
              suggestionDebounce?.cancel();
              Navigator.pop(context);
              await _showFoodServingDialog(suggestion);
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Add to $_selectedMealType',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildDialogTextField(
                      label: "Food Name",
                      controller: nameController,
                      onChanged: (value) {
                        onFieldChanged(value);
                        searchDialogSuggestions(value);
                      },
                    ),
                    if (isSearchingDialogSuggestions)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(
                          color: Color(0xFF00C874),
                          minHeight: 2,
                        ),
                      ),
                    if (dialogSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Color(0xFFE0E0E0)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: dialogSuggestions.take(5).length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final suggestion = dialogSuggestions[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                suggestion.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                suggestion.portion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF00C874),
                              ),
                              onTap: () => openSuggestion(suggestion),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      label: "Portion Size",
                      controller: portionController,
                      hint: "e.g. 1 medium, 100g",
                      onChanged: onFieldChanged,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isSavingDialogFood
                                ? null
                                : closeDialog,
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Color(0xFF37474F),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isFormValid && !isSavingDialogFood
                                ? () async {
                                    final foodToSave = FoodItem(
                                      foodId: food?.foodId,
                                      emoji: emoji,
                                      name: nameController.text.trim(),
                                      portion: portionController.text.trim(),
                                      calories: food?.calories ?? 0,
                                      time: DateFormat(
                                        'h:mm a',
                                      ).format(DateTime.now()),
                                      protein: food?.protein ?? 0,
                                      carbohydrate: food?.carbohydrate ?? 0,
                                      fat: food?.fat ?? 0,
                                      sodium: food?.sodium ?? 0,
                                      potassium: food?.potassium ?? 0,
                                      phosphorus: food?.phosphorus ?? 0,
                                      source: food?.source ?? 'manual_entry',
                                      needsManualReview:
                                          food?.needsManualReview ?? false,
                                      raw: food?.raw,
                                    );

                                    try {
                                      setStateDialog(() {
                                        isSavingDialogFood = true;
                                      });
                                      if (food?.id == null) {
                                        await _saveFoodItem(foodToSave);
                                      } else {
                                        await _updateFoodItem(food!, foodToSave);
                                      }
                                      if (context.mounted) {
                                        suggestionDebounce?.cancel();
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Unable to save food: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setStateDialog(() {
                                          isSavingDialogFood = false;
                                        });
                                      }
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C874),
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: isSavingDialogFood
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    food?.id == null ? 'Add Food' : 'Update',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showFoodServingDialog(
    FoodItem food, {
    Map<String, dynamic>? preloadedDetails,
    FoodItem? existingLog,
  }) async {
    if (food.foodId == null || food.foodId!.isEmpty) {
      _showAddFoodDialog(food.emoji, food.name, food: food);
      return;
    }

    if (preloadedDetails == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00C874)),
        ),
      );
    }

    Map<String, dynamic> details = preloadedDetails ?? {};
    try {
      if (preloadedDetails == null) {
        details = await ApiService.getFoodDetails(food.foodId!);
      }
    } catch (e) {
      if (mounted && preloadedDetails == null) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load serving options: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    if (preloadedDetails == null) Navigator.pop(context);

    final Map<String, dynamic> foodDetails = details['food'] is Map
        ? Map<String, dynamic>.from(details['food'] as Map)
        : Map<String, dynamic>.from(details);
    final List<dynamic> rawServings = foodDetails['servings'] is List
        ? List<dynamic>.from(foodDetails['servings'] as List)
        : details['servings'] is List
            ? List<dynamic>.from(details['servings'] as List)
            : <dynamic>[];
    final List<Map<String, dynamic>> servings = rawServings
        .whereType<Map>()
        .map<Map<String, dynamic>>(
          (serving) => Map<String, dynamic>.from(serving),
        )
        .toList(growable: false);

    if (servings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No serving options found for this food.')),
      );
      return;
    }

    Map<String, dynamic> selectedServing = servings.firstWhere(
      (serving) =>
          food.servingId != null &&
          serving['serving_id']?.toString() == food.servingId,
      orElse: () => servings.first,
    );
    final initialQuantity = (existingLog ?? food).quantity;
    final quantityController = TextEditingController(
      text: initialQuantity % 1 == 0
          ? initialQuantity.toInt().toString()
          : initialQuantity.toString(),
    );
    bool isSavingServing = false;
    final isEditing = existingLog != null;

    debugPrint('FOOD_REVIEW_PANEL_SHOW servings=${servings.length}');
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final quantity =
                double.tryParse(quantityController.text.trim()) ?? 1.0;
            final nutrients = selectedServing['nutrients'] is Map
                ? Map<String, dynamic>.from(selectedServing['nutrients'])
                : const <String, dynamic>{};
            final calories = (_asDouble(nutrients['calories']) * quantity)
                .round();
            final protein = _asDouble(nutrients['protein']) * quantity;
            final carbohydrate =
                _asDouble(nutrients['carbohydrate']) * quantity;
            final fat = _asDouble(nutrients['fat']) * quantity;
            final sodium = _asDouble(nutrients['sodium']) * quantity;
            final potassium = _asDouble(nutrients['potassium']) * quantity;
            final phosphorus = _asDouble(nutrients['phosphorus']) * quantity;
            final servingText = selectedServing['display_text']?.toString() ??
                selectedServing['serving_description']?.toString() ??
                'Serving';

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF37474F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEditing
                          ? 'Review the serving and nutrients before updating.'
                          : 'Review the serving and nutrients before adding.',
                      style: const TextStyle(
                        color: Color(0xFF90A4AE),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Serving option',
                      style: TextStyle(
                        color: Color(0xFF90A4AE),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: servings.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final serving = servings[index];
                          final label =
                              serving['display_text']?.toString() ??
                                  serving['serving_description']?.toString() ??
                                  'Serving';
                          final isSelected =
                              serving['serving_id']?.toString() ==
                                  selectedServing['serving_id']?.toString();
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF00C874),
                                  )
                                : const Icon(
                                    Icons.radio_button_unchecked,
                                    color: Color(0xFFB0BEC5),
                                  ),
                            onTap: () {
                              setStateDialog(() {
                                selectedServing = serving;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      label: _portionFieldLabel(selectedServing),
                      controller: quantityController,
                      isNumber: true,
                      hint: 'e.g. 1, 0.5, 2',
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_loggedPortionLabel(selectedServing, quantity)} • $calories kcal',
                      style: const TextStyle(
                        color: Color(0xFF546E7A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2FBF7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE0F2E9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nutrients for selected amount',
                            style: TextStyle(
                              color: Color(0xFF37474F),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildNutrientLine('Calories', '$calories kcal'),
                          _buildNutrientLine(
                            'Protein',
                            '${protein.toStringAsFixed(1)} g',
                          ),
                          _buildNutrientLine(
                            'Carbs',
                            '${carbohydrate.toStringAsFixed(1)} g',
                          ),
                          _buildNutrientLine(
                            'Fat',
                            '${fat.toStringAsFixed(1)} g',
                          ),
                          _buildNutrientLine(
                            'Sodium',
                            '${sodium.round()} mg',
                          ),
                          _buildNutrientLine(
                            'Potassium',
                            potassium > 0
                                ? '${potassium.round()} mg (estimate)'
                                : 'Not provided',
                          ),
                          _buildNutrientLine(
                            'Phosphorus',
                            phosphorus > 0
                                ? '${phosphorus.round()} mg (guide)'
                                : 'Not available',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isSavingServing
                                ? null
                                : () => Navigator.pop(dialogContext),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: quantity > 0 && !isSavingServing
                                ? () async {
                                    final pendingFood = FoodItem(
                                      foodId: food.foodId,
                                      servingId: selectedServing['serving_id']
                                          ?.toString(),
                                      emoji: food.emoji,
                                      name: food.name,
                                      portion: _loggedPortionLabel(
                                        selectedServing,
                                        quantity,
                                      ),
                                      quantity: quantity,
                                      calories: calories,
                                      time: DateFormat(
                                        'h:mm a',
                                      ).format(DateTime.now()),
                                      protein: protein,
                                      carbohydrate: carbohydrate,
                                      fat: fat,
                                      sodium: sodium,
                                      potassium: potassium,
                                      phosphorus: phosphorus,
                                      source: food.source == 'manual_entry'
                                          ? 'fatsecret'
                                          : food.source,
                                      raw: foodDetails,
                                    );
                                    final logKey = _logKeyFor(
                                      mealType: _selectedMealType,
                                      name: pendingFood.name,
                                      portion: pendingFood.portion,
                                      date: _selectedDate,
                                    );
                                    try {
                                      if (_savingLogKeys.contains(logKey) ||
                                          _hasDuplicateLog(
                                            pendingFood,
                                            exceptId: existingLog?.id,
                                          )) {
                                        throw Exception(
                                          'This food is already logged for $_selectedMealType.',
                                        );
                                      }
                                      setStateDialog(() {
                                        isSavingServing = true;
                                      });
                                      if (mounted) {
                                        setState(() {
                                          _savingLogKeys.add(logKey);
                                        });
                                      }
                                      final response = isEditing
                                          ? await ApiService.updateFoodLog(
                                              foodLogId: existingLog.id!,
                                              mealType: _selectedMealType,
                                              date: _selectedDate,
                                              servingId:
                                                  selectedServing['serving_id']
                                                      ?.toString(),
                                              quantity: quantity,
                                              name: food.name,
                                              portion: pendingFood.portion,
                                              calories: calories,
                                              protein: protein,
                                              carbohydrate: carbohydrate,
                                              fat: fat,
                                              sodium: sodium,
                                              potassium: potassium,
                                              phosphorus: phosphorus,
                                              raw: foodDetails,
                                            )
                                          : await _submitFoodLogWithAllergyCheck({
                                              'mealType': _selectedMealType,
                                              'date': _selectedDate,
                                              'foodId': food.foodId,
                                              'servingId':
                                                  selectedServing['serving_id']
                                                      ?.toString(),
                                              'quantity': quantity,
                                              'name': food.name,
                                              'portion': pendingFood.portion,
                                              'calories': calories,
                                              'protein': protein,
                                              'carbohydrate': carbohydrate,
                                              'fat': fat,
                                              'sodium': sodium,
                                              'potassium': potassium,
                                              'phosphorus': phosphorus,
                                              'source': 'fatsecret',
                                              'raw': foodDetails,
                                            });
                                      if (response == null) {
                                        return;
                                      }
                                      if (response['success'] == false) {
                                        throw Exception(
                                          response['error'] ??
                                              'Database save failed.',
                                        );
                                      }
                                      final log = response['log'];
                                      final savedFood = log is Map
                                          ? FoodItem.fromLog(
                                              Map<String, dynamic>.from(log),
                                            )
                                          : food;

                                      if (mounted) {
                                        setState(() {
                                          if (isEditing) {
                                            final foods =
                                                _loggedMeals[_selectedMealType] ??
                                                    [];
                                            final index = foods.indexWhere(
                                              (item) =>
                                                  item.id == existingLog.id,
                                            );
                                            if (index >= 0) {
                                              foods[index] = savedFood;
                                            }
                                          } else {
                                            _loggedMeals[_selectedMealType]
                                                ?.add(savedFood);
                                          }
                                        });
                                        await _loadGamificationSummary(
                                          showAchievementPopup: !isEditing,
                                        );
                                        await _refreshReminderNotifications();
                                      }
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                    } catch (e) {
                                      if (dialogContext.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Unable to save food: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _savingLogKeys.remove(logKey);
                                        });
                                      }
                                      if (dialogContext.mounted) {
                                        setStateDialog(() {
                                          isSavingServing = false;
                                        });
                                      }
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C874),
                            ),
                            child: isSavingServing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    isEditing ? 'Update' : 'Add',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredQuickAdds = _allQuickAdds
        .where((item) => item['name']!.toLowerCase().contains(_searchQuery))
        .toList();
    final allCurrentFoods = _loggedMeals[_selectedMealType] ?? [];
    final currentFoods = _searchQuery.isEmpty
        ? allCurrentFoods
        : allCurrentFoods
              .where((food) => food.name.toLowerCase().contains(_searchQuery))
              .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Food Log',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Track your meals and nutrition',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14),
              ),
              const SizedBox(height: 24),
              if (_foodLogError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Food logs are offline: $_foodLogError',
                    style: const TextStyle(
                      color: Color(0xFFE65100),
                      fontSize: 12,
                    ),
                  ),
                ),

              // --- Date & Streak Card ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d').format(DateTime.now()),
                          style: const TextStyle(
                            color: Color(0xFF37474F),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_totalCalories()} kcal logged',
                          style: const TextStyle(
                            color: Color(0xFF90A4AE),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF7043), Color(0xFFD81B60)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _currentLoggingStreak >= 2
                                ? '$_currentLoggingStreak day streak'
                                : 'Build streak',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Camera Card ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2FBF7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFA5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Take a Photo of Your Meal',
                      style: TextStyle(
                        color: Color(0xFF37474F),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'AI-powered food recognition',
                      style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _showImageInputOptions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFA5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Open Camera',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_imageReviewFoodDetails != null) ...[
                _buildImageReviewCard(),
                const SizedBox(height: 20),
              ],

              // --- Search Bar ---
              Container(
                height: 45,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search logged foods...",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // --- Quick Add ---
              const Text(
                'Quick Add',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              filteredQuickAdds.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          "No quick add foods found.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: filteredQuickAdds
                          .map(
                            (item) => _buildQuickAddItem(
                              item['emoji']!,
                              item['name']!,
                            ),
                          )
                          .toList(),
                    ),
              const SizedBox(height: 24),

              // --- Category Tabs ---
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTab('Breakfast'),
                    const SizedBox(width: 12),
                    _buildTab('Lunch'),
                    const SizedBox(width: 12),
                    _buildTab('Dinner'),
                    const SizedBox(width: 12),
                    _buildTab('Snacks'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- Dynamic Meals Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_selectedMealType Meals',
                    style: const TextStyle(
                      color: Color(0xFF37474F),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _showAddFoodDialog('\u{1F37D}\u{FE0F}', '');
                    },
                    icon: const Icon(
                      Icons.add,
                      color: Color(0xFF66BB6A),
                      size: 18,
                    ),
                    label: const Text(
                      'Add Food',
                      style: TextStyle(color: Color(0xFF66BB6A), fontSize: 14),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _isLoadingLogs
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF00C874),
                        ),
                      ),
                    )
                  : currentFoods.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? "No matching foods found in $_selectedMealType."
                              : "No foods logged for $_selectedMealType yet.\nClick Quick Add to log a meal!",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: currentFoods
                          .map((food) => _buildMealItemCard(food))
                          .toList(),
                    ),
              const SizedBox(height: 24),

              // --- Today's Summary Card ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF7F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Today's Summary",
                      style: TextStyle(
                        color: Color(0xFF546E7A),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSummaryItem(
                          'Protein',
                          '${_totalNutrient((food) => food.protein).round()}g',
                        ),
                        _buildSummaryItem(
                          'Carbs',
                          '${_totalNutrient((food) => food.carbohydrate).round()}g',
                        ),
                        _buildSummaryItem(
                          'Fat',
                          '${_totalNutrient((food) => food.fat).round()}g',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
              // --- UPDATED LOGIC HERE: Now routes to ProfilePage ---
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

  // --- UI Helpers ---
  Iterable<FoodItem> get _allLoggedFoods =>
      _loggedMeals.values.expand((foods) => foods);

  int _totalCalories() =>
      _allLoggedFoods.fold(0, (total, food) => total + food.calories);

  double _totalNutrient(double Function(FoodItem food) select) =>
      _allLoggedFoods.fold(0, (total, food) => total + select(food));

  List<Map<String, dynamic>> _servingsFromFoodDetails(
    Map<String, dynamic>? foodDetails,
  ) {
    if (foodDetails == null || foodDetails['servings'] is! List) {
      return [];
    }
    return List<dynamic>.from(foodDetails['servings'] as List)
        .whereType<Map>()
        .map<Map<String, dynamic>>(
          (serving) => Map<String, dynamic>.from(serving),
        )
        .toList(growable: false);
  }

  String _portionUnitFromServing(Map<String, dynamic> serving) {
    final rawMeasurement =
        serving['measurement_description']?.toString().trim() ?? '';
    final rawDescription = serving['display_text']?.toString().trim() ??
        serving['serving_description']?.toString().trim() ??
        'serving';
    final source = rawMeasurement.isNotEmpty ? rawMeasurement : rawDescription;
    final match = RegExp(r'[A-Za-z]+').firstMatch(source);
    return (match?.group(0) ?? 'serving').toLowerCase();
  }

  String _portionFieldLabel(Map<String, dynamic> serving) {
    return 'Portion size (${_portionUnitFromServing(serving)}):';
  }

  String _loggedPortionLabel(
    Map<String, dynamic> serving,
    double quantity,
  ) {
    final servingText = serving['display_text']?.toString() ??
        serving['serving_description']?.toString() ??
        'serving';
    final unit = _portionUnitFromServing(serving);
    final quantityText = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return '$quantityText $unit ($servingText)';
  }

  String _portionDisplayLabel(FoodItem food) {
    final match = RegExp(r'^\s*[\d.]+\s+([A-Za-z]+)').firstMatch(food.portion);
    final unit = match?.group(1)?.toLowerCase() ?? 'serving';
    return 'Portion size ($unit): ${food.portion}';
  }

  Future<void> _saveImageReviewFood() async {
    final foodDetails = _imageReviewFoodDetails;
    final selectedServing = _imageReviewSelectedServing;
    if (foodDetails == null || selectedServing == null) return;

    final quantity =
        double.tryParse(_imageReviewQuantityController.text.trim()) ?? 1.0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0.')),
      );
      return;
    }

    final nutrients = selectedServing['nutrients'] is Map
        ? Map<String, dynamic>.from(selectedServing['nutrients'])
        : const <String, dynamic>{};
    final name = foodDetails['display_food_name']?.toString() ??
        foodDetails['food_name']?.toString() ??
        'Recognized food';
    final foodId = foodDetails['display_food_id']?.toString() ??
        foodDetails['food_id']?.toString();
    final servingText = selectedServing['display_text']?.toString() ??
        selectedServing['serving_description']?.toString() ??
        'Serving';
    final portionLabel = _loggedPortionLabel(selectedServing, quantity);
    final calories = (_asDouble(nutrients['calories']) * quantity).round();
    final protein = _asDouble(nutrients['protein']) * quantity;
    final carbohydrate = _asDouble(nutrients['carbohydrate']) * quantity;
    final fat = _asDouble(nutrients['fat']) * quantity;
    final sodium = _asDouble(nutrients['sodium']) * quantity;
    final potassium = _asDouble(nutrients['potassium']) * quantity;
    final phosphorus = _asDouble(nutrients['phosphorus']) * quantity;

    final pendingFood = FoodItem(
      foodId: foodId,
      servingId: selectedServing['serving_id']?.toString(),
      emoji: '\u{1F37D}\u{FE0F}',
      name: name,
      portion: portionLabel,
      quantity: quantity,
      calories: calories,
      time: DateFormat('h:mm a').format(DateTime.now()),
      protein: protein,
      carbohydrate: carbohydrate,
      fat: fat,
      sodium: sodium,
      potassium: potassium,
      phosphorus: phosphorus,
      source: 'fatsecret_image',
      raw: foodDetails,
    );
    final logKey = _logKeyFor(
      mealType: _selectedMealType,
      name: pendingFood.name,
      portion: pendingFood.portion,
      date: _selectedDate,
    );

    try {
      if (_savingLogKeys.contains(logKey) || _hasDuplicateLog(pendingFood)) {
        throw Exception('This food is already logged for $_selectedMealType.');
      }
      setState(() {
        _isSavingImageReview = true;
        _savingLogKeys.add(logKey);
      });

      final response = await _submitFoodLogWithAllergyCheck({
        'mealType': _selectedMealType,
        'date': _selectedDate,
        'foodId': foodId,
        'servingId': selectedServing['serving_id']?.toString(),
        'quantity': quantity,
        'name': name,
        'portion': portionLabel,
        'calories': calories,
        'protein': protein,
        'carbohydrate': carbohydrate,
        'fat': fat,
        'sodium': sodium,
        'potassium': potassium,
        'phosphorus': phosphorus,
        'source': 'fatsecret_image',
        'raw': foodDetails,
      });
      if (response == null) {
        return;
      }
      if (response['success'] == false) {
        throw Exception(response['error'] ?? 'Database save failed.');
      }

      final log = response['log'];
      final savedFood = log is Map
          ? FoodItem.fromLog(Map<String, dynamic>.from(log))
          : pendingFood;
      setState(() {
        _loggedMeals[_selectedMealType]?.add(savedFood);
        _imageReviewFoodDetails = null;
        _imageReviewSelectedServing = null;
        _imageReviewQuantityController.text = '1';
      });
      await _loadGamificationSummary(showAchievementPopup: true);
      await _refreshReminderNotifications();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save recognized food: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingImageReview = false;
          _savingLogKeys.remove(logKey);
        });
      }
    }
  }

  Widget _buildImageReviewCard() {
    final foodDetails = _imageReviewFoodDetails!;
    final servings = _servingsFromFoodDetails(foodDetails);
    final selectedServing = _imageReviewSelectedServing ??
        (servings.isNotEmpty ? servings.first : <String, dynamic>{});
    final nutrients = selectedServing['nutrients'] is Map
        ? Map<String, dynamic>.from(selectedServing['nutrients'])
        : const <String, dynamic>{};
    final quantity =
        double.tryParse(_imageReviewQuantityController.text.trim()) ?? 1.0;
    final name = foodDetails['display_food_name']?.toString() ??
        foodDetails['food_name']?.toString() ??
        'Recognized food';
    final servingText = selectedServing['display_text']?.toString() ??
        selectedServing['serving_description']?.toString() ??
        'Serving';
    final portionLabel = _loggedPortionLabel(selectedServing, quantity);
    final calories = (_asDouble(nutrients['calories']) * quantity).round();
    final protein = _asDouble(nutrients['protein']) * quantity;
    final carbohydrate = _asDouble(nutrients['carbohydrate']) * quantity;
    final fat = _asDouble(nutrients['fat']) * quantity;
    final sodium = _asDouble(nutrients['sodium']) * quantity;
    final potassium = _asDouble(nutrients['potassium']) * quantity;
    final phosphorus = _asDouble(nutrients['phosphorus']) * quantity;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB2DFDB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_search, color: Color(0xFF00BFA5)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cancel',
                onPressed: _isSavingImageReview
                    ? null
                    : () {
                        setState(() {
                          _imageReviewFoodDetails = null;
                          _imageReviewSelectedServing = null;
                          _imageReviewQuantityController.text = '1';
                        });
                      },
                icon: const Icon(Icons.close, color: Color(0xFF90A4AE)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Review the recognized food before adding it to the log.',
            style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
          ),
          const SizedBox(height: 14),
          const Text(
            'Serving option',
            style: TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: servings.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final serving = servings[index];
                final label = serving['display_text']?.toString() ??
                    serving['serving_description']?.toString() ??
                    'Serving';
                final isSelected = serving['serving_id']?.toString() ==
                    selectedServing['serving_id']?.toString();
                return ListTile(
                  dense: true,
                  title: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? const Color(0xFF00C874)
                        : const Color(0xFFB0BEC5),
                  ),
                  onTap: _isSavingImageReview
                      ? null
                      : () {
                          setState(() {
                            _imageReviewSelectedServing =
                                Map<String, dynamic>.from(serving);
                          });
                        },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildDialogTextField(
            label: _portionFieldLabel(selectedServing),
            controller: _imageReviewQuantityController,
            isNumber: true,
            hint: 'e.g. 1, 0.5, 2',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            '$portionLabel • $calories kcal',
            style: const TextStyle(
              color: Color(0xFF546E7A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2FBF7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0F2E9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nutrients for selected amount',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildNutrientLine('Calories', '$calories kcal'),
                _buildNutrientLine('Protein', '${protein.toStringAsFixed(1)} g'),
                _buildNutrientLine(
                  'Carbs',
                  '${carbohydrate.toStringAsFixed(1)} g',
                ),
                _buildNutrientLine('Fat', '${fat.toStringAsFixed(1)} g'),
                _buildNutrientLine('Sodium', '${sodium.round()} mg'),
                _buildNutrientLine(
                  'Potassium',
                  potassium > 0
                      ? '${potassium.round()} mg (estimate)'
                      : 'Not provided',
                ),
                _buildNutrientLine(
                  'Phosphorus',
                  phosphorus > 0
                      ? '${phosphorus.round()} mg (guide)'
                      : 'Not available',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _isSavingImageReview
                      ? null
                      : () {
                          setState(() {
                            _imageReviewFoodDetails = null;
                            _imageReviewSelectedServing = null;
                            _imageReviewQuantityController.text = '1';
                          });
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSavingImageReview ? null : _saveImageReviewFood,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C874),
                  ),
                  child: _isSavingImageReview
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF546E7A), fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogFoodItem(FoodItem food) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showFoodServingDialog(food),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2FBF7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(food.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${food.portion} • ${food.calories} kcal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF90A4AE),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.add_circle, color: Color(0xFF00C874)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAddItem(String emoji, String title) {
    final isLoading = _quickAddLoadingName == title;
    return GestureDetector(
      onTap: () {
        _handleQuickAdd(emoji, title);
      },
      child: Container(
        width: 75,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            isLoading
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00C874),
                    ),
                  )
                : Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title) {
    bool isActive = _selectedMealType == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMealType = title;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFF7043) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
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

  Widget _buildMealItemCard(FoodItem food) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(food.emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    style: const TextStyle(
                      color: Color(0xFF37474F),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _portionDisplayLabel(food),
                    style: const TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              color: Color(0xFF37474F),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${food.calories} kcal',
                              style: const TextStyle(
                                color: Color(0xFF37474F),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        food.time,
                        style: const TextStyle(
                          color: Color(0xFFB0BEC5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF90A4AE)),
              onSelected: (value) {
                if (value == 'edit') {
                  _editFoodItem(food);
                } else if (value == 'delete') {
                  _confirmDeleteFoodItem(food);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF66BB6A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogTextField({
    required String label,
    required TextEditingController controller,
    bool isNumber = false,
    String hint = "",
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF90A4AE),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AchievementDetails {
  final String title;
  final String message;
  final IconData icon;
  final Color color;

  const _AchievementDetails({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });
}
