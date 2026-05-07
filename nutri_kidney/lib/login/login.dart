import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../create_account/profile_setup_intro.dart';
import '../main/authenticator_mfa_page.dart';
import '../create_account/register.dart';
import '../main/dashboard.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';

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
    super.dispose();
  }

  bool get _isFormValid {
    final email = _emailController.text.trim();
    final hasPassword = _passwordController.text.isNotEmpty;
    return email.isNotEmpty && hasPassword;
  }

  bool _isValidEmail(String input) {
    final email = input.trim();
    return RegExp(r"^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$").hasMatch(email);
  }

  Future<bool> _emailExists(String email) async {
    final resp = await ApiService.checkUserExists({"email": email});
    debugPrint('DEBUG check-user email $email -> $resp');
    return resp["success"] == true && resp["exists"] == true;
  }

  Future<void> _restartProfileSetup({
    required String uid,
    String? contact,
    String? userRole,
  }) async {
    ApiService.setUserId(uid);
    ApiService.setUserRole(userRole);
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

  Map<String, dynamic> _profileMapFromResponse(Map<String, dynamic> response) {
    final profile = response['profile'];
    if (profile is Map<String, dynamic>) return profile;
    if (profile is Map) return Map<String, dynamic>.from(profile);
    return {};
  }

  bool _isMfaEnabled(Map<String, dynamic> response) {
    return isAuthenticatorMfaEnabled(response);
  }

  Future<bool> _runMfaChallenge({
    required String uid,
    Map<String, dynamic>? securitySettings,
    String? method,
  }) async {
    return showAuthenticatorMfaChallengeDialog(
      context,
      uid: uid,
      securitySettings: {
        if (method != null) 'mfaMethod': method,
        ...?securitySettings,
      },
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

      if (profileStatus['needsProfileSetup'] == true) {
        setState(() => _isLoading = false);
        await _restartProfileSetup(
          uid: userCredential.user!.uid,
          contact: result['email'] as String?,
          userRole: profileStatus['userRole']?.toString() ??
              profileStatus['role']?.toString() ??
              _profileMapFromResponse(profileStatus)['userRole']?.toString() ??
              _profileMapFromResponse(profileStatus)['role']?.toString(),
        );
        return;
      }

      if (_isMfaEnabled(profileStatus)) {
        final passedMfa = await _runMfaChallenge(
          uid: userCredential.user!.uid,
          securitySettings: authenticatorSecuritySettingsFromResponse(profileStatus),
          method: mfaMethodFromResponse(profileStatus),
        );
        if (!passedMfa) {
          await AuthService.signOut();
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      // Save Remember Me preference if checked
      await AuthService.saveRememberedSession(
        userCredential.user!.uid,
        _rememberMe,
        contact: result['email'] as String?,
      );
      await PushNotificationService.syncTokenIfPossible();

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

      // Keep the app's Firebase session in sync with the backend login result.
      await _auth.signInWithEmailAndPassword(
        email: enteredEmail,
        password: enteredPassword,
      );

      // Store userId in ApiService
      ApiService.setUserId(uid);

      if (loginResponse['needsProfileSetup'] == true) {
        await _restartProfileSetup(
          uid: uid,
          contact: enteredEmail,
          userRole: loginResponse['userRole']?.toString() ??
              loginResponse['role']?.toString() ??
              _profileMapFromResponse(loginResponse)['userRole']?.toString() ??
              _profileMapFromResponse(loginResponse)['role']?.toString(),
        );
        return;
      }

      if (_isMfaEnabled(loginResponse)) {
        final passedMfa = await _runMfaChallenge(
          uid: uid,
          securitySettings: authenticatorSecuritySettingsFromResponse(loginResponse),
          method: mfaMethodFromResponse(loginResponse),
        );
        if (!passedMfa) {
          return;
        }
      }

      // Save credentials if "Remember me" is checked
      await AuthService.saveRememberedSession(
        uid,
        _rememberMe,
        contact: enteredEmail,
      );
      await PushNotificationService.syncTokenIfPossible();

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
        'Email Required',
        'Enter your email address first so we can reset your password.',
      );
      return;
    }

    try {
      setState(() => _isLoading = true);
      debugPrint('DEBUG forgot-password requested for: $enteredContact');

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

                    // Email input
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Email',
                          style: TextStyle(
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
                      tooltip: _isPasswordVisible
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
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
