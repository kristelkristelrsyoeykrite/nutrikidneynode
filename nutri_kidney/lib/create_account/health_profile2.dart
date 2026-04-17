import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'health_profile3.dart'; // IMPORT ADDED HERE

class HealthProfile2Page extends StatefulWidget {
  const HealthProfile2Page({super.key});

  @override
  State<HealthProfile2Page> createState() => _HealthProfile2PageState();
}

class _HealthProfile2PageState extends State<HealthProfile2Page> {
  // State variables for the selections
  String? _dialysisType;
  String? _treatmentFrequency;

  // Controllers for the large text fields
  final TextEditingController _medicationsController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _medicationsController.addListener(() {
      setState(() {});
    });
    _allergiesController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _medicationsController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  // --- Validation Logic ---
  bool get _isFormValid {
    return _dialysisType != null;
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
                          'Step 2 of 4',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF90A4AE),
                          ),
                        ),
                        Text(
                          '50% Complete',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF4DB6AC),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: 0.50, // 50% complete
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFF37474F),
                      minHeight: 4,
                    ),
                    const SizedBox(height: 16),

                    // Sub-header for this specific page
                    const Center(
                      child: Text(
                        'Treatment & Condition Details',
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
                        'Information about current treatment and medications',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB0BEC5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Form Fields ---

                    // Dialysis Radio Buttons
                    _buildLabel("Is the child on dialysis?"),
                    _buildRadioOption("None"),
                    _buildRadioOption("Peritoneal Dialysis"),
                    _buildRadioOption("Hemodialysis"),
                    const SizedBox(height: 16),

                    // Treatment Frequency Dropdown
                    _buildDropdownField(
                      label: "Treatment frequency:",
                      hint: "Once Every Week",
                      value: _treatmentFrequency,
                      items: [
                        "Once Every Week",
                        "Twice a Week",
                        "Three times a Week",
                        "Daily",
                        "Other",
                      ],
                      enabled: _dialysisType != null && _dialysisType != "none",
                      onChanged: (val) {
                        setState(() {
                          _treatmentFrequency = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Current Medications (Large Box)
                    _buildLargeTextField(
                      label: "Current Medications",
                      hint:
                          "List medications, dosages, and frequency (e.g., Calcium Supplement 500mg 2x daily)",
                      controller: _medicationsController,
                    ),
                    const SizedBox(height: 16),

                    // Current Allergies (Large Box)
                    _buildLargeTextField(
                      label: "Current Allergies / Food Restrictions",
                      hint: "List any allergies or food restrictions",
                      controller: _allergiesController,
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
                                Navigator.pop(context); // Go back to Step 1
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
                                    await ApiService.sendStep2({
                                      "isOnDialysis": _dialysisType != null && _dialysisType != "None",
                                      "dialysisType": _dialysisType,
                                      "treatmentFrequency": _treatmentFrequency,
                                      "medications": _medicationsController.text,
                                      "allergies": _allergiesController.text,
                                    });

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const HealthProfile3Page(),
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

  Widget _buildRadioOption(String title) {
    return SizedBox(
      height: 32,
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(unselectedWidgetColor: Colors.grey.shade400),
        child: RadioListTile<String>(
          title: Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF37474F)),
          ),
          value: title,
          groupValue: _dialysisType,
          activeColor: const Color(0xFF9E86FF),
          contentPadding: EdgeInsets.zero,
          dense: true,
          onChanged: (value) {
            setState(() {
              _dialysisType = value;
              if (value == "none") {
                _treatmentFrequency = null;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildLargeTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextFormField(
            controller: controller,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(color: Color(0xFF37474F), fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
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
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.grey.shade100,
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
              onChanged: enabled ? onChanged : null,
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
