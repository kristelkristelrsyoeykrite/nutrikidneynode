import 'package:flutter/material.dart';

class TermsOfServicePage extends StatefulWidget {
  const TermsOfServicePage({super.key});

  @override
  State<TermsOfServicePage> createState() => _TermsOfServicePageState();
}

class _TermsOfServicePageState extends State<TermsOfServicePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00C874),
        title: const Text(
          'Terms of Service',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'NutriKidney Terms of Service',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF37474F),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Last Updated: May 2026',
              style: TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
            ),
            const SizedBox(height: 24),

            // Section 1: Data Usage
            _buildSection(
              title: '1. How We Use Your Data',
              content: '''
NutriKidney collects and uses your information to:

• Track your daily meal intake and nutrition
• Calculate CKD (Chronic Kidney Disease) nutritional targets
• Monitor your health metrics (weight, height, BMI)
• Send reminders for meal logging and medication
• Display your achievements and progress
• Help caregivers/parents monitor your health

Your data is used ONLY to improve your health experience. We do NOT sell your data to third parties.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 2: Data Storage & Security
            _buildSection(
              title: '2. How Your Data is Stored',
              content: '''
Your personal health information is stored in:

• Firebase Cloud Database (encrypted)
• Your data is protected with security measures
• Only you and your linked caregiver/parent can access your data
• Data is stored securely and backed up regularly

IMPORTANT: For testing purposes, some data may be temporarily stored unencrypted. Before production use, all data will be encrypted.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 3: User Responsibilities
            _buildSection(
              title: '3. Your Responsibilities',
              content: '''
As a user, you must:

• Keep your password confidential and secure
• Not share your account with others
• Provide accurate information about your health
• Use the app responsibly and follow medical advice
• Not attempt to hack or damage the app
• Report any suspicious activity immediately

If you violate these rules, we may disable your account.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 4: Health Disclaimer
            _buildSection(
              title: '4. Health Disclaimer',
              content: '''
IMPORTANT MEDICAL INFORMATION:

⚠️ NutriKidney is NOT a medical device or treatment.
⚠️ This app provides INFORMATION ONLY, not medical advice.
⚠️ Always consult with your doctor or healthcare provider.
⚠️ Do NOT use this app to replace professional medical care.
⚠️ Nutrition recommendations are based on CKD guidelines but may not be suitable for every individual.

By using this app, you acknowledge that you understand these limitations.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 5: Limitation of Liability
            _buildSection(
              title: '5. Limitation of Liability',
              content: '''
NutriKidney is provided "as is" without warranties.

We are NOT responsible for:

• Inaccurate nutrition calculations
• Technical errors or app crashes
• Data loss or deletion
• Misuse of the app
• Health consequences from following app recommendations
• Third-party services (Firebase, FatSecret API)

Use the app at your own risk.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 6: Account Termination
            _buildSection(
              title: '6. Account Termination',
              content: '''
We may terminate or suspend your account if:

• You violate these Terms of Service
• You provide false health information
• You attempt to hack or damage the app
• You use the app for illegal purposes
• You harass other users or caregivers

Upon termination, your data will be deleted after 30 days.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 7: Changes to Terms
            _buildSection(
              title: '7. Changes to These Terms',
              content: '''
We may update these Terms of Service at any time.

We will notify you of changes by:
• Updating the "Last Updated" date
• Sending you an email notification
• Displaying a notice in the app

By continuing to use NutriKidney, you accept the updated terms.
              ''',
            ),
            const SizedBox(height: 20),

            // Section 8: Contact
            _buildSection(
              title: '8. Contact Us',
              content: '''
If you have questions about these Terms of Service:

Email: nutrikidney9@gmail.com

We will respond to your inquiry within 7 business days.
              ''',
            ),
            const SizedBox(height: 40),

            // Agreement Button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00C874)),
              ),
              child: const Text(
                'By using NutriKidney, you agree to these Terms of Service.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00897B),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Helper function to build each section
  Widget _buildSection({required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF37474F),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Color(0xFF546E7A),
          ),
        ),
      ],
    );
  }
}
