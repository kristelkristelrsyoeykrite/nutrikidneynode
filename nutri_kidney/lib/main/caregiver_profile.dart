import 'package:flutter/material.dart';

class CaregiverManagedProfile {
  const CaregiverManagedProfile({
    required this.id,
    required this.name,
    required this.typeLabel,
    required this.canRemove,
  });

  final String id;
  final String name;
  final String typeLabel;
  final bool canRemove;
}

class CaregiverProfileManager extends StatelessWidget {
  const CaregiverProfileManager({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.onProfileChanged,
    required this.onAddProfile,
    required this.onEditSelectedProfile,
    required this.onRemoveSelectedProfile,
    required this.onLinkExistingAccount,
    required this.onSendLinkRequest,
  });

  final List<CaregiverManagedProfile> profiles;
  final String? selectedProfileId;
  final ValueChanged<String?> onProfileChanged;
  final VoidCallback onAddProfile;
  final VoidCallback onEditSelectedProfile;
  final VoidCallback onRemoveSelectedProfile;
  final VoidCallback onLinkExistingAccount;
  final VoidCallback onSendLinkRequest;

  CaregiverManagedProfile? get _selectedProfile {
    if (profiles.isEmpty) return null;
    for (final profile in profiles) {
      if (profile.id == selectedProfileId) return profile;
    }
    return profiles.first;
  }

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _selectedProfile;
    final hasProfiles = profiles.isNotEmpty;
    final canAddMore = profiles.length < 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0ECE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.supervised_user_circle_outlined,
                color: Color(0xFF00897B),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Managed Profiles',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${profiles.length}/3',
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasProfiles) ...[
            const Text(
              'Managing:',
              style: TextStyle(
                color: Color(0xFF78909C),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0ECE8)),
              ),
              child: DropdownButton<String>(
                value: selectedProfile?.id,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: profiles
                    .map(
                      (profile) => DropdownMenuItem<String>(
                        value: profile.id,
                        child: Text(
                          '${profile.name} - ${profile.typeLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: profiles.length <= 1 ? null : onProfileChanged,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Each profile keeps separate health details, meal logs, hydration, medications, labs, insights, and analytics when supported by the linked account.',
              style: TextStyle(
                color: Color(0xFF78909C),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: onEditSelectedProfile,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C874),
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: canAddMore ? onAddProfile : null,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Add Child'),
                ),
                if (selectedProfile?.canRemove == true)
                  TextButton.icon(
                    onPressed: onRemoveSelectedProfile,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Remove Link'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                    ),
                  ),
              ],
            ),
          ] else ...[
            const Text(
              'No child account linked yet.',
              style: TextStyle(
                color: Color(0xFF37474F),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Link your adolescent child\'s NutriKidney account or add a directly managed profile to begin.',
              style: TextStyle(
                color: Color(0xFF78909C),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: onLinkExistingAccount,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Link Existing Account'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C874),
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onSendLinkRequest,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('Send Link Request'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddProfile,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Add Child'),
                ),
              ],
            ),
          ],
          if (!canAddMore) ...[
            const SizedBox(height: 12),
            const Text(
              'A caregiver account can manage up to 3 profiles.',
              style: TextStyle(color: Color(0xFFD32F2F), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
