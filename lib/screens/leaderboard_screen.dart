import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/leaderboard_service.dart';
import '../services/firestore_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _leaderboardService = LeaderboardService();
  final _firestoreService = FirestoreService();

  List<LeaderboardEntry> _entries = [];
  // unique exercise names that appear across all leaderboard entries, sorted
  List<String> _exercises = [];
  String? _selectedExercise;

  bool _loading = true;
  bool _isAnonymous = false;
  String? _gymId;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // fetches the user's profile (for gymId and anonymity setting)
  // then loads the leaderboard for their gym.
  Future<void> _loadData() async {
    try {
      _uid = FirebaseAuth.instance.currentUser!.uid;
      final profile = await _firestoreService.getUserProfile(_uid!);

      if (!mounted) return;

      if (profile == null || profile.gymId.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      _gymId = profile.gymId;
      final entries = await _leaderboardService.getLeaderboard(_gymId!);

      // collect all exercise names that exist across all entries, then sort
      final exerciseSet = <String>{};
      for (final entry in entries) {
        exerciseSet.addAll(entry.bestLifts.keys);
      }

      if (!mounted) return;
      setState(() {
        _isAnonymous = profile.isAnonymous;
        _entries = entries;
        _exercises = exerciseSet.toList()..sort();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // flips the user's anonymity preference, persisting it to both
  // their user profile and their leaderboard entry.
  Future<void> _toggleAnonymous() async {
    final newValue = !_isAnonymous;
    setState(() => _isAnonymous = newValue);

    // update both documents in parallel
    await Future.wait([
      _firestoreService.updateAnonymous(_uid!, newValue),
      if (_gymId != null)
        _leaderboardService.setAnonymous(_uid!, _gymId!, newValue),
    ]);

    // refresh the list so the current user's own row updates immediately
    if (_gymId != null) {
      final entries = await _leaderboardService.getLeaderboard(_gymId!);
      setState(() => _entries = entries);
    }
  }

  // returns the ranked list of entries for the selected exercise,
  // excluding users who have no data for it.
  List<LeaderboardEntry> _getRankedEntries() {
    if (_selectedExercise == null) return [];
    return _entries
        .where((e) => e.bestLifts.containsKey(_selectedExercise))
        .toList()
      ..sort((a, b) => b.bestLifts[_selectedExercise]!
          .compareTo(a.bestLifts[_selectedExercise]!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym Leaderboard'),
        actions: [
          // toggle between showing the user's name and appearing anonymous
          IconButton(
            icon: Icon(
              _isAnonymous ? Icons.visibility_off : Icons.visibility,
            ),
            tooltip: _isAnonymous
                ? 'You are anonymous — tap to show your name'
                : 'You are visible — tap to go anonymous',
            onPressed: _loading ? null : _toggleAnonymous,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gymId == null
              ? const Center(
                  child: Text(
                    'No gym ID set on your account.\nPlease update your profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _entries.isEmpty
                  ? const Center(
                      child: Text(
                        'No leaderboard data yet.\nLog a workout to appear here!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : Column(
                      children: [
                        _buildAnonymityBanner(),
                        _buildExerciseChips(),
                        Expanded(child: _buildRankedList()),
                      ],
                    ),
    );
  }

  // small banner reminding the user of their current visibility setting
  Widget _buildAnonymityBanner() {
    return Container(
      width: double.infinity,
      color: _isAnonymous
          ? Colors.grey.shade100
          : Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        _isAnonymous
            ? 'You appear as "Anonymous" on this leaderboard.'
            : 'You appear as your display name on this leaderboard.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildExerciseChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _exercises.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final name = _exercises[i];
          final selected = _selectedExercise == name;
          return FilterChip(
            label: Text(name),
            selected: selected,
            onSelected: (_) => setState(() =>
                _selectedExercise = selected ? null : name),
          );
        },
      ),
    );
  }

  Widget _buildRankedList() {
    if (_selectedExercise == null) {
      return const Center(
        child: Text(
          'Select an exercise above\nto see the rankings.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final ranked = _getRankedEntries();

    if (ranked.isEmpty) {
      return const Center(
        child: Text(
          'No entries for this exercise yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ranked.length,
      itemBuilder: (context, i) => _buildEntryRow(ranked[i], i + 1),
    );
  }

  Widget _buildEntryRow(LeaderboardEntry entry, int rank) {
    final isCurrentUser = entry.uid == _uid;
    final name = entry.isAnonymous ? 'Anonymous' : entry.displayName;
    final e1rm = entry.bestLifts[_selectedExercise]!;

    // medal colours for top 3
    final rankColor = switch (rank) {
      1 => const Color(0xFFFFD700), // gold
      2 => const Color(0xFFC0C0C0), // silver
      3 => const Color(0xFFCD7F32), // bronze
      _ => Colors.grey.shade400,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        // highlight the current user's own row
        color: isCurrentUser
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(80)
            : null,
        border: Border.all(
          color: isCurrentUser
              ? Theme.of(context).colorScheme.primary.withAlpha(100)
              : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withAlpha(200),
          child: Text(
            '$rank',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight:
                isCurrentUser ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: isCurrentUser
            ? Text(
                entry.isAnonymous ? '(you — anonymous)' : '(you)',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary),
              )
            : null,
        trailing: Text(
          '${e1rm.toStringAsFixed(1)} kg',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
