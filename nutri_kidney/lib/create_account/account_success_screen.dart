import 'package:flutter/material.dart';
import 'package:nutri_kidney/utils/app_logger.dart';
import '../main/dashboard.dart';
import 'profile_setup_intro.dart';
import 'privacy_consent_screen.dart';

/// Screen shown after successful account creation and verification
class AccountSuccessScreen extends StatefulWidget {
  final String userName;
  final String? userRole;
  final bool privacyConsentAccepted;

  const AccountSuccessScreen({
    super.key,
    required this.userName,
    this.userRole,
    this.privacyConsentAccepted = false,
  });

  @override
  State<AccountSuccessScreen> createState() => _AccountSuccessScreenState();
}

class _AccountSuccessScreenState extends State<AccountSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    AppLogger.info(
      'Account success screen shown for user: ${widget.userName}',
      tag: LogTag.onboarding,
    );

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _animationController.forward();

    // Auto-navigate after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        final role = widget.userRole?.trim().toLowerCase();
        final isCaregiver =
            role == 'caregiver' || role == 'parent_caregiver';
        AppLogger.info('Auto-navigating after account success', tag: LogTag.onboarding);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) {
              if (widget.privacyConsentAccepted) {
                return isCaregiver
                    ? const DashboardPage()
                    : const ProfileSetupIntroScreen();
              }
              return PrivacyConsentScreen(
                goToDashboardAfterAccept: isCaregiver,
              );
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success Icon with Animation
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.elasticOut,
                      ),
                    ),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ECA7F),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'Creating your account…',
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF90A4AE),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Success Message
                  Text(
                    'Successfully created your account',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Hello ${widget.userName}! Let\'s continue.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF90A4AE),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Loading indicator
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF4DB6AC),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
