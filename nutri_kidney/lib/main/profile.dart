import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // For the iOS style switches
import 'dashboard.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'health_metrics.dart';
import 'profile/account_management_page.dart';
import 'profile/edit_profile_page.dart';
import 'profile/notification_settings_page.dart';
import 'profile/privacy_security_page.dart';
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
  bool _medicationReminders = false;
  bool _hydrationAlerts = false;
  bool _breakfastReminders = false;
  bool _lunchReminders = false;
  bool _snackReminders = false;
  bool _dinnerReminders = false;
  bool _allowDataExport = false;
  bool _isLoadingProfile = true;
  bool _isSavingReminderSettings = false;
  Map<String, dynamic> _viewer = {};
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _medicalProfile = {};
  Map<String, dynamic> _anthropometrics = {};
  String? _profileOwnerId;
  Map<String, dynamic> _caregiverDashboardState = {};
  List<Map<String, dynamic>> _medications = [];
  Set<String> _unlockedAwardIds = {};

  Map<String, dynamic> get _caregiverSettings {
    final settings = _user["caregiverSettings"];
    if (settings is Map) {
      return Map<String, dynamic>.from(settings);
    }
    return {};
  }

  Map<String, dynamic> get _viewerSecuritySettings {
    final viewerSettings = _viewer["securitySettings"];
    if (viewerSettings is Map) {
      return Map<String, dynamic>.from(viewerSettings);
    }
    final userSettings = _user["securitySettings"];
    if (userSettings is Map) {
      return Map<String, dynamic>.from(userSettings);
    }
    return {};
  }

  Map<String, dynamic> get _reminderSettings {
    final settings = _user["reminderSettings"];
    if (settings is Map) {
      return Map<String, dynamic>.from(settings);
    }
    return {};
  }

  Map<String, dynamic> get _mealReminderSettings {
    final settings = _reminderSettings["mealReminders"];
    if (settings is Map) {
      return Map<String, dynamic>.from(settings);
    }
    return {};
  }

  bool get _isAdolescentRole =>
      _textValue(_user, ["role", "userRole"]).toLowerCase() == "adolescent";

  bool get _isCaregiverViewer {
    final role = _textValue(_viewer, ["role", "userRole"]).toLowerCase();
    return role == "caregiver" || role == "parent_caregiver";
  }

  bool get _caregiverLinked => _caregiverSettings["caregiverLinked"] == true;

  bool get _linkedChildAccountActive =>
      _caregiverDashboardState["linkedChildAccount"] == true;

  bool get _canManageReminderSettings {
    if (_isCaregiverViewer) return _linkedChildAccountActive;
    if (_isAdolescentRole && _caregiverLinked) return false;
    return true;
  }

  bool get _canOpenEditProfile {
    if (_isAdolescentRole && _caregiverLinked) return false;
    if (_isCaregiverViewer) return _linkedChildAccountActive;
    return true;
  }

  String get _reminderSettingsLockReason {
    if (_isCaregiverViewer && !_linkedChildAccountActive) {
      return 'Link an adolescent account first to manage reminders.';
    }
    if (_isAdolescentRole && _caregiverLinked) {
      return 'Reminder settings are managed by the linked caregiver.';
    }
    return 'Reminder settings are unavailable right now.';
  }

  String get _caregiverLinkStatus {
    final rawStatus = _caregiverSettings["linkStatus"]?.toString();
    final status = rawStatus?.trim() ?? "";
    if (status.isEmpty) {
      return _caregiverLinked ? "linked" : "none";
    }
    return status;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await ApiService.getHealthSummary();
      Map<String, dynamic> gamificationStatus = {};
      if (response["success"] == true) {
        try {
          final gamificationResponse = await ApiService.getGamificationSummary();
          final gamification = _asStringMap(gamificationResponse["gamification"]);
          gamificationStatus = _asStringMap(gamification["status"]);
        } catch (_) {
          gamificationStatus = {};
        }
      }
      if (!mounted) return;
      if (response["success"] == true) {
        setState(() {
          _viewer = _asStringMap(response["viewer"]);
          _user = _asStringMap(response["user"]);
          _medicalProfile = _asStringMap(response["medicalProfile"]);
          _anthropometrics = _asStringMap(response["anthropometrics"]);
          _profileOwnerId = response["profileOwnerId"]?.toString();
          _caregiverDashboardState = _asStringMap(
            response["caregiverDashboardState"],
          );
          _medications = _asStringMapList(response["medications"]);
          _medicationReminders =
              _reminderSettings["medicationReminders"] == true;
          _hydrationAlerts = _reminderSettings["hydrationAlerts"] == true;
          _breakfastReminders = _mealReminderSettings["breakfast"] == true;
          _lunchReminders = _mealReminderSettings["lunch"] == true;
          _snackReminders = _mealReminderSettings["snack"] == true;
          _dinnerReminders = _mealReminderSettings["dinner"] == true;
          _allowDataExport = _user["allowDataExport"] == true;
          final unlockedAwards = gamificationStatus["unlockedAwards"];
          _unlockedAwardIds = unlockedAwards is List
              ? unlockedAwards.map((award) => award.toString()).toSet()
              : {};
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

  List<Map<String, dynamic>> _asStringMapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
      .toList();
  }

  bool _hasAward(String awardId) => _unlockedAwardIds.contains(awardId);

  Widget _achievementIcon({
    required IconData icon,
    required Color color,
    required bool isLocked,
  }) {
    return Icon(
      isLocked ? Icons.lock_outline : icon,
      color: isLocked ? const Color(0xFFB0BEC5) : color,
      size: 40,
    );
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

  String get _viewerRoleLabel {
    final role = _textValue(_viewer, ["role", "userRole"]).toLowerCase();
    if (role == "caregiver" || role == "parent_caregiver") {
      return "Caregiver";
    }
    if (role == "adolescent") {
      return "Adolescent";
    }
    return "User";
  }

  String get _viewerEmail {
    return _textValue(_viewer, ["email"]).isNotEmpty
        ? _textValue(_viewer, ["email"])
        : _textValue(_user, ["email"]);
  }

  String get _viewerPhone {
    return _textValue(_viewer, ["phoneNumber"]).isNotEmpty
        ? _textValue(_viewer, ["phoneNumber"])
        : _textValue(_user, ["phoneNumber"]);
  }

  String get _linkedProfileEmail {
    return _textValue(_user, ["email"]);
  }

  String get _linkedProfileRoleLabel {
    final role = _textValue(_user, ["role", "userRole"]).toLowerCase();
    if (role == "caregiver" || role == "parent_caregiver") {
      return "Caregiver";
    }
    if (role == "adolescent") {
      return "Adolescent";
    }
    return "User";
  }

  String get _verificationContact {
    return _viewerEmail;
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
    if (!_canOpenEditProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAdolescentRole && _caregiverLinked
                ? 'Profile editing is managed by the linked caregiver.'
                : 'Link an adolescent account first to edit this profile.',
          ),
        ),
      );
      return;
    }

    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(
          viewer: _viewer,
          user: _user,
          medicalProfile: _medicalProfile,
          anthropometrics: _anthropometrics,
          profileOwnerId: _profileOwnerId,
        ),
      ),
    );

    if (updated == true) {
      _loadProfile();
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
      _isSavingReminderSettings = true;
    });

    try {
      final response = await ApiService.updateReminderSettings(
        profileUserId: _profileOwnerId,
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
      final savedSettings = response["reminderSettings"];
      if (savedSettings is Map) {
        _user["reminderSettings"] = Map<String, dynamic>.from(savedSettings);
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
        setState(() => _isSavingReminderSettings = false);
      }
    }
  }

  void _showReminderSettingsLockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_reminderSettingsLockReason)),
    );
  }

  Future<void> _openAccountManagement() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountManagementPage(
          email: _viewerEmail,
          roleLabel: _viewerRoleLabel,
          verificationContact: _verificationContact,
          linkedProfileEmail: _linkedProfileEmail,
          linkedProfileRoleLabel: _linkedProfileRoleLabel,
        ),
      ),
    );
  }

  Future<void> _openPrivacySecurity() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PrivacySecurityPage(
          initialMfaEnabled: _viewerSecuritySettings["mfaEnabled"] == true,
          accountLabel: _viewerEmail.isNotEmpty ? _viewerEmail : _viewerPhone,
        ),
      ),
    );

    if (updated == true) {
      _loadProfile();
    }
  }

  Future<void> _openNotificationSettings() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationSettingsPage(
          profileUserId: _profileOwnerId,
          canManageReminderSettings: _canManageReminderSettings,
          reminderSettingsLockReason: _reminderSettingsLockReason,
          initialMedicationReminders: _medicationReminders,
          initialHydrationAlerts: _hydrationAlerts,
          initialBreakfastReminders: _breakfastReminders,
          initialLunchReminders: _lunchReminders,
          initialSnackReminders: _snackReminders,
          initialDinnerReminders: _dinnerReminders,
          medications: _medications,
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
                    _buildAchievementCard(
                      title: '7 Day Streak',
                      subtitle: 'Logged meals and hydration daily',
                      iconWidget: _achievementIcon(
                        icon: Icons.local_fire_department,
                        color: const Color(0xFFFF8A65),
                        isLocked: !_hasAward('seven_day_streak'),
                      ),
                      isLocked: !_hasAward('seven_day_streak'),
                    ),
                    _buildAchievementCard(
                      title: '14 Day Streak',
                      subtitle: 'Logged meals and hydration for 14 days',
                      iconWidget: _achievementIcon(
                        icon: Icons.local_fire_department,
                        color: const Color(0xFFE53935),
                        isLocked: !_hasAward('fourteen_day_streak'),
                      ),
                      isLocked: !_hasAward('fourteen_day_streak'),
                    ),
                    _buildAchievementCard(
                      title: 'Rainbow Eater',
                      subtitle: 'Ate 5 different colored foods',
                      iconWidget: _achievementIcon(
                        icon: Icons.palette_outlined,
                        color: const Color(0xFF7E57C2),
                        isLocked: !_hasAward('rainbow_eater'),
                      ),
                      isLocked: !_hasAward('rainbow_eater'),
                    ),
                    _buildAchievementCard(
                      title: 'Hydration Hero',
                      subtitle: 'Met water goal 10 times',
                      iconWidget: _achievementIcon(
                        icon: Icons.water_drop,
                        color: const Color(0xFF64B5F6),
                        isLocked: !_hasAward('hydration_hero'),
                      ),
                      isLocked: !_hasAward('hydration_hero'),
                    ),
                    _buildAchievementCard(
                      title: 'Balanced Week',
                      subtitle: 'Within app nutrition ranges for 7 days',
                      iconWidget: _achievementIcon(
                        icon: Icons.star_rounded,
                        color: const Color(0xFFFFD54F),
                        isLocked: !_hasAward('balanced_week'),
                      ),
                      isLocked: !_hasAward('balanced_week'),
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
                subtitle: _canManageReminderSettings
                    ? 'Meals, hydration, and medication reminders'
                    : _reminderSettingsLockReason,
                onTap: _openNotificationSettings,
              ),
              _buildSettingTile(
                Icons.shield_outlined,
                'Privacy & Security',
                subtitle: _viewerSecuritySettings["mfaEnabled"] == true
                    ? 'MFA enabled'
                    : 'Manage multi-factor authentication',
                onTap: _openPrivacySecurity,
              ),
              _buildSettingTile(
                Icons.manage_accounts_outlined,
                'Account Management',
                subtitle: 'View linked account details and change password',
                onTap: _openAccountManagement,
              ),
              _buildSettingTile(
                Icons.people_outline,
                'Caregiver Access',
                subtitle: _isAdolescentRole
                    ? (_caregiverLinked
                        ? 'Linked caregiver'
                        : (_caregiverLinkStatus == 'pending'
                            ? 'Link pending'
                            : 'No caregiver linked'))
                    : (_isCaregiverViewer
                        ? (_caregiverDashboardState["linkedChildAccount"] == true
                            ? 'Linked adolescent account'
                            : 'No adolescent linked')
                        : 'Available for adolescent accounts'),
                onTap: _isAdolescentRole
                    ? _showCaregiverSettingsDialog
                    : (_isCaregiverViewer
                        ? _showCaregiverLinkManagementDialog
                        : () => _showFeatureDialog('Caregiver Access')),
              ),
              _buildSettingTile(
                Icons.insert_drive_file_outlined,
                'Export Health Data',
                subtitle: _allowDataExport
                    ? 'PDF health reports are enabled'
                    : 'Allow PDF reports for provider review',
                onTap: _showExportDataSettingsDialog,
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
                      onTap: _canOpenEditProfile ? _openEditProfile : _openEditProfile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _canOpenEditProfile
                              ? Colors.white
                              : Colors.white.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              color: _canOpenEditProfile
                                  ? const Color(0xFF00A864)
                                  : const Color(0xFF90A4AE),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "Edit Profile",
                              style: TextStyle(
                                color: _canOpenEditProfile
                                    ? const Color(0xFF00A864)
                                    : const Color(0xFF90A4AE),
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
              subtitle: 'Logged meals and hydration daily',
              iconWidget: _achievementIcon(
                icon: Icons.local_fire_department,
                color: const Color(0xFFFF8A65),
                isLocked: !_hasAward('seven_day_streak'),
              ),
              isLocked: !_hasAward('seven_day_streak'),
            ),
            _buildAchievementCard(
              title: 'Rainbow Eater',
              subtitle: 'Ate 5 different colored\nfoods',
              iconWidget: _achievementIcon(
                        icon: Icons.palette_outlined,
                        color: const Color(0xFF7E57C2),
                        isLocked: !_hasAward('rainbow_eater'),
                      ),
              isLocked: !_hasAward('rainbow_eater'),
            ),
            _buildAchievementCard(
              title: 'Hydration Hero',
              subtitle: 'Met water goal 10 times',
              iconWidget: _achievementIcon(
                icon: Icons.water_drop,
                color: const Color(0xFF64B5F6),
                isLocked: !_hasAward('hydration_hero'),
              ),
              isLocked: !_hasAward('hydration_hero'),
            ),
            _buildAchievementCard(
              title: 'Balanced Week',
              subtitle: 'Within app nutrition ranges for 7 days',
              iconWidget: _achievementIcon(
                icon: Icons.star_rounded,
                color: const Color(0xFFFFD54F),
                isLocked: !_hasAward('balanced_week'),
              ),
              isLocked: !_hasAward('balanced_week'),
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
    String? subtitle,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF37474F),
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF90A4AE),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
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
              MaterialPageRoute(
                builder: (context) => AnalyticsPage(allowDataExport: _allowDataExport),
              ),
            );
          else if (index == 2)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const AnalyticsPage(),
              ),
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

  Future<void> _showExportDataSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Export Health Data'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Allow Data Export',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enable this to allow NutriKidney to generate downloadable PDF health reports from your nutrition, hydration, and health metrics. These reports are useful for sharing with your doctor, dietitian, or caregiver to review your health trends.',
                    style: TextStyle(color: Color(0xFF546E7A), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: Color(0xFF00C874),
                    title: const Text('Allow Data Export'),
                    subtitle: const Text('Shows the Export PDF option in Analytics.'),
                    value: _allowDataExport,
                    onChanged: (value) async {
                      setDialogState(() => _allowDataExport = value);
                      setState(() {
                        _allowDataExport = value;
                        _user["allowDataExport"] = value;
                      });
                      try {
                        final response = await ApiService.updateProfile({
                          "allowDataExport": value,
                        });
                        if (response["success"] != true) {
                          throw Exception(
                            response["error"]?.toString() ??
                                'Unable to update export preference.',
                          );
                        }
                      } catch (e) {
                        if (!mounted) return;
                        if (context.mounted) {
                          setDialogState(() => _allowDataExport = !value);
                        }
                        setState(() {
                          _allowDataExport = !value;
                          _user["allowDataExport"] = !value;
                        });
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to update preference: $e',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    // Reload profile from backend to ensure state is up to date
                    await _loadProfile();
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCaregiverSettingsDialog() async {
    final pageContext = context;
    final currentSettings = _caregiverSettings;
    bool wantsCaregiverLink = currentSettings["wantsCaregiverLink"] == true;
    bool consentConfirmed = currentSettings["consentConfirmed"] == true;
    bool caregiverLinked = currentSettings["caregiverLinked"] == true;
    String linkStatus = _caregiverLinkStatus;
    String? caregiverId = currentSettings["caregiverId"]?.toString();
    String linkingCodeValue = "";
    bool isSaving = false;
    final initialWantsCaregiverLink = wantsCaregiverLink;
    final initialConsentConfirmed = consentConfirmed;
    final initialCaregiverLinked = caregiverLinked;
    final initialCaregiverId = caregiverId;
    final initialLinkStatus = linkStatus;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final statusText = caregiverLinked
                ? 'A caregiver is linked. Sensitive medical changes are protected.'
                : wantsCaregiverLink
                    ? 'Caregiver linking is requested. The pairing flow should complete with a code.'
                    : 'No caregiver is linked. The adolescent confirms sensitive actions directly.';
            final caregiverIdText = caregiverId?.trim() ?? "";

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Caregiver Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2FBF7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD8EEE6)),
                      ),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          color: Color(0xFF546E7A),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00C874),
                      title: const Text('Want to link a caregiver'),
                      subtitle: const Text(
                        'Stores whether the adolescent wants caregiver pairing.',
                      ),
                      value: wantsCaregiverLink,
                      onChanged: caregiverLinked
                          ? null
                          : (value) {
                              setDialogState(() {
                                wantsCaregiverLink = value;
                                if (value) {
                                  linkStatus = 'pending';
                                  consentConfirmed = false;
                                } else {
                                  linkStatus = 'none';
                                }
                              });
                            },
                    ),
                    if (!caregiverLinked)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: consentConfirmed,
                        onChanged: wantsCaregiverLink
                            ? null
                            : (value) {
                                setDialogState(() {
                                  consentConfirmed = value ?? false;
                                });
                              },
                        title: const Text('Consent confirmed without caregiver'),
                        subtitle: const Text(
                          'Required when no caregiver is linked.',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Link status: ${linkStatus.toUpperCase()}',
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (wantsCaregiverLink && !caregiverLinked) ...[
                      const SizedBox(height: 14),
                      TextField(
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (value) {
                          linkingCodeValue = value;
                        },
                        decoration: InputDecoration(
                          labelText: 'Enter caregiver linking code',
                          hintText: 'Example: AB12CD',
                          filled: true,
                          fillColor: const Color(0xFFF8FBFA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE9E4),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE9E4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'If your caregiver already generated a code, enter it here to complete the link.',
                        style: TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (caregiverIdText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Linked caregiver ID: $caregiverIdText',
                        style: const TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (caregiverLinked) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'If you want to revoke caregiver linkage, please ask your caregiver to remove it.',
                        style: TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final linkingCode =
                              linkingCodeValue.trim().toUpperCase();
                          final noSettingsChanged =
                              wantsCaregiverLink ==
                                  initialWantsCaregiverLink &&
                              consentConfirmed == initialConsentConfirmed &&
                              caregiverLinked == initialCaregiverLinked &&
                              caregiverId == initialCaregiverId &&
                              linkStatus == initialLinkStatus;
                          if (noSettingsChanged && linkingCode.isEmpty) {
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(
                                content: Text('No caregiver settings changes to save.'),
                              ),
                            );
                            return;
                          }

                          if (!wantsCaregiverLink &&
                              !caregiverLinked &&
                              !consentConfirmed) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Confirm consent if no caregiver is linked.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            if (
                              wantsCaregiverLink &&
                              !caregiverLinked &&
                              linkingCode.isNotEmpty
                            ) {
                              final linkResponse =
                                  await ApiService.linkCaregiverWithCode(
                                linkingCode: linkingCode,
                              );
                              if (!mounted) return;
                              if (linkResponse["success"] == true) {
                                Navigator.of(dialogContext).pop();
                                await _loadProfile();
                                if (!mounted) return;
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('Caregiver linked successfully.'),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      linkResponse["error"]?.toString() ??
                                          'Unable to link caregiver.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            final response = await ApiService.updateProfile({
                              "caregiverSettings": {
                                "wantsCaregiverLink": wantsCaregiverLink,
                                "caregiverLinked": caregiverLinked,
                                "caregiverId": caregiverLinked ? caregiverId : null,
                                "consentConfirmed":
                                    caregiverLinked ? true : consentConfirmed,
                                "linkStatus": caregiverLinked
                                    ? "linked"
                                    : (wantsCaregiverLink ? "pending" : "none"),
                              },
                            });
                            if (!mounted) return;
                            if (response["success"] == true) {
                              Navigator.of(dialogContext).pop();
                              await _loadProfile();
                              if (!mounted) return;
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Caregiver settings updated.'),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    response["error"]?.toString() ??
                                        'Unable to update caregiver settings.',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C874),
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCaregiverLinkManagementDialog() async {
    final pageContext = context;
    bool isRemoving = false;
    final linkedChildAccount =
        _caregiverDashboardState["linkedChildAccount"] == true;
    final linkedChildUserId =
        _caregiverDashboardState["linkedChildUserId"]?.toString();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Linked Child Access'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linkedChildAccount
                        ? 'You can view and manage the linked adolescent profile from this caregiver account.'
                        : 'No adolescent account is currently linked to this caregiver.',
                    style: const TextStyle(
                      color: Color(0xFF546E7A),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (linkedChildAccount && linkedChildUserId != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Linked child ID: $linkedChildUserId',
                      style: const TextStyle(
                        color: Color(0xFF78909C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isRemoving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                if (linkedChildAccount)
                  ElevatedButton(
                    onPressed: isRemoving
                        ? null
                        : () async {
                            setDialogState(() => isRemoving = true);
                            try {
                              final response =
                                  await ApiService.unlinkCaregiverChild(
                                linkedChildUserId: linkedChildUserId,
                              );
                              if (!mounted) return;
                              if (response["success"] == true) {
                                Navigator.of(dialogContext).pop();
                                await _loadProfile();
                                if (!mounted) return;
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Linked child removed from caregiver access.',
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      response["error"]?.toString() ??
                                          'Unable to remove linked child.',
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (dialogContext.mounted) {
                                setDialogState(() => isRemoving = false);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white,
                    ),
                    child: isRemoving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Remove Child'),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
