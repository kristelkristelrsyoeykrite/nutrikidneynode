import 'package:flutter/material.dart';

import '../authenticator_mfa_page.dart';
import '../../services/api_service.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> viewer;
  final Map<String, dynamic> user;
  final Map<String, dynamic> medicalProfile;
  final Map<String, dynamic> anthropometrics;
  final String? profileOwnerId;

  const EditProfilePage({
    super.key,
    required this.viewer,
    required this.user,
    required this.medicalProfile,
    required this.anthropometrics,
    required this.profileOwnerId,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const List<String> _allergyOptions = [
    'No known allergies',
    'Not sure',
    'Milk',
    'Egg',
    'Peanut',
    'Tree nuts',
    'Soy',
    'Wheat / Gluten',
    'Fish',
    'Shellfish',
    'Sesame',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, String> _originalNutritionFields = {};

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _dobController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _bmiController;
  late final TextEditingController _dryWeightController;
  late final TextEditingController _kidneyDiseaseTypeController;
  late final TextEditingController _diagnosisDateController;
  late final TextEditingController _treatmentFrequencyController;
  late final TextEditingController _fluidLimitController;
  late final TextEditingController _otherAllergyController;

  String? _sex;
  String? _ckdStage;
  String? _dialysisType;
  String? _dietPattern;
  String? _processedFoodIntake;
  String? _mealPattern;
  String? _physicalActivityLevel;
  String? _preferredMeasurementSystem;
  String? _fluidRestrictionStatus;
  String? _hasHypertension;
  bool _onDialysis = false;
  final Set<String> _selectedAllergies = {};

  bool get _isAdolescentRole =>
      _read(widget.user, ["role", "userRole"]).toLowerCase() == "adolescent";

  bool get _isCaregiverViewer {
    final role = _read(widget.viewer, ["role", "userRole"]).toLowerCase();
    return role == "caregiver" || role == "parent_caregiver";
  }

  bool get _caregiverLinked {
    final settings = widget.user["caregiverSettings"];
    if (settings is Map) {
      return settings["caregiverLinked"] == true;
    }
    return false;
  }

  bool get _canEditSensitive {
    if (_isCaregiverViewer) return true;
    if (!_isAdolescentRole) return true;
    if (_caregiverLinked) return false;
    final permissions = widget.user["editPermissions"];
    if (permissions is Map && permissions["canEditSensitive"] is bool) {
      return permissions["canEditSensitive"] == true;
    }
    return true;
  }

  bool get _canEditAge {
    if (_isCaregiverViewer) return true;
    return !_isAdolescentRole || !_caregiverLinked;
  }

  bool get _requiresAdolescentAgeRange => _isAdolescentRole;

  static const _sexOptions = ["Male", "Female"];
  static const _ckdStageOptions = [
    "Stage 1",
    "Stage 2",
    "Stage 3",
    "Stage 4",
    "Stage 5",
    "Stage 5D",
  ];
  static const _dialysisTypeOptions = ["HD", "PD"];
  static const _dietPatternOptions = [
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
  ];
  static const _processedFoodOptions = ["Often", "Sometimes", "Rarely"];
  static const _mealPatternOptions = [
    "Regular (3 meals)",
    "3 meals + snacks",
    "Irregular",
  ];
  static const _activityOptions = [
    "Low (Mostly sedentary)",
    "Moderate (Light active)",
    "High (Very active)",
  ];
  static const _measurementOptions = ["Grams", "Ounces/Cups", "Mixed"];
  static const _fluidRestrictionOptions = ["yes", "no", "not sure"];
  static const _hypertensionOptions = ["yes", "no", "not_sure"];

  int? _parsedAgeValue([String? raw]) {
    return int.tryParse((raw ?? _ageController.text).trim());
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

  bool _isAdolescentAgeValid() {
    if (!_requiresAdolescentAgeRange) return true;
    final age = _parsedAgeValue();
    return age != null && age >= 13 && age <= 18;
  }

  bool _isAdolescentDobValid() {
    if (!_requiresAdolescentAgeRange || _dobController.text.trim().isEmpty) {
      return true;
    }

    final dob = DateTime.tryParse(_dobController.text.trim());
    if (dob == null) return false;
    final age = _calculateAgeFromDate(dob);
    return age >= 13 && age <= 18;
  }

  bool _hasSensitiveIdentityChanges() {
    return _nameController.text.trim() !=
            _read(widget.user, ["childFullName", "child_name", "name"]) ||
        _ageController.text.trim() !=
            _read(widget.user, ["ageYears", "age_years"]) ||
        _dobController.text.trim() != _read(widget.user, ["dateOfBirth", "dob"]);
  }

  Future<bool> _confirmSensitiveActionWithMfa() async {
    final settingsResponse = await ApiService.getSecuritySettings();
    final settings = authenticatorSecuritySettingsFromResponse(settingsResponse);
    if (settings['mfaEnabled'] != true) {
      return true;
    }

    final currentUserId = ApiService.userId;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception('UserId not set. Please log in again.');
    }

    return showAuthenticatorMfaChallengeDialog(
      context,
      uid: currentUserId,
      purpose: 'profile_change',
      securitySettings: settings,
    );
  }

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: _read(widget.user, ["childFullName", "child_name", "name"]),
    );
    _ageController = TextEditingController(
      text: _read(widget.user, ["ageYears", "age_years"]),
    );
    _dobController = TextEditingController(
      text: _read(widget.user, ["dateOfBirth", "dob"]),
    );
    _heightController = TextEditingController(
      text: _read(widget.anthropometrics, ["height_cm", "height"]),
    );
    _weightController = TextEditingController(
      text: _read(widget.anthropometrics, ["weight_kg", "weight"]),
    );
    _bmiController = TextEditingController(
      text: _firstValue([
        _read(widget.anthropometrics, ["bmi"]),
        _read(widget.user, ["bmi"]),
      ]),
    );
    _dryWeightController = TextEditingController(
      text: _read(widget.anthropometrics, ["dryWeight", "dry_weight_kg"]),
    );
    _kidneyDiseaseTypeController = TextEditingController(
      text: _read(widget.medicalProfile, ["kidneyDiseaseType"]),
    );
    _diagnosisDateController = TextEditingController(
      text: _read(widget.medicalProfile, ["dateOfDiagnosis"]),
    );
    _treatmentFrequencyController = TextEditingController(
      text: _read(widget.medicalProfile, ["treatmentFrequency"]),
    );
    _fluidLimitController = TextEditingController(
      text: _read(widget.medicalProfile, ["fluidLimitMl", "fluid_limit_ml"]),
    );
    _otherAllergyController = TextEditingController();
    _heightController.addListener(_updateBmi);
    _weightController.addListener(_updateBmi);

    _populateDropdowns(
      user: widget.user,
      medical: widget.medicalProfile,
      targets: const {},
    );
    _onDialysis = _readBool(widget.medicalProfile["onDialysis"]);
    _originalNutritionFields = _nutritionAffectingValues();
    _loadLatestProfileForEdit();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _dobController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _bmiController.dispose();
    _dryWeightController.dispose();
    _kidneyDiseaseTypeController.dispose();
    _diagnosisDateController.dispose();
    _treatmentFrequencyController.dispose();
    _fluidLimitController.dispose();
    _otherAllergyController.dispose();
    super.dispose();
  }

  static String _read(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return "";
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  static String _firstValue(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value;
    }
    return "";
  }

  List<String> _allergyListFromDynamic(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,;\n]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _normalizeAllergyOption(String value) {
    final normalized = value.toLowerCase().trim();
    const aliases = {
      'milk': 'Milk',
      'dairy': 'Milk',
      'egg': 'Egg',
      'eggs': 'Egg',
      'peanut': 'Peanut',
      'peanuts': 'Peanut',
      'tree nuts': 'Tree nuts',
      'treenuts': 'Tree nuts',
      'soy': 'Soy',
      'soya': 'Soy',
      'wheat': 'Wheat / Gluten',
      'gluten': 'Wheat / Gluten',
      'wheat / gluten': 'Wheat / Gluten',
      'fish': 'Fish',
      'shellfish': 'Shellfish',
      'sesame': 'Sesame',
      'no known allergies': 'No known allergies',
      'not sure': 'Not sure',
      'other': 'Other',
    };
    return aliases[normalized] ?? value.trim();
  }

  void _populateAllergies(Map<String, dynamic> medical) {
    _selectedAllergies.clear();
    _otherAllergyController.clear();
    final allergyValues = _allergyListFromDynamic(medical['allergies']);
    final otherValues = <String>[];
    for (final item in allergyValues) {
      final normalized = _normalizeAllergyOption(item);
      if (_allergyOptions.contains(normalized)) {
        _selectedAllergies.add(normalized);
      } else if (item.trim().isNotEmpty) {
        otherValues.add(item.trim());
      }
    }
    if (otherValues.isNotEmpty) {
      _selectedAllergies.add('Other');
      _otherAllergyController.text = otherValues.join(', ');
    }
  }

  List<String> _selectedAllergyPayload() {
    if (_selectedAllergies.contains('No known allergies')) {
      return ['No known allergies'];
    }

    final allergies = _selectedAllergies
        .where((item) => item != 'Other')
        .toList(growable: true);
    final otherText = _otherAllergyController.text.trim();
    if (_selectedAllergies.contains('Other') && otherText.isNotEmpty) {
      allergies.add(otherText);
    }
    final seen = <String>{};
    return allergies.where((item) {
      final normalized = item.toLowerCase().trim();
      if (normalized.isEmpty || seen.contains(normalized)) {
        return false;
      }
      seen.add(normalized);
      return true;
    }).toList(growable: false);
  }

  void _toggleAllergyOption(String option) {
    setState(() {
      if (option == 'No known allergies') {
        if (_selectedAllergies.contains(option)) {
          _selectedAllergies.remove(option);
        } else {
          _selectedAllergies
            ..clear()
            ..add(option);
          _otherAllergyController.clear();
        }
        return;
      }

      _selectedAllergies.remove('No known allergies');

      if (_selectedAllergies.contains(option)) {
        _selectedAllergies.remove(option);
        if (option == 'Other') {
          _otherAllergyController.clear();
        }
      } else {
        _selectedAllergies.add(option);
      }
    });
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

  static String _normalizeOption(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
        .trim();
  }

  static String _normalizeDietPattern(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "regular": "Regular diet",
      "regular diet": "Regular diet",
      "renal": "Renal diet",
      "renal diet": "Renal diet",
      "high protein": "High protein",
      "low protein": "Low protein",
      "low salt low fat": "Low salt / Low fat",
      "low fat low salt": "Low salt / Low fat",
      "low fat": "Low fat",
      "low salt": "Low salt",
      "low sodium": "Low salt",
      "low potassium": "Low potassium",
      "low phosphorus": "Low phosphorus",
      "low phosphate": "Low phosphorus",
      "low purine": "Low purine",
      "vegetarian": "Vegetarian",
      "vegan": "Vegan",
      "other": "Other",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeProcessedFood(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "often": "Often",
      "frequent": "Often",
      "frequently": "Often",
      "daily": "Often",
      "sometimes": "Sometimes",
      "moderate": "Sometimes",
      "rarely": "Rarely",
      "rare": "Rarely",
      "low": "Rarely",
      "never": "Rarely",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeMealPattern(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "regular": "Regular (3 meals)",
      "regular 3 meals": "Regular (3 meals)",
      "3 meals": "Regular (3 meals)",
      "three meals": "Regular (3 meals)",
      "3 meals snacks": "3 meals + snacks",
      "3 meals plus snacks": "3 meals + snacks",
      "small frequent meals": "3 meals + snacks",
      "frequent meals": "3 meals + snacks",
      "irregular": "Irregular",
      "skips meals frequently": "Irregular",
      "skip meals": "Irregular",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeActivityLevel(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "low": "Low (Mostly sedentary)",
      "low mostly sedentary": "Low (Mostly sedentary)",
      "mostly sedentary": "Low (Mostly sedentary)",
      "moderate": "Moderate (Light active)",
      "moderate light active": "Moderate (Light active)",
      "light active": "Moderate (Light active)",
      "high": "High (Very active)",
      "high very active": "High (Very active)",
      "very active": "High (Very active)",
    };
    return aliases[text] ?? value;
  }

  static String _normalizeMeasurementSystem(String value) {
    final text = _normalizeOption(value);
    const aliases = {
      "grams": "Grams",
      "metric": "Grams",
      "ounces cups": "Ounces/Cups",
      "ounces": "Ounces/Cups",
      "cups": "Ounces/Cups",
      "imperial": "Ounces/Cups",
      "mixed": "Mixed",
    };
    return aliases[text] ?? value;
  }

  void _setText(TextEditingController controller, String value) {
    if (value.trim().isNotEmpty) {
      controller.text = value;
    }
  }

  String _normalizedFieldValue(dynamic value) {
    return (value ?? "").toString().trim();
  }

  Map<String, String> _nutritionAffectingValues() {
    return {
      "age": _normalizedFieldValue(_ageController.text),
      "dateOfBirth": _normalizedFieldValue(_dobController.text),
      "height": _normalizedFieldValue(_heightController.text),
      "weight": _normalizedFieldValue(_weightController.text),
      "bmi": _normalizedFieldValue(_bmiController.text),
      "dryWeight": _normalizedFieldValue(
        _onDialysis ? _dryWeightController.text : "",
      ),
      "ckdStage": _normalizedFieldValue(_ckdStage),
      "onDialysis": _normalizedFieldValue(_onDialysis),
      "dialysisType": _normalizedFieldValue(_onDialysis ? _dialysisType : ""),
      "treatmentFrequency": _normalizedFieldValue(
        _onDialysis ? _treatmentFrequencyController.text : "",
      ),
      "physicalActivityLevel": _normalizedFieldValue(_physicalActivityLevel),
      "fluidRestrictionStatus": _normalizedFieldValue(_fluidRestrictionStatus),
      "fluidLimit": _normalizedFieldValue(
        _fluidRestrictionStatus == "yes" ? _fluidLimitController.text : "",
      ),
    };
  }

  bool _hasNutritionAffectingChanges() {
    final currentValues = _nutritionAffectingValues();
    for (final entry in currentValues.entries) {
      if (_originalNutritionFields[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _confirmNutritionTargetUpdate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Update Nutrition Targets?"),
          content: const Text(
            "The changes you made affect the child's nutritional profile. "
            "Saving this update will trigger the system to recalculate "
            "nutrition targets and may change the recommended insights, "
            "limits, and guidance. Are you sure you want to continue?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
              ),
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  void _populateDropdowns({
    required Map<String, dynamic> user,
    required Map<String, dynamic> medical,
    required Map<String, dynamic> targets,
  }) {
    _sex = _dropdownValue(
      _sexOptions,
      _normalizeSex(_firstValue([
        _read(user, ["sex", "gender"]),
        _read(targets, ["sex", "gender"]),
      ])),
    );
    _ckdStage = _dropdownValue(
      _ckdStageOptions,
      _firstValue([
        _read(medical, ["ckdStage", "ckd_stage"]),
        _read(targets, ["ckd_stage", "ckdStage"]),
      ]),
    );
    _dialysisType = _dropdownValue(
      _dialysisTypeOptions,
      _read(medical, ["dialysisType", "dialysis_type"]),
    );
    _dietPattern = _dropdownValue(
      _dietPatternOptions,
      _normalizeDietPattern(_read(medical, ["dietPattern", "diet_pattern"])),
    );
    _processedFoodIntake = _dropdownValue(
      _processedFoodOptions,
      _normalizeProcessedFood(
        _read(medical, ["processedFoodIntake", "processed_food_intake"]),
      ),
    );
    _mealPattern = _dropdownValue(
      _mealPatternOptions,
      _normalizeMealPattern(_read(medical, ["mealPattern", "meal_pattern"])),
    );
    _physicalActivityLevel = _dropdownValue(
      _activityOptions,
      _normalizeActivityLevel(
        _read(medical, ["physicalActivityLevel", "physical_activity_level"]),
      ),
    );
    _preferredMeasurementSystem = _dropdownValue(
      _measurementOptions,
      _normalizeMeasurementSystem(
        _read(user, ["preferredMeasurementSystem", "preferredMeasurement"]),
      ),
    );
    _fluidRestrictionStatus = _dropdownValue(
      _fluidRestrictionOptions,
      _read(medical, ["fluidRestrictionStatus", "fluid_restriction_status"]),
    );
    _hasHypertension = _dropdownValue(
      _hypertensionOptions,
      _read(medical, ["hasHypertension", "has_hypertension"]),
    );
    _populateAllergies(medical);
  }

  Future<void> _loadLatestProfileForEdit() async {
    try {
      final response = await ApiService.getHealthSummary(
        profileUserId: widget.profileOwnerId,
      );
      if (!mounted) return;

      if (response["success"] == true) {
        final user = _asStringMap(response["user"]);
        final medical = _asStringMap(response["medicalProfile"]);
        final anthropometrics = _asStringMap(response["anthropometrics"]);
        final targets = _asStringMap(response["nutritionTargets"]);

        _setText(
          _nameController,
          _firstValue([
            _read(user, ["childFullName", "child_name", "name"]),
            _read(targets, ["child_name", "childFullName"]),
          ]),
        );
        _setText(
          _ageController,
          _firstValue([
            _read(user, ["ageYears", "age_years"]),
            _read(targets, ["age_years", "ageYears"]),
          ]),
        );
        _setText(_dobController, _read(user, ["dateOfBirth", "dob"]));
        _setText(
          _heightController,
          _firstValue([
            _read(anthropometrics, ["height_cm", "height"]),
            _read(targets, ["height_cm", "height"]),
          ]),
        );
        _setText(
          _weightController,
          _firstValue([
            _read(anthropometrics, ["weight_kg", "weight"]),
            _read(targets, ["weight_kg", "weight"]),
          ]),
        );
        _setText(
          _bmiController,
          _firstValue([
            _read(anthropometrics, ["bmi"]),
            _read(user, ["bmi"]),
            _read(targets, ["bmi"]),
          ]),
        );
        _setText(
          _dryWeightController,
          _firstValue([
            _read(anthropometrics, ["dryWeight", "dry_weight_kg"]),
            _read(targets, ["dry_weight_kg", "dryWeight"]),
          ]),
        );
        _setText(
          _kidneyDiseaseTypeController,
          _read(medical, ["kidneyDiseaseType"]),
        );
        _setText(
          _diagnosisDateController,
          _read(medical, ["dateOfDiagnosis"]),
        );
        _setText(
          _treatmentFrequencyController,
          _read(medical, ["treatmentFrequency"]),
        );
        _setText(
          _fluidLimitController,
          _read(medical, ["fluidLimitMl", "fluid_limit_ml"]),
        );

        setState(() {
          _populateDropdowns(user: user, medical: medical, targets: targets);
          _onDialysis = _readBool(medical["onDialysis"]);
          _originalNutritionFields = _nutritionAffectingValues();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    return text == "true" || text == "yes";
  }

  static String _normalizeSex(String value) {
    final text = value.toLowerCase().trim();
    if (text == "male") return "Male";
    if (text == "female") return "Female";
    return value;
  }

  static String? _dropdownValue(List<String> options, String value) {
    if (value.trim().isEmpty) return null;
    final normalizedValue = _normalizeOption(value);
    for (final option in options) {
      if (_normalizeOption(option) == normalizedValue) {
        return option;
      }
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController controller) async {
    if (controller == _dobController && !_canEditAge) {
      return;
    }

    final now = _todayDateOnly();
    final initialDate = DateTime.tryParse(controller.text) ??
        (_requiresAdolescentAgeRange ? _latestAllowedAdolescentDob() : now);
    final firstDate = controller == _dobController && _requiresAdolescentAgeRange
        ? _earliestAllowedAdolescentDob()
        : DateTime(1990);
    final lastDate = controller == _dobController && _requiresAdolescentAgeRange
        ? _latestAllowedAdolescentDob()
        : now;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate)
          ? firstDate
          : (initialDate.isAfter(lastDate) ? lastDate : initialDate),
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (selected != null) {
      controller.text = selected.toIso8601String().split("T").first;
      if (controller == _dobController) {
        _ageController.text = _calculateAgeFromDate(selected).toString();
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isAdolescentAgeValid()) {
      _showError('Adolescent accounts must stay between 13 and 18 years old.');
      return;
    }

    if (!_isAdolescentDobValid()) {
      _showError(
        'The date of birth must match an adolescent age between 13 and 18.',
      );
      return;
    }

    final shouldRecalculate = _hasNutritionAffectingChanges();
    if (shouldRecalculate) {
      final confirmed = await _confirmNutritionTargetUpdate();
      if (!confirmed) return;
    }

    setState(() => _isSaving = true);
    try {
      if (_hasSensitiveIdentityChanges()) {
        final passedMfa = await _confirmSensitiveActionWithMfa();
        if (!passedMfa) return;
      }

      final response = await ApiService.updateProfile({
        "profileUserId": widget.profileOwnerId,
        "childFullName": _nameController.text.trim(),
        "ageYears": _ageController.text.trim(),
        "dateOfBirth": _dobController.text.trim(),
        "sex": _sex,
        "height_cm": _heightController.text.trim(),
        "weight_kg": _weightController.text.trim(),
        "bmi": _bmiController.text.trim(),
        "dryWeight": _onDialysis ? _dryWeightController.text.trim() : null,
        "ckdStage": _ckdStage,
        "kidneyDiseaseType": _kidneyDiseaseTypeController.text.trim(),
        "dateOfDiagnosis": _diagnosisDateController.text.trim(),
        "onDialysis": _onDialysis,
        "dialysisType": _onDialysis ? _dialysisType : null,
        "treatmentFrequency":
            _onDialysis ? _treatmentFrequencyController.text.trim() : null,
        "dietPattern": _dietPattern,
        "processedFoodIntake": _processedFoodIntake,
        "mealPattern": _mealPattern,
        "physicalActivityLevel": _physicalActivityLevel,
        "preferredMeasurementSystem": _preferredMeasurementSystem,
        "fluidRestrictionStatus": _fluidRestrictionStatus,
        "fluidLimitMl": _fluidRestrictionStatus == "yes"
            ? _fluidLimitController.text.trim()
            : null,
        "hasHypertension": _hasHypertension,
        "allergies": _selectedAllergyPayload(),
        "recalculateNutritionTargets": shouldRecalculate,
      });

      if (!mounted) return;
      if (response["success"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully")),
        );
        Navigator.pop(context, true);
      } else {
        _showError(response["error"]?.toString() ?? "Unable to update profile");
      }
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _sensitiveEditNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: const Text(
        'Some medical fields are managed with your caregiver. Sensitive health information is read-only while a caregiver is linked.',
        style: TextStyle(
          color: Color(0xFF7A5C00),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(
                      color: Color(0xFF00C874),
                      backgroundColor: Color(0xFFE0F2F1),
                    ),
                  ),
                if (_caregiverLinked && _isAdolescentRole && !_canEditSensitive)
                  _sensitiveEditNotice(),
                _section(
                  "Child Information",
                  [
                    _textField(
                      _nameController,
                      "Child full name",
                      required: true,
                    ),
                    _numberField(
                      _ageController,
                      "Age",
                      required: true,
                      readOnly: !_canEditAge,
                      hint: !_canEditAge
                          ? "Age is managed by the caregiver"
                          : null,
                    ),
                    _dateField(
                      _dobController,
                      "Date of birth",
                      readOnly: !_canEditAge,
                      hint: !_canEditAge
                          ? "Date of birth is managed by the caregiver"
                          : (_requiresAdolescentAgeRange
                              ? "Adolescent date of birth must stay within ages 13-18"
                              : null),
                    ),
                    _dropdownField(
                      label: "Sex / gender",
                      value: _sex,
                      options: _sexOptions,
                      onChanged: (value) => setState(() => _sex = value),
                    ),
                  ],
                ),
                _section(
                  "Body Measurements",
                  [
                    _numberField(_heightController, "Height (cm)"),
                    _numberField(_weightController, "Weight (kg)"),
                    _numberField(
                      _bmiController,
                      "BMI",
                      readOnly: true,
                      hint: "Auto-calculated from height and weight",
                    ),
                    if (_onDialysis)
                      _numberField(_dryWeightController, "Dry weight (kg)"),
                  ],
                ),
                _section(
                  "Medical Profile",
                  [
                    if (_canEditSensitive) ...[
                      _dropdownField(
                        label: "CKD stage",
                        value: _ckdStage,
                        options: _ckdStageOptions,
                        onChanged: (value) => setState(() => _ckdStage = value),
                      ),
                      _textField(
                        _kidneyDiseaseTypeController,
                        "Kidney disease type",
                      ),
                      _dateField(_diagnosisDateController, "Date of diagnosis"),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF00C874),
                        title: const Text("On dialysis?"),
                        value: _onDialysis,
                        onChanged: (value) {
                          setState(() {
                            _onDialysis = value;
                            if (!value) _dialysisType = null;
                          });
                        },
                      ),
                      if (_onDialysis)
                        _dropdownField(
                          label: "Dialysis type",
                          value: _dialysisType,
                          options: _dialysisTypeOptions,
                          onChanged: (value) =>
                              setState(() => _dialysisType = value),
                        ),
                      if (_onDialysis)
                        _textField(
                          _treatmentFrequencyController,
                          "Treatment frequency",
                        ),
                    ] else
                      const Text(
                        'Medical condition details are managed with your caregiver.',
                        style: TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                _section(
                  "Dietary Lifestyle",
                  [
                    if (_canEditSensitive)
                      _dropdownField(
                        label: "Diet pattern",
                        value: _dietPattern,
                        options: _dietPatternOptions,
                        onChanged: (value) =>
                            setState(() => _dietPattern = value),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Diet restriction settings are managed with your caregiver.',
                          style: TextStyle(
                            color: Color(0xFF78909C),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    _dropdownField(
                      label: "Processed food intake",
                      value: _processedFoodIntake,
                      options: _processedFoodOptions,
                      onChanged: (value) =>
                          setState(() => _processedFoodIntake = value),
                    ),
                    _dropdownField(
                      label: "Meal pattern",
                      value: _mealPattern,
                      options: _mealPatternOptions,
                      onChanged: (value) =>
                          setState(() => _mealPattern = value),
                    ),
                    _dropdownField(
                      label: "Physical activity level",
                      value: _physicalActivityLevel,
                      options: _activityOptions,
                      onChanged: (value) =>
                          setState(() => _physicalActivityLevel = value),
                    ),
                    _dropdownField(
                      label: "Preferred measurement system",
                      value: _preferredMeasurementSystem,
                      options: _measurementOptions,
                      onChanged: (value) => setState(
                        () => _preferredMeasurementSystem = value,
                      ),
                    ),
                  ],
                ),
                _section(
                  "Allergies",
                  [
                    if (_canEditSensitive)
                      _allergySelector()
                    else
                      const Text(
                        'Allergy information is managed with your caregiver.',
                        style: TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                _section(
                  "Fluid And Condition Settings",
                  [
                    if (_canEditSensitive) ...[
                      _dropdownField(
                        label: "Is fluid intake restricted?",
                        value: _fluidRestrictionStatus,
                        options: _fluidRestrictionOptions,
                        onChanged: (value) =>
                            setState(() => _fluidRestrictionStatus = value),
                      ),
                      if (_fluidRestrictionStatus == "yes")
                        _numberField(
                          _fluidLimitController,
                          "Daily fluid limit (mL)",
                          required: true,
                        ),
                      _dropdownField(
                        label: "Does the child have high blood pressure?",
                        value: _hasHypertension,
                        options: _hypertensionOptions,
                        onChanged: (value) =>
                            setState(() => _hasHypertension = value),
                      ),
                    ] else
                      const Text(
                        'Fluid restriction and blood pressure settings are managed with your caregiver.',
                        style: TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading || _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C874),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Save Profile",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: _inputDecoration(label),
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return "$label is required";
                }
                return null;
              }
            : null,
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool readOnly = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        readOnly: readOnly,
        decoration: _inputDecoration(label).copyWith(hintText: hint),
        validator: (value) {
          final text = value?.trim() ?? "";
          if (required && text.isEmpty) return "$label is required";
          if (text.isNotEmpty && double.tryParse(text) == null) {
            return "Enter a valid number";
          }
          if (controller == _ageController && text.isNotEmpty && _requiresAdolescentAgeRange) {
            final age = int.tryParse(text);
            if (age == null || age < 13 || age > 18) {
              return "Adolescent age must be between 13 and 18";
            }
          }
          return null;
        },
      ),
    );
  }

  Widget _dateField(
    TextEditingController controller,
    String label, {
    bool readOnly = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: _inputDecoration(label).copyWith(
          hintText: hint,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        onTap: readOnly ? null : () => _pickDate(controller),
        validator: controller == _dobController && _requiresAdolescentAgeRange
            ? (value) {
                if ((value ?? '').trim().isEmpty) return null;
                if (!_isAdolescentDobValid()) {
                  return 'Adolescent date of birth must stay within ages 13-18';
                }
                return null;
              }
            : null,
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: _inputDecoration(label),
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _allergySelector() {
    final selectedSummary = _selectedAllergyPayload();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSummary.isNotEmpty) ...[
          const Text(
            'Existing allergies',
            style: TextStyle(
              color: Color(0xFF546E7A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedSummary
                .map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2FBF7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFCFE9DF)),
                    ),
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allergyOptions.map((option) {
            final isSelected = _selectedAllergies.contains(option);
            return FilterChip(
              selected: isSelected,
              onSelected: (_) => _toggleAllergyOption(option),
              label: Text(option),
              selectedColor: const Color(0xFFE0F2F1),
              checkmarkColor: const Color(0xFF00796B),
              labelStyle: TextStyle(
                color: isSelected
                    ? const Color(0xFF00796B)
                    : const Color(0xFF37474F),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF80CBC4)
                    : const Color(0xFFD5E3E0),
              ),
              backgroundColor: Colors.white,
            );
          }).toList(),
        ),
        if (_selectedAllergies.contains('Other')) ...[
          const SizedBox(height: 12),
          _textField(
            _otherAllergyController,
            "Other allergy details",
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF9FBFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00C874)),
      ),
    );
  }
}
