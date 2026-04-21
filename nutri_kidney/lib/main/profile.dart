import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // For the iOS style switches
import 'dashboard.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'health_metrics.dart';
import '../login/login.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _currentIndex = 4; // 4 corresponds to 'Profile' in the bottom nav

  // State variables for the toggles
  bool _medicationReminders = true;
  bool _hydrationAlerts = false;
  bool _isLoadingProfile = true;
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _medicalProfile = {};
  Map<String, dynamic> _anthropometrics = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await ApiService.getHealthSummary();
      if (!mounted) return;
      if (response["success"] == true) {
        setState(() {
          _user = _asStringMap(response["user"]);
          _medicalProfile = _asStringMap(response["medicalProfile"]);
          _anthropometrics = _asStringMap(response["anthropometrics"]);
          _isLoadingProfile = false;
        });
      } else {
        setState(() => _isLoadingProfile = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);
    }
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  String _textValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return "";
  }

  String get _childName {
    final name = _textValue(_user, ["childFullName", "child_name", "name"]);
    return name.isEmpty ? "Child Profile" : name;
  }

  String get _childInitials {
    final parts = _childName
        .split(RegExp(r"\s+"))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return "NK";
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return "${parts.first[0]}${parts.last[0]}".toUpperCase();
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(
          user: _user,
          medicalProfile: _medicalProfile,
          anthropometrics: _anthropometrics,
        ),
      ),
    );

    if (updated == true) {
      _loadProfile();
    }
  }

  // --- NEW: Pop-up for "View All" Achievements ---
  void _showAllAchievements() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height:
              MediaQuery.of(context).size.height * 0.75, // 75% of screen height
          decoration: const BoxDecoration(
            color: Color(0xFFF9FBFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'All Achievements',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF37474F)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                  children: [
                    // Unlocked Achievements
                    _buildAchievementCard(
                      title: '7 Day Streak',
                      subtitle: 'Logged food daily',
                      iconWidget: const Icon(
                        Icons.local_fire_department,
                        color: Color(0xFFFF8A65),
                        size: 40,
                      ),
                    ),
                    _buildAchievementCard(
                      title: 'Rainbow Eater',
                      subtitle: 'Ate 5 different colored foods',
                      iconWidget: const Text(
                        '🌈',
                        style: TextStyle(fontSize: 32),
                      ),
                    ),
                    _buildAchievementCard(
                      title: 'Hydration Hero',
                      subtitle: 'Met water goal 10 times',
                      iconWidget: const Icon(
                        Icons.water_drop,
                        color: Color(0xFF64B5F6),
                        size: 40,
                      ),
                    ),
                    _buildAchievementCard(
                      title: 'Perfect Week',
                      subtitle: 'All nutrients in range',
                      iconWidget: const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD54F),
                        size: 40,
                      ),
                    ),
                    // Locked Achievements (For realism in the "View All" page)
                    _buildAchievementCard(
                      title: '14 Day Streak',
                      subtitle: 'Keep going!',
                      iconWidget: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFB0BEC5),
                        size: 40,
                      ),
                      isLocked: true,
                    ),
                    _buildAchievementCard(
                      title: 'Lab Master',
                      subtitle: 'Log 5 lab results',
                      iconWidget: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFB0BEC5),
                        size: 40,
                      ),
                      isLocked: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- NEW: Generic Pop-up for Settings/Support options ---
  void _showFeatureDialog(String title) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'The $title feature is currently being updated. Please check back soon!',
            style: const TextStyle(color: Color(0xFF78909C), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF5F5F5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(
                  color: Color(0xFF00C874),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              const Text(
                'Account',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Manage your account and settings',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14),
              ),
              const SizedBox(height: 24),

              // --- Profile Card ---
              _buildProfileCard(),
              const SizedBox(height: 32),

              // --- Achievements Section ---
              _buildAchievementsSection(),
              const SizedBox(height: 32),

              // --- Settings Section ---
              const Text(
                'Settings',
                style: TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              _buildSettingTile(
                Icons.notifications_none,
                'Notifications',
                onTap: () => _showFeatureDialog('Notifications'),
              ),
              _buildSettingTile(
                Icons.notifications_active_outlined,
                'Medication Reminders',
                trailing: CupertinoSwitch(
                  value: _medicationReminders,
                  activeColor: const Color(0xFF00C874),
                  onChanged: (bool value) {
                    setState(() {
                      _medicationReminders = value;
                    });
                  },
                ),
              ),
              _buildSettingTile(
                Icons.water_drop_outlined,
                'Hydration Alerts',
                trailing: CupertinoSwitch(
                  value: _hydrationAlerts,
                  activeColor: const Color(0xFF00C874),
                  onChanged: (bool value) {
                    setState(() {
                      _hydrationAlerts = value;
                    });
                  },
                ),
              ),
              _buildSettingTile(
                Icons.shield_outlined,
                'Privacy & Security',
                onTap: () => _showFeatureDialog('Privacy & Security'),
              ),
              _buildSettingTile(
                Icons.people_outline,
                'Caregiver Access',
                onTap: () => _showFeatureDialog('Caregiver Access'),
              ),
              _buildSettingTile(
                Icons.insert_drive_file_outlined,
                'Export Health Data',
                onTap: () => _showFeatureDialog('Export Health Data'),
              ),

              const SizedBox(height: 24),

              // --- Support Section ---
              const Text(
                'Support',
                style: TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildSettingTile(
                Icons.help_outline,
                'Help Center',
                onTap: () => _showFeatureDialog('Help Center'),
              ),
              _buildSettingTile(
                Icons.description_outlined,
                'Terms of Service',
                onTap: () => _showFeatureDialog('Terms of Service'),
              ),

              const SizedBox(height: 40),

              // --- Sign Out Button ---
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // signOut() clears the active session but preserves rememberMe
                    // so the toggle can stay pre-checked on the next login.
                    await AuthService.signOut();

                    // Navigate to Login, clearing nav stack
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.logout,
                    color: Color(0xFFD32F2F),
                    size: 20,
                  ),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(
                      color: Color(0xFFD32F2F),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.grey.shade200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // ==========================================
  // COMPONENT BUILDERS
  // ==========================================

  Widget _buildProfileCard() {
    final age = _textValue(_user, ["ageYears", "age_years"]);
    final ckdStage = _textValue(_medicalProfile, ["ckdStage", "ckd_stage"]);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF00C874), // NutriKidney Green
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C874).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: _isLoadingProfile
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF009688),
                      ),
                    )
                  : Text(
                      _childInitials,
                      style: const TextStyle(
                        color: Color(0xFF009688),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isLoadingProfile ? "Loading profile..." : _childName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  age.isEmpty ? "Age not set" : "$age years old",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        ckdStage.isEmpty ? "CKD stage not set" : ckdStage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _openEditProfile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              color: Color(0xFF00A864),
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Edit Profile",
                              style: TextStyle(
                                color: Color(0xFF00A864),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Achievements',
              style: TextStyle(
                color: Color(0xFF78909C),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextButton(
              onPressed: _showAllAchievements,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View All',
                style: TextStyle(
                  color: Color(0xFF00C874),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.1,
          children: [
            _buildAchievementCard(
              title: '7 Day Streak',
              subtitle: 'Logged food daily',
              iconWidget: const Icon(
                Icons.local_fire_department,
                color: Color(0xFFFF8A65),
                size: 40,
              ),
            ),
            _buildAchievementCard(
              title: 'Rainbow Eater',
              subtitle: 'Ate 5 different colored\nfoods',
              iconWidget: const Text(
                '🌈',
                style: TextStyle(fontSize: 32),
              ),
            ),
            _buildAchievementCard(
              title: 'Hydration Hero',
              subtitle: 'Met water goal 10 times',
              iconWidget: const Icon(
                Icons.water_drop,
                color: Color(0xFF64B5F6),
                size: 40,
              ),
            ),
            _buildAchievementCard(
              title: 'Perfect Week',
              subtitle: 'All nutrients in range',
              iconWidget: const Icon(
                Icons.star_rounded,
                color: Color(0xFFFFD54F),
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAchievementCard({
    required String title,
    required String subtitle,
    required Widget iconWidget,
    bool isLocked = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLocked ? const Color(0xFFF5F6FA) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget,
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isLocked
                  ? const Color(0xFF90A4AE)
                  : const Color(0xFF37474F),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    IconData icon,
    String title, {
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: trailing != null ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF37474F), size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Color(0xFF37474F), fontSize: 16),
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right, color: Color(0xFFB0BEC5)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
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
          if (index == 0)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          else if (index == 1)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const FoodLogPage()),
            );
          else if (index == 2)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AnalyticsPage()),
            );
          else if (index == 3)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const HealthMetricsPage(),
              ),
            );
          else
            setState(() => _currentIndex = index);
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
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> medicalProfile;
  final Map<String, dynamic> anthropometrics;

  const EditProfilePage({
    super.key,
    required this.user,
    required this.medicalProfile,
    required this.anthropometrics,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, String> _originalNutritionFields = {};

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _dobController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _bmiController;
  late final TextEditingController _dryWeightController;
  late final TextEditingController _kidneyDiseaseTypeController;
  late final TextEditingController _diagnosisDateController;
  late final TextEditingController _treatmentFrequencyController;
  late final TextEditingController _fluidLimitController;

  String? _sex;
  String? _ckdStage;
  String? _dialysisType;
  String? _dietPattern;
  String? _processedFoodIntake;
  String? _mealPattern;
  String? _physicalActivityLevel;
  String? _preferredMeasurementSystem;
  String? _fluidRestrictionStatus;
  String? _hasHypertension;
  bool _onDialysis = false;

  static const _sexOptions = ["Male", "Female"];
  static const _ckdStageOptions = [
    "Stage 1",
    "Stage 2",
    "Stage 3",
    "Stage 4",
    "Stage 5",
    "Stage 5D",
  ];
  static const _dialysisTypeOptions = ["HD", "PD"];
  static const _dietPatternOptions = [
    "Regular diet",
    "Renal diet",
    "High protein",
    "Low protein",
    "Low salt / Low fat",
    "Low fat",
    "Low salt",
    "Low potassium",
    "Low phosphorus",
    "Low purine",
    "Vegetarian",
    "Vegan",
    "Other",
  ];
  static const _processedFoodOptions = ["Often", "Sometimes", "Rarely"];
  static const _mealPatternOptions = [
    "Regular (3 meals)",
    "3 meals + snacks",
    "Irregular",
  ];
  static const _activityOptions = [
    "Low (Mostly sedentary)",
    "Moderate (Light active)",
    "High (Very active)",
  ];
  static const _measurementOptions = ["Grams", "Ounces/Cups", "Mixed"];
  static const _fluidRestrictionOptions = ["yes", "no", "not sure"];
  static const _hypertensionOptions = ["yes", "no", "not_sure"];

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: _read(widget.user, ["childFullName", "child_name", "name"]),
    );
    _ageController = TextEditingController(
      text: _read(widget.user, ["ageYears", "age_years"]),
    );
    _dobController = TextEditingController(
      text: _read(widget.user, ["dateOfBirth", "dob"]),
    );
    _heightController = TextEditingController(
      text: _read(widget.anthropometrics, ["height_cm", "height"]),
    );
    _weightController = TextEditingController(
      text: _read(widget.anthropometrics, ["weight_kg", "weight"]),
    );
    _bmiController = TextEditingController(
      text: _firstValue([
        _read(widget.anthropometrics, ["bmi"]),
        _read(widget.user, ["bmi"]),
      ]),
    );
    _dryWeightController = TextEditingController(
      text: _read(widget.anthropometrics, ["dryWeight", "dry_weight_kg"]),
    );
    _kidneyDiseaseTypeController = TextEditingController(
      text: _read(widget.medicalProfile, ["kidneyDiseaseType"]),
    );
    _diagnosisDateController = TextEditingController(
      text: _read(widget.medicalProfile, ["dateOfDiagnosis"]),
    );
    _treatmentFrequencyController = TextEditingController(
      text: _read(widget.medicalProfile, ["treatmentFrequency"]),
    );
    _fluidLimitController = TextEditingController(
      text: _read(widget.medicalProfile, ["fluidLimitMl", "fluid_limit_ml"]),
    );
    _heightController.addListener(_updateBmi);
    _weightController.addListener(_updateBmi);

    _populateDropdowns(
      user: widget.user,
      medical: widget.medicalProfile,
      targets: const {},
    );
    _onDialysis = _readBool(widget.medicalProfile["onDialysis"]);
    _originalNutritionFields = _nutritionAffectingValues();
    _loadLatestProfileForEdit();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _dobController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _bmiController.dispose();
    _dryWeightController.dispose();
    _kidneyDiseaseTypeController.dispose();
    _diagnosisDateController.dispose();
    _treatmentFrequencyController.dispose();
    _fluidLimitController.dispose();
    super.dispose();
  }

  static String _read(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return "";
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  static String _firstValue(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value;
    }
    return "";
  }

  void _updateBmi() {
    final heightCm = double.tryParse(_heightController.text.trim());
    final weightKg = double.tryParse(_weightController.text.trim());

    if (heightCm == null || weightKg == null || heightCm <= 0) {
      if (_bmiController.text.isNotEmpty) {
        _bmiController.clear();
      }
      return;
    }

    final heightMeters = heightCm / 100;
    final bmi = weightKg / (heightMeters * heightMeters);
    final bmiText = bmi.toStringAsFixed(1);
    if (_bmiController.text != bmiText) {
      _bmiController.text = bmiText;
    }
  }

  static String _normalizeOption(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
        .trim();
  }

  static String _normalizeDietPattern(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "regular": "Regular diet",
      "regular diet": "Regular diet",
      "renal": "Renal diet",
      "renal diet": "Renal diet",
      "high protein": "High protein",
      "low protein": "Low protein",
      "low salt low fat": "Low salt / Low fat",
      "low fat low salt": "Low salt / Low fat",
      "low fat": "Low fat",
      "low salt": "Low salt",
      "low sodium": "Low salt",
      "low potassium": "Low potassium",
      "low phosphorus": "Low phosphorus",
      "low phosphate": "Low phosphorus",
      "low purine": "Low purine",
      "vegetarian": "Vegetarian",
      "vegan": "Vegan",
      "other": "Other",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeProcessedFood(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "often": "Often",
      "frequent": "Often",
      "frequently": "Often",
      "daily": "Often",
      "sometimes": "Sometimes",
      "moderate": "Sometimes",
      "rarely": "Rarely",
      "rare": "Rarely",
      "low": "Rarely",
      "never": "Rarely",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeMealPattern(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "regular": "Regular (3 meals)",
      "regular 3 meals": "Regular (3 meals)",
      "3 meals": "Regular (3 meals)",
      "three meals": "Regular (3 meals)",
      "3 meals snacks": "3 meals + snacks",
      "3 meals plus snacks": "3 meals + snacks",
      "small frequent meals": "3 meals + snacks",
      "frequent meals": "3 meals + snacks",
      "irregular": "Irregular",
      "skips meals frequently": "Irregular",
      "skip meals": "Irregular",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeActivityLevel(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "low": "Low (Mostly sedentary)",
      "low mostly sedentary": "Low (Mostly sedentary)",
      "mostly sedentary": "Low (Mostly sedentary)",
      "moderate": "Moderate (Light active)",
      "moderate light active": "Moderate (Light active)",
      "light active": "Moderate (Light active)",
      "high": "High (Very active)",
      "high very active": "High (Very active)",
      "very active": "High (Very active)",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeMeasurementSystem(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "grams": "Grams",
      "metric": "Grams",
      "ounces cups": "Ounces/Cups",
      "ounces": "Ounces/Cups",
      "cups": "Ounces/Cups",
      "imperial": "Ounces/Cups",
      "mixed": "Mixed",
    };
    return aliases[text] ?? value;
  }

  void _setText(TextEditingController controller, String value) {
    if (value.trim().isNotEmpty) {
      controller.text = value;
    }
  }

  String _normalizedFieldValue(dynamic value) {
    return (value ?? "").toString().trim();
  }

  Map<String, String> _nutritionAffectingValues() {
    return {
      "age": _normalizedFieldValue(_ageController.text),
      "dateOfBirth": _normalizedFieldValue(_dobController.text),
      "height": _normalizedFieldValue(_heightController.text),
      "weight": _normalizedFieldValue(_weightController.text),
      "bmi": _normalizedFieldValue(_bmiController.text),
      "dryWeight": _normalizedFieldValue(
        _onDialysis ? _dryWeightController.text : "",
      ),
      "ckdStage": _normalizedFieldValue(_ckdStage),
      "onDialysis": _normalizedFieldValue(_onDialysis),
      "dialysisType": _normalizedFieldValue(_onDialysis ? _dialysisType : ""),
      "treatmentFrequency": _normalizedFieldValue(
        _onDialysis ? _treatmentFrequencyController.text : "",
      ),
      "physicalActivityLevel": _normalizedFieldValue(_physicalActivityLevel),
      "fluidRestrictionStatus": _normalizedFieldValue(_fluidRestrictionStatus),
      "fluidLimit": _normalizedFieldValue(
        _fluidRestrictionStatus == "yes" ? _fluidLimitController.text : "",
      ),
    };
  }

  bool _hasNutritionAffectingChanges() {
    final currentValues = _nutritionAffectingValues();
    for (final entry in currentValues.entries) {
      if (_originalNutritionFields[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _confirmNutritionTargetUpdate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Update Nutrition Targets?"),
          content: const Text(
            "The changes you made affect the child's nutritional profile. "
            "Saving this update will trigger the system to recalculate "
            "nutrition targets and may change the recommended insights, "
            "limits, and guidance. Are you sure you want to continue?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
              ),
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  void _populateDropdowns({
    required Map<String, dynamic> user,
    required Map<String, dynamic> medical,
    required Map<String, dynamic> targets,
  }) {
    _sex = _dropdownValue(
      _sexOptions,
      _normalizeSex(_firstValue([
        _read(user, ["sex", "gender"]),
        _read(targets, ["sex", "gender"]),
      ])),
    );
    _ckdStage = _dropdownValue(
      _ckdStageOptions,
      _firstValue([
        _read(medical, ["ckdStage", "ckd_stage"]),
        _read(targets, ["ckd_stage", "ckdStage"]),
      ]),
    );
    _dialysisType = _dropdownValue(
      _dialysisTypeOptions,
      _read(medical, ["dialysisType", "dialysis_type"]),
    );
    _dietPattern = _dropdownValue(
      _dietPatternOptions,
      _normalizeDietPattern(_read(medical, ["dietPattern", "diet_pattern"])),
    );
    _processedFoodIntake = _dropdownValue(
      _processedFoodOptions,
      _normalizeProcessedFood(
        _read(medical, ["processedFoodIntake", "processed_food_intake"]),
      ),
    );
    _mealPattern = _dropdownValue(
      _mealPatternOptions,
      _normalizeMealPattern(_read(medical, ["mealPattern", "meal_pattern"])),
    );
    _physicalActivityLevel = _dropdownValue(
      _activityOptions,
      _normalizeActivityLevel(
        _read(medical, ["physicalActivityLevel", "physical_activity_level"]),
      ),
    );
    _preferredMeasurementSystem = _dropdownValue(
      _measurementOptions,
      _normalizeMeasurementSystem(
        _read(user, ["preferredMeasurementSystem", "preferredMeasurement"]),
      ),
    );
    _fluidRestrictionStatus = _dropdownValue(
      _fluidRestrictionOptions,
      _read(medical, ["fluidRestrictionStatus", "fluid_restriction_status"]),
    );
    _hasHypertension = _dropdownValue(
      _hypertensionOptions,
      _read(medical, ["hasHypertension", "has_hypertension"]),
    );
  }

  Future<void> _loadLatestProfileForEdit() async {
    try {
      final response = await ApiService.getHealthSummary();
      if (!mounted) return;

      if (response["success"] == true) {
        final user = _asStringMap(response["user"]);
        final medical = _asStringMap(response["medicalProfile"]);
        final anthropometrics = _asStringMap(response["anthropometrics"]);
        final targets = _asStringMap(response["nutritionTargets"]);

        _setText(
          _nameController,
          _firstValue([
            _read(user, ["childFullName", "child_name", "name"]),
            _read(targets, ["child_name", "childFullName"]),
          ]),
        );
        _setText(
          _ageController,
          _firstValue([
            _read(user, ["ageYears", "age_years"]),
            _read(targets, ["age_years", "ageYears"]),
          ]),
        );
        _setText(_dobController, _read(user, ["dateOfBirth", "dob"]));
        _setText(
          _heightController,
          _firstValue([
            _read(anthropometrics, ["height_cm", "height"]),
            _read(targets, ["height_cm", "height"]),
          ]),
        );
        _setText(
          _weightController,
          _firstValue([
            _read(anthropometrics, ["weight_kg", "weight"]),
            _read(targets, ["weight_kg", "weight"]),
          ]),
        );
        _setText(
          _bmiController,
          _firstValue([
            _read(anthropometrics, ["bmi"]),
            _read(user, ["bmi"]),
            _read(targets, ["bmi"]),
          ]),
        );
        _setText(
          _dryWeightController,
          _firstValue([
            _read(anthropometrics, ["dryWeight", "dry_weight_kg"]),
            _read(targets, ["dry_weight_kg", "dryWeight"]),
          ]),
        );
        _setText(
          _kidneyDiseaseTypeController,
          _read(medical, ["kidneyDiseaseType"]),
        );
        _setText(
          _diagnosisDateController,
          _read(medical, ["dateOfDiagnosis"]),
        );
        _setText(
          _treatmentFrequencyController,
          _read(medical, ["treatmentFrequency"]),
        );
        _setText(
          _fluidLimitController,
          _read(medical, ["fluidLimitMl", "fluid_limit_ml"]),
        );

        setState(() {
          _populateDropdowns(user: user, medical: medical, targets: targets);
          _onDialysis = _readBool(medical["onDialysis"]);
          _originalNutritionFields = _nutritionAffectingValues();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    return text == "true" || text == "yes";
  }

  static String _normalizeSex(String value) {
    final text = value.toLowerCase().trim();
    if (text == "male") return "Male";
    if (text == "female") return "Female";
    return value;
  }

  static String? _dropdownValue(List<String> options, String value) {
    if (value.trim().isEmpty) return null;
    final normalizedValue = _normalizeOption(value);
    for (final option in options) {
      if (_normalizeOption(option) == normalizedValue) {
        return option;
      }
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );

    if (selected != null) {
      controller.text = selected.toIso8601String().split("T").first;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final shouldRecalculate = _hasNutritionAffectingChanges();
    if (shouldRecalculate) {
      final confirmed = await _confirmNutritionTargetUpdate();
      if (!confirmed) return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await ApiService.updateProfile({
        "childFullName": _nameController.text.trim(),
        "ageYears": _ageController.text.trim(),
        "dateOfBirth": _dobController.text.trim(),
        "sex": _sex,
        "height_cm": _heightController.text.trim(),
        "weight_kg": _weightController.text.trim(),
        "bmi": _bmiController.text.trim(),
        "dryWeight": _onDialysis ? _dryWeightController.text.trim() : null,
        "ckdStage": _ckdStage,
        "kidneyDiseaseType": _kidneyDiseaseTypeController.text.trim(),
        "dateOfDiagnosis": _diagnosisDateController.text.trim(),
        "onDialysis": _onDialysis,
        "dialysisType": _onDialysis ? _dialysisType : null,
        "treatmentFrequency":
            _onDialysis ? _treatmentFrequencyController.text.trim() : null,
        "dietPattern": _dietPattern,
        "processedFoodIntake": _processedFoodIntake,
        "mealPattern": _mealPattern,
        "physicalActivityLevel": _physicalActivityLevel,
        "preferredMeasurementSystem": _preferredMeasurementSystem,
        "fluidRestrictionStatus": _fluidRestrictionStatus,
        "fluidLimitMl": _fluidRestrictionStatus == "yes"
            ? _fluidLimitController.text.trim()
            : null,
        "hasHypertension": _hasHypertension,
        "recalculateNutritionTargets": shouldRecalculate,
      });

      if (!mounted) return;
      if (response["success"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully")),
        );
        Navigator.pop(context, true);
      } else {
        _showError(response["error"]?.toString() ?? "Unable to update profile");
      }
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(
                      color: Color(0xFF00C874),
                      backgroundColor: Color(0xFFE0F2F1),
                    ),
                  ),
                _section(
                  "Child Information",
                  [
                    _textField(
                      _nameController,
                      "Child full name",
                      required: true,
                    ),
                    _numberField(_ageController, "Age", required: true),
                    _dateField(_dobController, "Date of birth"),
                    _dropdownField(
                      label: "Sex / gender",
                      value: _sex,
                      options: _sexOptions,
                      onChanged: (value) => setState(() => _sex = value),
                    ),
                  ],
                ),
                _section(
                  "Body Measurements",
                  [
                    _numberField(_heightController, "Height (cm)"),
                    _numberField(_weightController, "Weight (kg)"),
                    _numberField(
                      _bmiController,
                      "BMI",
                      readOnly: true,
                      hint: "Auto-calculated from height and weight",
                    ),
                    if (_onDialysis)
                      _numberField(_dryWeightController, "Dry weight (kg)"),
                  ],
                ),
                _section(
                  "Medical Profile",
                  [
                    _dropdownField(
                      label: "CKD stage",
                      value: _ckdStage,
                      options: _ckdStageOptions,
                      onChanged: (value) => setState(() => _ckdStage = value),
                    ),
                    _textField(
                      _kidneyDiseaseTypeController,
                      "Kidney disease type",
                    ),
                    _dateField(_diagnosisDateController, "Date of diagnosis"),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00C874),
                      title: const Text("On dialysis?"),
                      value: _onDialysis,
                      onChanged: (value) {
                        setState(() {
                          _onDialysis = value;
                          if (!value) _dialysisType = null;
                        });
                      },
                    ),
                    if (_onDialysis)
                      _dropdownField(
                        label: "Dialysis type",
                        value: _dialysisType,
                        options: _dialysisTypeOptions,
                        onChanged: (value) =>
                            setState(() => _dialysisType = value),
                      ),
                    if (_onDialysis)
                      _textField(
                        _treatmentFrequencyController,
                        "Treatment frequency",
                      ),
                  ],
                ),
                _section(
                  "Dietary Lifestyle",
                  [
                    _dropdownField(
                      label: "Diet pattern",
                      value: _dietPattern,
                      options: _dietPatternOptions,
                      onChanged: (value) =>
                          setState(() => _dietPattern = value),
                    ),
                    _dropdownField(
                      label: "Processed food intake",
                      value: _processedFoodIntake,
                      options: _processedFoodOptions,
                      onChanged: (value) =>
                          setState(() => _processedFoodIntake = value),
                    ),
                    _dropdownField(
                      label: "Meal pattern",
                      value: _mealPattern,
                      options: _mealPatternOptions,
                      onChanged: (value) =>
                          setState(() => _mealPattern = value),
                    ),
                    _dropdownField(
                      label: "Physical activity level",
                      value: _physicalActivityLevel,
                      options: _activityOptions,
                      onChanged: (value) =>
                          setState(() => _physicalActivityLevel = value),
                    ),
                    _dropdownField(
                      label: "Preferred measurement system",
                      value: _preferredMeasurementSystem,
                      options: _measurementOptions,
                      onChanged: (value) => setState(
                        () => _preferredMeasurementSystem = value,
                      ),
                    ),
                  ],
                ),
                _section(
                  "Fluid And Condition Settings",
                  [
                    _dropdownField(
                      label: "Is fluid intake restricted?",
                      value: _fluidRestrictionStatus,
                      options: _fluidRestrictionOptions,
                      onChanged: (value) =>
                          setState(() => _fluidRestrictionStatus = value),
                    ),
                    if (_fluidRestrictionStatus == "yes")
                      _numberField(
                        _fluidLimitController,
                        "Daily fluid limit (mL)",
                        required: true,
                      ),
                    _dropdownField(
                      label: "Does the child have high blood pressure?",
                      value: _hasHypertension,
                      options: _hypertensionOptions,
                      onChanged: (value) =>
                          setState(() => _hasHypertension = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading || _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C874),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Save Profile",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
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
              color: Color(0xFF37474F),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: _inputDecoration(label),
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return "$label is required";
                }
                return null;
              }
            : null,
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool readOnly = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        readOnly: readOnly,
        decoration: _inputDecoration(label).copyWith(hintText: hint),
        validator: (value) {
          final text = value?.trim() ?? "";
          if (required && text.isEmpty) return "$label is required";
          if (text.isNotEmpty && double.tryParse(text) == null) {
            return "Enter a valid number";
          }
          return null;
        },
      ),
    );
  }

  Widget _dateField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: _inputDecoration(label).copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        onTap: () => _pickDate(controller),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: _inputDecoration(label),
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF9FBFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00C874)),
      ),
    );
  }
}
