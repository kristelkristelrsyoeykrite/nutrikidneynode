import 'package:flutter/material.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String selectedCategory = 'Getting Started';
  final Map<String, List<Map<String, String>>> helpContent = {
    'Getting Started': [
      {
        'question': 'How do I create an account?',
        'answer': '''
1. Download NutriKidney app
2. Tap "Sign Up"
3. Enter your email address
4. Create a strong password
5. Verify your email
6. Complete your health profile

Your account is now ready to use!
        ''',
      },
      {
        'question': 'What is a caregiver/parent account?',
        'answer': '''
There are two types of accounts:

PARENT ACCOUNT (for ages 5-13):
- Parents have full control over child profile
- Parents log meals and track health
- Children cannot edit their own data

CAREGIVER ACCOUNT (for ages 13-18):
- Linked to adolescent account via code
- Can view health data and suggest changes
- Adolescent maintains control of their data
        ''',
      },
      {
        'question': 'How do I link my caregiver?',
        'answer': '''
If you are an ADOLESCENT (13-18):

1. Go to Profile → Caregiver Access
2. Ask your caregiver for their linking code
3. Enter the code
4. Tap "Link"

Your caregiver is now linked! They can view your health data.

To UNLINK later, go to Profile → Caregiver Access → Revoke
        ''',
      },
    ],
    'Food Logging': [
      {
        'question': 'How do I log a meal?',
        'answer': '''
Two ways to log meals:

METHOD 1: Manual Entry
1. Tap "Food Log"
2. Tap "Add Manual Meal"
3. Enter meal name (e.g., "Chicken & Rice")
4. Enter calories and nutrients
5. Tap "Save"

METHOD 2: Image Recognition
1. Tap "Food Log"
2. Tap camera icon
3. Take photo of your meal
4. Wait for AI to identify food
5. Select correct meal from suggestions
6. Adjust serving size if needed
7. Tap "Save"

Your meal is now logged and counts toward your daily nutrition!
        ''',
      },
      {
        'question': 'What is phosphorus?',
        'answer': '''
Phosphorus is a mineral important for people with CKD (Chronic Kidney Disease).

IMPORTANT: If you have CKD, you may need to limit phosphorus intake.

NutriKidney calculates phosphorus based on:
- Protein content of food
- A special formula for accuracy

Your daily phosphorus target depends on your CKD stage:
- Stage 1: No limit
- Stage 2: 800-1000 mg
- Stage 3: 700-900 mg
- Stage 4: 600-800 mg
- Stage 5: 500-700 mg

Ask your doctor about your specific limit!
        ''',
      },
      {
        'question': 'Why is potassium important?',
        'answer': '''
Potassium is a mineral that affects heart health.

For people with CKD:
- Kidneys may not filter potassium properly
- Too much potassium can be dangerous
- You may need to limit potassium intake

Daily potassium targets by CKD stage:
- Stage 1-2: 2000-2500 mg
- Stage 3: 1500-2000 mg
- Stage 4-5: Under 1500 mg

Foods HIGH in potassium:
- Bananas, oranges, tomatoes
- Potatoes, spinach
- Beans, nuts

Ask your doctor about your specific limit!
        ''',
      },
    ],
    'Health Metrics': [
      {
        'question': 'How do I track my weight and height?',
        'answer': '''
1. Go to "Health Metrics" tab
2. Tap "Add Measurements"
3. Enter your current weight (kg)
4. Enter your current height (cm)
5. Tap "Save"

Your BMI will be calculated automatically!

Track weekly for best results.
        ''',
      },
      {
        'question': 'What is BMI?',
        'answer': '''
BMI = Body Mass Index

It measures body fat based on:
- Your weight (kg)
- Your height (m²)

Formula: BMI = Weight ÷ (Height × Height)

Example: If you weigh 35 kg and are 140 cm tall:
BMI = 35 ÷ (1.4 × 1.4) = 17.9

BMI Categories:
- Under 18.5: Underweight
- 18.5-24.9: Normal weight
- 25-29.9: Overweight
- 30+: Obese

NOTE: BMI is just ONE indicator of health. Ask your doctor about your healthy weight!
        ''',
      },
      {
        'question': 'How do I upload my prescription?',
        'answer': '''
1. Go to "Health Metrics"
2. Look for "Medications" section
3. Tap "Upload Prescription"
4. Take a clear photo of your prescription
5. Wait for AI to read the prescription
6. Review extracted medicines
7. Tap "Confirm"

The app will:
- Extract medicine names
- Extract dosages
- Set up medication reminders

Make sure the prescription is clear and readable!
        ''',
      },
    ],
    'Notifications & Reminders': [
      {
        'question': 'How do I set up reminders?',
        'answer': '''
1. Go to Profile → Notifications
2. Enable the reminders you want:
   - Breakfast reminder (8:00 AM)
   - Lunch reminder (12:00 PM)
   - Snack reminder (3:30 PM)
   - Dinner reminder (6:30 PM)
   - Medication reminders
   - Hydration reminders
3. Tap "Save"

You will now receive notifications at scheduled times!

NOTE: If you have a linked caregiver, they control your reminders.
        ''',
      },
      {
        'question': 'Why am I not getting notifications?',
        'answer': '''
Check these things:

1. Enable notifications in app settings
2. Check phone notification settings:
   - Settings → Apps → NutriKidney → Notifications
   - Toggle "Allow notifications" ON

3. Check if reminders are enabled:
   - Profile → Notifications → Check each reminder

4. Check "Do Not Disturb" mode is OFF

5. Make sure app is not blocked

If still no notifications:
- Try restarting the app
- Restart your phone
- Contact support
        ''',
      },
    ],
    'Gamification': [
      {
        'question': 'What is a streak?',
        'answer': '''
A STREAK = Logging meals for consecutive days!

How streaks work:
- Log at least 1 meal per day = +1 streak
- Skip a day = Streak resets to 0
- Your longest streak is saved as "Best"

Rewards for streaks:
- 7 days: 7 points
- 14 days: 14 points
- 30 days: 30 points

Keep logging to build your streak! 🔥
        ''',
      },
      {
        'question': 'What are achievements?',
        'answer': '''
ACHIEVEMENTS = Badges you unlock by completing goals!

Examples:
- "7 Day Streak": Log meals for 7 days
- "Rainbow Eater": Eat 5 different colored foods
- "Hydration Hero": Log water 10 times
- "Balanced Week": Stay within nutrition targets for 7 days

Unlock achievements to earn points!
Compete on the leaderboard!
        ''',
      },
      {
        'question': 'How does the leaderboard work?',
        'answer': '''
The LEADERBOARD ranks all users by points!

How to earn points:
- Log meals: +1 point
- Complete challenges: +5-10 points
- Unlock achievements: +10-50 points
- Maintain streaks: +bonus points

View your rank:
1. Go to "Analytics" tab
2. Scroll to "Leaderboard"
3. See your position vs other users

Compete with friends and stay motivated! 🏆
        ''',
      },
    ],
    'Troubleshooting': [
      {
        'question': 'The app keeps crashing. What do I do?',
        'answer': '''
Try these steps:

1. Close the app completely
   - Swipe up and close app

2. Clear cache:
   - Settings → Apps → NutriKidney
   - Tap "Storage" → "Clear Cache"

3. Restart your phone

4. Update the app:
   - Open Play Store
   - Search NutriKidney
   - Tap "Update"

5. If still crashing:
   - Uninstall the app
   - Restart phone
   - Reinstall from Play Store

If problem persists, contact support!
        ''',
      },
      {
        'question': 'My data disappeared. Can I recover it?',
        'answer': '''
Your data is backed up in the cloud!

To recover your data:

1. Log in with your email and password
2. Wait for data to sync (5-10 seconds)

If data still missing:

1. Check your internet connection
2. Try logging out and back in
3. Restart the app
4. Restart your phone

Your data should reappear!

Contact support if you need help:
nutrikidney9@gmail.com
        ''',
      },
      {
        'question': 'I forgot my password. How do I reset it?',
        'answer': '''
1. Go to Login page
2. Tap "Forgot Password?"
3. Enter your email address
4. Tap "Send Reset Link"
5. Check your email
6. Click the reset link
7. Enter your new password
8. Tap "Reset Password"

You can now login with your new password!

Did not receive email?
- Check spam folder
- Wait 5 minutes and try again
- Contact support
        ''',
      },
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00C874),
        title: const Text(
          'Help Center',
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
      body: Column(
        children: [
          // Category Selection Dropdown
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedCategory,
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00C874)),
              items: helpContent.keys.map((String category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    selectedCategory = newValue;
                  });
                }
              },
            ),
          ),
          const Divider(height: 1),

          // FAQ List
          Expanded(
            child: ListView.builder(
              itemCount: helpContent[selectedCategory]?.length ?? 0,
              itemBuilder: (context, index) {
                final faq = helpContent[selectedCategory]![index];
                return _buildFAQItem(
                  question: faq['question']!,
                  answer: faq['answer']!,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper function to build each FAQ item
  Widget _buildFAQItem({required String question, required String answer}) {
    return ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            answer,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF546E7A),
            ),
          ),
        ),
      ],
    );
  }
}
