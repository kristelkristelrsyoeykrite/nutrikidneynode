import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'dashboard.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'profile.dart'; // Added Profile import

class HealthMetricsPage extends StatefulWidget {
  const HealthMetricsPage({super.key});

  @override
  State<HealthMetricsPage> createState() => _HealthMetricsPageState();
}

class _HealthMetricsPageState extends State<HealthMetricsPage> {
  int _currentIndex = 3;

  // ==========================================
  // STATE DATA
  // ==========================================

  Map<String, String> _vitals = {
    'Blood Pressure': 'Not set',
    'Weight': 'Not set',
    'Height': 'Not set',
    'Heart Rate': 'Not set',
  };

  List<Map<String, dynamic>> _medications = [];
  /*
    {
      'dosage': '500mg · 2x daily',
      'time': '8:00 AM, 8:00 PM',
      'status': 'Taken',
      'isPending': false,
    },
    {
      'time': '8:00 AM',
      'status': 'Taken',
      'isPending': false,
    },
    {
      'time': 'Meals',
      'status': 'Pending',
      'isPending': true,
    },
  ];
  */

  List<Map<String, dynamic>> _labResults = [];
  List<Map<String, dynamic>> _labHistory = [];
  bool _isLoadingHealth = true;
  String? _healthError;
  /*
    {
      'title': 'Creatinine',
      'unit': 'mg/dL',
      'status': 'Normal',
      'range': 'Range: 0.5-1.0',
      'isWarning': false,
    },
    {
      'title': 'eGFR',
      'unit': 'mL/min',
      'status': 'Monitor',
      'range': 'Range: >90',
      'isWarning': true,
    },
    {
      'title': 'Potassium',
      'unit': 'mEq/L',
      'status': 'Normal',
      'range': 'Range: 3.5-5.0',
      'isWarning': false,
    },
    {
      'title': 'Phosphorus',
      'unit': 'mEq/L',
      'status': 'Normal',
      'range': 'Range: 3.5-5.0',
      'isWarning': false,
    },
    {
      'title': 'Calcium',
      'unit': 'mEq/L',
      'status': 'Normal',
      'range': 'Range: 3.5-5.0',
      'isWarning': false,
    },
  ];
  */

  // ==========================================
  // INTERACTIVE POPUPS & MENUS
  // ==========================================

  @override
  void initState() {
    super.initState();
    _loadHealthSummary();
  }

  Future<void> _loadHealthSummary() async {
    try {
      final response = await ApiService.getHealthSummary();

      if (!mounted) return;

      if (response["success"] != true) {
        throw Exception(response["error"] ?? "Failed to load health data");
      }

      final anthropometrics = _asStringMap(response["anthropometrics"]);
      final latestLab = _asStringMap(response["latestLabResult"]);
      final labHistory = _asStringMapList(response["labResultsHistory"]);
      final medications = _asStringMapList(response["medications"]);

      setState(() {
        _vitals = _buildVitals(anthropometrics);
        _labResults = _buildLabCards(latestLab);
        _labHistory = labHistory
            .expand((lab) => _buildLabCards(lab))
            .toList();
        _medications = medications.map(_buildMedicationCardData).toList();
        _isLoadingHealth = false;
        _healthError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _vitals = _emptyVitals();
        _medications = [];
        _labResults = [];
        _labHistory = [];
        _isLoadingHealth = false;
        _healthError = e.toString();
      });
    }
  }

  Map<String, String> _emptyVitals() {
    return {
      'Blood Pressure': 'Not set',
      'Weight': 'Not set',
      'Height': 'Not set',
      'BMI': 'Not set',
      'Heart Rate': 'Not set',
    };
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  List<Map<String, dynamic>> _asStringMapList(dynamic value) {
    if (value is List) {
      return value.map(_asStringMap).where((map) => map.isNotEmpty).toList();
    }
    return [];
  }

  String _displayValue(dynamic value) {
    if (value == null) return 'Not set';
    final text = value.toString().trim();
    return text.isEmpty ? 'Not set' : text;
  }

  String _vitalValue(String key) {
    final value = _vitals[key];
    if (value == null || value.trim().isEmpty) return 'Not set';
    return value;
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
                backgroundColor: const Color(0xFF00B074),
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

  String _optionalText(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'No date';
    if (value is Map && value['_seconds'] != null) {
      final seconds = int.tryParse(value['_seconds'].toString());
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
            .toLocal()
            .toString()
            .split(' ')
            .first;
      }
    }
    final text = value.toString().trim();
    return text.isEmpty ? 'No date' : text;
  }

  Map<String, String> _buildVitals(Map<String, dynamic> anthropometrics) {
    final vitals = _emptyVitals();
    final weight = anthropometrics['weight_kg'] ?? anthropometrics['weight'];
    final height = anthropometrics['height_cm'] ?? anthropometrics['height'];
    final bmi = anthropometrics['bmi'];
    final bloodPressure = anthropometrics['blood_pressure'] ??
        anthropometrics['bloodPressure'];
    final systolic = anthropometrics['systolic'];
    final diastolic = anthropometrics['diastolic'];
    final heartRate =
        anthropometrics['heart_rate'] ?? anthropometrics['heartRate'];

    if (_displayValue(weight) != 'Not set') {
      vitals['Weight'] = _displayValue(weight);
    }
    if (_displayValue(height) != 'Not set') {
      vitals['Height'] = _displayValue(height);
    }
    if (_displayValue(bmi) != 'Not set') {
      vitals['BMI'] = _displayValue(bmi);
    }
    if (_displayValue(bloodPressure) != 'Not set') {
      vitals['Blood Pressure'] = _displayValue(bloodPressure);
    } else if (systolic != null && diastolic != null) {
      vitals['Blood Pressure'] = '$systolic/$diastolic';
    }
    if (_displayValue(heartRate) != 'Not set') {
      vitals['Heart Rate'] = _displayValue(heartRate);
    }

    return vitals;
  }

  Map<String, dynamic> _buildMedicationCardData(Map<String, dynamic> med) {
    final status = _optionalText(med['status']).isEmpty
        ? 'Pending'
        : _optionalText(med['status']);
    final dosage = _optionalText(med['dose'] ?? med['dosage']);
    final frequency = _optionalText(med['frequency']);

    return {
      'id': med['id'],
      'medicationId': med['id'] ?? med['medicationId'],
      'name': _displayValue(
        med['name'] ?? med['medicationName'] ?? med['medication_name'],
      ),
      'dosage': [
        if (dosage.isNotEmpty) dosage,
        if (frequency.isNotEmpty) frequency,
      ].join(' · '),
      'rawDosage': dosage,
      'frequency': frequency,
      'time': _displayValue(med['schedule'] ?? med['time'] ?? med['display_times']),
      'status': status,
      'isPending': status.toLowerCase() == 'pending',
      'instructions': _optionalText(med['instructions']),
      'frequency_type': med['frequency_type'],
      'frequency_value': med['frequency_value'],
      'start_time': med['start_time'],
      'scheduled_times': med['scheduled_times'],
    };
  }

  List<Map<String, dynamic>> _buildLabCards(Map<String, dynamic> lab) {
    if (lab.isEmpty) return [];

    final date = _formatDate(lab['date'] ?? lab['resultDate'] ?? lab['createdAt']);
    final cards = <Map<String, dynamic>>[];

    void addLab({
      required String title,
      required dynamic value,
      required String unit,
      required String fieldKey,
      String status = '',
    }) {
      final display = _optionalText(value);
      if (display.isEmpty || display == 'null') return;

      cards.add({
        'labResultId': lab['id'] ?? lab['labResultId'],
        'fieldKey': fieldKey,
        'title': title,
        'value': display,
        'unit': unit,
        'date': date,
        'status': status,
        'range': '',
        'isWarning': status.toLowerCase() == 'high' ||
            status.toLowerCase() == 'low',
      });
    }

    addLab(
      title: 'Creatinine',
      value: lab['creatinine'],
      unit: 'mg/dL',
      fieldKey: 'creatinine',
    );
    addLab(
      title: 'eGFR',
      value: lab['egfr'] ?? lab['eGFR'],
      unit: 'mL/min',
      fieldKey: 'egfr',
    );
    addLab(
      title: 'Potassium',
      value: lab['potassium'],
      unit: 'mEq/L',
      fieldKey: 'potassium',
    );
    addLab(
      title: 'Phosphorus',
      value: lab['phosphorus'],
      unit: 'mg/dL',
      fieldKey: 'phosphorus',
      status: _optionalText(lab['phosphorus_status']),
    );
    addLab(
      title: 'Calcium',
      value: lab['calcium'],
      unit: 'mg/dL',
      fieldKey: 'calcium',
    );
    addLab(
      title: 'Sodium',
      value: lab['sodium'],
      unit: 'mEq/L',
      fieldKey: 'sodium',
      status: _optionalText(lab['sodium_status']),
    );

    return cards;
  }

  // Action Menu: Slides up from bottom when tapping an existing item
  void _showItemManageSheet(int index, String collectionType) {
    String itemName = collectionType == 'Medication'
        ? _medications[index]['name']
        : _labResults[index]['title'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext bottomSheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Manage $itemName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF37474F),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: Colors.blueAccent,
                ),
                title: const Text('Edit Entry'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  if (collectionType == 'Medication') {
                    _showMedicationForm(editIndex: index);
                  } else {
                    _showMeasurementForm(editIndex: index);
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text('Delete Entry'),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  if (collectionType == 'Medication') {
                    final medicationId =
                        (_medications[index]['medicationId'] ??
                                _medications[index]['id'])
                            ?.toString();

                    if (medicationId == null || medicationId.isEmpty) {
                      setState(() {
                        _medications.removeAt(index);
                      });
                      return;
                    }

                    try {
                      final response =
                          await ApiService.deleteMedication(medicationId);
                      if (response["success"] != true) {
                        throw Exception(
                          response["error"] ?? "Failed to delete medication",
                        );
                      }

                      if (!mounted) return;
                      setState(() {
                        _medications.removeAt(index);
                      });
                      await _loadHealthSummary();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Medication deleted.')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Unable to delete medication: $e'),
                        ),
                      );
                    }
                  } else {
                    setState(() {
                      _labResults.removeAt(index);
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // --- NEW: History Pop-Up ---
  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled:
          true, // Allows the sheet to take up more vertical space
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height:
              MediaQuery.of(context).size.height *
              0.75, // Takes up 75% of screen
          decoration: const BoxDecoration(
            color: Color(0xFFF9FBFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lab Results History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF37474F)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable list of history
              Expanded(
                child: _labHistory.isEmpty
                    ? const Center(
                        child: Text(
                          "No lab history available.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _labHistory.length,
                        itemBuilder: (context, index) {
                          final lab = _labHistory[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lab['title'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF37474F),
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      lab['date'],
                                      style: const TextStyle(
                                        color: Color(0xFF90A4AE),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${lab['value']} ${lab['unit']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: lab['isWarning']
                                            ? Colors.orange.shade800
                                            : const Color(0xFF37474F),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (_optionalText(lab['status']).isNotEmpty)
                                      Text(
                                        lab['status'],
                                        style: TextStyle(
                                          color: lab['isWarning']
                                              ? Colors.orange
                                              : Colors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Form 1: Add/Edit Measurements (Vitals & Labs)
  void _showMeasurementForm({int? editIndex, String? initialType}) {
    final pageContext = context;
    final isEdit = editIndex != null;
    final existingLab = isEdit ? _labResults[editIndex] : null;
    bool isSavingMeasurement = false;

    String selectedType = existingLab?['title'] ?? initialType ?? 'Weight';
    final valueController = TextEditingController(
      text: existingLab?['value'] ?? '',
    );
    final dateController = TextEditingController(
      text: existingLab?['date'] ?? '',
    );

    final List<String> metricTypes = [
      'Weight',
      'Blood Pressure',
      'Heart Rate',
      'Height',
      'Creatinine',
      'eGFR',
      'Potassium',
      'Phosphorus',
      'Calcium',
    ];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                          Text(
                            isEdit ? 'Edit Measurement' : 'Log New Measurement',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _buildFormLabel('Metric Type'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        items: metricTypes
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: isEdit
                            ? null
                            : (val) => setDialogState(
                                () => selectedType = val!,
                              ), // Disable changing type if editing
                        decoration: _dropdownDecoration(),
                      ),
                      const SizedBox(height: 20),

                      _buildFormLabel('Value'),
                      const SizedBox(height: 8),
                      _buildTextFormField(valueController, 'Enter value'),
                      const SizedBox(height: 20),

                      _buildFormLabel('Date & Time'),
                      const SizedBox(height: 8),
                      _buildDatePickerFormField(
                        dialogContext,
                        dateController,
                        'Select date',
                      ),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isSavingMeasurement
                              ? null
                              : () async {
                            final measurementValue =
                                valueController.text.trim();
                            final measurementDate =
                                dateController.text.trim();
                            final isVitalMeasurement = [
                              'Blood Pressure',
                              'Weight',
                              'Height',
                              'Heart Rate',
                            ].contains(selectedType);

                            if (measurementValue.isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter a measurement value'),
                                ),
                              );
                              return;
                            }

                            if (!isVitalMeasurement &&
                                measurementDate.isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Lab result date is required.',
                                  ),
                                ),
                              );
                              return;
                            }

                            final affectsNutritionTargets = [
                              'Weight',
                              'Height',
                            ].contains(selectedType);

                            if (affectsNutritionTargets) {
                              final confirmed =
                                  await _confirmNutritionTargetUpdate();
                              if (!confirmed) return;
                            }

                            try {
                              setDialogState(() => isSavingMeasurement = true);

                              if (isVitalMeasurement) {
                                final response =
                                    await ApiService.saveMeasurement(
                                  metricType: selectedType,
                                  value: measurementValue,
                                  date: measurementDate.isEmpty
                                      ? null
                                      : measurementDate,
                                  recalculateNutritionTargets:
                                      affectsNutritionTargets,
                                );

                                if (response["success"] != true) {
                                  throw Exception(
                                    response["error"] ??
                                        "Failed to save measurement",
                                  );
                                }

                                await _loadHealthSummary();
                              } else {
                                final response =
                                    await ApiService.saveLabResult(
                                  metricType:
                                      existingLab?['fieldKey'] ?? selectedType,
                                  value: measurementValue,
                                  resultDate: measurementDate,
                                  labResultId:
                                      existingLab?['labResultId']?.toString(),
                                );

                                if (response["success"] != true) {
                                  throw Exception(
                                    response["error"] ??
                                        "Failed to save lab result",
                                  );
                                }

                                await _loadHealthSummary();
                              }

                              if (mounted) Navigator.of(dialogContext).pop();
                            } catch (e) {
                              if (!mounted) return;
                              setDialogState(() => isSavingMeasurement = false);
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B074),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: isSavingMeasurement
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Save Measurement',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                            ),
                        ),
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

  // Form 2: Add/Edit Medications with Time Picker & Frequency Scheduling
  void _showMedicationForm({int? editIndex}) {
    final pageContext = context;
    final isEdit = editIndex != null;
    final existingMed = isEdit ? _medications[editIndex] : null;

    final nameController = TextEditingController(
      text: existingMed?['name'] ?? '',
    );
    final dosageController = TextEditingController(
      text: existingMed?['rawDosage'] ?? existingMed?['dosage'] ?? '',
    );
    final instructionsController = TextEditingController(
      text: existingMed?['instructions'] ?? '',
    );

    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
    String frequencyType = 'times_per_day'; // 'times_per_day' or 'interval'
    int frequencyValue = 1;
    String status = existingMed?['status'] ?? 'Pending';
    bool isSavingMedication = false;

    // Parse existing data if editing
    if (isEdit && existingMed != null) {
      if (existingMed['start_time'] != null) {
        final parts = existingMed['start_time'].toString().split(':');
        if (parts.length == 2) {
          selectedTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 8,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
      frequencyType = existingMed['frequency_type'] ?? 'times_per_day';
      frequencyValue =
          int.tryParse(existingMed['frequency_value']?.toString() ?? '') ?? 1;
    }

    // Generate scheduled times based on start time and frequency
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
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Update scheduled times whenever frequency changes
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
                          Text(
                            isEdit ? 'Edit Medication' : 'Add Medication',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Medication Name
                      _buildFormLabel('Medication Name'),
                      const SizedBox(height: 8),
                      _buildTextFormField(nameController, 'e.g. Calcium'),
                      const SizedBox(height: 20),

                      // Dosage
                      _buildFormLabel('Dosage'),
                      const SizedBox(height: 8),
                      _buildTextFormField(dosageController, 'e.g. 500mg'),
                      const SizedBox(height: 20),

                      // Start Time Picker
                      _buildFormLabel('Start Time'),
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
                      const SizedBox(height: 20),

                      // Frequency Type
                      _buildFormLabel('Frequency Type'),
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
                                  val == 'times_per_day' ? 1 : 8; // Reset to default
                            });
                          }
                        },
                        decoration: _dropdownDecoration(),
                      ),
                      const SizedBox(height: 20),

                      // Frequency Value
                      _buildFormLabel('Frequency'),
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
                        decoration: _dropdownDecoration(),
                      ),
                      const SizedBox(height: 20),

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
                      const SizedBox(height: 20),

                      // Instructions (Optional)
                      _buildFormLabel('Instructions (Optional)'),
                      const SizedBox(height: 8),
                      _buildTextFormField(
                        instructionsController,
                        'e.g. Take with water, with food',
                      ),
                      const SizedBox(height: 20),

                      // Status
                      _buildFormLabel('Status'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: status,
                        items: ['Taken', 'Pending']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (val) => setDialogState(() => status = val!),
                        decoration: _dropdownDecoration(),
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isSavingMedication
                              ? null
                              : () async {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
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
                            final frequencyLabel = _getFrequencyLabel(
                              frequencyType,
                              frequencyValue,
                            );
                            final displayTimes = finalSchedule
                                .map((t) => _formatTime12Hour(t))
                                .join(', ');
                            final medicationId = isEdit
                                ? (existingMed?['medicationId'] ??
                                        existingMed?['id'])
                                    ?.toString()
                                : null;
                            final newMed = {
                              if (medicationId != null) 'id': medicationId,
                              if (medicationId != null)
                                'medicationId': medicationId,
                              'name': nameController.text.trim(),
                              'medicationName': nameController.text.trim(),
                              'medication_name': nameController.text.trim(),
                              'dosage': dosageController.text.trim(),
                              'dose': dosageController.text.trim(),
                              'frequency_type': frequencyType,
                              'frequency_value': frequencyValue,
                              'start_time':
                                  '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                              'scheduled_times': finalSchedule,
                              'instructions': instructionsController.text.trim(),
                              'status': status,
                              'isPending': status == 'Pending',
                              'frequency': frequencyLabel,
                              'time': displayTimes,
                              'schedule': displayTimes,
                              'display_freq': frequencyLabel,
                              'display_times': displayTimes,
                            };

                            try {
                              setDialogState(() => isSavingMedication = true);

                              if (isEdit &&
                                  medicationId != null &&
                                  medicationId.isNotEmpty) {
                                final response =
                                    await ApiService.updateMedication(
                                  medicationId,
                                  newMed,
                                );
                                if (response["success"] != true) {
                                  throw Exception(
                                    response["error"] ??
                                        "Failed to update medication",
                                  );
                                }
                              } else if (!isEdit) {
                                final response =
                                    await ApiService.saveMedication(newMed);
                                if (response["success"] != true) {
                                  throw Exception(
                                    response["error"] ??
                                        "Failed to save medication",
                                  );
                                }
                                final savedMedicationId =
                                    response["medicationId"]?.toString();
                                if (savedMedicationId != null &&
                                    savedMedicationId.isNotEmpty) {
                                  newMed['id'] = savedMedicationId;
                                  newMed['medicationId'] = savedMedicationId;
                                }
                              }

                              if (!mounted) return;
                              setState(() {
                                if (isEdit) {
                                  _medications[editIndex] = newMed;
                                } else {
                                  _medications.add(newMed);
                                }
                              });

                              Navigator.of(dialogContext).pop();
                              await _loadHealthSummary();
                              if (!mounted) return;
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Medication saved.'),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              setDialogState(() => isSavingMedication = false);
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Unable to save medication: $e',
                                  ),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B074),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: isSavingMedication
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Save Medication',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
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

  // ==========================================
  // MAIN BUILD METHOD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: SafeArea(
        child: _isLoadingHealth
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C874)),
              )
            : SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_healthError != null) ...[
                _buildHealthErrorCard(),
                const SizedBox(height: 16),
              ],
              // --- Header ---
              const Text(
                'Health Metrics',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Monitor vital signs and lab results',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14),
              ),
              const SizedBox(height: 24),

              // --- Log New Measurement Button ---
              InkWell(
                onTap: () => _showMeasurementForm(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2FBF7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00C874),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add, color: Color(0xFF00C874)),
                      SizedBox(width: 8),
                      Text(
                        'Log New Measurement',
                        style: TextStyle(
                          color: Color(0xFF00C874),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // --- Vital Signs Section ---
              const Text(
                'Vital Signs',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                childAspectRatio: 1.1,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildVitalCard(
                    'Blood Pressure',
                    _vitalValue('Blood Pressure'),
                    'mmHg',
                    Icons.favorite,
                    Colors.redAccent,
                  ),
                  _buildVitalCard(
                    'Weight',
                    _vitalValue('Weight'),
                    'kg',
                    Icons.scale,
                    Colors.greenAccent,
                  ),
                  _buildVitalCard(
                    'Height',
                    _vitalValue('Height'),
                    'cm',
                    Icons.straighten,
                    Colors.blueAccent,
                  ),
                  _buildVitalCard(
                    'BMI',
                    _vitalValue('BMI'),
                    'kg/m2',
                    Icons.analytics_outlined,
                    Colors.orangeAccent,
                  ),
                  _buildVitalCard(
                    'Heart Rate',
                    _vitalValue('Heart Rate'),
                    'bpm',
                    Icons.monitor_heart,
                    Colors.purpleAccent,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // --- Medications Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Medications',
                    style: TextStyle(
                      color: Color(0xFF37474F),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showMedicationForm(),
                    icon: const Icon(
                      Icons.add,
                      size: 18,
                      color: Color(0xFF9E86FF),
                    ),
                    label: const Text(
                      'Add',
                      style: TextStyle(
                        color: Color(0xFF9E86FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_medications.isEmpty)
                const Text(
                  "No medications added yet.",
                  style: TextStyle(color: Colors.grey),
                ),
              ..._medications.asMap().entries.map((entry) {
                int idx = entry.key;
                var med = entry.value;
                return _buildMedicationCard(
                  idx,
                  med['name'],
                  med['dosage'],
                  med['time'],
                  med['status'],
                  isPending: med['isPending'],
                );
              }).toList(),

              const SizedBox(height: 32),

              // --- Lab Results Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lab Results',
                    style: TextStyle(
                      color: Color(0xFF37474F),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Row(
                    children: [
                      // --- History Button ---
                      InkWell(
                        onTap: _showHistorySheet,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: Color(0xFF37474F),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'History',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF37474F),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Color(0xFF37474F),
                        ),
                        onSelected: (value) {
                          if (value == 'upload_lab_result') {
                            _showMeasurementForm(initialType: 'Creatinine');
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'upload_lab_result',
                            child: Text('Upload new lab result'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_labResults.isEmpty)
                const Text(
                  "No lab results recorded yet.",
                  style: TextStyle(color: Colors.grey),
                ),
              ..._labResults.asMap().entries.map((entry) {
                int idx = entry.key;
                var lab = entry.value;
                return _buildLabResultCard(
                  idx,
                  lab['title'],
                  '${lab['value']} ${lab['unit']}',
                  lab['date'],
                  lab['status'],
                  lab['range'],
                  isWarning: lab['isWarning'],
                );
              }).toList(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // ==========================================
  // COMPONENT BUILDERS
  // ==========================================

  Widget _buildHealthErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Text(
        "Health data could not be loaded: $_healthError",
        style: const TextStyle(
          color: Color(0xFF78909C),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildMedicationCard(
    int index,
    String name,
    String dosage,
    String time,
    String status, {
    bool isPending = false,
  }) {
    return InkWell(
      onTap: () => _showItemManageSheet(index, 'Medication'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.medication_outlined,
                color: Color(0xFF5C6BC0),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                  ),
                  Text(
                    dosage,
                    style: const TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(
                      color: Color(0xFFB0BEC5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isPending
                    ? const Color(0xFFFFF3E0)
                    : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: isPending ? Colors.orange : Colors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabResultCard(
    int index,
    String title,
    String value,
    String date,
    String status,
    String range, {
    bool isWarning = false,
  }) {
    return InkWell(
      onTap: () => _showItemManageSheet(index, 'Lab Result'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: isWarning
                        ? Colors.orange.shade800
                        : const Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: Color(0xFFB0BEC5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (status.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isWarning
                          ? const Color(0xFFFFF8E1)
                          : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: isWarning ? Colors.orange : Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (range.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    range,
                    style: const TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalCard(
    String title,
    String value,
    String unit,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF90A4AE),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (value != 'Not set')
            Text(
              unit,
              style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildFormLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xFF37474F),
        fontSize: 15,
      ),
    );
  }

  Widget _buildTextFormField(
    TextEditingController controller,
    String placeholder,
  ) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 15),
        filled: true,
        fillColor: const Color(0xFFF5F6FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDatePickerFormField(
    BuildContext dialogContext,
    TextEditingController controller,
    String placeholder,
  ) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: dialogContext,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF00B074),
                  onPrimary: Colors.white,
                  onSurface: Color(0xFF37474F),
                ),
              ),
              child: child!,
            );
          },
        );

        if (picked != null) {
          controller.text =
              "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        }
      },
      child: AbsorbPointer(
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 15,
            ),
            suffixIcon: const Icon(
              Icons.calendar_today_outlined,
              color: Color(0xFF90A4AE),
              size: 18,
            ),
            filled: true,
            fillColor: const Color(0xFFF5F6FA),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDCDCDC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDCDCDC)),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          else if (index == 1)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const FoodLogPage()),
            );
          else if (index == 2)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AnalyticsPage()),
            );
          else if (index == 4) // Added this logic to go to the Profile screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
          else
            setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF00C874),
        unselectedItemColor: const Color(0xFFB0BEC5),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: 'Food',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Health',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
