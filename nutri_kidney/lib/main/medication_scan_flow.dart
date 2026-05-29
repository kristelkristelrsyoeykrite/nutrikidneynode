import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nutri_kidney/services/api_service.dart';

typedef MedicationSeedSelection = Future<void> Function(
  Map<String, dynamic> seedMedication,
);

class MedicationScanFlow {
  static Future<void> showAddMedicationOptions({
    required BuildContext context,
    required bool isScanning,
    required Future<void> Function() onScanPrescription,
    required VoidCallback onManualEntry,
  }) {
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
                  onTap: isScanning
                      ? null
                      : () {
                          Navigator.pop(bottomSheetContext);
                          onScanPrescription();
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
                    onManualEntry();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> scanPrescriptionForMedications({
    required BuildContext context,
    required void Function(bool isScanning) onScanningChanged,
    required MedicationSeedSelection onMedicationSelected,
  }) async {
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

    if (source == null || !context.mounted) return;

    final imagePicker = ImagePicker();
    XFile? pickedImage;
    try {
      pickedImage = await imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1800,
      );
    } on PlatformException catch (error) {
      if (!context.mounted) return;
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to choose prescription image.')),
      );
      return;
    }

    if (pickedImage == null || !context.mounted) return;

    onScanningChanged(true);

    try {
      final response = await ApiService.extractPrescription(
        imagePath: pickedImage.path,
        contentType: _contentTypeForImage(pickedImage.path),
      );

      if (!context.mounted) return;
      if (response["success"] != true) {
        if (response["rateLimited"] == true) {
          await _showAiLimitDialog(context, response);
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

      final extractedText = response["extractedText"]?.toString() ?? "";
      await _showPrescriptionScanResultSheet(
        context: context,
        medications: medications,
        extractedText: extractedText,
        onMedicationSelected: onMedicationSelected,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to scan prescription: $error')),
      );
    } finally {
      onScanningChanged(false);
    }
  }

  static Future<void> _showAiLimitDialog(
    BuildContext context,
    Map<String, dynamic> response,
  ) {
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

  static Future<void> _showPrescriptionScanResultSheet({
    required BuildContext context,
    required List<Map<String, dynamic>> medications,
    required String extractedText,
    required MedicationSeedSelection onMedicationSelected,
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
                          'The system extracts text using OCR, then compares the detected medication names against the RxNorm database to identify and validate the prescribed drugs.',
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
                              if (!context.mounted) return;
                              await onMedicationSelected(selectedMedication);
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

  static String _contentTypeForImage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class MedicationScanProgressOverlay extends StatelessWidget {
  const MedicationScanProgressOverlay({super.key});

  @override
  Widget build(BuildContext context) {
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
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  'We are extracting medication details from the image. If the scanning service is starting up, please wait at least 15 seconds.',
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
}
