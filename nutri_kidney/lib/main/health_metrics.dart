import 'package:flutter/material.dart';
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
    'Blood Pressure': '110/70',
    'Weight': '31.0',
    'Height': '130',
    'Heart Rate': '82',
  };

  List<Map<String, dynamic>> _medications = [
    {
      'name': 'Calcium Supplement',
      'dosage': '500mg · 2x daily',
      'time': '8:00 AM, 8:00 PM',
      'status': 'Taken',
      'isPending': false,
    },
    {
      'name': 'Vitamin D',
      'dosage': '400 IU · 1x daily',
      'time': '8:00 AM',
      'status': 'Taken',
      'isPending': false,
    },
    {
      'name': 'Phosphate Binder',
      'dosage': '800mg · With meals',
      'time': 'Meals',
      'status': 'Pending',
      'isPending': true,
    },
  ];

  List<Map<String, dynamic>> _labResults = [
    {
      'title': 'Creatinine',
      'value': '0.8',
      'unit': 'mg/dL',
      'date': 'Oct 15, 2025',
      'status': 'Normal',
      'range': 'Range: 0.5-1.0',
      'isWarning': false,
    },
    {
      'title': 'eGFR',
      'value': '85',
      'unit': 'mL/min',
      'date': 'Oct 15, 2025',
      'status': 'Monitor',
      'range': 'Range: >90',
      'isWarning': true,
    },
    {
      'title': 'Potassium',
      'value': '4.2',
      'unit': 'mEq/L',
      'date': 'Oct 15, 2025',
      'status': 'Normal',
      'range': 'Range: 3.5-5.0',
      'isWarning': false,
    },
    {
      'title': 'Phosphorus',
      'value': '4.2',
      'unit': 'mEq/L',
      'date': 'Oct 15, 2025',
      'status': 'Normal',
      'range': 'Range: 3.5-5.0',
      'isWarning': false,
    },
    {
      'title': 'Calcium',
      'value': '4.2',
      'unit': 'mEq/L',
      'date': 'Oct 15, 2025',
      'status': 'Normal',
      'range': 'Range: 3.5-5.0',
      'isWarning': false,
    },
  ];

  // ==========================================
  // INTERACTIVE POPUPS & MENUS
  // ==========================================

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
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  setState(() {
                    if (collectionType == 'Medication') {
                      _medications.removeAt(index);
                    } else {
                      _labResults.removeAt(index);
                    }
                  });
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
                child: _labResults.isEmpty
                    ? const Center(
                        child: Text(
                          "No history available.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _labResults.length,
                        itemBuilder: (context, index) {
                          final lab = _labResults[index];
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
  void _showMeasurementForm({int? editIndex}) {
    final isEdit = editIndex != null;
    final existingLab = isEdit ? _labResults[editIndex] : null;

    String selectedType = existingLab?['title'] ?? 'Weight';
    final valueController = TextEditingController(
      text: existingLab?['value'] ?? '',
    );
    final dateController = TextEditingController(
      text: existingLab?['date'] ?? 'Oct 16, 2025',
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
                            onPressed: () => Navigator.of(context).pop(),
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
                      _buildTextFormField(dateController, 'e.g. Oct 16, 2025'),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              if ([
                                'Blood Pressure',
                                'Weight',
                                'Height',
                                'Heart Rate',
                              ].contains(selectedType)) {
                                _vitals[selectedType] = valueController.text;
                              } else {
                                final newLab = {
                                  'title': selectedType,
                                  'value': valueController.text,
                                  'unit': existingLab?['unit'] ?? 'units',
                                  'date': dateController.text,
                                  'status': existingLab?['status'] ?? 'Logged',
                                  'range': existingLab?['range'] ?? 'N/A',
                                  'isWarning':
                                      existingLab?['isWarning'] ?? false,
                                };
                                if (isEdit) {
                                  _labResults[editIndex] = newLab;
                                } else {
                                  _labResults.insert(0, newLab); // Add to top
                                }
                              }
                            });
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B074),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
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

  // Form 2: Add/Edit Medications
  void _showMedicationForm({int? editIndex}) {
    final isEdit = editIndex != null;
    final existingMed = isEdit ? _medications[editIndex] : null;

    final nameController = TextEditingController(
      text: existingMed?['name'] ?? '',
    );
    final dosageController = TextEditingController(
      text: existingMed?['dosage'] ?? '',
    );
    final timeController = TextEditingController(
      text: existingMed?['time'] ?? '',
    );
    String status = existingMed?['status'] ?? 'Pending';

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
                            isEdit ? 'Edit Medication' : 'Add Medication',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _buildFormLabel('Medication Name'),
                      const SizedBox(height: 8),
                      _buildTextFormField(nameController, 'e.g. Vitamin C'),
                      const SizedBox(height: 20),

                      _buildFormLabel('Dosage & Frequency'),
                      const SizedBox(height: 8),
                      _buildTextFormField(
                        dosageController,
                        'e.g. 500mg · 1x daily',
                      ),
                      const SizedBox(height: 20),

                      _buildFormLabel('Time / Schedule'),
                      const SizedBox(height: 8),
                      _buildTextFormField(timeController, 'e.g. 8:00 AM'),
                      const SizedBox(height: 20),

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

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              final newMed = {
                                'name': nameController.text.isNotEmpty
                                    ? nameController.text
                                    : 'Unknown Med',
                                'dosage': dosageController.text,
                                'time': timeController.text,
                                'status': status,
                                'isPending': status == 'Pending',
                              };
                              if (isEdit) {
                                _medications[editIndex] = newMed;
                              } else {
                                _medications.add(newMed);
                              }
                            });
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B074),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    _vitals['Blood Pressure']!,
                    'mmHg',
                    Icons.favorite,
                    Colors.redAccent,
                  ),
                  _buildVitalCard(
                    'Weight',
                    _vitals['Weight']!,
                    'kg',
                    Icons.scale,
                    Colors.greenAccent,
                  ),
                  _buildVitalCard(
                    'Height',
                    _vitals['Height']!,
                    'cm',
                    Icons.straighten,
                    Colors.blueAccent,
                  ),
                  _buildVitalCard(
                    'Heart Rate',
                    _vitals['Heart Rate']!,
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
              const SizedBox(height: 16),

              if (_labResults.isEmpty)
                const Text(
                  "No lab results logged yet.",
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
                const SizedBox(height: 8),
                Text(
                  range,
                  style: const TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 11,
                  ),
                ),
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
