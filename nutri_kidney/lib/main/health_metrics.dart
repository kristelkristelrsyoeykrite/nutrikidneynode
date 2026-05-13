import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nutri_kidney/main/medication_scan_flow.dart';
import 'package:nutri_kidney/main/health_metrics_widgets.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:nutri_kidney/services/notification_service.dart';
import 'dashboard.dart';
import 'food_log.dart';
import 'analytics.dart';
import 'profile.dart'; // Added Profile import

class HealthMetricsPage extends StatefulWidget {
  const HealthMetricsPage({
    super.key,
    this.profileUserId,
    this.caregiverNoChildEmptyState = false,
  });

  final String? profileUserId;
  final bool caregiverNoChildEmptyState;

  @override
  State<HealthMetricsPage> createState() => _HealthMetricsPageState();
}

class _HealthMetricsPageState extends State<HealthMetricsPage> {
  static final Map<String, List<Map<String, dynamic>>> _medicationCache = {};
  static final Map<String, List<Map<String, dynamic>>> _labResultCache = {};
  static final Map<String, List<Map<String, dynamic>>> _labHistoryCache = {};

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
    },2222222
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
  bool _isScanningPrescription = false;
  bool _isLoadingHealth = true;
  String? _healthError;
  bool _resolvedCaregiverNoChildEmptyState = false;
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
    _resolvedCaregiverNoChildEmptyState = widget.caregiverNoChildEmptyState;
    if (!widget.caregiverNoChildEmptyState) {
      _loadCachedMedications();
      _loadCachedLabResults();
      _loadHealthSummary();
    } else {
      _isLoadingHealth = false;
    }
  }

  String get _medicationCacheKey => widget.profileUserId ?? '_self';

  void _loadCachedMedications() {
    final cached = _medicationCache[_medicationCacheKey];
    if (cached == null || cached.isEmpty) return;
    _medications = cached
        .map((medication) => Map<String, dynamic>.from(medication))
        .toList();
    _isLoadingHealth = false;
  }

  void _cacheMedications() {
    _medicationCache[_medicationCacheKey] = _medications
        .map((medication) => Map<String, dynamic>.from(medication))
        .toList();
  }

  String get _labCacheKey => widget.profileUserId ?? '_self';

  void _loadCachedLabResults() {
    final cachedResults = _labResultCache[_labCacheKey];
    final cachedHistory = _labHistoryCache[_labCacheKey];
    if ((cachedResults == null || cachedResults.isEmpty) &&
        (cachedHistory == null || cachedHistory.isEmpty)) {
      return;
    }
    if (cachedResults != null) {
      _labResults = cachedResults
          .map((lab) => Map<String, dynamic>.from(lab))
          .toList();
    }
    if (cachedHistory != null) {
      _labHistory = cachedHistory
          .map((lab) => Map<String, dynamic>.from(lab))
          .toList();
    }
    _isLoadingHealth = false;
  }

  void _cacheLabResults() {
    _labResultCache[_labCacheKey] = _labResults
        .map((lab) => Map<String, dynamic>.from(lab))
        .toList();
    _labHistoryCache[_labCacheKey] = _labHistory
        .map((lab) => Map<String, dynamic>.from(lab))
        .toList();
  }

  Future<void> _loadHealthSummary() async {
    try {
      if (await _shouldShowCaregiverEmptyState()) {
        if (!mounted) return;
        setState(() {
          _resolvedCaregiverNoChildEmptyState = true;
          _isLoadingHealth = false;
        });
        return;
      }
      final response = await ApiService.getHealthSummary(
        profileUserId: widget.profileUserId,
      );

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
        _cacheMedications();
        _cacheLabResults();
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
        _cacheLabResults();
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

  String _formatTime12Hour(String time24h) {
    final parts = time24h.split(':');
    if (parts.length != 2) return time24h;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
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
    final dosage = _optionalText(med['dose'] ?? med['dosage']);
    final frequency = _optionalText(med['frequency']);
    final takenTimesToday = med['takenTimesToday'] is List
        ? (med['takenTimesToday'] as List)
            .map((t) => t.toString())
            .where((t) => t.trim().isNotEmpty)
            .toList()
        : <String>[];
    final nextDoseTime24h = _optionalText(med['nextDoseTime']);
    final scheduleTimes = med['scheduled_times'] is List
        ? (med['scheduled_times'] as List)
            .map((t) => t.toString())
            .where((t) => t.trim().isNotEmpty)
            .toList()
        : <String>[];

    final missedCountToday = int.tryParse(med['missedCountToday']?.toString() ?? '') ?? 0;

    final status = missedCountToday > 0
        ? 'Missed'
        : takenTimesToday.isNotEmpty
            ? 'Taken'
            : 'Pending';
    final isPending = status.toLowerCase() == 'pending';
    final isMissed = status.toLowerCase() == 'missed';
    final shouldShowUpcomingNote =
        status == 'Taken' &&
        scheduleTimes.length > 1 &&
        nextDoseTime24h.isNotEmpty;
    final upcomingNote = shouldShowUpcomingNote
        ? 'Upcoming ${_formatTime12Hour(nextDoseTime24h)}'
        : null;

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
      'isPending': isPending,
      'isMissed': isMissed,
      'note': upcomingNote,
      'instructions': _optionalText(med['instructions']),
      'frequency_type': med['frequency_type'],
      'frequency_value': med['frequency_value'],
      'start_time': med['start_time'],
      'scheduled_times': med['scheduled_times'],
      'takenTimesToday': takenTimesToday,
      'nextDoseTime': nextDoseTime24h,
      'missedCountToday': missedCountToday,
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

    List<String> medicationDoseTimes(Map<String, dynamic> medication) {
      final scheduled = medication['scheduled_times'];
      if (scheduled is List && scheduled.isNotEmpty) {
        return scheduled
            .map((t) => t.toString().trim())
            .where((t) => RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t))
            .toList();
      }
      final start = _optionalText(medication['start_time']);
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(start)) return [start];
      return [];
    }

    String formatTime12Hour(String time24h) {
      final parts = time24h.split(':');
      if (parts.length != 2) return time24h;
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    }

    bool isMedicationDoseTaken(Map<String, dynamic> medication, String time) {
      final takenTimes = medication['takenTimesToday'];
      if (takenTimes is! List) return false;
      return takenTimes.map((t) => t.toString().trim()).contains(time.trim());
    }

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
              if (collectionType == 'Medication')
                ListTile(
                  leading: Icon(
                    (_medications[index]['takenTimesToday'] is List &&
                            (_medications[index]['takenTimesToday'] as List)
                                .isNotEmpty)
                        ? Icons.undo_outlined
                        : Icons.check_circle_outline,
                    color: (_medications[index]['takenTimesToday'] is List &&
                            (_medications[index]['takenTimesToday'] as List)
                                .isNotEmpty)
                        ? Colors.orange
                        : const Color(0xFF2E7D32),
                  ),
                  title: Text(
                    (_medications[index]['takenTimesToday'] is List &&
                            (_medications[index]['takenTimesToday'] as List)
                                .isNotEmpty)
                        ? 'Mark as untaken'
                        : 'Mark as taken',
                  ),
                  onTap: () async {
                    Navigator.pop(bottomSheetContext);
                    final medication =
                        Map<String, dynamic>.from(_medications[index]);
                    final medicationId =
                        (medication['medicationId'] ?? medication['id'])
                            ?.toString();
                    if (medicationId == null || medicationId.isEmpty) return;

                    final times = medicationDoseTimes(medication);
                    if (times.isEmpty) return;

                    String? selectedTime;
                    if (times.length == 1) {
                      selectedTime = times.first;
                    } else {
                      selectedTime = await showModalBottomSheet<String>(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        builder: (context) {
                          return SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select dose time',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF37474F),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...times.map(
                                    (time) {
                                      final isTaken =
                                          isMedicationDoseTaken(medication, time);
                                      return ListTile(
                                        leading: Icon(
                                          isTaken
                                              ? Icons.undo_outlined
                                              : Icons.check_circle_outline,
                                          color: isTaken
                                              ? Colors.orange
                                              : const Color(0xFF2E7D32),
                                        ),
                                        title: Text(formatTime12Hour(time)),
                                        subtitle:
                                            Text(isTaken ? 'Taken' : 'Not taken'),
                                        onTap: () =>
                                            Navigator.pop(context, time),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }

                    if (selectedTime == null || selectedTime.isEmpty) return;

                    try {
                      final isTaken =
                          isMedicationDoseTaken(medication, selectedTime);
                      final response = isTaken
                          ? await ApiService.markMedicationUntaken(
                              medicationId,
                              time: selectedTime,
                              profileUserId: widget.profileUserId,
                            )
                          : await ApiService.markMedicationTaken(
                              medicationId,
                              time: selectedTime,
                              profileUserId: widget.profileUserId,
                            );
                      if (response["success"] != true) {
                        throw Exception(
                          response["error"] ??
                              "Failed to update medication status",
                        );
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isTaken
                                ? 'Marked as untaken for ${formatTime12Hour(selectedTime)}.'
                                : 'Marked as taken for ${formatTime12Hour(selectedTime)}.',
                          ),
                        ),
                      );
                      await _loadHealthSummary();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Unable to update medication: $e'),
                        ),
                      );
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
                      final removedMedication =
                          Map<String, dynamic>.from(_medications[index]);
                      setState(() {
                        _medications.removeAt(index);
                        _cacheMedications();
                      });
                      unawaited(
                        NotificationService.syncSingleMedicationReminder(
                          medication: {
                            ...removedMedication,
                            'status': 'Taken',
                            'isPending': false,
                          },
                          previousMedication: removedMedication,
                          profileUserId: widget.profileUserId,
                        ),
                      );
                      return;
                    }

                    final removedMedication =
                        Map<String, dynamic>.from(_medications[index]);
                    setState(() {
                      _medications.removeAt(index);
                      _cacheMedications();
                    });

                    try {
                      final response = await ApiService.deleteMedication(
                        medicationId,
                        profileUserId: widget.profileUserId,
                      );
                      if (response["success"] != true) {
                        throw Exception(
                          response["error"] ?? "Failed to delete medication",
                        );
                      }

                      if (!mounted) return;
                      unawaited(
                        NotificationService.syncSingleMedicationReminder(
                          medication: {
                            ...removedMedication,
                            'status': 'Taken',
                            'isPending': false,
                          },
                          previousMedication: removedMedication,
                          profileUserId: widget.profileUserId,
                        ),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Medication deleted.')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        final insertIndex = index < 0
                            ? 0
                            : (index > _medications.length
                                ? _medications.length
                                : index);
                        _medications.insert(insertIndex, removedMedication);
                        _cacheMedications();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Unable to delete medication: $e'),
                        ),
                      );
                    }
                    return;
                  }

                  final labResultId = _labResults[index]['labResultId']?.toString();
                  final metricType = _labResults[index]['fieldKey']?.toString();
                  if (labResultId == null ||
                      labResultId.isEmpty ||
                      metricType == null ||
                      metricType.isEmpty) {
                    setState(() {
                      _labResults.removeAt(index);
                      _cacheLabResults();
                    });
                    return;
                  }

                  final removedLab = Map<String, dynamic>.from(_labResults[index]);
                  final previousLabResults = _labResults
                      .map((lab) => Map<String, dynamic>.from(lab))
                      .toList();
                  final previousLabHistory = _labHistory
                      .map((lab) => Map<String, dynamic>.from(lab))
                      .toList();
                  setState(() {
                    _labResults.removeAt(index);
                    _labHistory.removeWhere(
                      (lab) =>
                          lab['labResultId']?.toString() == labResultId &&
                          lab['fieldKey']?.toString() == metricType,
                    );
                    _cacheLabResults();
                  });

                  try {
                    final response = await ApiService.deleteLabResult(
                      labResultId: labResultId,
                      metricType: metricType,
                      profileUserId: widget.profileUserId,
                    );
                    if (response["success"] != true) {
                      throw Exception(
                        response["error"] ?? "Failed to delete lab result",
                      );
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lab result deleted.')),
                    );
                    unawaited(_loadHealthSummary());
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _labResults = previousLabResults;
                      _labHistory = previousLabHistory;
                      _cacheLabResults();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unable to delete ${removedLab['title'] ?? 'lab result'}: $e',
                        ),
                      ),
                    );
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

    // ==================== UNIT MAPPING ====================
    final Map<String, String> unitMap = {
      'Height': 'cm',
      'Weight': 'kg',
      'BMI': 'kg/m²',
      'Dry Weight': 'kg',
      'Blood Pressure': 'mmHg',
      'Heart Rate': 'bpm',
      'Creatinine': 'mg/dL',
      'Potassium': 'mmol/L',
      'Phosphorus': 'mg/dL',
      'Sodium': 'mmol/L',
      'Calcium': 'mg/dL',
      'eGFR': 'mL/min',
    };

    String selectedType = existingLab?['title'] ?? initialType ?? 'Weight';
    final valueController = TextEditingController(
      text: existingLab?['value'] ?? '',
    );
    final dateController = TextEditingController(
      text: existingLab?['date'] ?? '',
    );

    final List<String> metricTypes = [
      'Height',
      'Weight',
      'Dry Weight',
      'Blood Pressure',
      'Heart Rate',
      'Creatinine',
      'Potassium',
      'Phosphorus',
      'Sodium',
      'Calcium',
      'eGFR',
    ];

    var dialogMounted = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void closeDialog() {
              dialogMounted = false;
              Navigator.of(dialogContext).pop();
            }

            // Track validation state
            bool hasDate = dateController.text.trim().isNotEmpty;
            bool hasValue = valueController.text.trim().isNotEmpty;
            bool isFormValid = hasDate && hasValue;

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
                            isEdit ? 'Edit Measurement' : 'Add Measurement',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                            ),
                          ),
                          IconButton(
                            onPressed: closeDialog,
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      const HealthMetricsFormLabel(label: 'Metric Type'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        items: metricTypes
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(
                                  '${type} (${unitMap[type] ?? 'unit'})',
                                ),
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

                      HealthMetricsFormLabel(
                        label:
                            'Measurement Value (${unitMap[selectedType] ?? 'unit'})',
                      ),
                      const SizedBox(height: 8),
                      HealthMetricsTextFormField(
                        controller: valueController,
                        placeholder: 'Enter value',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (hasDate && !hasValue)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Enter at least one measurement value.',
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      const HealthMetricsFormLabel(
                        label: 'Measurement Date (Required)',
                      ),
                      const SizedBox(height: 8),
                      HealthMetricsDatePickerFormField(
                        dialogContext: dialogContext,
                        controller: dateController,
                        placeholder: 'Select date',
                        onDateSelected: () => setDialogState(() {}),
                      ),
                      if (!hasDate)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Please enter the measurement date.',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (isSavingMeasurement || !isFormValid)
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

                            // Validate numeric value
                            if (measurementValue.isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter a measurement value'),
                                ),
                              );
                              return;
                            }

                            // Validate date is required for ALL measurements
                            if (measurementDate.isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please enter the measurement date.',
                                  ),
                                ),
                              );
                              return;
                            }

                            // Try to parse value as number for basic validation
                            final numValue = double.tryParse(measurementValue);
                            if (numValue == null) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please enter a valid number for the measurement value.',
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
                              if (!dialogMounted || !mounted) return;
                              if (!confirmed) return;
                            }

                            List<Map<String, dynamic>>? previousLabResults;
                            List<Map<String, dynamic>>? previousLabHistory;

                            try {
                              if (!dialogMounted || !mounted) return;
                              setDialogState(() => isSavingMeasurement = true);

                              if (isVitalMeasurement) {
                                final response =
                                    await ApiService.saveMeasurement(
                                  profileUserId: widget.profileUserId,
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
                                final fieldKey =
                                    existingLab?['fieldKey']?.toString() ??
                                        (selectedType == 'eGFR'
                                            ? 'egfr'
                                            : selectedType.toLowerCase());
                                final tempLabResultId = existingLab?['labResultId']
                                        ?.toString() ??
                                    'temp_lab_${DateTime.now().millisecondsSinceEpoch}';
                                final optimisticLab = {
                                  'labResultId': tempLabResultId,
                                  'fieldKey': fieldKey,
                                  'title': selectedType,
                                  'value': measurementValue,
                                  'unit': unitMap[selectedType] ?? 'unit',
                                  'date': _formatDate(measurementDate),
                                  'status': existingLab?['status'] ?? '',
                                  'range': existingLab?['range'] ?? '',
                                  'isWarning': existingLab?['isWarning'] ?? false,
                                };
                                previousLabResults = _labResults
                                    .map((lab) => Map<String, dynamic>.from(lab))
                                    .toList();
                                previousLabHistory = _labHistory
                                    .map((lab) => Map<String, dynamic>.from(lab))
                                    .toList();

                                if (!mounted) return;
                                setState(() {
                                  if (isEdit && editIndex >= 0) {
                                    _labResults[editIndex] = optimisticLab;
                                  } else {
                                    final existingIndex =
                                        _labResults.indexWhere(
                                      (lab) =>
                                          lab['fieldKey']?.toString() ==
                                          fieldKey,
                                    );
                                    if (existingIndex >= 0) {
                                      _labResults[existingIndex] =
                                          optimisticLab;
                                    } else {
                                      _labResults.add(optimisticLab);
                                    }
                                  }
                                  _cacheLabResults();
                                });
                                if (dialogMounted) closeDialog();

                                final response =
                                    await ApiService.saveLabResult(
                                  profileUserId: widget.profileUserId,
                                  metricType: fieldKey,
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

                                final savedLabResultId =
                                    response["labResultId"]?.toString();
                                if (!mounted) return;
                                if (savedLabResultId != null &&
                                    savedLabResultId.isNotEmpty &&
                                    savedLabResultId != tempLabResultId) {
                                  setState(() {
                                    final savedIndex =
                                        _labResults.indexWhere(
                                      (lab) =>
                                          lab['labResultId'] ==
                                          tempLabResultId,
                                    );
                                    if (savedIndex >= 0) {
                                      _labResults[savedIndex] = {
                                        ..._labResults[savedIndex],
                                        'labResultId': savedLabResultId,
                                      };
                                      _cacheLabResults();
                                    }
                                  });
                                }
                                unawaited(_loadHealthSummary());
                              }

                              if (dialogMounted && mounted) closeDialog();
                            } catch (e) {
                              if (!mounted) return;
                              if (previousLabResults != null &&
                                  previousLabHistory != null) {
                                setState(() {
                                  _labResults = previousLabResults!;
                                  _labHistory = previousLabHistory!;
                                  _cacheLabResults();
                                });
                              }
                              if (dialogMounted) {
                                setDialogState(
                                  () => isSavingMeasurement = false,
                                );
                              }
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFormValid && !isSavingMeasurement
                                ? const Color(0xFF00B074)
                                : Colors.grey.shade400,
                            disabledBackgroundColor: Colors.grey.shade400,
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
                              : Text(
                                  isEdit
                                      ? 'Update Measurement'
                                      : 'Add Measurement',
                                  style: TextStyle(
                                    color: isFormValid && !isSavingMeasurement
                                        ? Colors.white
                                        : Colors.white60,
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
    ).then((_) {
      dialogMounted = false;
    });
  }

  // Form 2: Add/Edit Medications with Time Picker & Frequency Scheduling
  void _showMedicationForm({
    int? editIndex,
    Map<String, dynamic>? seedMedication,
  }) {
    final pageContext = context;
    final isEdit = editIndex != null;
    final existingMed = isEdit ? _medications[editIndex] : null;

    final nameController = TextEditingController(
      text:
          existingMed?['name'] ??
          existingMed?['medicineName'] ??
          existingMed?['medicationName'] ??
          existingMed?['medication_name'] ??
          seedMedication?['name']?.toString() ??
          seedMedication?['medicineName']?.toString() ??
          seedMedication?['medicationName']?.toString() ??
          seedMedication?['medication_name']?.toString() ??
          '',
    );
    final dosageController = TextEditingController(
      text:
          existingMed?['rawDosage'] ??
          existingMed?['dosage'] ??
          seedMedication?['dosage']?.toString() ??
          '',
    );
    final instructionsController = TextEditingController(
      text:
          existingMed?['instructions'] ??
          seedMedication?['instructions']?.toString() ??
          '',
    );

    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
    String frequencyType = 'times_per_day'; // 'times_per_day' or 'interval'
    int frequencyValue = 1;
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

    var dialogMounted = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void closeDialog() {
              dialogMounted = false;
              Navigator.of(dialogContext).pop();
            }

            // Update scheduled times whenever frequency changes
            final currentSchedule =
                _generateScheduledTimes(selectedTime, frequencyType, frequencyValue);
            final isNameMissing = nameController.text.trim().isEmpty;
            final isDosageMissing = dosageController.text.trim().isEmpty;
            final isMedicationFormValid =
                !isNameMissing && !isDosageMissing;
            final canSubmitMedication =
                isMedicationFormValid && !isSavingMedication;
            final mediaQuery = MediaQuery.of(context);
            final maxDialogHeight = mediaQuery.size.height -
                mediaQuery.viewInsets.bottom -
                mediaQuery.padding.vertical -
                40;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.all(20),
              backgroundColor: Colors.white,
              child: Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: maxDialogHeight.clamp(320.0, 720.0).toDouble(),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: mediaQuery.viewInsets.bottom > 0 ? 12 : 0,
                  ),
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
                            onPressed: closeDialog,
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Medication Name
                      const HealthMetricsFormLabel(
                        label: 'Medication Name (Required)',
                      ),
                      const SizedBox(height: 8),
                      HealthMetricsTextFormField(
                        controller: nameController,
                        placeholder: 'e.g. Calcium',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (isNameMissing)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Medication name is required.',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Dosage
                      const HealthMetricsFormLabel(label: 'Dosage (Required)'),
                      const SizedBox(height: 8),
                      HealthMetricsTextFormField(
                        controller: dosageController,
                        placeholder: 'e.g. 500mg',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (isDosageMissing)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Dosage is required.',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Start Time Picker
                      const HealthMetricsFormLabel(label: 'Start Time'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            if (!dialogMounted || !mounted) return;
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
                      const HealthMetricsFormLabel(label: 'Frequency Type'),
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
                      const HealthMetricsFormLabel(label: 'Frequency'),
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
                      const HealthMetricsFormLabel(
                        label: 'Instructions (Optional)',
                      ),
                      const SizedBox(height: 8),
                      HealthMetricsTextFormField(
                        controller: instructionsController,
                        placeholder: 'e.g. Take with water, with food',
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: canSubmitMedication
                              ? () async {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter medication name'),
                                ),
                              );
                              return;
                            }
                            if (dosageController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter medication dosage'),
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
                              if (seedMedication?['form'] != null)
                                'form': seedMedication?['form'],
                              'frequency_type': frequencyType,
                              'frequency_value': frequencyValue,
                              'start_time':
                                  '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                              'scheduled_times': finalSchedule,
                              'instructions': instructionsController.text.trim(),
                              if (seedMedication?['duration'] != null)
                                'duration': seedMedication?['duration'],
                              if (seedMedication?['rxcui'] != null)
                                'rxcui': seedMedication?['rxcui'],
                              if (seedMedication?['rawOcrText'] != null)
                                'rawOcrText': seedMedication?['rawOcrText'],
                              if (seedMedication?['confirmedByUser'] != null)
                                'confirmedByUser':
                                    seedMedication?['confirmedByUser'],
                              // Keep status internal and default to Pending; per-dose marking is tracked separately.
                              'status': 'Pending',
                              'isPending': true,
                              'frequency': frequencyLabel,
                              'time': displayTimes,
                              'schedule': displayTimes,
                              'display_freq': frequencyLabel,
                              'display_times': displayTimes,
                              'source':
                                  seedMedication?['source'] ?? 'manual_entry',
                            };

                            try {
                              if (!dialogMounted || !mounted) return;
                              setDialogState(() => isSavingMedication = true);
                              final tempMedicationId = isEdit
                                  ? medicationId
                                  : 'temp_${DateTime.now().millisecondsSinceEpoch}';
                              if (!isEdit) {
                                newMed['id'] = tempMedicationId;
                                newMed['medicationId'] = tempMedicationId;
                              }
                              newMed['saveStatus'] = 'saving';
                              final previousMedication = isEdit
                                  ? Map<String, dynamic>.from(
                                      _medications[editIndex],
                                    )
                                  : null;

                              if (!mounted) return;
                              setState(() {
                                if (isEdit) {
                                  _medications[editIndex] = newMed;
                                } else {
                                  _medications.add(newMed);
                                }
                                _cacheMedications();
                              });
                              if (dialogMounted) closeDialog();

                              if (isEdit &&
                                  medicationId != null &&
                                  medicationId.isNotEmpty) {
                                final savePayload =
                                    Map<String, dynamic>.from(newMed)
                                      ..remove('saveStatus');
                                final response =
                                    await ApiService.updateMedication(
                                  medicationId,
                                  savePayload,
                                  profileUserId: widget.profileUserId,
                                );
                                if (response["success"] != true) {
                                  throw Exception(
                                    response["error"] ??
                                        "Failed to update medication",
                                  );
                                }
                              } else if (!isEdit) {
                                final savePayload =
                                    Map<String, dynamic>.from(newMed)
                                      ..remove('id')
                                      ..remove('medicationId')
                                      ..remove('saveStatus');
                                final response =
                                    await ApiService.saveMedication(
                                  savePayload,
                                  profileUserId: widget.profileUserId,
                                );
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
                              newMed['saveStatus'] = 'saved';
                              setState(() {
                                if (isEdit) {
                                  _medications[editIndex] = newMed;
                                } else {
                                  final savedIndex = _medications.indexWhere(
                                    (medication) =>
                                        medication['medicationId'] ==
                                            tempMedicationId ||
                                        medication['id'] == tempMedicationId,
                                  );
                                  if (savedIndex >= 0) {
                                    _medications[savedIndex] = newMed;
                                  }
                                }
                                _cacheMedications();
                              });
                              unawaited(
                                NotificationService.syncSingleMedicationReminder(
                                  medication: newMed,
                                  previousMedication: previousMedication,
                                  profileUserId: widget.profileUserId,
                                ),
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Medication saved.'),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              setState(() {
                                if (isEdit) {
                                  if (editIndex >= 0 &&
                                      editIndex < _medications.length) {
                                    _medications[editIndex] =
                                        Map<String, dynamic>.from(
                                      existingMed ?? {},
                                    );
                                  }
                                } else {
                                  _medications.removeWhere(
                                    (medication) =>
                                        medication['saveStatus'] == 'saving' &&
                                        medication['name'] ==
                                            newMed['name'] &&
                                        medication['dosage'] ==
                                            newMed['dosage'],
                                  );
                                }
                                _cacheMedications();
                              });
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Unable to save medication: $e',
                                  ),
                                ),
                              );
                            }
                          }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canSubmitMedication
                                ? const Color(0xFF00B074)
                                : Colors.grey.shade400,
                            disabledBackgroundColor: Colors.grey.shade400,
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
                              : Text(
                                  isEdit ? 'Save Medication' : 'Add Medication',
                                  style: TextStyle(
                                    color: canSubmitMedication
                                        ? Colors.white
                                        : Colors.white70,
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
    ).then((_) {
      dialogMounted = false;
    });
  }

  Future<void> _scanPrescriptionForMedications() {
    if (_isScanningPrescription) return Future<void>.value();

    return MedicationScanFlow.scanPrescriptionForMedications(
      context: context,
      onScanningChanged: (isScanning) {
        if (!mounted) return;
        setState(() {
          _isScanningPrescription = isScanning;
        });
      },
      onMedicationSelected: (seedMedication) async {
        if (!mounted) return;
        _showMedicationForm(seedMedication: seedMedication);
      },
    );
  }

  Future<void> _showAddMedicationOptions() {
    return MedicationScanFlow.showAddMedicationOptions(
      context: context,
      isScanning: _isScanningPrescription,
      onScanPrescription: _scanPrescriptionForMedications,
      onManualEntry: () => _showMedicationForm(),
    );
  }

  // ==========================================
  // MAIN BUILD METHOD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_resolvedCaregiverNoChildEmptyState) {
      return _buildCaregiverNoChildScaffold();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: SafeArea(
        child: Stack(
          children: [
            _isLoadingHealth
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00C874)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
              if (_healthError != null) ...[
                HealthErrorCard(
                  message: "Health data could not be loaded: $_healthError",
                ),
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
                  HealthMetricsVitalCard(
                    title: 'Blood Pressure',
                    value: _vitalValue('Blood Pressure'),
                    unit: 'mmHg',
                    icon: Icons.favorite,
                    color: Colors.redAccent,
                  ),
                  HealthMetricsVitalCard(
                    title: 'Weight',
                    value: _vitalValue('Weight'),
                    unit: 'kg',
                    icon: Icons.scale,
                    color: Colors.greenAccent,
                  ),
                  HealthMetricsVitalCard(
                    title: 'Height',
                    value: _vitalValue('Height'),
                    unit: 'cm',
                    icon: Icons.straighten,
                    color: Colors.blueAccent,
                  ),
                  HealthMetricsVitalCard(
                    title: 'BMI',
                    value: _vitalValue('BMI'),
                    unit: 'kg/m2',
                    icon: Icons.analytics_outlined,
                    color: Colors.orangeAccent,
                  ),
                  HealthMetricsVitalCard(
                    title: 'Heart Rate',
                    value: _vitalValue('Heart Rate'),
                    unit: 'bpm',
                    icon: Icons.monitor_heart,
                    color: Colors.purpleAccent,
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
                    onPressed: _showAddMedicationOptions,
                    icon: _isScanningPrescription
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.add,
                            size: 18,
                            color: Color(0xFF9E86FF),
                          ),
                    label: Text(
                      _isScanningPrescription ? 'Scanning...' : 'Add',
                      style: const TextStyle(
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
                final isSaving = med['saveStatus'] == 'saving';
                return HealthMetricsMedicationCard(
                  name: med['name'],
                  dosage: med['dosage'],
                  time: med['time'],
                  status: isSaving ? 'Saving...' : (med['status'] ?? 'Pending'),
                  onTap:
                      isSaving ? () {} : () => _showItemManageSheet(idx, 'Medication'),
                  isPending: med['isPending'] == true,
                  isMissed: med['isMissed'] == true,
                  note: med['note']?.toString(),
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
                      IconButton(
                        onPressed: () => _showMeasurementForm(),
                        tooltip: 'Add Measurement',
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Color(0xFF00C874),
                        ),
                      ),
                      const SizedBox(width: 4),
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
                return HealthMetricsLabResultCard(
                  title: lab['title'],
                  value: '${lab['value']} ${lab['unit']}',
                  date: lab['date'],
                  status: lab['status'],
                  range: lab['range'],
                  onTap: () => _showItemManageSheet(idx, 'Lab Result'),
                  isWarning: lab['isWarning'],
                );
              }).toList(),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
            if (_isScanningPrescription)
              const MedicationScanProgressOverlay(),
          ],
        ),
      ),
      bottomNavigationBar: HealthMetricsBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FoodLogPage(
                      profileUserId: widget.profileUserId,
                      caregiverNoChildEmptyState:
                          _resolvedCaregiverNoChildEmptyState,
                    ),
              ),
            );
          } else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AnalyticsPage(
                      profileUserId: widget.profileUserId,
                      caregiverNoChildEmptyState:
                          _resolvedCaregiverNoChildEmptyState,
                    ),
              ),
            );
          } else if (index == 4) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
          } else {
            setState(() => _currentIndex = index);
          }
        },
      ),
    );
  }

  Widget _buildCaregiverNoChildScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health Metrics',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Add or link a child profile from the dashboard before viewing health metrics.',
                style: TextStyle(
                  color: Color(0xFF607D8B),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: HealthMetricsBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => FoodLogPage(
                  profileUserId: widget.profileUserId,
                  caregiverNoChildEmptyState:
                      _resolvedCaregiverNoChildEmptyState,
                ),
              ),
            );
          } else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AnalyticsPage(
                  profileUserId: widget.profileUserId,
                  caregiverNoChildEmptyState:
                      _resolvedCaregiverNoChildEmptyState,
                ),
              ),
            );
          } else if (index == 4) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
          }
        },
      ),
    );
  }

  Future<bool> _shouldShowCaregiverEmptyState() async {
    final response = await ApiService.getDashboardSummary();
    final viewer = response['viewer'];
    final role = viewer is Map
        ? (viewer['role'] ?? viewer['userRole'] ?? '').toString().toLowerCase()
        : '';
    if (role != 'caregiver' && role != 'parent_caregiver') return false;
    final state = response['caregiverDashboardState'];
    final children = state is Map ? state['linkedChildren'] : null;
    return children is! List || children.isEmpty;
  }

  // ==========================================
  // COMPONENT BUILDERS
  // ==========================================


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

}
