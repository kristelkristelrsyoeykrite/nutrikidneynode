import 'package:flutter/material.dart';

import '../authenticator_mfa_page.dart';

class PrivacySecurityPage extends StatelessWidget {
  final bool initialMfaEnabled;
  final String accountLabel;

  const PrivacySecurityPage({
    super.key,
    required this.initialMfaEnabled,
    required this.accountLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AuthenticatorMfaPage(
      initialMfaEnabled: initialMfaEnabled,
      accountLabel: accountLabel,
    );
  }
}
