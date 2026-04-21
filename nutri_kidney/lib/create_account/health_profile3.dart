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
  String? _processedFoodIntake;
  String? _mealPattern;
  String? _fluidRestrictionStatus;
  String? _hasHypertension;

  // Controllers for numeric and text fields
  final TextEditingController _fluidLimitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fluidLimitController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _fluidLimitController.dispose();
    super.dispose();
  }

  // --- Validation Logic ---
  bool get _isFormValid {
    return _dietPattern != null &&
        _activityLevel != null &&
        _measurementSystem != null &&
        _processedFoodIntake != null &&
        _mealPattern != null &&
        _fluidRestrictionStatus != null &&
        _hasHypertension != null &&
        (_fluidRestrictionStatus != "yes" ||
            _fluidLimitController.text.trim().isNotEmpty);
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

                    // Usual Diet Pattern (expanded with 13 options)
                    _buildDropdownField(
                      label: "Usual Diet Pattern",
                      hint: "Select Pattern",
                      value: _dietPattern,
                      items: [
                        "Regular diet",
                        "Renal diet",
                        "High protein",
                        "Low protein",
                        "Low salt / Low fat",
                        "Low fat",
                        "Low salt",
                        "Low potassium",
                        "Low phosphorus",
                        "Low purine",
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

                    _buildDropdownField(
                      label: "Fluid Restriction Status",
                      hint: "Select Status",
                      value: _fluidRestrictionStatus,
                      items: const ["yes", "no", "not sure"],
                      onChanged: (val) {
                        setState(() {
                          _fluidRestrictionStatus = val;
                          if (val != "yes") {
                            _fluidLimitController.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildHypertensionDropdown(),
                    const SizedBox(height: 16),

                    // Daily Fluid Limit (numeric input in mL)
                    _buildTextField(
                      label: "Daily Fluid Limit (mL)",
                      hint: "e.g., 800 or 1200",
                      controller: _fluidLimitController,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Processed Food Intake (NEW)
                    _buildDropdownField(
                      label: "Processed Food Intake",
                      hint: "Select Frequency",
                      value: _processedFoodIntake,
                      items: ["Often", "Sometimes", "Rarely"],
                      onChanged: (val) {
                        setState(() {
                          _processedFoodIntake = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Meal Pattern (NEW)
                    _buildDropdownField(
                      label: "Meal Pattern",
                      hint: "Select Pattern",
                      value: _mealPattern,
                      items: ["Regular (3 meals)", "3 meals + snacks", "Irregular"],
                      onChanged: (val) {
                        setState(() {
                          _mealPattern = val;
                        });
                      },
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
                                      "fluidRestrictionStatus": _fluidRestrictionStatus,
                                      "fluid_restriction_status": _fluidRestrictionStatus,
                                      "fluidLimitMl": _fluidLimitController.text.isNotEmpty ? int.parse(_fluidLimitController.text) : null,
                                      "fluid_limit_ml": _fluidLimitController.text.isNotEmpty ? int.parse(_fluidLimitController.text) : null,
                                      "processedFoodIntake": _processedFoodIntake,
                                      "hasHypertension": _hasHypertension,
                                      "has_hypertension": _hasHypertension,
                                      "mealPattern": _mealPattern,
                                      "physicalActivityLevel": _activityLevel,
                                      "physical_activity_level": _activityLevel,
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

  Widget _buildHypertensionDropdown() {
    const optionLabels = {
      "yes": "Yes",
      "no": "No",
      "not_sure": "Not sure",
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel("Does the child have high blood pressure (hypertension)?"),
        const Text(
          "Select the option based on the child's current medical condition or recent clinical advice. This helps the system assess whether sodium-related dietary guidance may be needed.",
          style: TextStyle(
            color: Color(0xFF78909C),
            fontSize: 11,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
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
              value: _hasHypertension,
              hint: Text(
                "Select option",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey.shade400,
              ),
              style: const TextStyle(color: Color(0xFF37474F), fontSize: 13),
              onChanged: (val) {
                setState(() {
                  _hasHypertension = val;
                });
              },
              items: optionLabels.entries.map<DropdownMenuItem<String>>((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
