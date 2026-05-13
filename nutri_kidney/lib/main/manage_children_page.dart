import 'package:flutter/material.dart';

import '../create_account/profile_setup_intro.dart';
import 'profile/edit_profile_page.dart';
import '../services/api_service.dart';

class ManageChildrenPage extends StatefulWidget {
  const ManageChildrenPage({super.key});

  @override
  State<ManageChildrenPage> createState() => _ManageChildrenPageState();
}

class _ManageChildrenPageState extends State<ManageChildrenPage> {
  bool _isLoading = true;
  Map<String, dynamic> _viewer = {};
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _medicalProfile = {};
  Map<String, dynamic> _anthropometrics = {};
  Map<String, dynamic> _caregiverDashboardState = {};
  String? _profileOwnerId;
  bool _isDeletingChildDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren({String? profileUserId}) async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getHealthSummary(
        profileUserId: profileUserId,
      );
      if (!mounted) return;
      if (response["success"] == true) {
        setState(() {
          _viewer = _asStringMap(response["viewer"]);
          _user = _asStringMap(response["user"]);
          _medicalProfile = _asStringMap(response["medicalProfile"]);
          _anthropometrics = _asStringMap(response["anthropometrics"]);
          _caregiverDashboardState = _asStringMap(
            response["caregiverDashboardState"],
          );
          _profileOwnerId = response["profileOwnerId"]?.toString();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  String _textValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return "";
  }

  bool get _hasDirectManagedProfile {
    final ageGroup = _caregiverDashboardState["childAgeGroup"]?.toString();
    return ageGroup == "5-12" ||
        ageGroup == "5-13" ||
        ageGroup == "13-18-direct";
  }

  bool _isDirectChildEntry(Map item) {
    if (item["type"] == "direct") return true;
    if (item["relationship"] == "adolescent" ||
        item["type"] == "linked" ||
        item["type"] == "adolescent") {
      return false;
    }
    final childAgeGroup = item["childAgeGroup"]?.toString();
    if (childAgeGroup == "5-12" ||
        childAgeGroup == "5-13" ||
        childAgeGroup == "13-18-direct") {
      return true;
    }
    return true;
  }

  String get _currentChildName {
    final name = _textValue(_user, ["childFullName", "child_name", "name"]);
    return name.isEmpty ? "Child Profile" : name;
  }

  List<_ChildProfileItem> get _children {
    final children = <_ChildProfileItem>[];
    final seenIds = <String>{};
    final linkedChildren = _caregiverDashboardState["linkedChildren"];
    final hasLinkedChildrenList =
        linkedChildren is List && linkedChildren.isNotEmpty;

    if (_hasDirectManagedProfile && !hasLinkedChildrenList) {
      final id = (_profileOwnerId ??
              _user["id"] ??
              _user["uid"] ??
              "direct-managed-profile")
          .toString();
      children.add(
        _ChildProfileItem(
          id: id,
          name: _currentChildName,
          age: _textValue(_user, ["ageYears", "age_years"]),
          ckdStage: _textValue(_medicalProfile, ["ckdStage", "ckd_stage"]),
          label: "Directly Managed Child",
          isLinkedAdolescent: false,
        ),
      );
      seenIds.add(id);
    }

    if (linkedChildren is List) {
      for (final item in linkedChildren) {
        if (item is! Map) continue;
        final id = (item["id"] ?? item["uid"] ?? item["userId"])?.toString();
        if (id == null || id.isEmpty || seenIds.contains(id)) continue;
        final isDirectProfile = _isDirectChildEntry(item);
        children.add(
          _ChildProfileItem(
            id: id,
            name: (item["childFullName"] ??
                    item["fullName"] ??
                    item["name"] ??
                    (isDirectProfile ? "Child Profile" : "Linked adolescent"))
                .toString(),
            age: (item["age"] ?? item["ageYears"] ?? "").toString(),
            ckdStage: (item["ckdStage"] ?? "").toString(),
            label: isDirectProfile
                ? "Directly Managed Child"
                : "Linked Adolescent Account",
            isLinkedAdolescent: !isDirectProfile,
          ),
        );
        seenIds.add(id);
      }
    }

    final legacyLinkedId =
        _caregiverDashboardState["linkedChildUserId"]?.toString();
    if (_caregiverDashboardState["linkedChildAccount"] == true &&
        legacyLinkedId != null &&
        legacyLinkedId.isNotEmpty &&
        !seenIds.contains(legacyLinkedId)) {
      children.add(
        _ChildProfileItem(
          id: legacyLinkedId,
          name: _currentChildName,
          age: _textValue(_user, ["ageYears", "age_years"]),
          ckdStage: _textValue(_medicalProfile, ["ckdStage", "ckd_stage"]),
          label: "Linked Adolescent Account",
          isLinkedAdolescent: true,
        ),
      );
    }

    return children.take(3).toList(growable: false);
  }

  Future<void> _showLinkCodeDialog(String code, String expiresAt) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Caregiver Linking Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share this code with the child or adolescent account owner.',
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2FBF7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD7ECE5)),
                ),
                child: Text(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Color(0xFF009688),
                  ),
                ),
              ),
              if (expiresAt.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Expires: $expiresAt',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF78909C),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateCaregiverLinkCode() async {
    try {
      final response = await ApiService.generateCaregiverLinkCode();
      if (!mounted) return;
      if (response["success"] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ??
                  'Unable to generate a linking code right now.',
            ),
          ),
        );
        return;
      }
      await _showLinkCodeDialog(
        response["code"]?.toString() ?? "",
        response["expiresAt"]?.toString() ?? "",
      );
      if (mounted) await _loadChildren();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate a linking code: $error')),
      );
    }
  }

  Future<void> _startChildProfileSetup(String childAgeGroup) async {
    try {
      final response = await ApiService.saveCaregiverChildAgeGroup(
        childAgeGroup: childAgeGroup,
      );
      if (!mounted) return;
      if (response["success"] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ??
                  'Unable to start profile setup right now.',
            ),
          ),
        );
        return;
      }
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const ProfileSetupIntroScreen(
            isChildProfileSetup: true,
          ),
        ),
      );
      if (mounted) await _loadChildren();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add child: $error')),
      );
    }
  }

  Future<void> _showAddChildDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Add Child'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AddChildOption(
                icon: Icons.person_add_alt_1_outlined,
                title: 'Create child profile',
                subtitle: 'Create a child profile under this caregiver account.',
                onTap: () =>
                    Navigator.of(dialogContext).pop('child_profile'),
              ),
              const SizedBox(height: 10),
              _AddChildOption(
                icon: Icons.link_outlined,
                title: 'Link existing account',
                subtitle:
                    'Link a child or adolescent account with its own login.',
                onTap: () =>
                    Navigator.of(dialogContext).pop('link_account'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'link_account') {
      await _generateCaregiverLinkCode();
      return;
    }

    await _startChildProfileSetup('5-12');
  }

  Future<bool> _confirmHealthEdit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Continue editing child profile?'),
        content: const Text(
          'Changing health information may recalculate nutritional targets and insights. Are you sure you want to continue?',
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
      ),
    );
    return confirmed == true;
  }

  Future<void> _editChild(_ChildProfileItem child) async {
    if (!await _confirmHealthEdit()) return;
    await _loadChildren(profileUserId: child.id);
    if (!mounted) return;
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(
          viewer: _viewer,
          user: _user,
          medicalProfile: _medicalProfile,
          anthropometrics: _anthropometrics,
          profileOwnerId: _profileOwnerId,
        ),
      ),
    );
    if (updated == true) {
      await _loadChildren(profileUserId: child.id);
    }
  }

  Future<void> _viewChild(_ChildProfileItem child) async {
    await _loadChildren(profileUserId: child.id);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(child.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(child.label),
            const SizedBox(height: 8),
            Text(child.age.isEmpty ? 'Age not set' : 'Age: ${child.age}'),
            const SizedBox(height: 8),
            Text(
              child.ckdStage.isEmpty
                  ? 'CKD stage not set'
                  : 'CKD Stage: ${child.ckdStage}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDeletingChildDialog() {
    _isDeletingChildDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: const Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Deleting child profile...',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _isDeletingChildDialogOpen = false);
  }

  void _closeDeletingChildDialog() {
    if (!mounted || !_isDeletingChildDialogOpen) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _removeChild(_ChildProfileItem child) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          child.isLinkedAdolescent
              ? 'Remove caregiver access?'
              : 'Delete child profile?',
        ),
        content: Text(
          child.isLinkedAdolescent
              ? 'Remove caregiver access to this adolescent account? This will not delete the adolescent\'s NutriKidney account.'
              : 'This directly managed child profile will be archived for recovery. Associated child health records will no longer appear in caregiver views.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            child: Text(child.isLinkedAdolescent ? 'Remove Access' : 'Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!child.isLinkedAdolescent) {
      _showDeletingChildDialog();
      Map<String, dynamic> response;
      try {
        response = await ApiService.archiveDirectChildProfile(
          childProfileId: child.id,
        );
      } finally {
        _closeDeletingChildDialog();
      }
      if (!mounted) return;
      if (response["success"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Child profile archived.')),
        );
        await _loadChildren();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response["error"]?.toString() ??
                  'Unable to archive child profile.',
            ),
          ),
        );
      }
      return;
    }

    final response = await ApiService.unlinkCaregiverChild(
      linkedChildUserId: child.id,
    );
    if (!mounted) return;
    if (response["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver access removed.')),
      );
      await _loadChildren();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response["error"]?.toString() ?? 'Unable to remove access.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    final canAddMore = children.length < 3;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        title: const Text('Children Profiles'),
        actions: [
          IconButton(
            tooltip: 'Add child',
            onPressed: canAddMore ? _showAddChildDialog : null,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Manage linked and caregiver-managed child profiles separately from your own account settings.',
                  style: TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                if (!canAddMore) ...[
                  const Text(
                    'A caregiver account can manage up to 3 profiles.',
                    style: TextStyle(color: Color(0xFFD32F2F), fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                ],
                if (children.isEmpty)
                  _EmptyChildrenCard(onAdd: _showAddChildDialog)
                else
                  ...children.map(
                    (child) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ChildProfileCard(
                        child: child,
                        onView: () => _viewChild(child),
                        onEdit: () => _editChild(child),
                        onRemove: () => _removeChild(child),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ChildProfileItem {
  const _ChildProfileItem({
    required this.id,
    required this.name,
    required this.age,
    required this.ckdStage,
    required this.label,
    required this.isLinkedAdolescent,
  });

  final String id;
  final String name;
  final String age;
  final String ckdStage;
  final String label;
  final bool isLinkedAdolescent;
}

class _ChildProfileCard extends StatelessWidget {
  const _ChildProfileCard({
    required this.child,
    required this.onView,
    required this.onEdit,
    required this.onRemove,
  });

  final _ChildProfileItem child;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(Icons.child_care, color: Color(0xFF00897B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  child.name,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            child.label,
            style: const TextStyle(color: Color(0xFF78909C), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                text: child.age.isEmpty ? 'Age not set' : 'Age: ${child.age}',
              ),
              _InfoChip(
                text: child.ckdStage.isEmpty
                    ? 'CKD stage not set'
                    : child.ckdStage,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View Profile'),
              ),
              ElevatedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit Child Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C874),
                  foregroundColor: Colors.white,
                ),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: Icon(
                  child.isLinkedAdolescent
                      ? Icons.link_off
                      : Icons.archive_outlined,
                  size: 18,
                ),
                label: Text(
                  child.isLinkedAdolescent ? 'Remove Access' : 'Archive',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD32F2F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddChildOption extends StatelessWidget {
  const _AddChildOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0ECE8)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF00897B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF37474F),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF78909C),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF90A4AE)),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0ECE8)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF546E7A), fontSize: 12),
      ),
    );
  }
}

class _EmptyChildrenCard extends StatelessWidget {
  const _EmptyChildrenCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0ECE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No child profiles yet',
            style: TextStyle(
              color: Color(0xFF37474F),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create or link a child profile to begin.',
            style: TextStyle(color: Color(0xFF78909C), height: 1.4),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add Child Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C874),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
