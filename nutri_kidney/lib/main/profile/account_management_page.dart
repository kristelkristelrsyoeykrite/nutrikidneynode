import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../login/login.dart';
import '../../services/auth_service.dart';
import '../authenticator_mfa_page.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';

class AccountManagementPage extends StatefulWidget {
  final String email;
  final String roleLabel;
  final String verificationContact;
  final String linkedProfileEmail;
  final String linkedProfileRoleLabel;

  const AccountManagementPage({
    super.key,
    required this.email,
    required this.roleLabel,
    required this.verificationContact,
    required this.linkedProfileEmail,
    required this.linkedProfileRoleLabel,
  });

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _currentPasswordController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _confirmPasswordController;
  late final TextEditingController _verificationController;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  bool get _passwordFieldsAreFilled =>
      _currentPasswordController.text.trim().isNotEmpty &&
      _newPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty &&
      _verificationController.text.trim().isNotEmpty;

  bool get _passwordsDoNotMatch =>
      _newPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty &&
      _newPasswordController.text != _confirmPasswordController.text;

  bool get _canSubmitPasswordChange =>
      widget.verificationContact.isNotEmpty &&
      _passwordFieldsAreFilled &&
      !_passwordsDoNotMatch;

  String? get _confirmPasswordErrorText =>
      _passwordsDoNotMatch ? 'Passwords do not match' : null;

  void _handlePasswordFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _confirmPasswordUpdateRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Password Update'),
          content: const Text(
            'Your password will only be changed after you finish the verification step for this request.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<bool> _confirmSensitiveActionWithMfa() async {
    final settingsResponse = await ApiService.getSecuritySettings();
    final settings = authenticatorSecuritySettingsFromResponse(settingsResponse);
    if (settings['mfaEnabled'] != true) {
      return true;
    }

    final currentUserId = ApiService.userId;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception('UserId not set. Please log in again.');
    }

    return showAuthenticatorMfaChallengeDialog(
      context,
      uid: currentUserId,
      purpose: 'password_change',
      securitySettings: settings,
    );
  }

  @override
  void initState() {
    super.initState();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _verificationController = TextEditingController();
    _currentPasswordController.addListener(_handlePasswordFieldChanged);
    _newPasswordController.addListener(_handlePasswordFieldChanged);
    _confirmPasswordController.addListener(_handlePasswordFieldChanged);
    _verificationController.addListener(_handlePasswordFieldChanged);
  }

  @override
  void dispose() {
    _currentPasswordController.removeListener(_handlePasswordFieldChanged);
    _newPasswordController.removeListener(_handlePasswordFieldChanged);
    _confirmPasswordController.removeListener(_handlePasswordFieldChanged);
    _verificationController.removeListener(_handlePasswordFieldChanged);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _verificationController.dispose();
    super.dispose();
  }

  bool _isPasswordStrong(String password) {
    if (password.length < 8) return false;
    if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
    if (!RegExp(r'[0-9]').hasMatch(password)) return false;
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) return false;
    return true;
  }

  Future<void> _changePassword() async {
    if (!_canSubmitPasswordChange) return;
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await _confirmPasswordUpdateRequest();
    if (!confirmed) return;

    setState(() => _isSaving = true);
    try {
      final passedMfa = await _confirmSensitiveActionWithMfa();
      if (!passedMfa) return;

      final response = await ApiService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        verificationContact: _verificationController.text.trim(),
      );

      if (!mounted) return;
      if (response["success"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully.'),
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ?? 'Unable to update password.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update password: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<String?> _promptForSecret({
    required String title,
    required String message,
    required String label,
    bool obscureText = false,
    bool digitsOnly = false,
    int? maxLength,
    String? Function(String value)? validator,
  }) async {
    final controller = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    obscureText: obscureText,
                    keyboardType:
                        digitsOnly ? TextInputType.number : TextInputType.text,
                    maxLength: maxLength,
                    decoration: InputDecoration(
                      labelText: label,
                      counterText: '',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    final validationError = validator?.call(value);
                    if (validationError != null) {
                      setDialogState(() => errorText = validationError);
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    if (_isDeleting) return;

    setState(() => _isDeleting = true);
    try {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Delete Account?'),
            content: const Text(
              'This will disable sign-in immediately and schedule permanent deletion of your NutriKidney account and health data. You will need your password and Microsoft Authenticator to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
      if (!mounted || proceed != true) return;

      final settingsResponse = await ApiService.getSecuritySettings();
      final settings =
          authenticatorSecuritySettingsFromResponse(settingsResponse);
      if (settings['authenticatorEnabled'] != true ||
          settings['hasAuthenticatorSecret'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable Microsoft Authenticator MFA before deleting this account.',
            ),
          ),
        );
        return;
      }

      final password = await _promptForSecret(
        title: 'Reauthenticate',
        message:
            'Enter your current password before account deletion can continue.',
        label: 'Current password',
        obscureText: true,
        validator: (value) =>
            value.isEmpty ? 'Current password is required.' : null,
      );
      if (!mounted || password == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;
      final email = currentUser?.email ?? widget.email;
      if (currentUser == null || email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in again before deleting.')),
        );
        return;
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);

      if (!mounted) return;
      final totpCode = await _promptForSecret(
        title: 'Microsoft Authenticator',
        message:
            'Enter the 6-digit verification code from Microsoft Authenticator. Codes expire every 30 seconds.',
        label: '6-digit code',
        digitsOnly: true,
        maxLength: 6,
        validator: (value) =>
            RegExp(r'^\d{6}$').hasMatch(value) ? null : 'Enter a valid 6-digit code.',
      );
      if (!mounted || totpCode == null) return;

      final confirmation = await _promptForSecret(
        title: 'Final Confirmation',
        message:
            'This permanently schedules deletion of your NutriKidney account and health data. Type DELETE MY ACCOUNT to continue.',
        label: 'DELETE MY ACCOUNT',
        validator: (value) => value == 'DELETE MY ACCOUNT'
            ? null
            : 'Type DELETE MY ACCOUNT exactly.',
      );
      if (!mounted || confirmation == null) return;

      final idToken = await currentUser.getIdToken(true);
      final response = await ApiService.requestAccountDeletion(
        password: password,
        totpCode: totpCode,
        idToken: idToken ?? '',
      );
      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'Account deletion failed.');
      }

      await NotificationService.cancelAllForCurrentUser();
      await AuthService.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response['scheduledDeletionAt'] == null
                ? 'Account deletion requested.'
                : 'Account scheduled for deletion on ${response['scheduledDeletionAt']}.',
          ),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  InputDecoration _fieldDecoration(
    String label, {
    Widget? suffixIcon,
    String? hintText,
    TextStyle? hintStyle,
    String? errorText,
    bool readOnly = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      hintStyle: hintStyle,
      errorText: errorText,
      filled: true,
      fillColor: readOnly ? const Color(0xFFEFF3F1) : const Color(0xFFF8FBFA),
      prefixIcon: readOnly
          ? const Icon(
              Icons.lock_outline,
              size: 18,
              color: Color(0xFF90A4AE),
            )
          : null,
      helperText: readOnly ? 'Read-only' : null,
      helperStyle: const TextStyle(
        color: Color(0xFF90A4AE),
        fontSize: 11,
      ),
      labelStyle: TextStyle(
        color: readOnly ? const Color(0xFF78909C) : null,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: readOnly ? const Color(0xFFCFD8D4) : const Color(0xFFDCE9E4),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: readOnly ? const Color(0xFFCFD8D4) : const Color(0xFFDCE9E4),
        ),
      ),
      suffixIcon: suffixIcon,
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value.isEmpty ? 'Not linked' : value,
        readOnly: true,
        enableInteractiveSelection: false,
        style: const TextStyle(
          color: Color(0xFF78909C),
          fontWeight: FontWeight.w600,
        ),
        decoration: _fieldDecoration(label, readOnly: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const verificationLabel = 'Linked email confirmation';
    final verificationHint = widget.verificationContact.isNotEmpty
        ? 'Type ${widget.verificationContact} exactly as shown'
        : 'No linked email found';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        title: const Text('Account Management'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE1ECE8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account Details',
                      style: TextStyle(
                        color: Color(0xFF37474F),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _readOnlyField('Linked Email', widget.email),
                    _readOnlyField('Role', widget.roleLabel),
                    if (widget.linkedProfileEmail != widget.email ||
                        widget.linkedProfileRoleLabel != widget.roleLabel) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Linked Profile Data',
                        style: TextStyle(
                          color: Color(0xFF546E7A),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _readOnlyField(
                        'Linked Profile Email',
                        widget.linkedProfileEmail,
                      ),
                      _readOnlyField(
                        'Linked Profile Role',
                        widget.linkedProfileRoleLabel,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE1ECE8)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Change Password',
                        style: TextStyle(
                          color: Color(0xFF37474F),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'To protect this account, enter the current password, complete MFA if enabled, and confirm the linked contact on file.',
                        style: TextStyle(
                          color: Color(0xFF78909C),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _currentPasswordController,
                        obscureText: !_showCurrentPassword,
                        decoration: _fieldDecoration(
                          'Current Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _showCurrentPassword = !_showCurrentPassword;
                              });
                            },
                            icon: Icon(
                              _showCurrentPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Current password is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: !_showNewPassword,
                        decoration: _fieldDecoration(
                          'New Password',
                          hintText:
                              'At least 8 characters, with uppercase, number, and symbol',
                          hintStyle: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _showNewPassword = !_showNewPassword;
                              });
                            },
                            icon: Icon(
                              _showNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) return 'New password is required';
                          if (!_isPasswordStrong(text)) {
                            return 'Use at least 8 characters, an uppercase letter, a number, and a symbol';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_showConfirmPassword,
                        decoration: _fieldDecoration(
                          'Confirm New Password',
                          errorText: _confirmPasswordErrorText,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _showConfirmPassword = !_showConfirmPassword;
                              });
                            },
                            icon: Icon(
                              _showConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm the new password';
                          }
                          if (value != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _verificationController,
                        decoration: _fieldDecoration(
                          verificationLabel,
                          hintText: verificationHint,
                        ),
                        validator: (value) {
                          if (widget.verificationContact.isEmpty) {
                            return 'No linked verification contact found';
                          }
                          if (value == null || value.trim().isEmpty) {
                            return 'Verification confirmation is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2FBF7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD6ECE4)),
                        ),
                        child: Text(
                          widget.verificationContact.isEmpty
                              ? 'A linked email is required before password changes can be verified.'
                              : 'Verification contact on file: ${widget.verificationContact}',
                          style: const TextStyle(
                            color: Color(0xFF546E7A),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving || !_canSubmitPasswordChange
                              ? null
                              : _changePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C874),
                            disabledBackgroundColor: const Color(0xFFB0BEC5),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Update Password',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFCDD2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delete Account',
                      style: TextStyle(
                        color: Color(0xFFD32F2F),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Deleting your account permanently removes health records, medications, food logs, hydration logs, caregiver links, notifications, analytics, and uploaded files. This action cannot be undone.',
                      style: TextStyle(
                        color: Color(0xFF78909C),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Requires password reauthentication, Microsoft Authenticator, and final typed confirmation.',
                      style: TextStyle(
                        color: Color(0xFF546E7A),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSaving || _isDeleting ? null : _deleteAccount,
                        icon: _isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_forever_outlined),
                        label: Text(
                          _isDeleting ? 'Scheduling Deletion...' : 'Delete Account',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD32F2F),
                          side: const BorderSide(color: Color(0xFFD32F2F)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
