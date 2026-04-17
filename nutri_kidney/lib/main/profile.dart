import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // For the iOS style switches
import 'dashboard.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'health_metrics.dart';
import '../login/login.dart';
import '../../services/auth_service.dart';

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
            child: const Center(
              child: Text(
                'SM',
                style: TextStyle(
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
                const Text(
                  'Sarah Mitchell',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '8 years old',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'PatientID:NK-2024-1847',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
