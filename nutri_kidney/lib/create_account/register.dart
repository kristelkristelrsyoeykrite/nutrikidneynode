import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:nutri_kidney/services/auth_service.dart';
import 'package:nutri_kidney/utils/app_logger.dart';
import 'package:nutri_kidney/models/user_status.dart';
import 'health_profile1.dart';
import 'account_success_screen.dart';
import 'caregiver_child_age_screen.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Visibility states
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  // Privacy agreement state
  bool _hasAgreedToPrivacy = false;
  late TapGestureRecognizer _privacyTapRecognizer;

  // Role selection (NEW)
  String? _selectedRole;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Controllers to track text input in real-time
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String? _normalizedRole(String? role) {
    if (role == null) return null;
    if (role == 'parent_caregiver') return 'caregiver';
    return role;
  }

  String _roleLabel(String? role) {
    final normalized = _normalizedRole(role);
    if (normalized == 'adolescent') return 'adolescent';
    if (normalized == 'caregiver') return 'caregiver';
    return 'not selected';
  }

  @override
  void initState() {
    super.initState();
    _privacyTapRecognizer = TapGestureRecognizer()..onTap = _showPrivacyDialog;

    // If signup data was prefilled (e.g., from Google), populate the fields
    final prefill = ApiService.signupData;
    if (prefill.isNotEmpty) {
      final contact = prefill['email']?.toString() ?? '';
      _nameController.text = (prefill['fullName'] ?? '').toString();
      _emailController.text = contact;
    }

    _selectedRole = _normalizedRole(ApiService.userRole);

    // Listeners rebuild the UI whenever a user types
    _nameController.addListener(() {
      setState(() {});
    });
    _emailController.addListener(() {
      setState(() {});
    });

    _passwordController.addListener(() {
      setState(() {});
    });
    _confirmPasswordController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _privacyTapRecognizer.dispose();
    super.dispose();
  }

  // --- NEW: Validation Helper Methods ---

  bool _isEmailFormat(String input) {
    // Basic email format check
    final email = input.trim();
    return RegExp(r"^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}").hasMatch(email);
  }

  bool _isPasswordValid(String password) {
    // 1. Minimum 8 characters
    if (password.length < 8) return false;
    // 2. Contains at least one number
    if (!RegExp(r'[0-9]').hasMatch(password)) return false;
    // 3. Contains at least one special character
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) return false;

    return true;
  }

  // --- Updated Validation Logic ---
  bool get _isFormValid {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    return _nameController.text.trim().isNotEmpty &&
        _isEmailFormat(email) &&
        _isPasswordValid(password) &&
        password == confirmPassword &&
        _normalizedRole(_selectedRole) != null &&
        _hasAgreedToPrivacy;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF7),
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
                  children: [
                    const SizedBox(height: 30),

                    // Brand Logo
                    const Text(
                      'NutriKidney',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'FredokaOne',
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF37474F),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Subtitle
                    const Text(
                      'Create your account to get started',
                      style: TextStyle(fontSize: 18, color: Color(0xFF90A4AE)),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // Instruction Text
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Fill in your details to register',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF78909C),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Input Fields
                    _buildInputField(
                      label: 'Full Name',
                      hintText: 'John Doe',
                      controller: _nameController,
                    ),
                    const SizedBox(height: 16),

                    _buildContactField(),
                    const SizedBox(height: 16),

                    _buildInputField(
                      label: 'Password',
                      hintText: '••••••••',
                      isPassword: true,
                      isVisible: _isPasswordVisible,
                      onVisibilityToggle: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                      controller: _passwordController,
                    ),

                    // Helpful text so the user knows the strict password rules
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Password must be at least 8 characters and include a number and special character.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF90A4AE),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildInputField(
                      label: 'Confirm Password',
                      hintText: '••••••••',
                      isPassword: true,
                      isVisible: _isConfirmPasswordVisible,
                      onVisibilityToggle: () {
                        setState(() {
                          _isConfirmPasswordVisible =
                              !_isConfirmPasswordVisible;
                        });
                      },
                      controller: _confirmPasswordController,
                    ),

                    if (_passwordController.text.isNotEmpty &&
                        _confirmPasswordController.text.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          "Please confirm the password entered.",
                          style: TextStyle(color: Colors.red, fontSize: 11),
                        ),
                      )
                    else if (_confirmPasswordController.text.isNotEmpty &&
                        _passwordController.text !=
                            _confirmPasswordController.text)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          "Passwords do not match",
                          style: TextStyle(color: Colors.red, fontSize: 11),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ROLE SELECTION (NEW)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "I am a...",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF37474F),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedRole,
                        hint: const Text("Select your role"),
                        items: const [
                          DropdownMenuItem(value: "caregiver", child: Text("Parent/Caregiver")),
                          DropdownMenuItem(value: "adolescent", child: Text("Adolescent (13-18)")),
                        ]
                            .map<DropdownMenuItem<String>>((DropdownMenuItem<String> value) {
                          return value;
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedRole = _normalizedRole(newValue);
                          });
                          final normalizedRole = _normalizedRole(newValue);
                          if (normalizedRole != null) {
                            ApiService.setUserRole(normalizedRole);
                          }
                        },
                        underline: Container(),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Google Sign-In Button  
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _handleGoogleSignInRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_circle, color: Color(0xFF4DB6AC), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Sign in with Google',
                              style: TextStyle(
                                color: Color(0xFF37474F),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // --- Continue Button ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          // Call signup - validation happens inside
                          _signupUser();
                        },
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

                    const SizedBox(height: 16),

                    // Back Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
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
                            color: Color(0xFF9E86FF),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Privacy Disclaimer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text.rich(
                        TextSpan(
                          text:
                              'By signing in, you agree to our Terms of Service and Privacy Policy\n',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                          children: [
                            const TextSpan(text: 'Click '),
                            TextSpan(
                              text: 'here',
                              style: const TextStyle(
                                color: Color.fromARGB(255, 34, 162, 160),
                                fontWeight: FontWeight.bold,
                              ),
                              recognizer: _privacyTapRecognizer,
                            ),
                            const TextSpan(
                              text: ' to know more on how we use your data.',
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
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

  void _proceedWithSignup() async {
    // NEW FLOW: All Firebase operations go through backend
    AppLogger.info(
      'Starting signup process for user: ${_nameController.text.trim()}',
      tag: LogTag.signup,
    );

    try {
      final fullName = _nameController.text.trim();
      final contact = _emailController.text.trim();
      final password = _passwordController.text;

      final String emailToSend = contact;

      // Save signup data locally for later use
      final signupPayload = {
        "fullName": fullName,
        "email": emailToSend,
        "password": password,
        "phoneNumber": null,
        "userRole": _normalizedRole(_selectedRole),
      };
      ApiService.setSignupData(signupPayload);

      String? userId;

      AppLogger.info(
        'Creating email user via backend: $emailToSend',
        tag: LogTag.signup,
      );

      final createResponse = await ApiService.createUser(
        fullName: fullName,
        email: emailToSend,
        phoneNumber: null,
        password: password,
        userRole: _normalizedRole(_selectedRole),
      );

      if (createResponse['success'] != true) {
        throw Exception(createResponse['error'] ?? 'Failed to create user');
      }

      userId = createResponse['uid'];
      if (userId == null) {
        throw Exception('Failed to get user ID after creation');
      }

      ApiService.setUserId(userId);
      ApiService.signupData['uid'] = userId;

      AppLogger.success(
        'Email user created via backend: $userId',
        tag: LogTag.signup,
      );

      // Step 2: Send email verification
        AppLogger.info(
          'Sending email verification request to backend for: $emailToSend',
          tag: LogTag.signup,
        );
        
        try {
          await _sendFirebaseEmailVerification(
            email: emailToSend,
            password: password,
          );
        } catch (e) {
          AppLogger.error(
            'Error sending Firebase email verification',
            tag: LogTag.signup,
            error: e,
          );
          rethrow;
        }

        // Show email-link verification dialog
        if (mounted) {
          bool? verified;
          try {
            verified = await _showEmailVerificationDialog(
              userId: userId!,
              email: emailToSend,
            );
          } catch (e) {
            AppLogger.error(
              'Error showing email verification dialog',
              tag: LogTag.signup,
              error: e,
            );
            verified = false;
          }

          if (verified != true && mounted) {
            AppLogger.warning(
              'User cancelled email verification - requesting deletion for user: $userId',
              tag: LogTag.signup,
            );
            
            try {
              await ApiService.deleteUserAccount(userId!);
              AppLogger.info(
                'User deletion requested from backend: $userId',
                tag: LogTag.signup,
              );
            } catch (e) {
              AppLogger.error(
                'Error requesting user deletion from backend',
                tag: LogTag.signup,
                error: e,
              );
            }
            
            return;
          }
        }

      // Step 3: Save user profile via backend with VERIFIED status
      AppLogger.info(
        'Saving verified user profile via backend: $userId',
        tag: LogTag.signup,
      );

      try {
        if (userId == null || userId!.isEmpty) {
          throw Exception('User ID is missing after verification');
        }
        final String verifiedUserId = userId!;
        await ApiService.saveUserProfileAfterVerification(
          uid: verifiedUserId,
          fullName: fullName,
          email: emailToSend,
          phoneNumber: null,
          password: password,
          userRole: _normalizedRole(_selectedRole),
          status: UserStatus.verified.toShortString(),
        );
      } catch (e) {
        AppLogger.error(
          'Error saving user profile via backend',
          tag: LogTag.signup,
          error: e,
        );
      }

      // Step 4: Navigate to Account Success Screen
      if (mounted) {
        AppLogger.success(
          'Signup completed - navigating to account success screen',
          tag: LogTag.signup,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => _normalizedRole(_selectedRole) == "caregiver"
                ? CaregiverChildAgeScreen(userName: fullName)
                : AccountSuccessScreen(userName: fullName),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      AppLogger.error(
        'Firebase auth error during signup',
        tag: LogTag.signup,
        error: e,
      );
      if (mounted) {
        String message = 'An error occurred';
        if (e.code == 'invalid-verification-code') {
          message = 'Invalid verification code. Please try again.';
        } else if (e.code == 'session-expired') {
          message = 'Verification session expired. Please try again.';
        }
        _showErrorDialog('Verification Error', message);
      }
    } catch (e) {
      AppLogger.error(
        'Unexpected error during signup',
        tag: LogTag.signup,
        error: e,
      );
      if (mounted) {
        _showErrorDialog('Signup Error', e.toString());
      }
    }
  }

  Future<bool> _showEmailVerificationDialog({
    required String userId,
    required String email,
  }) async {
    while (mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Verify Your Email',
              style: TextStyle(
                color: Color(0xFF37474F),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We sent a verification link to $email.',
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Open the email and click the verification link first. Only then tap "I Verified My Email".',
                  style: TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('I Verified My Email'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return false;
      }

      try {
        final response = await ApiService.completeEmailVerification(userId);
        if (response['success'] == true) {
          AppLogger.success(
            'Email verification confirmed by backend',
            tag: LogTag.signup,
          );
          return true;
        }

        if (mounted) {
          _showErrorDialog(
            'Email Not Verified Yet',
            response['error'] ??
                'Please click the verification link in your email first.',
          );
        }
      } catch (e) {
        AppLogger.error(
          'Error completing email verification',
          tag: LogTag.signup,
          error: e,
        );
        if (mounted) {
          _showErrorDialog(
            'Email Not Verified Yet',
            'Please click the verification link in your email first.',
          );
        }
      }
    }

    return false;
  }

  Future<void> _sendFirebaseEmailVerification({
    required String email,
    required String password,
  }) async {
    UserCredential? credential;

    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Unable to sign in for email verification.');
    }

    final user = credential.user;
    if (user == null) {
      throw Exception('Unable to access the created Firebase user.');
    }

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Unable to send verification email.');
    } finally {
      await _auth.signOut();
    }
  }

  // Google Sign-In for Registration
  Future<void> _handleGoogleSignInRegister() async {
    try {
      final result = await AuthService.getGoogleProfileForRegistration();
      
      if (!result['success']) {
        _showErrorDialog('Google Sign-In Failed', result['error'] ?? 'Unknown error');
        return;
      }

      final email = result['email'] as String?;
      final displayName = result['displayName'] as String?;

      // Set signup data for prefilling the form
      ApiService.setSignupData({
        'fullName': displayName ?? '',
        'email': email ?? '',
        'userRole': _normalizedRole(_selectedRole),
      });

      // Populate form fields
      _nameController.text = displayName ?? '';
      _emailController.text = email ?? '';

      // Show success snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google account linked! Please complete your profile.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Google Sign-In Error: $e');
      _showErrorDialog('Google Sign-In Failed', 'Error: $e');
    }
  }

Future<void> _signupUser() async {
  AppLogger.info('Starting signup validation', tag: LogTag.signup);

  // Validation 1: Check if name is empty
  if (_nameController.text.trim().isEmpty) {
    AppLogger.warning('Signup rejected: Empty name', tag: LogTag.signup);
    _showErrorDialog("Please enter your full name");
    return;
  }

  // Validation 2: Check email
  final contact = _emailController.text.trim();
  if (contact.isEmpty) {
    AppLogger.warning('Signup rejected: Empty email', tag: LogTag.signup);
    _showErrorDialog("Please enter an email address");
    return;
  }

  final bool contactIsEmail = _isEmailFormat(contact);
  if (!contactIsEmail) {
    AppLogger.warning('Signup rejected: Invalid email format', tag: LogTag.signup);
    _showErrorDialog("Please enter a valid email address");
    return;
  }

  // Validation 3: Check if password is empty and valid
  final password = _passwordController.text;
  if (password.isEmpty) {
    AppLogger.warning('Signup rejected: Empty password', tag: LogTag.signup);
    _showErrorDialog("Please enter a password");
    return;
  }
  if (!_isPasswordValid(password)) {
    AppLogger.warning('Signup rejected: Weak password', tag: LogTag.signup);
    _showErrorDialog("Password must be at least 8 characters and include a number and special character.");
    return;
  }

  // Validation 4: Check if passwords match
  final confirmPassword = _confirmPasswordController.text;
  if (confirmPassword.isEmpty) {
    AppLogger.warning('Signup rejected: Confirm password is empty', tag: LogTag.signup);
    _showErrorDialog("Please confirm the password entered.");
    return;
  }

  if (password != confirmPassword) {
    AppLogger.warning('Signup rejected: Passwords do not match', tag: LogTag.signup);
    _showErrorDialog("Passwords do not match");
    return;
  }

  // Validation 5: Check if privacy agreed
  if (_normalizedRole(_selectedRole) == null) {
    AppLogger.warning('Signup rejected: Role not selected', tag: LogTag.signup);
    _showErrorDialog("Please select your role");
    return;
  }

  if (!_hasAgreedToPrivacy) {
    AppLogger.warning('Signup rejected: Privacy not agreed', tag: LogTag.signup);
    _showErrorDialog("Please agree to the privacy policy");
    return;
  }

  final confirmed = await _confirmRegistrationCredentials();
  if (confirmed != true) {
    AppLogger.info('Signup confirmation cancelled for review', tag: LogTag.signup);
    return;
  }

  AppLogger.info('All validations passed, proceeding with signup', tag: LogTag.signup);

  // Email-based signup: proceed to signup without phone verification
  _proceedWithSignup();
}

  Future<bool?> _confirmRegistrationCredentials() {
    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final role = _roleLabel(_selectedRole);

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Are you sure these credentials are correct?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please review your registration details before continuing.',
                style: TextStyle(color: Color(0xFF78909C), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text('Name: $fullName'),
              const SizedBox(height: 8),
              Text('Email: $email'),
              const SizedBox(height: 8),
              Text('role: $role'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DB6AC),
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  // --- Privacy Dialog ---
  void _showPrivacyDialog() {
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'How We Collect and Use Your Data',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00B074),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'NutriKidney keeps your information safe and private. We only collect data to help monitor your child’s nutrition and kidney health — such as:',
                        style: TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      _buildBulletPoint('Age'),
                      _buildBulletPoint('Food intake and meal logs'),
                      _buildBulletPoint('Weight and height'),
                      _buildBulletPoint('Medication and hydration records'),
                      _buildBulletPoint('Lab results (optional)'),
                      _buildBulletPoint('Medicine Prescription (optional)'),
                      const SizedBox(height: 8),
                      const Text(
                        'This information helps caregivers and health professionals track progress and make better health recommendations.\n\nYour data will always be stored securely and used only for your child’s health monitoring — never shared without your permission.',
                        style: TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _hasAgreedToPrivacy,
                              activeColor: const Color(0xFF2ECA7F),
                              onChanged: (bool? value) {
                                setStateDialog(() {
                                  _hasAgreedToPrivacy = value ?? false;
                                });
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text.rich(
                              TextSpan(
                                text:
                                    'By signing in I agree to the Data Privacy Terms. ',
                                style: TextStyle(
                                  color: Color(0xFF9E86FF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        "I also consent to NutriKidney collecting my child's health logs and lab results for monitoring and clinical oversight in accordance with the Data Privacy Act of 2012 standards.",
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2ECA7F),
                            minimumSize: const Size(120, 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Back',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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

void _showErrorDialog(String title, [String message = '']) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, height: 1.2)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hintText,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onVisibilityToggle,
    TextInputType keyboardType = TextInputType.text,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9E86FF),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: isPassword && !isVisible,
            keyboardType: keyboardType,
            style: const TextStyle(color: Color(0xFF37474F)),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(
                color: Color(0xFFB0BEC5),
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: isPassword
                  ? IconButton(
                      tooltip: isVisible ? 'Hide password' : 'Show password',
                      icon: Icon(
                        isVisible ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF90A4AE),
                        size: 20,
                      ),
                      onPressed: onVisibilityToggle,
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: const TextStyle(
            color: Color(0xFF9E86FF),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Color(0xFF37474F)),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: const TextStyle(
                      color: Color(0xFFB0BEC5),
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
