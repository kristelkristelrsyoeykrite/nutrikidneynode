import 'package:flutter/material.dart';
import 'package:nutri_kidney/create_account/profile_setup_intro.dart';
import 'package:nutri_kidney/main/dashboard.dart';
import 'package:nutri_kidney/services/api_service.dart';

class CaregiverChildAgeScreen extends StatefulWidget {
  final String userName;

  const CaregiverChildAgeScreen({
    super.key,
    required this.userName,
  });

  @override
  State<CaregiverChildAgeScreen> createState() => _CaregiverChildAgeScreenState();
}

class _CaregiverChildAgeScreenState extends State<CaregiverChildAgeScreen> {
  bool _isSaving = false;

  Future<void> _selectAgeGroup(String childAgeGroup) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final response = await ApiService.saveCaregiverChildAgeGroup(
        childAgeGroup: childAgeGroup,
      );

      if (!mounted) return;

      if (response["success"] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ??
                  "Unable to save your caregiver setup right now.",
            ),
          ),
        );
        return;
      }

      final nextPage = childAgeGroup == "5-13"
          ? const ProfileSetupIntroScreen()
          : const DashboardPage();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => nextPage),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Something went wrong: $error"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildAgeOption({
    required String title,
    required String childAgeGroup,
    required String description,
  }) {
    return InkWell(
      onTap: _isSaving ? null : () => _selectAgeGroup(childAgeGroup),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9ECE5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F7F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.family_restroom,
                color: Color(0xFF009B72),
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
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF37474F),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF78909C),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.arrow_forward_ios,
              size: 18,
              color: Color(0xFF90A4AE),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF7),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              bottom: -360,
              left: -110,
              right: -90,
              child: Image.asset(
                'assets/images/bottom_waves.png',
                fit: BoxFit.fitWidth,
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'One more step',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF90A4AE),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'How old is your child, ${widget.userName}?',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'We use this to decide whether you should create the health profile directly or link to your child’s own account.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF78909C),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildAgeOption(
                    title: '5-13 years old',
                    childAgeGroup: '5-13',
                    description:
                        'Continue the normal setup so you can create and manage your child’s health profile directly.',
                  ),
                  const SizedBox(height: 16),
                  _buildAgeOption(
                    title: '13-18 years old',
                    childAgeGroup: '13-18',
                    description:
                        'Skip profile creation for now and generate a linking code so your adolescent can connect their own account.',
                  ),
                  const SizedBox(height: 28),
                  if (_isSaving)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00C874),
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
