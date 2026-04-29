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
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _bmiController = TextEditingController();
  final TextEditingController _diagnosisDateController =
      TextEditingController();

  String? _selectedSex;
  String? _kidneyDiseaseType;
  String? _appetiteStatus;

  String? _dryWeight;
  String? _muac;
  String? _ckdStage;

  // REAL DATE VALUES (for backend)
  DateTime? _dob;
  DateTime? _diagnosisDate;

  bool get _isAdolescentRole => ApiService.userRole == 'adolescent';

  DateTime _todayDateOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int _calculateAgeFromDate(DateTime dob) {
    final today = _todayDateOnly();
    var age = today.year - dob.year;
    final birthdayThisYearPassed =
        today.month > dob.month ||
        (today.month == dob.month && today.day >= dob.day);
    if (!birthdayThisYearPassed) {
      age -= 1;
    }
    return age;
  }

  DateTime _latestAllowedAdolescentDob() {
    final today = _todayDateOnly();
    return DateTime(today.year - 13, today.month, today.day);
  }

  DateTime _earliestAllowedAdolescentDob() {
    final today = _todayDateOnly();
    return DateTime(today.year - 18, today.month, today.day);
  }

  bool _isAgeAllowedForRole() {
    final age = int.tryParse(_ageController.text.trim());
    if (age == null) return false;
    if (_isAdolescentRole) {
      return age >= 13 && age <= 18;
    }
    return age > 0;
  }

  bool _isDobAllowedForRole() {
    if (_dob == null) return false;
    if (_isAdolescentRole) {
      final age = _calculateAgeFromDate(_dob!);
      return age >= 13 && age <= 18;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _nameController,
      _ageController,
      _heightController,
      _weightController,
      _bmiController,
    ]) {
      controller.addListener(() {
        setState(() {});
      });
    }
    _heightController.addListener(_updateBmi);
    _weightController.addListener(_updateBmi);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _bmiController.dispose();
    _diagnosisDateController.dispose();
    super.dispose();
  }

  void _updateBmi() {
    final heightCm = double.tryParse(_heightController.text.trim());
    final weightKg = double.tryParse(_weightController.text.trim());

    if (heightCm == null || weightKg == null || heightCm <= 0) {
      if (_bmiController.text.isNotEmpty) {
        _bmiController.clear();
      }
      return;
    }

    final heightMeters = heightCm / 100;
    final bmi = weightKg / (heightMeters * heightMeters);
    final bmiText = bmi.toStringAsFixed(1);
    if (_bmiController.text != bmiText) {
      _bmiController.text = bmiText;
    }
  }

  // FORM VALIDATION
  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
        _dob != null &&
        _ageController.text.trim().isNotEmpty &&
        _isAgeAllowedForRole() &&
        _isDobAllowedForRole() &&
        _selectedSex != null &&
        _heightController.text.trim().isNotEmpty &&
        _weightController.text.trim().isNotEmpty &&
        _bmiController.text.trim().isNotEmpty &&
        _diagnosisDate != null &&
        _kidneyDiseaseType != null &&
        _appetiteStatus != null;
  }

  // FORMAT DATE FOR UI ONLY
  String _formatDate(DateTime date) {
    return "${date.month.toString().padLeft(2, '0')}/"
        "${date.day.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  // DATE PICKER (DOB + Diagnosis)
  Future<void> _selectDate(BuildContext context, String type) async {
    final now = _todayDateOnly();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: type == "dob" && _isAdolescentRole
          ? _latestAllowedAdolescentDob()
          : now,
      firstDate: type == "dob" && _isAdolescentRole
          ? _earliestAllowedAdolescentDob()
          : DateTime(1990),
      lastDate: type == "dob" && _isAdolescentRole
          ? _latestAllowedAdolescentDob()
          : now,
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
          _ageController.text = _calculateAgeFromDate(picked).toString();
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

                    // DOB + SEX
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
                        Expanded(child: _buildSex()),
                      ],
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      label: "Age (years)",
                      hint: _isAdolescentRole
                          ? "Adolescent age must be 13-18"
                          : "Enter age in years",
                      controller: _ageController,
                      keyboardType: TextInputType.number,
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

                    _buildTextField(
                      label: "BMI (kg/m2)",
                      hint: "Auto-calculated from height and weight",
                      controller: _bmiController,
                      keyboardType: TextInputType.number,
                      readOnly: true,
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

                    // APPETITE STATUS (NEW)
                    _buildDropdown(
                      "Appetite Status",
                      _appetiteStatus,
                      ["Very Good", "Good", "Fair", "Poor", "Very Poor"],
                      (val) => setState(() => _appetiteStatus = val),
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

                    // CKD STAGE (updated with "Not sure" option)
                    _buildDropdown(
                      "CKD Stage",
                      _ckdStage,
                      ["Stage 1", "Stage 2", "Stage 3", "Stage 4", "Stage 5", "Stage 5D", "Not sure"],
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
                                if (!_isAgeAllowedForRole()) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _isAdolescentRole
                                            ? 'Adolescent accounts must be between 13 and 18 years old.'
                                            : 'Enter a valid age before continuing.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                if (!_isDobAllowedForRole()) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'The date of birth must match an adolescent age between 13 and 18.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                final data = {
                                  "name": _nameController.text,
                                  "dob": _dob!.toIso8601String(),
                                  "ageYears": int.parse(_ageController.text),
                                  "age_years": int.parse(_ageController.text),
                                  "sex": _selectedSex,
                                  "gender": _selectedSex,
                                  "height": double.parse(_heightController.text),
                                  "height_cm": double.parse(_heightController.text),
                                  "weight": double.parse(_weightController.text),
                                  "weight_kg": double.parse(_weightController.text),
                                  "bmi": double.parse(_bmiController.text),
                                  "diagnosisDate":
                                      _diagnosisDate!.toIso8601String(),
                                  "kidneyType": _kidneyDiseaseType,
                                  "dryWeight": _dryWeight,
                                  "muac": _muac,
                                  "appetiteStatus": _appetiteStatus,
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
    bool readOnly = false,
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
            readOnly: readOnly,
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

  Widget _buildSex() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Sex"),
        RadioListTile(
          title: const Text("Male"),
          value: "Male",
          groupValue: _selectedSex,
          onChanged: (val) => setState(() => _selectedSex = val.toString()),
        ),
        RadioListTile(
          title: const Text("Female"),
          value: "Female",
          groupValue: _selectedSex,
          onChanged: (val) => setState(() => _selectedSex = val.toString()),
        ),
      ],
    );
  }
}
