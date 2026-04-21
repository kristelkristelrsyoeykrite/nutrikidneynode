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
  List<Map<String, dynamic>> _medications = [];

  final TextEditingController _allergiesController = TextEditingController();

  void _showAddMedicationDialog() {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final instructionsController = TextEditingController();
    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
    String frequencyType = 'times_per_day';
    int frequencyValue = 1;

    // Generate scheduled times
    List<String> _generateScheduledTimes(TimeOfDay start, String type, int value) {
      List<String> times = [];
      int interval = type == 'times_per_day' ? (24 ~/ value) : value;
      int count = type == 'times_per_day' ? value : (24 ~/ value);

      for (int i = 0; i < count; i++) {
        int hour = (start.hour + (i * interval)) % 24;
        int minute = start.minute;
        times.add(
          "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}",
        );
      }
      return times;
    }

    // Convert 24-hour time to 12-hour format with AM/PM
    String _formatTime12Hour(String time24h) {
      final parts = time24h.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

      return "$displayHour:${minute.toString().padLeft(2, '0')} $period";
    }

    // Get frequency label
    String _getFrequencyLabel(String type, int value) {
      if (type == 'times_per_day') {
        switch (value) {
          case 1:
            return 'Once daily';
          case 2:
            return '2x daily';
          case 3:
            return '3x daily';
          case 4:
            return '4x daily';
          default:
            return '$value times daily';
        }
      } else {
        return 'Every $value hours';
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
        builder: (context, setDialogState) {
          final currentSchedule =
              _generateScheduledTimes(selectedTime, frequencyType, frequencyValue);

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
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF37474F),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Medication Name
                    _buildLabel("Medication Name"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      label: "",
                      hint: "e.g. Calcium",
                      controller: nameController,
                    ),
                    const SizedBox(height: 16),

                    // Dosage
                    _buildLabel("Dosage"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      label: "",
                      hint: "e.g. 500mg",
                      controller: dosageController,
                    ),
                    const SizedBox(height: 16),

                    // Start Time Picker
                    _buildLabel("Start Time"),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              color: Color(0xFF90A4AE),
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              selectedTime.format(context),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF37474F),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Frequency Type
                    _buildLabel("Frequency Type"),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: frequencyType,
                      items: const [
                        DropdownMenuItem(
                          value: 'times_per_day',
                          child: Text('Times per day'),
                        ),
                        DropdownMenuItem(
                          value: 'interval',
                          child: Text('Interval (hours)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            frequencyType = val;
                            frequencyValue =
                                val == 'times_per_day' ? 1 : 8;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDCDCDC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDCDCDC)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Frequency Value
                    _buildLabel("Frequency"),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: frequencyValue,
                      items: (frequencyType == 'times_per_day'
                              ? [1, 2, 3, 4]
                              : [6, 8, 12])
                          .map(
                            (val) => DropdownMenuItem(
                              value: val,
                              child: Text(
                                frequencyType == 'times_per_day'
                                    ? (val == 1
                                        ? 'Once daily'
                                        : '${val}x daily')
                                    : 'Every $val hours',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => frequencyValue = val);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDCDCDC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDCDCDC)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Schedule Preview
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2FBF7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE0F2ED)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 16,
                                color: Color(0xFF00C874),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getFrequencyLabel(frequencyType, frequencyValue),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF37474F),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Scheduled times: ${currentSchedule.map((t) => _formatTime12Hour(t)).join(', ')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Instructions (Optional)
                    _buildLabel("Instructions (Optional)"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      label: "",
                      hint: "e.g. Take with water, with food",
                      controller: instructionsController,
                    ),
                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFFF0F0F0),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(
                                color: Color(0xFF37474F),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (nameController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter medication name'),
                                  ),
                                );
                                return;
                              }

                              final finalSchedule = _generateScheduledTimes(
                                selectedTime,
                                frequencyType,
                                frequencyValue,
                              );

                              setState(() {
                                final frequencyLabel = _getFrequencyLabel(
                                  frequencyType,
                                  frequencyValue,
                                );
                                final displayTimes = finalSchedule
                                    .map((t) => _formatTime12Hour(t))
                                    .join(', ');
                                final medicationName =
                                    nameController.text.trim();

                                _medications.add({
                                  "name": medicationName,
                                  "medicationName": medicationName,
                                  "medication_name": medicationName,
                                  "dosage": dosageController.text.trim(),
                                  "instructions": instructionsController.text.trim(),
                                  "frequency_type": frequencyType,
                                  "frequency_value": frequencyValue,
                                  "start_time":
                                      "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}",
                                  "scheduled_times": finalSchedule,
                                  "frequency": frequencyLabel,
                                  "display_freq": frequencyLabel,
                                  "time": displayTimes,
                                  "schedule": displayTimes,
                                  "display_times": displayTimes,
                                  "status": "Pending",
                                });
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4DB6AC),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              "Add Medication",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _buildMedicationList() {
    if (_medications.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0ECEA)),
        ),
        child: const Text(
          "No medications added yet.",
          style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
        ),
      );
    }

    return Column(
      children: _medications.map<Widget>((med) {
        final medicationName =
            (med['medication_name'] ?? med['name'] ?? 'Unknown').toString();
        final dosage = (med['dosage'] ?? '').toString();
        return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          title: Text(
            medicationName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF37474F),
              fontSize: 15,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                dosage,
                style: const TextStyle(
                  color: Color(0xFF90A4AE),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "${med['display_freq']} • ${med['display_times'] ?? med['scheduled_times'].join(', ')}",
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                ),
              ),
              if (med['instructions'] != null && med['instructions'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "📝 ${med['instructions']}",
                    style: const TextStyle(
                      color: Color(0xFFB0BEC5),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            onPressed: () => setState(() => _medications.remove(med)),
          ),
          isThreeLine: true,
        ),
      );
      }).toList(),
    );
  }

  String _medicationSummary(Map<String, dynamic> medication) {
    final name =
        (medication['medication_name'] ?? medication['name'] ?? 'Medication')
            .toString();
    final dosage = medication['dosage']?.toString().trim() ?? '';
    final frequency =
        medication['display_freq'] ?? medication['frequency'] ?? '';
    final times = medication['display_times'] ?? medication['time'] ?? '';

    return [
      name,
      if (dosage.isNotEmpty) dosage,
      if (frequency.toString().isNotEmpty) frequency,
      if (times.toString().isNotEmpty) times,
    ].join(' - ');
  }

  Widget _buildTextField({required String label, required String hint, required TextEditingController controller}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildLabel(label),
      TextField(controller: controller, decoration: InputDecoration(hintText: hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _allergiesController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
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
                      enabled: _dialysisType != null && _dialysisType != "None",
                      onChanged: (val) {
                        setState(() {
                          _treatmentFrequency = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Current Medications (Large Box)
                    _buildLabel("Current Medications"),
                    _buildMedicationList(),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _showAddMedicationDialog,
                      icon: const Icon(Icons.add),
                      label: const Text("Add Medication"),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        side: const BorderSide(color: Color(0xFF4DB6AC)),
                        foregroundColor: const Color(0xFF4DB6AC),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Allergies (Large Box)
                    _buildLargeTextField(
                      label: "Allergies (if any)",
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
                                    for (final medication in _medications) {
                                      if (medication['medicationId'] != null) {
                                        continue;
                                      }

                                      final response =
                                          await ApiService.saveMedication(
                                        medication,
                                      );
                                      if (response["success"] != true) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Unable to save medication: ${response["error"] ?? "Please try again."}",
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      medication['medicationId'] =
                                          response['medicationId'];
                                    }

                                    final medicationSummaries =
                                        _medications.map(_medicationSummary).toList();
                                    await ApiService.sendStep2({
                                      "isOnDialysis": _dialysisType != null && _dialysisType != "None",
                                      "dialysisType": _dialysisType,
                                      "treatmentFrequency": _treatmentFrequency,
                                      "medications": _medications,
                                      "medicationsSummary": medicationSummaries.join('; '),
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
              if (value == "None") {
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
