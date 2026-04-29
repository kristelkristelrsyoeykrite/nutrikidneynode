import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';

Map<String, dynamic> authenticatorSecuritySettingsFromResponse(
  Map<String, dynamic> response,
) {
  final directSettings = response['securitySettings'];
  if (directSettings is Map<String, dynamic>) return directSettings;
  if (directSettings is Map) return Map<String, dynamic>.from(directSettings);

  final profile = response['profile'];
  if (profile is Map<String, dynamic>) {
    final nested = profile['securitySettings'];
    if (nested is Map<String, dynamic>) return nested;
    if (nested is Map) return Map<String, dynamic>.from(nested);
  } else if (profile is Map) {
    final nested = profile['securitySettings'];
    if (nested is Map<String, dynamic>) return nested;
    if (nested is Map) return Map<String, dynamic>.from(nested);
  }

  return {};
}

String mfaMethodFromResponse(Map<String, dynamic> response) {
  final rawMethod = response['mfaMethod']?.toString().trim();
  if (rawMethod == 'authenticator') {
    return rawMethod!;
  }

  final settings = authenticatorSecuritySettingsFromResponse(response);
  final nestedMethod = settings['mfaMethod']?.toString().trim();
  if (nestedMethod == 'authenticator') {
    return nestedMethod!;
  }

  return 'none';
}

bool isAuthenticatorMfaEnabled(Map<String, dynamic> response) {
  if (response['mfaRequired'] == true) {
    return mfaMethodFromResponse(response) != 'none';
  }

  final settings = authenticatorSecuritySettingsFromResponse(response);
  return mfaMethodFromResponse(response) == 'authenticator' &&
      (settings['mfaEnabled'] == true ||
          settings['authenticatorEnabled'] == true);
}

Future<bool> showAuthenticatorMfaChallengeDialog(
  BuildContext context, {
  required String uid,
  String purpose = 'login',
  Map<String, dynamic>? securitySettings,
}) async {
  final codeController = TextEditingController();
  var isSubmitting = false;
  var errorText = '';
  var verified = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Authenticator Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Open Microsoft Authenticator and enter the current 6-digit code.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: '6-digit code',
                    errorText: errorText.isEmpty ? null : errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() {
                          isSubmitting = true;
                          errorText = '';
                        });

                        try {
                          final response =
                              await ApiService.verifyAuthenticatorMfaCode(
                            uid: uid,
                            code: codeController.text.trim(),
                          );

                          if (response['success'] != true) {
                            throw Exception(
                              response['error'] ??
                                  'The verification could not be confirmed.',
                            );
                          }

                          verified = true;
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            isSubmitting = false;
                            errorText = error.toString().replaceFirst('Exception: ', '');
                          });
                        }
                    },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
            ],
          );
        },
      );
    },
  );

  return verified;
}

class AuthenticatorMfaPage extends StatefulWidget {
  final bool initialMfaEnabled;
  final String accountLabel;

  const AuthenticatorMfaPage({
    super.key,
    required this.initialMfaEnabled,
    required this.accountLabel,
  });

  @override
  State<AuthenticatorMfaPage> createState() => _AuthenticatorMfaPageState();
}

class _AuthenticatorMfaPageState extends State<AuthenticatorMfaPage>
    with WidgetsBindingObserver {
  final TextEditingController _codeController = TextEditingController();
  bool _mfaEnabled = false;
  bool _isLoading = true;
  bool _isWorking = false;
  String? _otpauthUrl;
  String? _errorText;
  String? _infoMessage;
  bool _hasPendingEnrollment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mfaEnabled = widget.initialMfaEnabled;
    _loadSecuritySettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload settings when returning from background (e.g., after using authenticator app)
    if (state == AppLifecycleState.resumed && mounted) {
      _loadSecuritySettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final response = await ApiService.getSecuritySettings();
      if (!mounted) return;

      final settings = authenticatorSecuritySettingsFromResponse(response);
      setState(() {
        _mfaEnabled = settings['mfaEnabled'] == true;
        _hasPendingEnrollment = settings['hasPendingEnrollment'] == true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _isWorking = true;
      _errorText = null;
      _infoMessage = null;
    });

    try {
      final response = await ApiService.startAuthenticatorMfaSetup(
        email: widget.accountLabel,
      );
      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'Unable to start MFA setup.');
      }

      final isReusing = response['reusedSecret'] == true;

      if (!mounted) return;
      setState(() {
        _otpauthUrl = response['otpauthUrl']?.toString();
        _hasPendingEnrollment = true;
        
        // If reusing, show appropriate message
        if (isReusing) {
          _infoMessage = 'Using existing authenticator setup. Enter the current 6-digit code from your app.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _verifyEnrollment() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _errorText = 'Enter a valid 6-digit code.';
      });
      return;
    }

    setState(() {
      _isWorking = true;
      _errorText = null;
      _infoMessage = null;
    });

    try {
      final response = await ApiService.verifyAuthenticatorMfaSetup(code: code);
      
      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'Invalid verification.');
      }

      // For authenticator, the code verification also enables it.
      await _loadSecuritySettings();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authenticator MFA enabled.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _errorText = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<String?> _promptForDisableCode() async {
    final controller = TextEditingController();
    var errorText = '';

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text('Disable MFA'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter the current 6-digit code from Microsoft Authenticator to turn off MFA.',
                    ),
                    const SizedBox(height: 12),
                  TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: '6-digit code',
                        errorText: errorText.isEmpty ? null : errorText,
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
                  TextButton(
                    onPressed: () {
                      final code = controller.text.trim();
                      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                        setDialogState(() {
                          errorText = 'Enter a valid 6-digit code.';
                        });
                        return;
                      }
                      Navigator.of(dialogContext).pop(code);
                    },
                    child: const Text('Disable'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _disableMfa() async {
    final mfaCode = await _promptForDisableCode();
    if (!mounted || mfaCode == null) return;

    setState(() {
      _isWorking = true;
      _errorText = null;
    });

    try {
      final response = await ApiService.updateSecuritySettings(
        mfaEnabled: false,
        mfaMethod: 'none',
        mfaCode: mfaCode,
      );
      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'Unable to disable MFA.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Multi-factor authentication disabled.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        title: const Text('Multi-Factor Authentication'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C874)),
              )
            : SingleChildScrollView(
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
                          Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Enable MFA',
                                      style: TextStyle(
                                        color: Color(0xFF37474F),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Choose how this account should verify sensitive actions and sign-ins.',
                                      style: TextStyle(
                                        color: Color(0xFF78909C),
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoSwitch(
                                value: _mfaEnabled,
                                activeColor: const Color(0xFF00C874),
                                onChanged: _isWorking
                                    ? null
                                    : (value) {
                                        if (value) {
                                          _startEnrollment();
                                        } else {
                                          _disableMfa();
                                        }
                                      },
                              ),
                            ],
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
                              _mfaEnabled
                                  ? 'MFA is active for sign-in, password changes, sensitive profile changes, and profile setup confirmation.'
                                  : _hasPendingEnrollment
                                      ? 'Enter the 6-digit code from your authenticator app to complete setup.'
                                      : 'Generate a QR code, scan it with Microsoft Authenticator, then enter the 6-digit code.',
                              style: const TextStyle(
                                color: Color(0xFF546E7A),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Authenticator app',
                            style: TextStyle(
                              color: Color(0xFF37474F),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use Microsoft Authenticator to generate a 6-digit verification code.',
                            style: TextStyle(
                              color: Color(0xFF78909C),
                              fontSize: 12,
                            ),
                          ),
                          if (_otpauthUrl != null) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE1ECE8)),
                                ),
                                child: QrImageView(
                                  data: _otpauthUrl!,
                                  size: 220,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (_otpauthUrl != null) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: 'Current 6-digit code',
                                errorText: _errorText,
                                helperText: _infoMessage,
                                filled: true,
                                fillColor: const Color(0xFFF8FBFA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFDCE9E4),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFDCE9E4),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00C874),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isWorking ? null : _verifyEnrollment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00C874),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isWorking
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Verify And Enable',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ] else if (!_mfaEnabled) ...[
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _isWorking ? null : _startEnrollment,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF00C874),
                                  side: const BorderSide(color: Color(0xFF00C874)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isWorking
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF00C874),
                                        ),
                                      )
                                    : const Text('Generate QR Code'),
                              ),
                            ),
                          ],
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
