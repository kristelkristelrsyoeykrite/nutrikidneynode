import 'package:flutter/material.dart';
import 'package:nutri_kidney/utils/app_logger.dart';
import 'privacy_consent_screen.dart';

/// Introduction screen for profile setup
/// Explains what data privacy means and gets user ready for profile setup
class ProfileSetupIntroScreen extends StatelessWidget {
  const ProfileSetupIntroScreen({super.key});

  void _navigateToPrivacyConsent(BuildContext context) {
    AppLogger.info(
      'User proceeding to privacy consent from intro screen',
      tag: LogTag.onboarding,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const PrivacyConsentScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.info(
      'Profile setup intro screen shown',
      tag: LogTag.onboarding,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF7),
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Background Graphics
            Positioned(
              bottom: -360,
              left: -110,
              right: -90,
              child: Image.asset(
                'assets/images/bottom_waves.png',
                fit: BoxFit.fitWidth,
              ),
            ),

            // Content
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // Icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DB6AC).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF4DB6AC),
                        size: 60,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Title
                    const Text(
                      'Let\'s Set Up Your Profile',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF37474F),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Subtitle
                    const Text(
                      'We\'ll ask you about your health information to provide personalized nutrition insights for your kidney health.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF90A4AE),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // Info Cards
                    _buildInfoCard(
                      icon: Icons.security,
                      title: 'Your Data is Secure',
                      description:
                          'We use industry-standard encryption to protect your personal and health information.',
                    ),
                    const SizedBox(height: 16),

                    _buildInfoCard(
                      icon: Icons.verified_user,
                      title: 'Privacy First',
                      description:
                          'Your data is never shared without your explicit consent, and only used for your health monitoring.',
                    ),
                    const SizedBox(height: 16),

                    _buildInfoCard(
                      icon: Icons.timeline,
                      title: 'Personalized Care',
                      description:
                          'Your information helps us deliver more accurate insights and recommendations for your kidney health.',
                    ),
                    const SizedBox(height: 48),

                    // Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _navigateToPrivacyConsent(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4DB6AC),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Let\'s Get Started',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4DB6AC).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF4DB6AC),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF37474F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF90A4AE),
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
