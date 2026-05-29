import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'health_profile2.dart';
import 'profile_setup_intro.dart';

class HealthProfile1Page extends StatefulWidget {
  const HealthProfile1Page({
    super.key,
    this.isChildProfileSetup = false,
  });

  final bool isChildProfileSetup;

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
  String? _hasEdema;
  String? _isPostTransplant;
  String? _postTransplantWeeks;

  String? _dryWeight;
  String? _muac;
  String? _ckdStage;
  final Set<String> _touchedFields = {};

  // REAL DATE VALUES (for backend)
  DateTime? _dob;
  DateTime? _diagnosisDate;

  String? get _currentUserRole {
    return ApiService.normalizeUserRole(
      ApiService.userRole ??
          ApiService.signupData['userRole']?.toString() ??
          ApiService.signupData['role']?.toString(),
    );
  }

  bool get _isAdolescentRole => _currentUserRole == 'adolescent';

  String get _accountTypeLabel {
    final role = _currentUserRole;
    if (role == 'adolescent') return 'Adolescent';
    if (role == 'caregiver') return 'Caregiver';
    return 'Profile';
  }

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

  String? get _ageHelperText {
    if (!_isAdolescentRole) return null;
    final text = _ageController.text.trim();
    if (text.isEmpty) {
      return 'Required';
    }
    final age = int.tryParse(text);
    if (age == null || age < 13) {
      return 'Required';
    }
    if (age > 18) {
      return 'Required';
    }
    return null;
  }

  bool get _requiresPostTransplantWeeks => _isPostTransplant == "yes";

  int? get _sterileDietWeeksValue {
    if (_postTransplantWeeks == "6-8 weeks") return 8;
    if (_postTransplantWeeks == "8 weeks onwards") return 9;
    return null;
  }

  bool _hasTouched(String field) {
    return _touchedFields.contains(field);
  }

  String? _requiredHint(String field, bool isMissing, [String message = 'Required']) {
    return _hasTouched(field) && isMissing ? message : null;
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
    _nameController.addListener(() => _markTouchedWhenNotEmpty('name', _nameController));
    _heightController.addListener(() => _markTouchedWhenNotEmpty('height', _heightController));
    _weightController.addListener(() => _markTouchedWhenNotEmpty('weight', _weightController));
    _heightController.addListener(_updateBmi);
    _weightController.addListener(_updateBmi);
  }

  void _markTouched(String field) {
    if (_touchedFields.contains(field)) return;
    setState(() {
      _touchedFields.add(field);
    });
  }

  void _markTouchedWhenNotEmpty(
    String field,
    TextEditingController controller,
  ) {
    if (controller.text.trim().isEmpty || _touchedFields.contains(field)) {
      return;
    }
    setState(() {
      _touchedFields.add(field);
    });
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
        _hasEdema != null &&
        _isPostTransplant != null &&
        (!_requiresPostTransplantWeeks || _postTransplantWeeks != null) &&
        _appetiteStatus != null;
  }

  void _returnToPrivacyConsent() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ProfileSetupIntroScreen(
          isChildProfileSetup: widget.isChildProfileSetup,
        ),
      ),
    );
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

  Future<void> _continueToStep2() async {
    if (!_isAgeAllowedForRole()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAdolescentRole
                ? 'If you selected Adolescent, the age must be 13 or above.'
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
            'The date of birth must match an adolescent age of 13 or above.',
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
      "diagnosisDate": _diagnosisDate!.toIso8601String(),
      "kidneyType": _kidneyDiseaseType,
      "kidneyDiseaseType": _kidneyDiseaseType,
      "ckdType": _kidneyDiseaseType,
      "ckd_type": _kidneyDiseaseType,
      "dryWeight": _dryWeight,
      "muac": _muac,
      "appetiteStatus": _appetiteStatus,
      "ckdStage": _ckdStage,
      "hasEdema": _hasEdema,
      "has_edema": _hasEdema,
      "isPostTransplant": _isPostTransplant,
      "is_post_transplant": _isPostTransplant,
      "requiresSterileDiet": _isPostTransplant == "yes",
      "requires_sterile_diet": _isPostTransplant == "yes",
      "sterileDietWeeks":
          _requiresPostTransplantWeeks ? _sterileDietWeeksValue : null,
      "sterile_diet_weeks":
          _requiresPostTransplantWeeks ? _sterileDietWeeksValue : null,
      "weeksPostTransplant":
          _requiresPostTransplantWeeks ? _sterileDietWeeksValue : null,
      "weeks_post_transplant":
          _requiresPostTransplantWeeks ? _sterileDietWeeksValue : null,
    };

    try {
      // Attempt to send step1 data, but don't crash on failure.
      await ApiService.sendStep1(data);
    } catch (e) {
      // Log and continue if backend is unreachable during development.
      debugPrint('sendStep1 failed: $e');
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HealthProfile2Page(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _returnToPrivacyConsent();
        return false;
      },
      child: Scaffold(
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

                    const SizedBox(height: 12),

                    Center(child: _buildAccountTypeBadge()),

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
                      label: "Enter Child's Full Name (Required)",
                      hint: "Type here",
                      controller: _nameController,
                      onTap: () => _markTouched('name'),
                      helperText: _requiredHint(
                        'name',
                        _nameController.text.trim().isEmpty,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // DOB + SEX
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateField(
                            label: "Date of Birth (Required)",
                            hint: "MM/DD/YYYY",
                            controller: _dobController,
                            onTap: () {
                              _markTouched('dob');
                              _selectDate(context, "dob");
                            },
                            helperText: _requiredHint(
                              'dob',
                              _dob == null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSex(
                            helperText: _requiredHint(
                              'sex',
                              _selectedSex == null,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      label: "Age (years)",
                      hint: "Calculated from date of birth",
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      readOnly: true,
                      helperText: (_hasTouched('dob') ? _ageHelperText : null) ??
                          _requiredHint(
                            'dob',
                            _ageController.text.trim().isEmpty,
                          ),
                    ),

                    const SizedBox(height: 16),

                    // HEIGHT + WEIGHT
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: "Height(cm) (Required)",
                            hint: "Height in CM",
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                            onTap: () => _markTouched('height'),
                            helperText: _requiredHint(
                              'height',
                              _heightController.text.trim().isEmpty,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: "Weight (kg) (Required)",
                            hint: "Weight in kg",
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            onTap: () => _markTouched('weight'),
                            helperText: _requiredHint(
                              'weight',
                              _weightController.text.trim().isEmpty,
                            ),
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
                      helperText:
                          (_hasTouched('height') || _hasTouched('weight')) &&
                                  _bmiController.text.trim().isEmpty
                              ? "Required"
                              : null,
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
                      "Mid-Upper Arm Circumference (MUAC) (if Applicable)",
                      _muac,
                      ["< 11.5 cm", "11.5 - 12.5 cm", "> 12.5 cm"],
                      (val) => setState(() => _muac = val),
                    ),

                    const SizedBox(height: 16),

                    // APPETITE STATUS (NEW)
                    _buildDropdown(
                      "Appetite Status (Required)",
                      _appetiteStatus,
                      ["Very Good", "Good", "Fair", "Poor", "Very Poor"],
                      (val) => setState(() {
                        _touchedFields.add('appetite');
                        _appetiteStatus = val;
                      }),
                      onTap: () => _markTouched('appetite'),
                      helperText: _requiredHint(
                        'appetite',
                        _appetiteStatus == null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // DIAGNOSIS DATE
                    _buildDateField(
                      label: "Date of Diagnosis (Required)",
                      hint: "MM/DD/YYYY",
                      controller: _diagnosisDateController,
                      onTap: () {
                        _markTouched('diagnosisDate');
                        _selectDate(context, "diagnosis");
                      },
                      helperText: _requiredHint(
                        'diagnosisDate',
                        _diagnosisDate == null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // KIDNEY TYPE
                    _buildDropdown(
                      "Type of Kidney Disease (Required)",
                      _kidneyDiseaseType,
                      [
                        "CKD DKD",
                        "Congenital Anomaly",
                        "Glomerulonephritis",
                        "Hereditary Nephropathy",
                        "Other",
                      ],
                      (val) => setState(() {
                        _touchedFields.add('kidneyDisease');
                        _kidneyDiseaseType = val;
                      }),
                      onTap: () => _markTouched('kidneyDisease'),
                      helperText: _requiredHint(
                        'kidneyDisease',
                        _kidneyDiseaseType == null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildDropdown(
                      "Does the child have edema? (Required)",
                      _hasEdema,
                      ["yes", "no", "not sure"],
                      (val) => setState(() {
                        _touchedFields.add('edema');
                        _hasEdema = val;
                      }),
                      onTap: () => _markTouched('edema'),
                      helperText: _requiredHint(
                        'edema',
                        _hasEdema == null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildDropdown(
                      "Is the child on post-transplant? (Required)",
                      _isPostTransplant,
                      ["yes", "no", "not sure"],
                      (val) => setState(() {
                        _touchedFields.add('postTransplant');
                        _isPostTransplant = val;
                        if (val != "yes") {
                          _postTransplantWeeks = null;
                        }
                      }),
                      onTap: () => _markTouched('postTransplant'),
                      helperText: _requiredHint(
                        'postTransplant',
                        _isPostTransplant == null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildDropdown(
                      "Weeks post-transplant",
                      _requiresPostTransplantWeeks
                          ? _postTransplantWeeks
                          : null,
                      ["6-8 weeks", "8 weeks onwards"],
                      _requiresPostTransplantWeeks
                          ? (val) => setState(() {
                                _touchedFields.add('postTransplantWeeks');
                                _postTransplantWeeks = val;
                              })
                          : null,
                      onTap: _requiresPostTransplantWeeks
                          ? () => _markTouched('postTransplantWeeks')
                          : null,
                      helperText: _requiredHint(
                        'postTransplantWeeks',
                        _requiresPostTransplantWeeks &&
                            _postTransplantWeeks == null,
                      ),
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

                    // --- Side-by-Side Buttons ---
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: TextButton(
                              onPressed: _returnToPrivacyConsent,
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFFE8EDEA),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Back",
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
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isFormValid ? _continueToStep2 : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4DB6AC),
                                disabledBackgroundColor:
                                    Colors.grey.shade400,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
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
      ),
    );
  }

  // ================= HELPERS (UNCHANGED DESIGN) =================

  Widget _buildAccountTypeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5F1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4DB6AC)),
      ),
      child: Text(
        _accountTypeLabel == 'Adolescent'
            ? 'Setting up adolescent profile'
            : _accountTypeLabel == 'Profile'
                ? 'Setting up profile'
                : 'Setting up $_accountTypeLabel account',
        style: const TextStyle(
          color: Color(0xFF37474F),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String? helperText,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel(label),
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
            onTap: onTap,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onTap,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel(label),
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
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?>? onChanged,
    {String? helperText,
    VoidCallback? onTap}
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel(label),
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
              onTap: onTap,
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
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSex({String? helperText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel("Sex (Required)"),
        RadioListTile(
          title: const Text("Male"),
          value: "Male",
          groupValue: _selectedSex,
          onChanged: (val) => setState(() {
            _touchedFields.add('sex');
            _selectedSex = val.toString();
          }),
        ),
        RadioListTile(
          title: const Text("Female"),
          value: "Female",
          groupValue: _selectedSex,
          onChanged: (val) => setState(() {
            _touchedFields.add('sex');
            _selectedSex = val.toString();
          }),
        ),
        if (helperText != null)
          Text(
            helperText,
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              fontSize: 12,
              height: 1.3,
            ),
          ),
      ],
    );
  }

  Widget _buildRequiredLabel(String label) {
    const marker = " (Required)";
    if (!label.endsWith(marker)) {
      return Text(label);
    }
    return Text.rich(
      TextSpan(
        text: label.substring(0, label.length - marker.length),
        children: const [
          TextSpan(
            text: marker,
            style: TextStyle(color: Color(0xFFD32F2F)),
          ),
        ],
      ),
    );
  }
}
