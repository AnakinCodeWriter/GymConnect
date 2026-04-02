import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/workout_service.dart';
import '../services/recommendation_service.dart';
import 'log_workout_screen.dart';
import 'progress_screen.dart';
import 'starter_plan_screen.dart';
import 'leaderboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _workoutService = WorkoutService();
  final _recommendationService = RecommendationService();
  final _firestoreService = FirestoreService();

  Recommendation? _recommendation;
  NextWorkoutSuggestion? _nextWorkout;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // fetches the user profile and workouts from Firestore in parallel,
  // then generates the recommendation and next workout suggestion.
  Future<void> _loadData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // start both requests before awaiting either, so they run in parallel.
      final profileFuture = _firestoreService.getUserProfile(uid);
      final workoutsFuture = _workoutService.getWorkouts(uid);
      final profile = await profileFuture;
      final workouts = await workoutsFuture;
      if (!mounted) return;
      setState(() {
        final name = profile?.displayName;
        _displayName = (name != null && name.isNotEmpty) ? name : null;
        _recommendation = _recommendationService.generate(workouts);
        _nextWorkout = _recommendationService.suggestNextWorkout(workouts);
      });
    } catch (_) {
      // silently ignore load errors — the home screen remains usable
      // and the user can still navigate or sign out
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GymConnect'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome, ${_displayName ?? user?.email ?? 'User'}!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LogWorkoutScreen()),
                );
                // reload so the recommendation reflects any newly logged workouts
                if (mounted) _loadData();
              },
              icon: const Icon(Icons.fitness_center),
              label: const Text('Log Workout'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProgressScreen()),
              ),
              icon: const Icon(Icons.bar_chart),
              label: const Text('View Progress'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
              ),
              icon: const Icon(Icons.leaderboard),
              label: const Text('Gym Leaderboard'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StarterPlanScreen()),
              ),
              icon: const Icon(Icons.help_outline),
              label: const Text('Not sure what to do? Start here'),
            ),
            const SizedBox(height: 24),
            // only shown once the recommendation has loaded from Firestore.
            if (_recommendation != null)
              _RecommendationCard(recommendation: _recommendation!),
            if (_nextWorkout != null) ...[
              const SizedBox(height: 12),
              _NextWorkoutCard(suggestion: _nextWorkout!),
            ],
          ],
        ),
      ),
    );
  }
}

// displays the recommendation as a coloured card. The icon and colour
// change depending on the recommendation type returned by RecommendationService
class _RecommendationCard extends StatelessWidget {
  final Recommendation recommendation;

  const _RecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (recommendation.type) {
      RecommendationType.startBeginner => (Icons.directions_run, Colors.blue),
      RecommendationType.balanceWorkout => (Icons.balance, Colors.orange),
      RecommendationType.plateauAdvice => (Icons.trending_flat, Colors.deepOrange),
      RecommendationType.keepGoing => (Icons.thumb_up, Colors.green),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended Next Step',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recommendation.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recommendation.message,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Shows what muscle group to train next based on the most recent workout.
class _NextWorkoutCard extends StatelessWidget {
  final NextWorkoutSuggestion suggestion;

  const _NextWorkoutCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withAlpha(20),
        border: Border.all(color: Colors.purple.withAlpha(80)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_note, color: Colors.purple, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested Next Workout',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion.message,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
