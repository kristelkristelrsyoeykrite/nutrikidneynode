import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'health_profile4.dart'; // IMPORT ADDED HERE FOR STEP 4

class HealthProfile3Page extends StatefulWidget {
  const HealthProfile3Page({super.key});

  @override
  State<HealthProfile3Page> createState() => _HealthProfile3PageState();
}

class _HealthProfile3PageState extends State<HealthProfile3Page> {
  // State variables for dropdowns
  String? _dietPattern;
  String? _activityLevel;
  String? _measurementSystem;

  // Controller for the text field
  final TextEditingController _fluidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fluidController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _fluidController.dispose();
    super.dispose();
  }

  // --- Validation Logic ---
  // Fluid restriction says "if any", so we will make it optional.
  // The dropdowns, however, should be filled to continue.
  bool get _isFormValid {
    return _dietPattern != null &&
        _activityLevel != null &&
        _measurementSystem != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // --- Background Graphics ---
            Positioned(
              bottom: -360,
              left: -110,
              right: -90,
              child: Image.asset(
                'assets/images/bottom_waves.png',
                fit: BoxFit.fitWidth,
              ),
            ),

            // --- Foreground Content ---
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // Header
                    const Center(
                      child: Text(
                        'NutriKidney',
                        style: TextStyle(
                          fontFamily: 'FredokaOne',
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF37474F),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Health Profile Setup',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF90A4AE),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Progress Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Step 3 of 4',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF90A4AE),
                          ),
                        ),
                        Text(
                          '75% Complete',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF4DB6AC),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: 0.75, // 75% complete
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFF37474F),
                      minHeight: 4,
                    ),
                    const SizedBox(height: 16),

                    // Sub-header for this specific page
                    const Center(
                      child: Text(
                        'Dietary & Lifestyle Information',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78909C),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Help us understand eating habits and activity levels',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB0BEC5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Form Fields ---

                    // Usual Diet Pattern
                    _buildDropdownField(
                      label: "Usual Diet Pattern",
                      hint: "Select Pattern",
                      value: _dietPattern,
                      items: [
                        "Standard/No Restrictions",
                        "Low Sodium",
                        "Renal Diet",
                        "Vegetarian",
                        "Vegan",
                        "Other",
                      ],
                      onChanged: (val) {
                        setState(() {
                          _dietPattern = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Fluid Restriction
                    _buildTextField(
                      label: "Fluid Restriction (if any)",
                      hint: "e.g., 1.5L/day or None",
                      controller: _fluidController,
                    ),
                    const SizedBox(height: 16),

                    // Physical Activity Level
                    _buildDropdownField(
                      label: "Physical Activity Level",
                      hint: "Select Activity Level",
                      value: _activityLevel,
                      items: [
                        "Low (Mostly sedentary)",
                        "Moderate (Light active)",
                        "High (Very active)",
                      ],
                      onChanged: (val) {
                        setState(() {
                          _activityLevel = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Preferred Measurement System
                    _buildDropdownField(
                      label: "Preferred Measurement System",
                      hint: "Select System",
                      value: _measurementSystem,
                      items: ["Grams", "Ounces/Cups", "Mixed"],
                      onChanged: (val) {
                        setState(() {
                          _measurementSystem = val;
                        });
                      },
                    ),
                    const SizedBox(height: 40),

                    // --- Side-by-Side Buttons ---
                    Row(
                      children: [
                        // Back Button
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: TextButton(
                              onPressed: () {
                                Navigator.pop(context); // Go back to Step 2
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFFE8EDEA),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Back',
                                style: TextStyle(
                                  color: Color(0xFF37474F),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Continue Button
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                             onPressed: _isFormValid
                                ? () async {
                                    await ApiService.sendStep3({
                                      "dietPattern": _dietPattern,
                                      "fluidRestriction": _fluidController.text,
                                      "physicalActivityLevel": _activityLevel,
                                      "preferredMeasurement": _measurementSystem,
                                    });

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const HealthProfile4Page(),
                                      ),
                                    );
                                  }
                                : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4DB6AC),
                                disabledBackgroundColor: Colors.grey.shade400,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI Helper Methods ---
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9E86FF),
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        Container(
          height: 45,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Color(0xFF37474F), fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              hint: Text(
                hint,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey.shade400,
              ),
              style: const TextStyle(color: Color(0xFF37474F), fontSize: 13),
              onChanged: onChanged,
              items: items.map<DropdownMenuItem<String>>((String item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
