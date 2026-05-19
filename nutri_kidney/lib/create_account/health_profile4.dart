import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutri_kidney/services/auth_service.dart';
import '../main/dashboard.dart';
import '../main/medication_scan_flow.dart';

class HealthProfile4Page extends StatefulWidget {
  const HealthProfile4Page({super.key});

  @override
  State<HealthProfile4Page> createState() => _HealthProfile4PageState();
}

class _HealthProfile4PageState extends State<HealthProfile4Page> {
  // --- Controllers for numeric input fields ---
  final TextEditingController _creatinineController = TextEditingController();
  final TextEditingController _potassiumController = TextEditingController();
  final TextEditingController _phosphorusController = TextEditingController();
  final TextEditingController _sodiumController = TextEditingController();
  final TextEditingController _resultDateController = TextEditingController();

  // Additional optional lab fields (NEW)
  final TextEditingController _ureaController = TextEditingController();
  final TextEditingController _albumController = TextEditingController();
  final TextEditingController _hemoglobinController = TextEditingController();
  bool _expandAdditionalLabs = false;

  // --- State for dropdown selections ---
  String? _calciumLevel;
  String? _phosphorusStatus;
  String? _sodiumStatus;

  // --- Medication setup ---
  final List<Map<String, dynamic>> _medications = [];
  bool _isScanningPrescription = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isFinishingRegistration = false;
  bool _registrationCompleted = false;

  @override
  void initState() {
    super.initState();
    // Rebuild screen when text changes
    _creatinineController.addListener(() {
      setState(() {});
    });
    _potassiumController.addListener(() {
      setState(() {});
    });
    _phosphorusController.addListener(() {
      setState(() {});
    });
    _sodiumController.addListener(() {
      setState(() {});
    });
    _resultDateController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    // Clean up controllers to prevent memory leaks
    _creatinineController.dispose();
    _potassiumController.dispose();
    _phosphorusController.dispose();
    _sodiumController.dispose();
    _resultDateController.dispose();
    _ureaController.dispose();
    _albumController.dispose();
    _hemoglobinController.dispose();
    super.dispose();
  }

  // --- Helper method to display a calendar picker ---
  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4DB6AC), // NutriKidney Green
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
        // Format the date to MM/DD/YYYY
        controller.text =
            "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  Future<void> _showAddMedicationOptions() {
    return MedicationScanFlow.showAddMedicationOptions(
      context: context,
      isScanning: _isScanningPrescription,
      onScanPrescription: _scanPrescriptionForMedications,
      onManualEntry: () => _showAddMedicationDialog(),
    );
  }

  Future<void> _scanPrescriptionForMedications() {
    return MedicationScanFlow.scanPrescriptionForMedications(
      context: context,
      onScanningChanged: (isScanning) {
        if (mounted) {
          setState(() => _isScanningPrescription = isScanning);
        }
      },
      onMedicationSelected: (seedMedication) async {
        if (mounted) {
          _showAddMedicationDialog(seedMedication: seedMedication);
        }
      },
    );
  }

  void _showAddMedicationDialog({Map<String, dynamic>? seedMedication}) {
    final nameController = TextEditingController(
      text: seedMedication?['name']?.toString() ??
          seedMedication?['medicineName']?.toString() ??
          seedMedication?['medicationName']?.toString() ??
          seedMedication?['medication_name']?.toString() ??
          '',
    );
    final dosageController = TextEditingController(
      text: seedMedication?['dosage']?.toString() ?? '',
    );
    final instructionsController = TextEditingController(
      text: seedMedication?['instructions']?.toString() ?? '',
    );
    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
    String frequencyType = 'times_per_day';
    int frequencyValue = 1;

    List<String> generateScheduledTimes() {
      final interval = frequencyType == 'times_per_day'
          ? (24 ~/ frequencyValue)
          : frequencyValue;
      final count = frequencyType == 'times_per_day'
          ? frequencyValue
          : (24 ~/ frequencyValue);
      return List.generate(count, (index) {
        final hour = (selectedTime.hour + (index * interval)) % 24;
        return '${hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
      });
    }

    String formatTime(String time24h) {
      final parts = time24h.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    }

    String frequencyLabel() {
      if (frequencyType != 'times_per_day') return 'Every $frequencyValue hours';
      switch (frequencyValue) {
        case 1:
          return 'Once daily';
        case 2:
          return '2x daily';
        case 3:
          return '3x daily';
        case 4:
          return '4x daily';
        default:
          return '$frequencyValue times daily';
      }
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentSchedule = generateScheduledTimes();
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.all(20),
              backgroundColor: Colors.white,
              child: Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add Medication',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        label: 'Medication Name',
                        hint: 'e.g. Calcium',
                        controller: nameController,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        label: 'Dosage',
                        hint: 'e.g. 500mg',
                        controller: dosageController,
                      ),
                      const SizedBox(height: 16),
                      _buildLabel('Start Time'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: dialogContext,
                            initialTime: selectedTime,
                          );
                          if (picked != null && context.mounted) {
                            setDialogState(() => selectedTime = picked);
                          }
                        },
                        icon: const Icon(Icons.access_time),
                        label: Text(selectedTime.format(context)),
                      ),
                      const SizedBox(height: 16),
                      _buildLabel('Frequency'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: frequencyType,
                        decoration: _inputDecoration('Frequency type'),
                        items: const [
                          DropdownMenuItem(
                            value: 'times_per_day',
                            child: Text('Times per day'),
                          ),
                          DropdownMenuItem(
                            value: 'every_x_hours',
                            child: Text('Every X hours'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            frequencyType = value;
                            frequencyValue = 1;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: frequencyValue,
                        decoration: _inputDecoration(
                          frequencyType == 'times_per_day'
                              ? 'Times per day'
                              : 'Every X hours',
                        ),
                        items: (frequencyType == 'times_per_day'
                                ? const [1, 2, 3, 4]
                                : const [4, 6, 8, 12])
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => frequencyValue = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${frequencyLabel()} at ${currentSchedule.map(formatTime).join(', ')}',
                        style: const TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        label: 'Instructions',
                        hint: 'e.g. Take with food',
                        controller: instructionsController,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter medication name',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final schedule = generateScheduledTimes();
                                final medication = {
                                  'name': name,
                                  'medicationName': name,
                                  'medication_name': name,
                                  'dosage': dosageController.text.trim(),
                                  'frequency': frequencyLabel(),
                                  'frequency_type': frequencyType,
                                  'frequency_value': frequencyValue,
                                  'time': schedule.join(', '),
                                  'display_times':
                                      schedule.map(formatTime).join(', '),
                                  'scheduled_times': schedule,
                                  'instructions':
                                      instructionsController.text.trim(),
                                  if (seedMedication?['form'] != null)
                                    'form': seedMedication?['form'],
                                  if (seedMedication?['duration'] != null)
                                    'duration': seedMedication?['duration'],
                                  if (seedMedication?['rxcui'] != null)
                                    'rxcui': seedMedication?['rxcui'],
                                  if (seedMedication?['rawOcrText'] != null)
                                    'rawOcrText':
                                        seedMedication?['rawOcrText'],
                                  'source':
                                      seedMedication?['source'] ??
                                      'manual_entry',
                                };
                                setState(() => _medications.add(medication));
                                Navigator.pop(dialogContext);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C874),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Add Medication'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- POPUP: Finish Completion Dialog ---
  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String? _summaryTextFrom(dynamic value) {
    final map = _asStringMap(value);
    if (map == null) return null;

    final summary = (map['summary_text'] ?? map['summaryText'])?.toString().trim();
    if (summary != null && summary.isNotEmpty) return summary;

    final recommendations = map['recommendations'] ?? map['insights'];
    if (recommendations is List && recommendations.isNotEmpty) {
      return recommendations
          .map((note) => '- ${note.toString()}')
          .join('\n');
    }

    return null;
  }

  Widget _buildSummaryCard({
    required String title,
    required String text,
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  void _showFinishDialog([
    Map<String, dynamic>? baselineTargets,
    Map<String, dynamic>? phase2DecisionSupport,
  ]) {
    final summaryText = _summaryTextFrom(baselineTargets);
    final phase2Text = _summaryTextFrom(phase2DecisionSupport);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text.rich(
                  TextSpan(
                    text:
                        'You’ve successfully created your account, Welcome to ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                    children: [
                      TextSpan(
                        text: 'NutriKidney!',
                        style: TextStyle(
                          color: Color(0xFF009663), // Welcome_continue green
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                if ((summaryText != null && summaryText.isNotEmpty) ||
                    (phase2Text != null && phase2Text.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (summaryText != null && summaryText.isNotEmpty)
                            _buildSummaryCard(
                              title: 'Baseline Nutrition Targets',
                              text: summaryText,
                              backgroundColor: const Color(0xFFF5FAF8),
                              borderColor: const Color(0xFFE0F2ED),
                            ),
                          if (phase2Text != null && phase2Text.isNotEmpty)
                            _buildSummaryCard(
                              title: 'Decision Support Notes',
                              text: phase2Text,
                              backgroundColor: const Color(0xFFFFFAF0),
                              borderColor: const Color(0xFFFFECB3),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // OK Button
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DashboardPage(),
                      ),
                      (Route<dynamic> route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFF00C874,
                    ), // welcome_continue green
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 30,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
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
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  MediaQuery.of(context).viewInsets.bottom + 100,
                ),
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
                          'Step 4 of 4',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF90A4AE),
                          ),
                        ),
                        Text(
                          '100% Complete',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF4DB6AC),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: 1.0, // 100% complete
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFF37474F),
                      minHeight: 4,
                    ),
                    const SizedBox(height: 16),

                    // Sub-header for this specific page
                    const Center(
                      child: Text(
                        'Laboratory Results and Medicine Prescription (Optional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78909C),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Adding lab results and prescription helps us provide more accurate recommendations',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB0BEC5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Form Fields ---

                    // Optional note (NEW)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Text(
                        "Optional but recommended for personalized guidance.",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF555555),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 2x2 grid for numeric inputs
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.55,
                      children: [
                        _buildTextField(
                          label: "Serum Creatinine (mg/dL)",
                          hint: "9.8",
                          controller: _creatinineController,
                          keyboardType: TextInputType.number,
                        ),
                        _buildTextField(
                          label: "Potassium (mEq/L)",
                          hint: "9.8",
                          controller: _potassiumController,
                          keyboardType: TextInputType.number,
                        ),
                        _buildTextField(
                          label: "Phosphorus (mg/dL)",
                          hint: "9.8",
                          controller: _phosphorusController,
                          keyboardType: TextInputType.number,
                        ),
                        _buildTextField(
                          label: "Sodium (mEq/L)",
                          hint: "9.8",
                          controller: _sodiumController,
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Calcium Dropdown
                    _buildDropdownField(
                      label: "Calcium (mg/dL)",
                      hint: "9.8",
                      value: _calciumLevel,
                      items: [
                        "8.5",
                        "9.0",
                        "9.5",
                        "10.0",
                        "10.5+",
                      ], // replace with real range
                      onChanged: (val) {
                        setState(() {
                          _calciumLevel = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildDropdownField(
                      label: "Phosphorus Status",
                      hint: "Select phosphorus status",
                      value: _phosphorusStatus,
                      items: const ["normal", "high", "low"],
                      onChanged: (val) {
                        setState(() {
                          _phosphorusStatus = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildDropdownField(
                      label: "Sodium Status",
                      hint: "Select sodium status",
                      value: _sodiumStatus,
                      items: const ["normal", "high", "low"],
                      onChanged: (val) {
                        setState(() {
                          _sodiumStatus = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Result Date Picker (Functioning as DatePicker but styled like Dropdown)
                    _buildDatePickerField(
                      label: _hasStep4LabDataWithoutDate()
                          ? "Result Date (Required)"
                          : "Result Date",
                      hint: "Enter the date of release",
                      controller: _resultDateController,
                      helperText: _hasStep4LabDataWithoutDate()
                          ? "Required"
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // --- Additional Labs Section (Expandable) ---
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _expandAdditionalLabs = !_expandAdditionalLabs;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Additional Laboratory Values",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF37474F),
                              ),
                            ),
                            Icon(
                              _expandAdditionalLabs
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expandAdditionalLabs)
                      Column(
                        children: [
                          const SizedBox(height: 12),
                          _buildTextField(
                            label: "Urea/BUN (mg/dL)",
                            hint: "Optional",
                            controller: _ureaController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            label: "Albumin (g/dL)",
                            hint: "Optional",
                            controller: _albumController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            label: "Hemoglobin (g/dL)",
                            hint: "Optional",
                            controller: _hemoglobinController,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),

                    const SizedBox(height: 24),
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
                                Navigator.pop(context); // Go back to Step 3
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
                        // Finish Button (changes to "Skip and finish" when all fields are empty)
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _hasStep4LabDataWithoutDate()
                                  ? null
                                  : _showProceedDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF00BFA5,
                                ), // Primary teal
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                _isStep4Empty() ? 'Skip and finish' : 'Finish',
                                style: const TextStyle(
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
            // Medication setup is handled in the Health Metrics page.
          ],
        ),
      ),
    );
  }
void _showLoadingDialog(String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => WillPopScope(
      onWillPop: () async => false, // Prevent dismissal by back button
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF37474F),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _handleFinishRegistration() async {
  if (_isFinishingRegistration || _registrationCompleted) return;

  if (_hasStep4LabDataWithoutDate()) {
    _showMissingLabDateMessage();
    return;
  }

  setState(() {
    _isFinishingRegistration = true;
  });

  try {
    final existingUserId =
        ApiService.userId ?? ApiService.signupData["uid"] as String?;
    if ((existingUserId == null || existingUserId.trim().isEmpty) &&
        ApiService.signupData.isEmpty) {
      throw Exception("Signup data missing. Please log in again.");
    }

    if (existingUserId != null && existingUserId.trim().isNotEmpty) {
      print("Existing user already created earlier: $existingUserId");
    } else {
      // Phone-number sign-up is no longer supported.
      final phone = ApiService.signupData["phoneNumber"] as String?;
      if (phone != null && phone.trim().isNotEmpty) {
        throw Exception("Phone-number sign-up is no longer supported. Please create your account with an email address.");
      } else {
        // EMAIL-BASED SIGNUP FLOW
        _showLoadingDialog("Preparing email verification...");
        try {
          final signupData = ApiService.signupData;
          final signupEmail = signupData["email"] as String?;
          final signupPassword = signupData["password"] as String?;
          final signupFullName = signupData["fullName"] as String?;

        if (signupEmail != null && signupEmail.isNotEmpty && signupPassword != null && signupPassword.isNotEmpty) {
          // Step 1.5: Validate email format
          if (!_isValidEmail(signupEmail)) {
            _updateLoadingDialog("Verifying email domain...");
          }

          // Step 1.6: Verify email domain has mail servers
          try {
            final verifyDomainResp = await ApiService.verifyEmailDomain({"email": signupEmail});
            if (verifyDomainResp["success"] == true && verifyDomainResp["valid"] != true) {
              Navigator.pop(context); // Close loading dialog
              throw Exception(verifyDomainResp["message"] ?? "Email domain is invalid. Please check the email address.");
            }
            if (verifyDomainResp["success"] != true) {
              Navigator.pop(context); // Close loading dialog
              throw Exception('Unable to verify email domain. Check the email address.');
            }
            print("✅ Email domain verified: ${verifyDomainResp["message"]}");
          } catch (e) {
            Navigator.pop(context); // Close loading dialog
            if (e.toString().contains('domain') || e.toString().contains('valid')) {
              rethrow;
            }
            print('Email domain check error: $e');
            throw Exception('Could not verify email domain: $e');
          }

          // Step 2: Notify backend that client will handle email verification
          print("Starting client-side email verification...");
          _updateLoadingDialog("Sending verification email...");
          try {
            final sendVerifyResponse = await ApiService.startEmailVerification({
              "email": signupEmail,
              "fullName": signupFullName,
            });

            if (sendVerifyResponse["success"] != true) {
              Navigator.pop(context); // Close loading dialog
              throw Exception(sendVerifyResponse["error"] ?? "Failed to start verification");
            }

            // Step 3: Create Firebase Auth user on CLIENT (temporarily)
            _updateLoadingDialog("Creating your account...");
            UserCredential? cred;
            try {
              cred = await _auth.createUserWithEmailAndPassword(
                email: signupEmail,
                password: signupPassword,
              );
            } on FirebaseAuthException catch (e) {
              if (e.code == 'email-already-in-use') {
                // Try to sign in instead
                try {
                  cred = await _auth.signInWithEmailAndPassword(
                    email: signupEmail,
                    password: signupPassword,
                  );
                } catch (e2) {
                  Navigator.pop(context); // Close loading dialog
                  throw Exception('Failed to authenticate: $e2');
                }
              } else {
                Navigator.pop(context); // Close loading dialog
                throw Exception('Firebase error: ${e.message}');
              }
            }

            // Step 4: Send verification email via Firebase SDK
            print("Sending verification email via Firebase...");
            _updateLoadingDialog("Finalizing setup...");
            final user = cred!.user ?? _auth.currentUser;
            if (user != null && !user.emailVerified) {
              try {
                // Send verification email - Firebase will handle the email sending
                await user.sendEmailVerification();
                print('✅ Verification email sent to ${user.email}');
                print('📧 Please check your email (including spam/junk folder)');
              } catch (e) {
                Navigator.pop(context); // Close loading dialog
                print('❌ Error sending verification: $e');
                print('Firebase User Email: ${user.email}');
                print('Firebase User ID: ${user.uid}');
                throw Exception('Failed to send verification email: $e');
              }
            }

            Navigator.pop(context); // Close the loading dialog

            // Step 5: Show dialog and wait for verification
            bool emailVerified = false;
            while (!emailVerified) {
              if (!mounted) return;

              final okPressed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Verify Your Email'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A verification link has been sent to your email. Click the link in your email to verify your account. If you do not receive the email, please check that your email address was entered correctly.',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Email: $signupEmail',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('I have verified'),
                    ),
                  ],
                ),
              );

              if (okPressed != true) {
                // User cancelled - delete the Firebase Auth user to prevent clutter
                try {
                  final currentUser = _auth.currentUser;
                  if (currentUser != null) {
                    await currentUser.delete();
                    print('❌ Verification cancelled - Firebase user deleted');
                  }
                } catch (deleteError) {
                  print('Error deleting user: $deleteError');
                }
                throw Exception('Email verification required');
              }

              // Step 6: Check Firebase verification status
              _showLoadingDialog("Checking verification status...");
              try {
                await _auth.currentUser?.reload();
                final reloadedUser = _auth.currentUser;
                
                if (reloadedUser?.emailVerified == true) {
                  emailVerified = true;
                  print("✅ Email verified successfully");
                  Navigator.pop(context); // Close loading dialog
                } else {
                  Navigator.pop(context); // Close loading dialog
                  if (!mounted) return;
                  await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Not Verified Yet'),
                      content: const Text('Please click the verification link in your email and try again.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context); // Close loading dialog
                print('Error reloading user: $e');
                if (!mounted) return;
                await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Error'),
                    content: Text('Failed to check verification: $e'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            }

            // Step 7: Email verified - create user + profile in backend
            if (emailVerified && mounted) {
              _showLoadingDialog("Finalizing your account...");
              try {
                // Notify backend that email is verified
                await ApiService.verifyEmailToken({
                  "email": signupEmail,
                });

                // Now create the user + profile
                final createUserResponse = await ApiService.createUserAfterEmailVerification({
                  "email": signupEmail,
                  "password": signupPassword,
                  "fullName": signupFullName,
                  "phoneNumber": signupData["phoneNumber"],
                });

                if (createUserResponse["success"] != true) {
                  Navigator.pop(context); // Close loading dialog
                  throw Exception(createUserResponse["error"] ?? "Failed to create account");
                }

                print("Email-verified account created successfully");
                Navigator.pop(context); // Close loading dialog
              } catch (e) {
                Navigator.pop(context); // Close loading dialog
                print('Error creating account: $e');
                throw Exception('Account creation failed: $e');
              }
            }
          } catch (e) {
            print('Email verification flow error: $e');
            
            // Clean up: delete the Firebase Auth user if verification failed
            try {
              final currentUser = _auth.currentUser;
              if (currentUser != null) {
                await currentUser.delete();
                print('🗑️ Verification failed - Firebase user deleted');
              }
            } catch (deleteError) {
              print('Error deleting user during cleanup: $deleteError');
            }
            
            throw Exception('Email verification failed: $e');
          }
        }
        } catch (e) {
          Navigator.pop(context); // Close loading dialog
          throw e;
        }
      }
    }

    if (_medications.isNotEmpty) {
      _showLoadingDialog("Saving medications...");
      try {
        for (final medication in _medications) {
          if (medication['medicationId'] != null) continue;

          final response = await ApiService.saveMedication(medication);
          if (response["success"] != true) {
            throw Exception(
              response["error"] ?? "Unable to save medication.",
            );
          }
          medication['id'] = response['medicationId'];
          medication['medicationId'] = response['medicationId'];
        }
        Navigator.pop(context); // Close loading dialog
      } catch (e) {
        Navigator.pop(context); // Close loading dialog
        throw Exception('Failed to save medications: $e');
      }
    }

    final medicationSummaries = _medications.map(_medicationSummary).toList();

    // SEND STEP 4 DATA only if fields or medications were provided
    if (!_isStep4Empty()) {
      _showLoadingDialog("Saving lab results...");
      try {
        await ApiService.sendStep4({
          "creatinine": _creatinineController.text,
          "potassium": _potassiumController.text,
          "phosphorus": _phosphorusController.text,
          "sodium": _sodiumController.text,
          "sodium_status": _sodiumStatus,
          "calcium": _calciumLevel,
          "phosphorus_status": _phosphorusStatus,
          "resultDate": _resultDateController.text,
          "medications": _medications,
          "medicationsSummary": medicationSummaries.join('; '),
        });
        Navigator.pop(context); // Close loading dialog
      } catch (e) {
        Navigator.pop(context); // Close loading dialog
        throw Exception('Failed to save lab results: $e');
      }
    }

    // THEN SUBMIT ALL DATA TO DATABASE
    _showLoadingDialog("Completing registration...");
    try {
      final submitResponse = await ApiService.submitAll();
      Navigator.pop(context); // Close loading dialog

      if (submitResponse["success"] == true) {
        _registrationCompleted = true;
        final targets = submitResponse["baselineTargets"];
        final phase2 = submitResponse["phase2DecisionSupport"];
        _showFinishDialog(
          _asStringMap(targets),
          _asStringMap(phase2),
        ); // SHOW FINAL SUCCESS DIALOG
      } else {
        throw Exception(submitResponse["error"] ?? "Failed to save data");
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      throw e;
    }

  } catch (e) {
    if (mounted) {
      setState(() {
        _isFinishingRegistration = false;
      });
    }
    print("Registration Error: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$e"),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

void _updateLoadingDialog(String message) {
  // Replace the current loading message without closing and reopening
  Navigator.of(context).pop(); // Close current loading dialog
  _showLoadingDialog(message);    // Show new one with updated message
}

void _showProceedDialog() {
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Proceed?",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF37474F),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Make sure the details are correct. Entering accurate data will help provide better insights.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF78909C),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  // REVIEW BUTTON
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close dialog
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE0E0E0),
                      ),
                      child: const Text(
                        "Review",
                        style: TextStyle(color: Color(0xFF37474F)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // PROCEED BUTTON
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close dialog
                        _handleFinishRegistration(); // Start verification with loading indicators
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C874),
                      ),
                      child: const Text(
                        "Proceed",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

  String _medicationSummary(Map<String, dynamic> medication) {
    final name =
        (medication['medication_name'] ?? medication['name'] ?? 'Medication')
            .toString();
    final dosage = medication['dosage']?.toString().trim() ?? '';
    final frequency =
        (medication['display_freq'] ?? medication['frequency'] ?? '')
            .toString()
            .trim();
    final times =
        (medication['display_times'] ?? medication['time'] ?? '')
            .toString()
            .trim();
    return [
      name,
      if (dosage.isNotEmpty) dosage,
      if (frequency.isNotEmpty) frequency,
      if (times.isNotEmpty) times,
    ].join(' - ');
  }

  Widget _buildMedicationList() {
    if (_medications.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text(
          "No medications added yet.",
          style: TextStyle(color: Color(0xFF78909C), fontSize: 12),
        ),
      );
    }

    return Column(
      children: _medications.map((medication) {
        final name =
            (medication['medication_name'] ?? medication['name'] ?? 'Medication')
                .toString();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.medication_outlined, color: Color(0xFF4DB6AC)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _medicationSummary(medication),
                      style: const TextStyle(
                        color: Color(0xFF78909C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _medications.remove(medication)),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFE57373)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _isStep4Empty() {
    return _creatinineController.text.trim().isEmpty &&
        _potassiumController.text.trim().isEmpty &&
        _phosphorusController.text.trim().isEmpty &&
        (_phosphorusStatus == null || _phosphorusStatus!.trim().isEmpty) &&
        _sodiumController.text.trim().isEmpty &&
        (_sodiumStatus == null || _sodiumStatus!.trim().isEmpty) &&
        (_calciumLevel == null || _calciumLevel!.trim().isEmpty) &&
        _resultDateController.text.trim().isEmpty &&
        _medications.isEmpty;
  }

  bool _hasStep4LabDataWithoutDate() {
    final hasLabData = _creatinineController.text.trim().isNotEmpty ||
        _potassiumController.text.trim().isNotEmpty ||
        _phosphorusController.text.trim().isNotEmpty ||
        (_phosphorusStatus != null && _phosphorusStatus!.trim().isNotEmpty) ||
        _sodiumController.text.trim().isNotEmpty ||
        (_sodiumStatus != null && _sodiumStatus!.trim().isNotEmpty) ||
        (_calciumLevel != null && _calciumLevel!.trim().isNotEmpty);

    return hasLabData && _resultDateController.text.trim().isEmpty;
  }

  void _showMissingLabDateMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lab result date is required.'),
      ),
    );
  }

  // --- Email Validation Helper ---
  bool _isValidEmail(String email) {
    // Simple email validation
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  
  // --- UI Helper Methods ---
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: _buildRequiredLabel(
        text,
        baseStyle: const TextStyle(
          color: Color(0xFF9E86FF),
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildRequiredLabel(String label, {TextStyle? baseStyle}) {
    const marker = " (Required)";
    if (!label.endsWith(marker)) {
      return Text(label, style: baseStyle);
    }
    return Text.rich(
      TextSpan(
        text: label.substring(0, label.length - marker.length),
        style: baseStyle,
        children: const [
          TextSpan(
            text: marker,
            style: TextStyle(color: Color(0xFFD32F2F)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF4DB6AC)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Widget _buildDatePickerField({
    required String label,
    required String hint,
    required TextEditingController controller,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        GestureDetector(
          onTap: () => _selectDate(context, controller),
          child: AbsorbPointer(
            // Prevents keyboard from opening
            child: Container(
              height: 45,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextFormField(
                controller: controller,
                style: const TextStyle(color: Color(0xFF37474F), fontSize: 13),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  suffixIcon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (helperText != null) _buildValidationHint(helperText),
      ],
    );
  }

  Widget _buildValidationHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFD32F2F),
          fontSize: 11,
          height: 1.3,
        ),
      ),
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

  // Helper method to build the tappable camera/folder columns in the popup
  Widget _buildTappableIconColumn(IconData icon, String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE), // Light grey background
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.grey.shade600, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF37474F)),
        ),
      ],
    );
  }
}
