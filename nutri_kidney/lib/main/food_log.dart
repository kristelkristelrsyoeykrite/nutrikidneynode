import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'analytics.dart';
import 'dashboard.dart';
import 'health_metrics.dart';
import 'profile.dart'; // Ensure Profile is imported

class FoodItem {
  final String emoji;
  final String name;
  final String portion;
  final int calories;
  final String time;

  FoodItem({
    required this.emoji,
    required this.name,
    required this.portion,
    required this.calories,
    required this.time,
  });
}

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

  final List<Map<String, String>> _allQuickAdds = [
    {'emoji': '🍎', 'name': 'Apple'},
    {'emoji': '🍌', 'name': 'Banana'},
    {'emoji': '💧', 'name': 'Water'},
    {'emoji': '🥚', 'name': 'Egg'},
  ];

  final Map<String, List<FoodItem>> _loggedMeals = {
    'Breakfast': [
      FoodItem(
        emoji: '🥣',
        name: 'Oatmeal with Berries',
        portion: '1 bowl (250g)',
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddFoodDialog(String emoji, String defaultName) {
    final TextEditingController nameController = TextEditingController(
      text: defaultName,
    );
    final TextEditingController portionController = TextEditingController(
      text: '1 serving',
    );
    final TextEditingController caloriesController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isFormValid =
                nameController.text.trim().isNotEmpty &&
                portionController.text.trim().isNotEmpty &&
                caloriesController.text.trim().isNotEmpty;
            void onFieldChanged(String _) {
              setStateDialog(() {});
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
                      onChanged: onFieldChanged,
                    ),
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      label: "Portion Size",
                      controller: portionController,
                      hint: "e.g. 1 medium, 100g",
                      onChanged: onFieldChanged,
                    ),
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      label: "Calories (kcal)",
                      controller: caloriesController,
                      isNumber: true,
                      hint: "e.g. 95",
                      onChanged: onFieldChanged,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
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
                            onPressed: isFormValid
                                ? () {
                                    setState(() {
                                      _loggedMeals[_selectedMealType]?.add(
                                        FoodItem(
                                          emoji: emoji,
                                          name: nameController.text.trim(),
                                          portion: portionController.text
                                              .trim(),
                                          calories:
                                              int.tryParse(
                                                caloriesController.text.trim(),
                                              ) ??
                                              0,
                                          time: DateFormat(
                                            'h:mm a',
                                          ).format(DateTime.now()),
                                        ),
                                      );
                                    });
                                    Navigator.pop(context);
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
                            child: const Text(
                              'Add Food',
                              style: TextStyle(
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
                      children: const [
                        Text(
                          'Tuesday, Oct 21',
                          style: TextStyle(
                            color: Color(0xFF37474F),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '1,450/1,800kcal',
                          style: TextStyle(
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
                        children: const [
                          Icon(
                            Icons.workspace_premium,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '7 day streak',
                            style: TextStyle(
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
                      onPressed: () {},
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
                      _showAddFoodDialog('🍽️', '');
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
              currentFoods.isEmpty
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
                        _buildSummaryItem('Protein', '45g'),
                        _buildSummaryItem('Carbs', '180g'),
                        _buildSummaryItem('Fat', '52g'),
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
  Widget _buildQuickAddItem(String emoji, String title) {
    return GestureDetector(
      onTap: () {
        _showAddFoodDialog(emoji, title);
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
            Text(emoji, style: const TextStyle(fontSize: 28)),
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
                    food.portion,
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
