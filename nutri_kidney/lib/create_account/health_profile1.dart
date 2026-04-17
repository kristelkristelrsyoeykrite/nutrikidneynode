import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'health_profile2.dart';

class HealthProfile1Page extends StatefulWidget {
  const HealthProfile1Page({super.key});

  @override
  State<HealthProfile1Page> createState() => _HealthProfile1PageState();
}

class _HealthProfile1PageState extends State<HealthProfile1Page> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _diagnosisDateController =
      TextEditingController();

  String? _selectedGender;
  String? _kidneyDiseaseType;

  String? _dryWeight;
  String? _muac;
  String? _ckdStage;

  // REAL DATE VALUES (for backend)
  DateTime? _dob;
  DateTime? _diagnosisDate;

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _diagnosisDateController.dispose();
    super.dispose();
  }

  // FORM VALIDATION
  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
        _dob != null &&
        _selectedGender != null &&
        _heightController.text.trim().isNotEmpty &&
        _weightController.text.trim().isNotEmpty &&
        _diagnosisDate != null &&
        _kidneyDiseaseType != null;
  }

  // FORMAT DATE FOR UI ONLY
  String _formatDate(DateTime date) {
    return "${date.month.toString().padLeft(2, '0')}/"
        "${date.day.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  // DATE PICKER (DOB + Diagnosis)
  Future<void> _selectDate(BuildContext context, String type) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4DB6AC),
              onPrimary: Colors.white,
              onSurface: Color(0xFF37474F),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (type == "dob") {
          _dob = picked;
          _dobController.text = _formatDate(picked);
        } else {
          _diagnosisDate = picked;
          _diagnosisDateController.text = _formatDate(picked);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // BACKGROUND (UNCHANGED)
            Positioned(
              bottom: -360,
              left: -110,
              right: -90,
              child: Image.asset(
                'assets/images/bottom_waves.png',
                fit: BoxFit.fitWidth,
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

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

                    // PROGRESS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Step 1 of 4',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF90A4AE),
                          ),
                        ),
                        Text(
                          '25% Complete',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF4DB6AC),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    LinearProgressIndicator(
                      value: 0.25,
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFF37474F),
                      minHeight: 4,
                    ),

                    const SizedBox(height: 24),

                    // NAME
                    _buildTextField(
                      label: "Enter Child's Full Name",
                      hint: "Type here",
                      controller: _nameController,
                    ),

                    const SizedBox(height: 16),

                    // DOB + GENDER
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateField(
                            label: "Date of Birth",
                            hint: "MM/DD/YYYY",
                            controller: _dobController,
                            onTap: () => _selectDate(context, "dob"),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _buildGender()),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // HEIGHT + WEIGHT
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: "Height(cm)",
                            hint: "Height in CM",
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: "Weight (kg)",
                            hint: "Weight in kg",
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // DRY WEIGHT
                    _buildDropdown(
                      "Dry Weight (if Applicable)",
                      _dryWeight,
                      ["10 kg", "15 kg", "20 kg", "25+ kg"],
                      (val) => setState(() => _dryWeight = val),
                    ),

                    const SizedBox(height: 16),

                    // MUAC
                    _buildDropdown(
                      "MUAC (if Applicable)",
                      _muac,
                      ["< 11.5 cm", "11.5 - 12.5 cm", "> 12.5 cm"],
                      (val) => setState(() => _muac = val),
                    ),

                    const SizedBox(height: 16),

                    // DIAGNOSIS DATE
                    _buildDateField(
                      label: "Date of Diagnosis",
                      hint: "MM/DD/YYYY",
                      controller: _diagnosisDateController,
                      onTap: () => _selectDate(context, "diagnosis"),
                    ),

                    const SizedBox(height: 16),

                    // KIDNEY TYPE
                    _buildDropdown(
                      "Type of Kidney Disease",
                      _kidneyDiseaseType,
                      [
                        "Congenital Anomaly",
                        "Glomerulonephritis",
                        "Hereditary Nephropathy",
                        "Other",
                      ],
                      (val) => setState(() => _kidneyDiseaseType = val),
                    ),

                    const SizedBox(height: 16),

                    // CKD STAGE
                    _buildDropdown(
                      "CKD Stage",
                      _ckdStage,
                      ["Stage 1", "Stage 2", "Stage 3", "Stage 4", "Stage 5"],
                      (val) => setState(() => _ckdStage = val),
                    ),

                    const SizedBox(height: 40),

                    // CONTINUE BUTTON (ONLY LOGIC ADDED HERE)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isFormValid
                            ? () async {
                                final data = {
                                  "name": _nameController.text,
                                  "dob": _dob!.toIso8601String(),
                                  "gender": _selectedGender,
                                  "height": double.parse(_heightController.text),
                                  "weight": double.parse(_weightController.text),
                                  "diagnosisDate":
                                      _diagnosisDate!.toIso8601String(),
                                  "kidneyType": _kidneyDiseaseType,
                                  "dryWeight": _dryWeight,
                                  "muac": _muac,
                                  "ckdStage": _ckdStage,
                                };

                                try {
                                  // Attempt to send step1 data, but don't crash on failure.
                                  await ApiService.sendStep1(data);
                                } catch (e) {
                                  // Log and continue — backend may be unreachable during development.
                                  debugPrint('sendStep1 failed: $e');
                                }

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const HealthProfile2Page(),
                                  ),
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4DB6AC),
                          disabledBackgroundColor: Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Continue",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Back"),
                      ),
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

  // ================= HELPERS (UNCHANGED DESIGN) =================

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: controller,
            readOnly: true,
            onTap: onTap,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGender() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Gender"),
        RadioListTile(
          title: const Text("Male"),
          value: "Male",
          groupValue: _selectedGender,
          onChanged: (val) => setState(() => _selectedGender = val.toString()),
        ),
        RadioListTile(
          title: const Text("Female"),
          value: "Female",
          groupValue: _selectedGender,
          onChanged: (val) => setState(() => _selectedGender = val.toString()),
        ),
      ],
    );
  }
}