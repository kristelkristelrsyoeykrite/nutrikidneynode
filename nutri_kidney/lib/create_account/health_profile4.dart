import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutri_kidney/services/auth_service.dart';
import '../main/dashboard.dart';

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

  // --- Variables to store popup data ---
  String? _uploadedPrescriptionPath;
  // --- Phone verification state for final proceed ---
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _verifyPhoneController = TextEditingController();
  final TextEditingController _verifyOtpController = TextEditingController();
  String? _verifyId;
  bool _verifyShowOtp = false;
  String _otpErrorMessage = '';
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

  Future<bool> _showVerifyDialogAndSignIn(String phone) async {
    _verifyPhoneController.text = phone;
    _verifyShowOtp = false;
    _verifyId = null;
    _otpErrorMessage = '';

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Verify Your Phone'),
            content: _verifyShowOtp
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Enter the OTP sent to your phone'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _verifyOtpController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '000000',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          errorText: _otpErrorMessage.isNotEmpty ? _otpErrorMessage : null,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('We will send an OTP to this phone to verify it before creating your account'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _verifyPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '+63 912 345 6789',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  if (_verifyShowOtp) {
                    // verify OTP
                    final otp = _verifyOtpController.text.trim();
                    if (otp.isEmpty || _verifyId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the OTP')));
                      return;
                    }
                    try {
                      debugPrint('DEBUG profile OTP verify tapped with input length=${otp.length}');
                      final cred = PhoneAuthProvider.credential(verificationId: _verifyId!, smsCode: otp);
                      final userCredential = await _auth.signInWithCredential(cred);
                      
                      // Save the UID so backend knows this user was created in Firebase Auth
                      ApiService.signupData["uid"] = userCredential.user?.uid ?? "";
                      
                      // Sign out immediately - backend will use the UID to just create Firestore profile
                      await _auth.signOut();
                      
                      Navigator.pop(context, true);
                    } catch (e) {
                      debugPrint('DEBUG profile OTP verify failed: $e');
                      setStateDialog(() {
                        _otpErrorMessage = _getOtpErrorMessage(e);
                      });
                      _verifyOtpController.clear();
                    }
                  } else {
                    // send OTP
                    final phoneNumber = _verifyPhoneController.text.trim();
                    if (phoneNumber.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter phone number')));
                      return;
                    }
                    try {
                      await _auth.verifyPhoneNumber(
                        phoneNumber: phoneNumber,
                        timeout: const Duration(seconds: 60),
                        verificationCompleted: (PhoneAuthCredential credential) async {
                          // auto verified
                          final userCredential = await _auth.signInWithCredential(credential);
                          
                          // Save the UID so backend knows this user was created in Firebase Auth
                          ApiService.signupData["uid"] = userCredential.user?.uid ?? "";
                          
                          // Sign out immediately - backend will use the UID to just create Firestore profile
                          await _auth.signOut();
                          if (mounted) Navigator.pop(context, true);
                        },
                        verificationFailed: (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification failed: ${e.message}')));
                        },
                        codeSent: (verId, _) {
                          _verifyId = verId;
                          setStateDialog(() {
                            _verifyShowOtp = true;
                          });
                        },
                        codeAutoRetrievalTimeout: (verId) {
                          _verifyId = verId;
                        },
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send OTP failed: $e')));
                    }
                  }
                },
                child: Text(_verifyShowOtp ? 'Verify OTP' : 'Send OTP'),
              ),
            ],
          );
        });
      },
    ).then((v) => v == true);
  }

  String _getOtpErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      debugPrint(
        'DEBUG OTP error code=${error.code} message=${error.message}',
      );
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      if (code == 'invalid-verification-code' ||
          code == 'invalid-credential' ||
          message.contains('invalid verification code') ||
          message.contains('verification code is invalid') ||
          message.contains('invalid code') ||
          message.contains('invalid otp') ||
          message.contains('invalid sms code')) {
        return 'Wrong OTP. Please try again.';
      }
      if (code == 'session-expired' ||
          message.contains('code has expired') ||
          message.contains('session expired') ||
          message.contains('sms code has expired')) {
        return 'OTP expired. Please request a new code.';
      }
      return error.message ?? 'OTP verification failed. Please try again.';
    }
    final text = error.toString().toLowerCase();
    debugPrint('DEBUG OTP error raw=$error');
    if (text.contains('invalid-verification-code') ||
        text.contains('invalid verification code') ||
        text.contains('verification code is invalid') ||
        text.contains('invalid credential') ||
        text.contains('invalid code') ||
        text.contains('invalid otp') ||
        text.contains('invalid sms code')) {
      return 'Wrong OTP. Please try again.';
    }
    if (text.contains('session-expired') ||
        text.contains('code has expired') ||
        text.contains('session expired') ||
        text.contains('sms code has expired')) {
      return 'OTP expired. Please request a new code.';
    }
    return 'OTP verification failed. Please try again.';
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
    _verifyPhoneController.dispose();
    _verifyOtpController.dispose();
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

  // --- POPUP: Prescription Upload Dialog ---
  void _showUploadPrescriptionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
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
                        text: 'Upload ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF37474F),
                        ),
                        children: [
                          TextSpan(
                            text:
                                'handwritten or computerized\nprescription here',
                            style: TextStyle(
                              color: Color(0xFF9E86FF), // Purple color
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '(recommended computerized)',
                      style: TextStyle(fontSize: 14, color: Color(0xFF78909C)),
                    ),
                    const Text(
                      'Our secure AI scans your prescription to save you time',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB0BEC5)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Icons grid
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Open Camera tappable area
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              _uploadedPrescriptionPath =
                                  "path/to/camera_photo.jpg";
                            });
                          },
                          child: _buildTappableIconColumn(
                            Icons.camera_alt,
                            "Open Camera",
                          ),
                        ),
                        // Find in files tappable area
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              _uploadedPrescriptionPath =
                                  "path/to/picked_file.pdf";
                            });
                          },
                          child: _buildTappableIconColumn(
                            Icons.folder_open,
                            "Find in files",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Buttons row
                    Row(
                      children: [
                        // Upload button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _uploadedPrescriptionPath == null
                                ? null // Disabled if nothing selected
                                : () {
                                    Navigator.pop(context);
                                    // Integrate actual upload here
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF00C874,
                              ), // upload_confirm green
                              disabledBackgroundColor: Colors.grey.shade400,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Upload File',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Cancel Button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context); // Close Popup
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFFEEEEEE,
                              ), // Light grey
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Color(0xFF37474F),
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
                      childAspectRatio:
                          2.15, // Keeps label + input from clipping.
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
                      label: "Result Date",
                      hint: "Enter the date of release",
                      controller: _resultDateController,
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
                    _buildLabel("Prescription"),
                    const SizedBox(height: 8),
                    // Tappable container for prescription upload
                    GestureDetector(
                      onTap: () {
                        _showUploadPrescriptionDialog(); // Open 1st Popup
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(
                                  0xFFAAAAAA,
                                ), // Grey camera background
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _uploadedPrescriptionPath == null
                                    ? "Upload Medicine Prescription (Handwritten or Digital)"
                                    : "Prescription uploaded successfully!", // change text when uploaded
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF37474F),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Small indicator for upload status
                            Icon(
                              _uploadedPrescriptionPath == null
                                  ? Icons.upload_file
                                  : Icons.check_circle_outline,
                              color: _uploadedPrescriptionPath == null
                                  ? const Color(0xFF78909C)
                                  : const Color(0xFF00C874),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
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
                              onPressed: () {
                                if (_hasStep4LabDataWithoutDate()) {
                                  _showMissingLabDateMessage();
                                  return;
                                }
                                _showProceedDialog(); // Show confirmation dialog
                              },
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
      // If signupData contains a phoneNumber, verify it first (send OTP now)
      final phone = ApiService.signupData["phoneNumber"] as String?;
      if (phone != null && phone.trim().isNotEmpty) {
        // Phone-based flow
        _showLoadingDialog("Verifying phone number...");
      
      // Show OTP dialog for verification
      final ok = await _showVerifyDialogAndSignIn(phone);
      if (!ok) {
        Navigator.pop(context); // Close loading dialog
        return;
      }

      _showLoadingDialog("Creating your account...");
      try {
        final phoneVerifyResponse = await ApiService.verifyPhoneAndCreateProfile(ApiService.signupData);
        Navigator.pop(context); // Close loading dialog

        if (phoneVerifyResponse["success"] != true) {
          throw Exception(phoneVerifyResponse["error"] ?? "Failed to create account after phone verification");
        }

        print("Phone verified and user account created successfully");
      } catch (e) {
        Navigator.pop(context); // Close loading dialog
        throw e;
      }
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

    // SEND STEP 4 DATA only if fields were provided
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

  bool _isStep4Empty() {
    return _creatinineController.text.trim().isEmpty &&
        _potassiumController.text.trim().isEmpty &&
        _phosphorusController.text.trim().isEmpty &&
        (_phosphorusStatus == null || _phosphorusStatus!.trim().isEmpty) &&
        _sodiumController.text.trim().isEmpty &&
        (_sodiumStatus == null || _sodiumStatus!.trim().isEmpty) &&
        (_calciumLevel == null || _calciumLevel!.trim().isEmpty) &&
        _resultDateController.text.trim().isEmpty &&
        _uploadedPrescriptionPath == null;
  }

  bool _hasStep4LabDataWithoutDate() {
    final hasLabData = _creatinineController.text.trim().isNotEmpty ||
        _potassiumController.text.trim().isNotEmpty ||
        _phosphorusController.text.trim().isNotEmpty ||
        (_phosphorusStatus != null && _phosphorusStatus!.trim().isNotEmpty) ||
        _sodiumController.text.trim().isNotEmpty ||
        (_sodiumStatus != null && _sodiumStatus!.trim().isNotEmpty) ||
        (_calciumLevel != null && _calciumLevel!.trim().isNotEmpty) ||
        _uploadedPrescriptionPath != null;

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
      ],
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
