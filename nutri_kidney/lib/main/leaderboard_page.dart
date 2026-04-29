import 'package:flutter/material.dart';
import 'package:nutri_kidney/services/api_service.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  bool _isLoading = true;
  bool _isSavingVisibility = false;
  bool _showOnLeaderboard = false;
  String? _errorText;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  List<Map<String, dynamic>> _asStringMapList(dynamic value) {
    if (value is! List) return [];
    return value.map(_asStringMap).where((map) => map.isNotEmpty).toList();
  }

  int _intValue(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _loadLeaderboard() async {
    try {
      final summaryResponse = await ApiService.getGamificationSummary();
      final leaderboardResponse =
          await ApiService.getGamificationLeaderboard(limit: 20);

      if (!mounted) return;
      if (summaryResponse["success"] != true) {
        throw Exception(summaryResponse["error"] ?? "Unable to load status");
      }
      if (leaderboardResponse["success"] != true) {
        throw Exception(
          leaderboardResponse["error"] ?? "Unable to load leaderboard",
        );
      }

      final gamification = _asStringMap(summaryResponse["gamification"]);
      final status = _asStringMap(gamification["status"]);
      setState(() {
        _showOnLeaderboard = status["leaderboardOptIn"] == true;
        _entries = _asStringMapList(leaderboardResponse["leaderboard"]);
        _isLoading = false;
        _errorText = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _setVisibility(bool value) async {
    setState(() {
      _isSavingVisibility = true;
      _errorText = null;
    });

    try {
      final response = await ApiService.updateLeaderboardVisibility(
        showOnLeaderboard: value,
      );
      if (response["success"] != true) {
        throw Exception(
          response["error"] ?? "Unable to update leaderboard visibility",
        );
      }
      if (!mounted) return;
      setState(() => _showOnLeaderboard = value);
      await _loadLeaderboard();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSavingVisibility = false);
      }
    }
  }

  Widget _buildEntry(Map<String, dynamic> entry, int index) {
    final displayName = entry["displayName"]?.toString() ?? "NutriKidney user";
    final initials = entry["avatarInitials"]?.toString() ?? "NK";
    final weeklyPoints = _intValue(entry["weeklyPoints"]);
    final currentStreak = _intValue(entry["currentStreak"]);
    final badges = entry["badges"] is List ? entry["badges"] as List : const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1ECE8)),
      ),
      child: Row(
        children: [
          Text(
            '${index + 1}',
            style: const TextStyle(
              color: Color(0xFF78909C),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE0F2ED),
            child: Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF009688),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$weeklyPoints pts - $currentStreak-day streak - ${badges.length} badges',
                  style: const TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFB),
      appBar: AppBar(
        title: const Text('Weekly Logging Leaderboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C874)),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE1ECE8)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Show me on leaderboard',
                            style: TextStyle(
                              color: Color(0xFF37474F),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Switch(
                          value: _showOnLeaderboard,
                          activeColor: const Color(0xFF00C874),
                          onChanged:
                              _isSavingVisibility ? null : (value) => _setVisibility(value),
                        ),
                      ],
                    ),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorText!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_entries.isEmpty)
                    const Text(
                      'No leaderboard entries yet.',
                      style: TextStyle(color: Color(0xFF78909C)),
                    )
                  else
                    ..._entries.asMap().entries.map(
                          (entry) => _buildEntry(entry.value, entry.key),
                        ),
                ],
              ),
      ),
    );
  }
}
