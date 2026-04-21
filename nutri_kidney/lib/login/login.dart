import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../create_account/profile_setup_intro.dart';
import '../create_account/register.dart';
import '../main/dashboard.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Phone login controllers/state
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _phoneOtpController = TextEditingController();
  final TextEditingController _resetOtpController = TextEditingController();
  final TextEditingController _resetNewPasswordController =
      TextEditingController();
  final TextEditingController _resetConfirmPasswordController =
      TextEditingController();
  String? _phoneVerificationId;
  bool _showPhoneOtpInput = false;
  String _loginPhoneOtpError = '';
  // Country code selection for phone detection
  String _selectedCountryCode = '+63';
  final List<String> _countryCodes = ['+1', '+63', '+44', '+61', '+91'];

@override
void initState() {
  super.initState();

  // Restore the Remember Me preference and saved contact.
  _loadRememberedLoginState();

  // Listeners to refresh the UI and enable/disable the button instantly
  _emailController.addListener(() => setState(() {}));
  _passwordController.addListener(() => setState(() {}));
}

/// Reads the saved rememberMe flag and pre-fills the saved contact.
Future<void> _loadRememberedLoginState() async {
  final flag = await AuthService.getRememberMeFlag();
  final savedContact = await AuthService.getSavedContact();
  if (mounted) {
    setState(() {
      _rememberMe = flag;
      if (savedContact != null && savedContact.isNotEmpty) {
        _emailController.text = savedContact;
      }
    });
  }
}

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _phoneOtpController.dispose();
    _resetOtpController.dispose();
    _resetNewPasswordController.dispose();
    _resetConfirmPasswordController.dispose();
    super.dispose();
  }

  // Simplified: Now only checks if email and password are not empty
  bool get _isFormValid {
    final contact = _emailController.text.trim();
    final hasPassword = _passwordController.text.isNotEmpty;
    // If the input looks like a phone, allow login button (phone flow)
    if (_isProbablyPhone(contact)) return contact.isNotEmpty;
    return contact.isNotEmpty && hasPassword;
  }

  bool _isProbablyPhone(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    if (s.contains('@')) return false;
    return RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(s);
  }

  String _normalizePhone(String input) {
    var n = input.replaceAll(RegExp(r"[\s\-\(\)]"), '');
    if (n.startsWith('+')) return n;
    n = n.replaceFirst(RegExp(r'^0+'), '');
    return '$_selectedCountryCode$n';
  }

  bool _isValidEmail(String input) {
    final email = input.trim();
    return RegExp(r"^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$").hasMatch(email);
  }

  bool _isPasswordValidForReset(String password) {
    if (password.length < 8) return false;
    if (!RegExp(r'[0-9]').hasMatch(password)) return false;
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(password)) return false;
    return true;
  }

  String _otpErrorMessage(Object error) {
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

  List<String> _buildPhoneVariants(String input) {
    final normalizedPlus = _normalizePhone(input);
    final normalizedNoPlus = normalizedPlus.startsWith('+')
        ? normalizedPlus.substring(1)
        : normalizedPlus;
    final codeNoPlus = _selectedCountryCode.startsWith('+')
        ? _selectedCountryCode.substring(1)
        : _selectedCountryCode;

    String normalizedWithoutCountry = normalizedNoPlus;
    if (normalizedNoPlus.startsWith(codeNoPlus)) {
      normalizedWithoutCountry = normalizedNoPlus.substring(codeNoPlus.length);
    }

    return <String>{
      normalizedPlus,
      normalizedNoPlus,
      normalizedWithoutCountry,
    }.toList();
  }

  Future<String?> _findExistingPhoneNumber(String input) async {
    for (final variant in _buildPhoneVariants(input)) {
      final resp = await ApiService.checkUserExists({"phoneNumber": variant});
      debugPrint('DEBUG check-user phone $variant -> $resp');
      if (resp["success"] == true && resp["exists"] == true) {
        return variant;
      }
    }
    return null;
  }

  Future<bool> _emailExists(String email) async {
    final resp = await ApiService.checkUserExists({"email": email});
    debugPrint('DEBUG check-user email $email -> $resp');
    return resp["success"] == true && resp["exists"] == true;
  }

  Future<void> _restartProfileSetup({
    required String uid,
    String? contact,
  }) async {
    ApiService.setUserId(uid);
    ApiService.clearProfileSetupData();
    await AuthService.saveRememberedSession(uid, false, contact: contact);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please complete your health profile setup.'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ProfileSetupIntroScreen()),
    );
  }

  // Google Sign-In Method (Login) - Uses shared auth service
  Future<void> _handleGoogleSignIn() async {
    try {
      setState(() => _isLoading = true);
      
      final result = await AuthService.handleGoogleSignIn();
      
      if (!result['success']) {
        setState(() => _isLoading = false);
        _showErrorDialog('Google Sign-In Failed', result['error'] ?? 'Unknown error');
        return;
      }

      final userCredential = result['user'] as UserCredential;
      final profileStatus = await ApiService.getProfileStatus(
        uid: userCredential.user?.uid,
        email: result['email'] as String?,
      );

      if (profileStatus['success'] != true ||
          profileStatus['exists'] != true ||
          profileStatus['verified'] != true) {
        await AuthService.signOut();
        setState(() => _isLoading = false);
        _showErrorDialog(
          'Google Sign-In Failed',
          'No registered app account was found for this Google account. Please sign up first.',
        );
        return;
      }

      ApiService.setUserId(userCredential.user!.uid);

      if (profileStatus['profileComplete'] != true) {
        setState(() => _isLoading = false);
        await _restartProfileSetup(
          uid: userCredential.user!.uid,
          contact: result['email'] as String?,
        );
        return;
      }

      // Save Remember Me preference if checked
      await AuthService.saveRememberedSession(
        userCredential.user!.uid,
        _rememberMe,
        contact: result['email'] as String?,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print('Google Sign-In Error: $e');
      _showErrorDialog('Google Sign-In Failed', 'Error: $e');
    }
  }

  void _handleLogin() async {
    if (_isLoading) return; // prevent re-entrancy
    setState(() => _isLoading = true);
    try {
      String enteredEmail = _emailController.text.trim();
      String enteredPassword = _passwordController.text;

      // If the input looks like a phone number, perform phone login flow
      if (_isProbablyPhone(enteredEmail)) {
        if (enteredPassword.isEmpty) {
          _showErrorDialog('Missing Password', 'Please enter your password before continuing.');
          return;
        }

        final normalizedPhone = await _findExistingPhoneNumber(enteredEmail);
        if (normalizedPhone == null) {
          _showErrorDialog('Phone Not Registered', 'This phone number is not registered. Please sign up first.');
          return;
        }

        bool passwordValid = false;
        bool passwordUnsupported = false;
        bool profileMissing = false;
        String? verifiedUserId;
        for (final v in _buildPhoneVariants(enteredEmail)) {
          final resp = await ApiService.verifyPhonePassword({
            "phoneNumber": v,
            "password": enteredPassword,
          });
          debugPrint('DEBUG phone password check $v -> $resp');

          if (resp["success"] == true && resp["valid"] == true) {
            passwordValid = true;
            final userId = resp["userId"];
            if (userId is String && userId.isNotEmpty) {
              verifiedUserId = userId;
            }
            break;
          }

          if (resp["success"] == true && resp["reason"] == "password-not-set") {
            passwordUnsupported = true;
          }
          if (resp["success"] == true && resp["reason"] == "profile-not-found") {
            profileMissing = true;
          }
        }

        if (!passwordValid) {
          if (profileMissing) {
            _showErrorDialog(
              'Phone Login Unavailable',
              'This phone number does not have a completed app account yet. Please finish sign-up first.',
            );
          } else if (passwordUnsupported) {
            _showErrorDialog(
              'Phone Login Unavailable',
              'This account does not support password verification yet. Please use OTP or recreate the account.',
            );
          } else {
            _showErrorDialog('Login Failed', 'Incorrect password. OTP was not sent.');
          }
          return;
        }

        if (verifiedUserId == null) {
          _showErrorDialog(
            'Login Failed',
            'Phone login succeeded but no user ID was returned.',
          );
          return;
        }

        ApiService.setUserId(verifiedUserId);

        final profileStatus = await ApiService.getProfileStatus(
          uid: verifiedUserId,
          phoneNumber: normalizedPhone,
        );
        if (profileStatus['success'] == true &&
            profileStatus['verified'] == true &&
            profileStatus['profileComplete'] != true) {
          await _restartProfileSetup(
            uid: verifiedUserId,
            contact: normalizedPhone,
          );
          return;
        }

        await AuthService.saveRememberedSession(
          verifiedUserId,
          _rememberMe,
          contact: normalizedPhone,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardPage()),
          );
        }
        return;
      }

      // Email/password flow - authenticate via backend
      if (enteredEmail.isEmpty || enteredPassword.isEmpty) {
        _showErrorDialog('Missing Fields', 'Please enter both email and password');
        return;
      }

      // Call backend login endpoint
      final loginResponse = await ApiService.login(
        email: enteredEmail,
        password: enteredPassword,
      );

      if (loginResponse['success'] != true) {
        _showErrorDialog('Login Failed', loginResponse['error'] ?? 'Login failed. Please try again.');
        return;
      }

      final uid = loginResponse['uid'];
      if (uid is! String || uid.isEmpty) {
        _showErrorDialog('Login Failed', 'Failed to get user ID');
        return;
      }

      // Store userId in ApiService
      ApiService.setUserId(uid);

      if (loginResponse['profileComplete'] != true) {
        await _restartProfileSetup(
          uid: uid,
          contact: enteredEmail,
        );
        return;
      }

      // Save credentials if "Remember me" is checked
      await AuthService.saveRememberedSession(
        uid,
        _rememberMe,
        contact: enteredEmail,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
      }
    } catch (e) {
      _showErrorDialog('Login Failed', e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final enteredContact = _emailController.text.trim();

    if (enteredContact.isEmpty) {
      _showErrorDialog(
        'Contact Required',
        'Enter your email address or phone number first so we can reset your password.',
      );
      return;
    }

    try {
      setState(() => _isLoading = true);
      debugPrint('DEBUG forgot-password requested for: $enteredContact');

      if (_isProbablyPhone(enteredContact)) {
        final existingPhone = await _findExistingPhoneNumber(enteredContact);
        if (existingPhone == null) {
          if (!mounted) return;
          _showErrorDialog(
            'Account Not Found',
            'No phone number with "$enteredContact" exists in our database. Please check your entry.',
          );
          return;
        }

        if (!mounted) return;
        setState(() => _isLoading = false);
        await _showPhonePasswordResetDialog(existingPhone, enteredContact);
        return;
      }

      if (!_isValidEmail(enteredContact)) {
        _showErrorDialog(
          'Invalid Email',
          'Please enter a valid email address.',
        );
        return;
      }

      final exists = await _emailExists(enteredContact);
      if (!exists) {
        if (!mounted) return;
        _showErrorDialog(
          'Account Not Found',
          'No email with "$enteredContact" exists in our database. Please check your entry.',
        );
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: enteredContact);

      if (!mounted) return;
      _showSuccessDialog(
        'Reset Email Sent',
        'We sent a password reset link to $enteredContact. Check your inbox and spam folder.',
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage =
          e.message ?? 'Unable to send reset email right now.';

      if (e.code == 'invalid-email') {
        errorMessage = 'Please enter a valid email address.';
      } else if (e.code == 'user-not-found') {
        errorMessage = 'No account found with this email.';
      } else if (e.code == 'missing-email') {
        errorMessage = 'Please enter your email address first.';
      } else if (e.code == 'too-many-requests') {
        errorMessage =
            'Too many attempts. Please wait a bit before trying again.';
      }

      if (!mounted) return;
      _showErrorDialog('Reset Failed', errorMessage);
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('Reset Failed', e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showPhonePasswordResetDialog(
    String phoneNumber,
    String displayValue,
  ) async {
    _resetOtpController.clear();
    _resetNewPasswordController.clear();
    _resetConfirmPasswordController.clear();

    String? verificationId;
    bool otpSent = false;
    bool otpRequestStarted = false;
    bool verified = false;
    bool isSubmitting = false;
    bool dialogOpen = true;
    bool isClosingDialog = false;
    User? verifiedUser;
    String resetOtpError = '';

    Future<void> closeResetDialog(BuildContext dialogContext) async {
      if (isClosingDialog) return;
      isClosingDialog = true;
      dialogOpen = false;

      FocusScope.of(dialogContext).unfocus();

      try {
        await _auth.signOut();
      } catch (_) {}

      if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop();
      }
    }

    Future<void> sendOtp(StateSetter setStateDialog) async {
      try {
        debugPrint('DEBUG reset OTP request started for $phoneNumber');
        await _auth.verifyPhoneNumber(
          phoneNumber: phoneNumber,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {
            if (!dialogOpen) return;
            debugPrint('DEBUG reset OTP auto-verified for $phoneNumber');
            final userCred = await _auth.signInWithCredential(credential);
            verifiedUser = userCred.user;
            if (!dialogOpen) return;
            setStateDialog(() {
              verified = true;
              otpSent = true;
            });
          },
          verificationFailed: (e) {
            if (!dialogOpen || !mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Verification failed: ${e.message}')),
            );
          },
          codeSent: (verId, _) {
            if (!dialogOpen) return;
            verificationId = verId;
            debugPrint('DEBUG reset OTP sent to $phoneNumber');
            setStateDialog(() {
              otpSent = true;
            });
          },
          codeAutoRetrievalTimeout: (verId) {
            verificationId = verId;
            debugPrint('DEBUG reset OTP auto-retrieval timeout for $phoneNumber');
          },
        );
      } catch (e) {
        if (!dialogOpen || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send OTP failed: $e')),
        );
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            if (!otpRequestStarted) {
              otpRequestStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogOpen) {
                  sendOtp(setStateDialog);
                }
              });
            }

            return PopScope(
              canPop: !isSubmitting,
              onPopInvokedWithResult: (_, __) async {
                if (!isSubmitting) {
                  await closeResetDialog(dialogContext);
                }
              },
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text('Reset Phone Password'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      verified
                          ? 'Enter your new password for $displayValue.'
                          : 'Enter the OTP sent to $displayValue to continue.',
                      style: const TextStyle(color: Color(0xFF78909C)),
                    ),
                    const SizedBox(height: 12),
                    if (!verified) ...[
                      TextField(
                        controller: _resetOtpController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: '000000',
                          labelText: 'OTP',
                          errorText: resetOtpError.isNotEmpty ? resetOtpError : null,
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: _resetNewPasswordController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.visiblePassword,
                        obscureText: true,
                        onSubmitted: (_) =>
                            FocusScope.of(dialogContext).nextFocus(),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          labelText: 'New password',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _resetConfirmPasswordController,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.visiblePassword,
                        obscureText: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          labelText: 'Confirm password',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use at least 8 characters with a number and a special character.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF78909C)),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            await closeResetDialog(dialogContext);
                          },
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                          if (!verified) {
                            final otp = _resetOtpController.text.trim();
                            if (otp.isEmpty || verificationId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enter the OTP')),
                              );
                              return;
                            }

                            try {
                              debugPrint(
                                'DEBUG reset OTP verify tapped for $phoneNumber with input length=${otp.length}',
                              );
                              setStateDialog(() => isSubmitting = true);
                              final cred = PhoneAuthProvider.credential(
                                verificationId: verificationId!,
                                smsCode: otp,
                              );
                              final userCred =
                                  await _auth.signInWithCredential(cred);
                              debugPrint(
                                'DEBUG reset OTP manually verified for $phoneNumber',
                              );
                              verifiedUser = userCred.user;
                              if (!dialogOpen) return;
                              FocusScope.of(dialogContext).unfocus();
                              setStateDialog(() {
                                verified = true;
                                isSubmitting = false;
                              });
                            } catch (e) {
                              debugPrint(
                                'DEBUG reset OTP verify failed for $phoneNumber: $e',
                              );
                              if (!dialogOpen || !mounted) return;
                              setStateDialog(() {
                                isSubmitting = false;
                                resetOtpError = _otpErrorMessage(e);
                              });
                              _resetOtpController.clear();
                            }
                            return;
                          }

                          final newPassword = _resetNewPasswordController.text;
                          final confirmPassword =
                              _resetConfirmPasswordController.text;

                          if (!_isPasswordValidForReset(newPassword)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password must be at least 8 characters and include a number and special character.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (newPassword != confirmPassword) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passwords do not match.'),
                              ),
                            );
                            return;
                          }

                          try {
                            setStateDialog(() => isSubmitting = true);
                            final idToken =
                                await verifiedUser?.getIdToken(true);
                            final resp = await ApiService.resetPassword({
                              "phoneNumber": phoneNumber,
                              "newPassword": newPassword,
                              "idToken": idToken,
                            });
                            debugPrint(
                              'DEBUG reset-password response for $phoneNumber -> $resp',
                            );

                            if (resp["success"] != true) {
                              throw Exception(
                                resp["error"] ??
                                    'Unable to reset phone password.',
                              );
                            }

                            await closeResetDialog(dialogContext);
                            if (!mounted) return;
                            _showSuccessDialog(
                              'Password Updated',
                              'Your password has been updated for $displayValue. You can log in with your new password now.',
                            );
                          } catch (e) {
                            if (!dialogOpen || !mounted) return;
                            setStateDialog(() => isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Reset failed: $e'),
                              ),
                            );
                          }
                        },
                    child: Text(isSubmitting
                        ? 'Please wait...'
                        : (verified ? 'Update Password' : 'Verify OTP')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPhoneSignInDialog([String? initialPhone]) async {
    _phoneController.text = initialPhone ?? '';
    _phoneOtpController.text = '';
    _showPhoneOtpInput = false;
    _phoneVerificationId = null;

    bool started = false;
    bool dialogOpen = true;
    bool isClosingDialog = false;

    void resetPhoneDialogState() {
      _phoneVerificationId = null;
      _phoneOtpController.clear();
      _showPhoneOtpInput = false;
    }

    Future<void> closeDialogIfOpen(BuildContext dialogContext) async {
      if (!dialogOpen || isClosingDialog) return;
      isClosingDialog = true;
      dialogOpen = false;

      resetPhoneDialogState();

      if (Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop();
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (_, __) async {
            await closeDialogIfOpen(dialogContext);
          },
          child: StatefulBuilder(builder: (dialogContext, setStateDialog) {
          // If initialPhone is provided, start sending OTP once.
          if (initialPhone != null && !started) {
            started = true;
            try {
              _auth.verifyPhoneNumber(
                phoneNumber: initialPhone,
                timeout: const Duration(seconds: 60),
                verificationCompleted: (PhoneAuthCredential credential) async {
                  if (!dialogOpen || isClosingDialog || !mounted) return;
                  final userCred = await _auth.signInWithCredential(credential);
                  ApiService.setUserId(userCred.user!.uid);
                  await AuthService.saveRememberedSession(
                    userCred.user!.uid,
                    _rememberMe,
                    contact: initialPhone,
                  );
                  if (mounted && dialogOpen && !isClosingDialog) {
                    await closeDialogIfOpen(dialogContext);
                    Navigator.of(this.context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const DashboardPage()),
                    );
                  }
                },
                verificationFailed: (e) {
                  if (!dialogOpen || isClosingDialog || !mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Verification failed: ${e.message}')),
                  );
                },
                codeSent: (verId, _) {
                  if (!dialogOpen || isClosingDialog) return;
                  _phoneVerificationId = verId;
                  setStateDialog(() {
                    _showPhoneOtpInput = true;
                    _loginPhoneOtpError = '';
                  });
                },
                codeAutoRetrievalTimeout: (verId) {
                  _phoneVerificationId = verId;
                },
              );
            } catch (e) {
              if (dialogOpen && !isClosingDialog && mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Send OTP failed: $e')),
                );
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Sign in with Phone'),
            content: _showPhoneOtpInput
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Enter the OTP sent to your phone'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneOtpController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          hintText: '000000',
                          errorText: _loginPhoneOtpError.isNotEmpty ? _loginPhoneOtpError : null,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('We will send an OTP to this phone to sign you in'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), hintText: '+63 912 345 6789'),
                      ),
                    ],
                  ),
            actions: [
              TextButton(
                onPressed: () async {
                  await closeDialogIfOpen(dialogContext);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (_showPhoneOtpInput) {
                    final otp = _phoneOtpController.text.trim();
                    if (otp.isEmpty || _phoneVerificationId == null) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Enter the OTP')),
                      );
                      return;
                    }
                    try {
                      debugPrint(
                        'DEBUG login OTP verify tapped with input length=${otp.length}',
                      );
                      final cred = PhoneAuthProvider.credential(verificationId: _phoneVerificationId!, smsCode: otp);
                      final userCred = await _auth.signInWithCredential(cred);
                      if (!dialogOpen || isClosingDialog || !mounted) return;
                      ApiService.setUserId(userCred.user!.uid);
                      await AuthService.saveRememberedSession(
                        userCred.user!.uid,
                        _rememberMe,
                        contact: _phoneController.text.trim(),
                      );
                      await closeDialogIfOpen(dialogContext);
                      if (mounted && !isClosingDialog) {
                        Navigator.of(this.context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const DashboardPage()),
                        );
                      }
                    } catch (e) {
                      debugPrint('DEBUG login OTP verify failed: $e');
                      if (dialogOpen && !isClosingDialog && mounted) {
                        setState(() {
                          _loginPhoneOtpError = _otpErrorMessage(e);
                        });
                        _phoneOtpController.clear();
                      }
                    }
                  } else {
                    // Manual send if user enters number here
                    final phone = _phoneController.text.trim();
                    if (phone.isEmpty) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Enter phone number')),
                      );
                      return;
                    }
                    try {
                      await _auth.verifyPhoneNumber(
                        phoneNumber: phone,
                        timeout: const Duration(seconds: 60),
                        verificationCompleted: (PhoneAuthCredential credential) async {
                          if (!dialogOpen || isClosingDialog || !mounted) return;
                          final userCred = await _auth.signInWithCredential(credential);
                          ApiService.setUserId(userCred.user!.uid);
                          await AuthService.saveRememberedSession(
                            userCred.user!.uid,
                            _rememberMe,
                            contact: phone,
                          );
                          if (mounted && dialogOpen && !isClosingDialog) {
                            await closeDialogIfOpen(dialogContext);
                            Navigator.of(this.context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const DashboardPage()),
                            );
                          }
                        },
                        verificationFailed: (e) {
                          if (dialogOpen && !isClosingDialog && mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Verification failed: ${e.message}')),
                            );
                          }
                        },
                        codeSent: (verId, _) {
                          if (!dialogOpen || isClosingDialog) return;
                          _phoneVerificationId = verId;
                          setStateDialog(() {
                            _showPhoneOtpInput = true;
                            _loginPhoneOtpError = '';
                          });
                        },
                        codeAutoRetrievalTimeout: (verId) {
                          _phoneVerificationId = verId;
                        },
                      );
                    } catch (e) {
                      if (dialogOpen && !isClosingDialog && mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Send OTP failed: $e')),
                        );
                      }
                    }
                  }
                },
                child: Text(_showPhoneOtpInput ? 'Verify OTP' : 'Send OTP'),
              ),
            ],
          );
          }),
        );
      },
    );

    dialogOpen = false;
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(color: Color(0xFF78909C)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF5F5F5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.mark_email_read_outlined, color: Color(0xFF4DB6AC), size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(color: Color(0xFF78909C)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF5F5F5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF7),
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Background Graphics
            Positioned(
              top: -200,
              left: -120,
              right: -60,
              child: Image.asset(
                'assets/images/salad_header.png',
                fit: BoxFit.fitWidth,
              ),
            ),
            Positioned(
              bottom: -360,
              left: -110,
              right: -90,
              child: Image.asset(
                'assets/images/bottom_waves.png',
                fit: BoxFit.fitWidth,
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 120),
                    const Text(
                      'Nutri\nKidney',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'FredokaOne',
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        color: Color(0xFF37474F),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Log in',
                      style: TextStyle(fontSize: 22, color: Color(0xFF90A4AE)),
                    ),
                    const SizedBox(height: 40),

                    // Email or Phone input with inline country-code selector when a phone is detected
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email or Phone',
                          style: const TextStyle(
                            color: Color(0xFF9E86FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              if (_isProbablyPhone(_emailController.text))
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: DropdownButton<String>(
                                    value: _selectedCountryCode,
                                    items: _countryCodes
                                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() {
                                        _selectedCountryCode = val;
                                      });
                                    },
                                    underline: const SizedBox.shrink(),
                                    style: const TextStyle(color: Color(0xFF37474F)),
                                  ),
                                ),
                              Expanded(
                                child: TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.text,
                                  style: const TextStyle(color: Color(0xFF37474F)),
                                  decoration: InputDecoration(
                                    hintText: 'you@example.com or +63 912 345 6789',
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
                    ),
                    const SizedBox(height: 20),

                    _buildInputField(
                      label: 'Password',
                      hintText: '••••••••',
                      isPassword: true,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Remember Me Checkbox
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                              activeColor: const Color(0xFF4DB6AC),
                            ),
                            const Text(
                              'Remember me',
                              style: TextStyle(
                                color: Color(0xFF37474F),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        // Forgot Password Link
                        TextButton(
                          onPressed: _isLoading ? null : _handleForgotPassword,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              color: Color(0xFF81C784),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // Log In Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : (_isFormValid ? _handleLogin : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4DB6AC),
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Log in',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Google Sign-In Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DB6AC)),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_circle, color: Color(0xFF4DB6AC), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Log in with Google',
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
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'No account? ',
                          style: TextStyle(
                            color: Color(0xFF37474F),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterPage(),
                              ),
                            );
                          },
                          child: const Text(
                            'Sign up here',
                            style: TextStyle(
                              color: Color(0xFF37474F),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
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

  Widget _buildInputField({
    required String label,
    required String hintText,
    bool isPassword = false,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            obscureText: isPassword && !_isPasswordVisible,
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
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: const Color(0xFF90A4AE),
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
