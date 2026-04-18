import 'package:flutter/material.dart';
import 'package:nutri_kidney/utils/app_logger.dart';
import 'setup_complete_screen.dart';

/// Final review screen before profile setup completion
/// Displays all collected health profile information for user confirmation
class FinalReviewScreen extends StatefulWidget {
  final Map<String, dynamic> profileData;
  final VoidCallback onConfirm;

  const FinalReviewScreen({
    super.key,
    required this.profileData,
    required this.onConfirm,
  });

  @override
  State<FinalReviewScreen> createState() => _FinalReviewScreenState();
}

class _FinalReviewScreenState extends State<FinalReviewScreen> {
  bool _isProcessing = false;

  void _handleConfirm() async {
    AppLogger.info(
      'User confirmed profile data in final review',
      tag: LogTag.onboarding,
    );

    setState(() {
      _isProcessing = true;
    });

    try {
      // Call the onConfirm callback (typically saves to database)
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate delay
      widget.onConfirm();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const SetupCompleteScreen(),
          ),
        );
      }
    } catch (e) {
      AppLogger.error(
        'Error confirming profile data',
        tag: LogTag.onboarding,
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _handleEdit() {
    AppLogger.info(
      'User clicked edit in final review - going back',
      tag: LogTag.onboarding,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.info(
      'Final review screen shown',
      tag: LogTag.onboarding,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: _isProcessing ? null : _handleEdit,
          child: Icon(
            Icons.arrow_back,
            color: _isProcessing ? const Color(0xFFE0E0E0) : const Color(0xFF37474F),
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
              'Review Your Information',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF37474F),
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            const Text(
              'Is your information correct? Providing accurate information helps us deliver more accurate insights.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF90A4AE),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // Profile Data Sections
            _buildReviewSection(
              'Basic Information',
              [
                _buildReviewItem('Full Name', widget.profileData['fullName'] ?? 'N/A'),
                _buildReviewItem('Date of Birth', widget.profileData['dateOfBirth'] ?? 'N/A'),
                _buildReviewItem('Gender', widget.profileData['gender'] ?? 'N/A'),
              ],
            ),
            const SizedBox(height: 20),

            _buildReviewSection(
              'Physical Measurements',
              [
                _buildReviewItem('Height', widget.profileData['height'] ?? 'N/A'),
                _buildReviewItem('Weight', widget.profileData['weight'] ?? 'N/A'),
              ],
            ),
            const SizedBox(height: 20),

            _buildReviewSection(
              'Kidney Health',
              [
                _buildReviewItem('CKD Stage', widget.profileData['ckdStage'] ?? 'N/A'),
                _buildReviewItem('Disease Type', widget.profileData['kidneyDiseaseType'] ?? 'N/A'),
                _buildReviewItem('Diagnosis Date', widget.profileData['diagnosisDate'] ?? 'N/A'),
              ],
            ),
            const SizedBox(height: 20),

            _buildReviewSection(
              'Health Conditions',
              [
                _buildReviewItem('Conditions', widget.profileData['conditions'] ?? 'None'),
                _buildReviewItem('Medications', widget.profileData['medications'] ?? 'None'),
              ],
            ),
            const SizedBox(height: 20),

            _buildReviewSection(
              'Dietary Information',
              [
                _buildReviewItem('Allergies', widget.profileData['allergies'] ?? 'None'),
                _buildReviewItem('Restrictions', widget.profileData['restrictions'] ?? 'None'),
              ],
            ),
            const SizedBox(height: 20),

            _buildReviewSection(
              'User Context',
              [
                _buildReviewItem('Role', widget.profileData['userRole'] ?? 'N/A'),
              ],
            ),
            const SizedBox(height: 32),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _handleConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DB6AC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Confirm',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Edit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _handleEdit,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _isProcessing ? const Color(0xFFE0E0E0) : const Color(0xFFE0E0E0),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Edit',
                  style: TextStyle(
                    color: _isProcessing ? const Color(0xFFE0E0E0) : const Color(0xFF90A4AE),
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
    );
  }

  Widget _buildReviewSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF37474F),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3FAF7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildReviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF90A4AE),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF37474F),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
