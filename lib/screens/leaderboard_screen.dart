import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/leaderboard_service.dart';
import '../services/firestore_service.dart';
import '../utils/units.dart';
import '../widgets/state_views.dart';
import '../main.dart';

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
  // failure loading the profile or leaderboard - distinct from "no gym ID"
  // so a network error is never misreported as a missing gym (Phase 4).
  bool _loadFailed = false;
  bool _isAnonymous = false;
  // profile display name, needed to restore the readable leaderboard name
  // when anonymity is switched off (Phase 10).
  String _displayName = '';
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
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      _uid = FirebaseAuth.instance.currentUser!.uid;
      final profile = await _firestoreService.getUserProfile(_uid!);

      if (!mounted) return;

      if (profile == null || profile.gymId.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      _gymId = profile.gymId;
      final result = await _leaderboardService.loadLeaderboard(_gymId!);
      final entries = result.dataOrNull;
      if (entries == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadFailed = true;
          });
        }
        return;
      }

      // collect all exercise names that exist across all entries, then sort
      final exerciseSet = <String>{};
      for (final entry in entries) {
        exerciseSet.addAll(entry.bestLifts.keys);
      }

      if (!mounted) return;
      setState(() {
        _isAnonymous = profile.isAnonymous;
        _displayName = profile.displayName;
        _entries = entries;
        _exercises = exerciseSet.toList()..sort();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  // flips the user's anonymity preference, persisting it to both
  // their user profile and their leaderboard entry. Reverts the toggle and
  // tells the user if persisting fails (previously an unhandled error).
  Future<void> _toggleAnonymous() async {
    final previous = _isAnonymous;
    final newValue = !_isAnonymous;
    setState(() => _isAnonymous = newValue);

    try {
      // update both documents in parallel
      await Future.wait([
        _firestoreService.updateAnonymous(_uid!, newValue),
        if (_gymId != null)
          _leaderboardService.setAnonymous(
            _uid!,
            _gymId!,
            newValue,
            displayName: _displayName,
          ),
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAnonymous = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t update your visibility.')),
      );
      return;
    }

    // refresh the list so the current user's own row updates immediately
    if (_gymId != null) {
      final entries = (await _leaderboardService.loadLeaderboard(
        _gymId!,
      )).dataOrNull;
      if (entries != null && mounted) setState(() => _entries = entries);
    }
  }

  // returns the ranked list of entries for the selected exercise,
  // excluding users who have no data for it.
  List<LeaderboardEntry> _getRankedEntries() {
    if (_selectedExercise == null) return [];
    return _entries
        .where((e) => e.bestLifts.containsKey(_selectedExercise))
        .toList()
      ..sort(
        (a, b) => b.bestLifts[_selectedExercise]!.compareTo(
          a.bestLifts[_selectedExercise]!,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym Leaderboard'),
        actions: [
          // toggle between showing the user's name and appearing anonymous
          IconButton(
            icon: Icon(_isAnonymous ? Icons.visibility_off : Icons.visibility),
            tooltip: _isAnonymous
                ? 'You are anonymous - tap to show your name'
                : 'You are visible - tap to go anonymous',
            onPressed: _loading ? null : _toggleAnonymous,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _loadFailed
          ? ErrorRetryView(
              title: 'Couldn\'t load the leaderboard',
              message: 'Check your connection and try again.',
              onRetry: _loadData,
            )
          : _gymId == null
          ? const EmptyView(
              icon: Icons.fitness_center,
              message:
                  'No gym ID set on your account.\nPlease update your profile.',
            )
          : _entries.isEmpty
          ? const EmptyView(
              icon: Icons.leaderboard,
              message:
                  'No leaderboard data yet.\nLog a workout to appear here!',
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
            onSelected: (_) =>
                setState(() => _selectedExercise = selected ? null : name),
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
    final e1rmKg = entry.bestLifts[_selectedExercise]!;
    final unit = weightUnitLabel(weightUnitNotifier.value);
    final displayE1rm = kgToDisplayUnit(e1rmKg, unit);

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
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: isCurrentUser
            ? Text(
                entry.isAnonymous ? '(you - anonymous)' : '(you)',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : null,
        trailing: Text(
          '${displayE1rm.toStringAsFixed(1)} $unit',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
