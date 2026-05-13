import 'package:flutter/material.dart';
import 'package:nutri_kidney/login/login.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:nutri_kidney/services/auth_service.dart';
import 'package:nutri_kidney/utils/app_logger.dart';
import 'health_profile1.dart';
import '../main/dashboard.dart';

/// Privacy consent screen for profile setup
/// Blocking step - user must accept before proceeding
/// NOTE: This has different content than the signup registration privacy dialog
class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({
    super.key,
    this.continueToHealthProfile = false,
    this.goToDashboardAfterAccept = false,
    this.isChildProfileSetup = false,
  });

  final bool continueToHealthProfile;
  final bool goToDashboardAfterAccept;
  final bool isChildProfileSetup;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _hasAcceptedConsent = false;

  Future<void> _handleAccept() async {
    if (!_hasAcceptedConsent) {
      AppLogger.warning(
        'User clicked accept without checking consent box',
        tag: LogTag.onboarding,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the privacy consent to continue'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    AppLogger.info(
      'User accepted privacy consent for profile setup',
      tag: LogTag.onboarding,
    );

    await ApiService.updatePrivacyConsent(accepted: true);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => widget.goToDashboardAfterAccept
            ? const DashboardPage()
            : HealthProfile1Page(
                isChildProfileSetup: widget.isChildProfileSetup,
              ),
      ),
    );
  }

  Future<void> _leaveSetup() async {
    AppLogger.warning(
      'User left profile setup consent before completing setup',
      tag: LogTag.onboarding,
    );
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.info(
      'Privacy consent screen shown',
      tag: LogTag.onboarding,
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _leaveSetup();
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            _leaveSetup();
          },
          child: const Icon(
            Icons.arrow_back,
            color: Color(0xFF37474F),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text(
              'Data Privacy & Consent',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF37474F),
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            const Text(
              'What health information we collect and how we use it',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF90A4AE),
              ),
            ),
            const SizedBox(height: 24),

            // Content Cards
            _buildContentSection(
              icon: Icons.info_outline,
              title: 'Information We Collect',
              items: [
                'Basic health metrics (age, height, weight, gender)',
                'CKD stage and kidney disease type',
                'Current medications and prescriptions',
                'Dietary preferences and food allergies',
                'Lifestyle information (activity level, hydration habits)',
                'Lab results and medical test data (optional)',
              ],
            ),
            const SizedBox(height: 24),

            _buildContentSection(
              icon: Icons.analytics,
              title: 'How We Use Your Data',
              items: [
                'Provide personalized nutrition and health recommendations',
                'Track your kidney health progress over time',
                'Alert you and your caregivers about important health insights',
                'Generate reports for your healthcare providers',
                'Improve our app\'s features and recommendations (anonymized)',
              ],
            ),
            const SizedBox(height: 24),

            _buildContentSection(
              icon: Icons.shield_outlined,
              title: 'Your Privacy Rights',
              items: [
                'Your data is encrypted and stored securely',
                'You can update or delete your information anytime',
                'We never sell or share your data without permission',
                'You can access all information we have about you',
                'Compliant with Data Privacy Act of 2012',
              ],
            ),
            const SizedBox(height: 32),

            // Consent Checkbox
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3FAF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasAcceptedConsent
                      ? const Color(0xFF4DB6AC)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _hasAcceptedConsent,
                    activeColor: const Color(0xFF4DB6AC),
                    onChanged: (bool? value) {
                      setState(() {
                        _hasAcceptedConsent = value ?? false;
                      });
                      AppLogger.debug(
                        'Privacy consent checkbox toggled: $_hasAcceptedConsent',
                        tag: LogTag.onboarding,
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'I understand and accept',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF37474F),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'I consent to NutriKidney collecting and processing my health information according to the privacy terms above. I also consent to health data monitoring and clinical oversight.',
                          style: TextStyle(
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
            ),
            const SizedBox(height: 32),

            // Buttons
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _handleAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasAcceptedConsent
                      ? const Color(0xFF4DB6AC)
                      : const Color(0xFFE0E0E0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Accept and Continue',
                  style: TextStyle(
                    color: _hasAcceptedConsent ? Colors.white : const Color(0xFF90A4AE),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Decline Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: _leaveSetup,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Decline',
                  style: TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildContentSection({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF4DB6AC), size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF37474F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 32, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '• ',
                style: TextStyle(
                  color: Color(0xFF4DB6AC),
                  fontSize: 16,
                ),
              ),
              Expanded(
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF90A4AE),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}
