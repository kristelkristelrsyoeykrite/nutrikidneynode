import 'package:flutter/material.dart';

class CaregiverPendingDashboard extends StatelessWidget {
  const CaregiverPendingDashboard({
    super.key,
    required this.caregiverName,
    required this.roleLabel,
    required this.onAddChildProfile,
    required this.onLinkExistingAccount,
  });

  final String caregiverName;
  final String roleLabel;
  final VoidCallback onAddChildProfile;
  final VoidCallback onLinkExistingAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CaregiverHeader(caregiverName: caregiverName, roleLabel: roleLabel),
        const SizedBox(height: 24),
        _PendingLinkCard(
          onAddChildProfile: onAddChildProfile,
          onLinkExistingAccount: onLinkExistingAccount,
        ),
      ],
    );
  }
}

class CaregiverManagedChildSelector extends StatelessWidget {
  const CaregiverManagedChildSelector({
    super.key,
    required this.children,
    required this.selectedChildId,
    required this.onChanged,
  });

  final List<Map<String, String>> children;
  final String? selectedChildId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final selectedId = selectedChildId != null &&
            children.any((child) => child["id"] == selectedChildId)
        ? selectedChildId
        : children.first["id"];

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              value: selectedId,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                color: Color(0xFF37474F),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              items: children
                  .map(
                    (child) => DropdownMenuItem<String>(
                      value: child["id"],
                      child: Text(
                        child["name"] ?? "Child",
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: children.length <= 1 ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaregiverHeader extends StatelessWidget {
  const _CaregiverHeader({
    required this.caregiverName,
    required this.roleLabel,
  });

  final String caregiverName;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFD5F5E3),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.volunteer_activism_outlined,
              color: Color(0xFF009688),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Caregiver dashboard',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
              ),
              Text(
                caregiverName,
                style: const TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7F1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$roleLabel Dashboard',
                  style: const TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

class _PendingLinkCard extends StatelessWidget {
  const _PendingLinkCard({
    required this.onAddChildProfile,
    required this.onLinkExistingAccount,
  });

  final VoidCallback onAddChildProfile;
  final VoidCallback onLinkExistingAccount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F2),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.link,
              color: Color(0xFF00A676),
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Set up child access',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF37474F),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'You may create a child profile under this caregiver account or link an existing child/adolescent account.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF78909C),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Choose one option below to begin managing nutrition and CKD support from your caregiver dashboard.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF78909C),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAddChildProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C874),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Add Child Profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: onLinkExistingAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00897B),
                side: const BorderSide(color: Color(0xFF00C874)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Link Existing Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
