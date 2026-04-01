import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/workout_service.dart';
import '../services/recommendation_service.dart';
import 'log_workout_screen.dart';
import 'progress_screen.dart';
import 'starter_plan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _workoutService = WorkoutService();
  final _recommendationService = RecommendationService();

  Recommendation? _recommendation;

  @override
  void initState() {
    super.initState();
    _loadRecommendation();
  }

  // fetches the user's workouts from Firestore and passes them to the
  // recommendation service to generate a contextual suggestion.
  Future<void> _loadRecommendation() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final workouts = await _workoutService.getWorkouts(uid);
    setState(() {
      _recommendation = _recommendationService.generate(workouts);
    });
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
              'Welcome, ${user?.email ?? 'User'}!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogWorkoutScreen()),
              ),
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
