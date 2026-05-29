import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'health_profile3.dart'; // IMPORT ADDED HERE

class HealthProfile2Page extends StatefulWidget {
  const HealthProfile2Page({super.key});

  @override
  State<HealthProfile2Page> createState() => _HealthProfile2PageState();
}

class _HealthProfile2PageState extends State<HealthProfile2Page> {
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

  // State variables for the selections
  String? _dialysisType;
  String? _treatmentFrequency;
  List<Map<String, dynamic>> _medications = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isScanningPrescription = false;
  bool _showValidationHints = false;
  final Set<String> _selectedAllergies = {};

  final TextEditingController _allergiesController = TextEditingController();

  void _showAddMedicationDialog({Map<String, dynamic>? seedMedication}) {
    final nameController = TextEditingController(
      text:
          seedMedication?['name']?.toString() ??
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
                                  if (seedMedication?['form'] != null)
                                    "form": seedMedication?['form'],
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
                                  if (seedMedication?['duration'] != null)
                                    "duration": seedMedication?['duration'],
                                  if (seedMedication?['rxcui'] != null)
                                    "rxcui": seedMedication?['rxcui'],
                                  if (seedMedication?['rawOcrText'] != null)
                                    "rawOcrText": seedMedication?['rawOcrText'],
                                  if (seedMedication?['confirmedByUser'] != null)
                                    "confirmedByUser":
                                        seedMedication?['confirmedByUser'],
                                  "source":
                                      seedMedication?['source'] ?? 'manual_entry',
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

  List<String> _selectedAllergyPayload() {
    final selected = _selectedAllergies.toList(growable: true);
    final otherText = _allergiesController.text.trim();
    if (_selectedAllergies.contains('No known allergies')) {
      return ['No known allergies'];
    }
    if (_selectedAllergies.contains('Other') && otherText.isNotEmpty) {
      selected.add(otherText);
    }
    return selected;
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
          _allergiesController.clear();
        }
        return;
      }

      _selectedAllergies.remove('No known allergies');

      if (_selectedAllergies.contains(option)) {
        _selectedAllergies.remove(option);
        if (option == 'Other') {
          _allergiesController.clear();
        }
      } else {
        _selectedAllergies.add(option);
      }
    });
  }

  Widget _buildAllergySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel("Allergies (Required)"),
        const SizedBox(height: 8),
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
        if (_needsAllergySelectionHint)
          _buildValidationHint("Required"),
        if (_selectedAllergies.contains('Other')) ...[
          const SizedBox(height: 12),
          _buildLargeTextField(
            label: "Other allergy details (Required)",
            hint: "Enter other allergies",
            controller: _allergiesController,
            errorText: _needsOtherAllergyHint ? "Required" : null,
          ),
        ],
      ],
    );
  }

  Future<void> _showAddMedicationOptions() {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Medication',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose how you want to add medication details.',
                  style: TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.document_scanner_outlined,
                    color: Color(0xFF00BFA5),
                  ),
                  title: const Text('Scan Prescription'),
                  subtitle: FutureBuilder<Map<String, dynamic>>(
                    future: ApiService.getAiUsageStatus('medication_ocr'),
                    builder: (context, snapshot) {
                      final label = ApiService.aiUsageLabel(
                        snapshot.hasData
                            ? ApiService.aiUsageFromResponse(snapshot.data!)
                            : null,
                      );
                      return Text(
                        label == null
                            ? 'Use OCR to extract medication details'
                            : 'Use OCR to extract medication details - used today: $label',
                      );
                    },
                  ),
                  onTap: _isScanningPrescription
                      ? null
                      : () {
                          Navigator.pop(bottomSheetContext);
                          _scanPrescriptionForMedications();
                        },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.edit_note_outlined,
                    color: Color(0xFF9E86FF),
                  ),
                  title: const Text('Manual Entry'),
                  subtitle: const Text('Type medication details yourself'),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _showAddMedicationDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _scanPrescriptionForMedications() async {
    if (_isScanningPrescription) return;

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scan Prescription',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'For better accuracy, it is recommended to scan a computerized prescription.',
                style: TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFF00BFA5),
                ),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(dialogContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_outlined,
                  color: Color(0xFF00BFA5),
                ),
                title: const Text('Upload File'),
                onTap: () => Navigator.pop(dialogContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    XFile? pickedImage;
    try {
      pickedImage = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1800,
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      final sourceLabel = source == ImageSource.camera ? 'camera' : 'gallery';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code.toLowerCase().contains('cancel')
                ? 'Prescription scan canceled.'
                : 'Unable to open the $sourceLabel.',
          ),
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to choose prescription image.')),
      );
      return;
    }

    if (pickedImage == null) return;

    setState(() {
      _isScanningPrescription = true;
    });

    try {
      final imageBytes = await pickedImage.readAsBytes();
      final response = await ApiService.extractPrescription(
        imageBytes: imageBytes,
        contentType: _contentTypeForImage(pickedImage.path),
      );

      if (!mounted) return;
      if (response["success"] != true) {
        if (response["rateLimited"] == true) {
          await _showAiLimitDialog(response);
          return;
        }
        throw Exception(response["error"] ?? "Prescription scan failed");
      }

      final medications = response["medications"] is List
          ? (response["medications"] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : <Map<String, dynamic>>[];

      await _showPrescriptionScanResultSheet(
        medications: medications,
        extractedText: response["extractedText"]?.toString() ?? "",
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to scan prescription: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isScanningPrescription = false;
        });
      }
    }
  }

  Future<void> _showAiLimitDialog(Map<String, dynamic> response) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily scan limit reached'),
        content: Text(ApiService.aiLimitMessage(response)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrescriptionScanResultSheet({
    required List<Map<String, dynamic>> medications,
    required String extractedText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prescription Scan Results',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  medications.isEmpty
                      ? 'No medications could be confidently extracted.'
                      : 'Tap a result to prefill the medication form. Medication name verification uses the RxNorm database.',
                  style: const TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: const Text(
                    'Medication scanning does not guarantee 100% accuracy. Please double-check the medicine name, dosage, and instructions before inputting or saving.',
                    style: TextStyle(
                      color: Color(0xFF7A5C00),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC8E6C9)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        size: 16,
                        color: Color(0xFF2E7D32),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Prescription scan results use the RxNorm database for medication verification.',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (medications.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0ECE8)),
                    ),
                    child: Text(
                      extractedText.isEmpty ? 'No OCR text found.' : extractedText,
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: medications.map((medication) {
                          final name = medication["medicineName"]
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true
                              ? medication["medicineName"].toString().trim()
                              : (medication["name"]?.toString().trim().isNotEmpty ==
                                      true
                                  ? medication["name"].toString().trim()
                                  : "Medication");
                          final dosage =
                              medication["dosage"]?.toString().trim() ?? "";
                          final frequency =
                              medication["frequency"]?.toString().trim() ?? "";
                          final form =
                              medication["form"]?.toString().trim() ?? "";
                          final duration =
                              medication["duration"]?.toString().trim() ?? "";
                          final instructions =
                              medication["instructions"]?.toString().trim() ?? "";
                          final subtitle = [
                            if (dosage.isNotEmpty) dosage,
                            if (form.isNotEmpty) form,
                            if (frequency.isNotEmpty) frequency,
                            if (duration.isNotEmpty) duration,
                            if (instructions.isNotEmpty) instructions,
                          ].join(' - ');

                          return InkWell(
                            onTap: () async {
                              final selectedMedication = {
                                "name": name,
                                "medicineName": name,
                                "medicationName": name,
                                "medication_name": name,
                                "dosage": dosage,
                                "form": form,
                                "duration": duration,
                                "instructions": instructions,
                                "frequency": frequency,
                                "rxcui": medication["rxcui"]?.toString(),
                                "confirmedByUser": true,
                                "rawOcrText": extractedText.isNotEmpty
                                    ? extractedText
                                    : (medication["rawLine"]?.toString() ?? ""),
                                "source": medication["verified"] == true
                                    ? "ocr_rxnorm"
                                    : "ocr_unverified",
                              };
                              Navigator.pop(bottomSheetContext);
                              await Future<void>.delayed(
                                const Duration(milliseconds: 150),
                              );
                              if (!mounted) return;
                              _showAddMedicationDialog(
                                seedMedication: selectedMedication,
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
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
                                  if (subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                        color: Color(0xFF78909C),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5E9),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'Database: RxNorm',
                                          style: TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (medication["verified"] == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE3F2FD),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: const Text(
                                            'Verified',
                                            style: TextStyle(
                                              color: Color(0xFF1565C0),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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

  String _contentTypeForImage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
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
    final hasRequiredTreatmentFrequency =
        _dialysisType == "None" || _treatmentFrequency != null;
    final hasAllergyInput =
        _selectedAllergies.isNotEmpty &&
        (!_selectedAllergies.contains('Other') ||
            _allergiesController.text.trim().isNotEmpty);

    return _dialysisType != null &&
        hasRequiredTreatmentFrequency &&
        hasAllergyInput;
  }

  bool get _needsDialysisSelectionHint =>
      _showValidationHints && _dialysisType == null;

  bool get _needsTreatmentFrequencyHint =>
      _dialysisType != null &&
      _dialysisType != "None" &&
      _treatmentFrequency == null;

  bool get _needsAllergySelectionHint =>
      _showValidationHints && _selectedAllergies.isEmpty;

  bool get _needsOtherAllergyHint =>
      _selectedAllergies.contains('Other') &&
      _allergiesController.text.trim().isEmpty;

  bool get _canTapContinue =>
      !_needsTreatmentFrequencyHint && !_needsOtherAllergyHint;

  Future<void> _continueToStep3() async {
    setState(() {
      _showValidationHints = true;
    });

    if (!_isFormValid) return;

    await ApiService.sendStep2({
      "isOnDialysis": _dialysisType != null && _dialysisType != "None",
      "dialysisType": _dialysisType,
      "treatmentFrequency": _treatmentFrequency,
      "allergies": _selectedAllergyPayload(),
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HealthProfile3Page(),
      ),
    );
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
                        'Information about current treatment and allergies',
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
                    _buildLabel("Is the child on dialysis? (Required)"),
                    _buildRadioOption("None"),
                    _buildRadioOption("Peritoneal Dialysis"),
                    _buildRadioOption("Hemodialysis"),
                    if (_needsDialysisSelectionHint)
                      _buildValidationHint("Required"),
                    const SizedBox(height: 16),

                    // Treatment Frequency Dropdown
                    _buildDropdownField(
                      label: _dialysisType != null && _dialysisType != "None"
                          ? "Treatment frequency: (Required)"
                          : "Treatment frequency:",
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
                      helperText: null,
                      errorText: _needsTreatmentFrequencyHint
                          ? "Required"
                          : null,
                      onChanged: (val) {
                        setState(() {
                          _treatmentFrequency = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Allergies (Large Box)
                    _buildAllergySelector(),
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
                              onPressed:
                                  _canTapContinue ? _continueToStep3 : null,
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
            if (_isScanningPrescription) _buildPrescriptionScanOverlay(),
          ],
        ),
      ),
    );
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

  Widget _buildPrescriptionScanOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withOpacity(0.28),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Scanning Prescription',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'We are extracting medication details from the image. This can take a few seconds.',
                  style: TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 16),
                LinearProgressIndicator(
                  minHeight: 8,
                  backgroundColor: Color(0xFFE8F5E9),
                  color: Color(0xFF00B074),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                SizedBox(height: 12),
                Text(
                  'Uploading image and running OCR...',
                  style: TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    String? errorText,
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
              errorText: errorText,
              errorStyle: const TextStyle(fontSize: 11, height: 1.3),
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
    String? helperText,
    String? errorText,
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
        if (errorText != null)
          _buildValidationHint(errorText)
        else if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helperText,
              style: const TextStyle(
                color: Color(0xFF90A4AE),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
      ],
    );
  }
}
