import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/workout_service.dart';
import '../services/recommendation_service.dart';
import '../services/feel_analysis_service.dart';
import '../main.dart';
import 'login_screen.dart';
import 'log_workout_screen.dart';
import 'profile_screen.dart';
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
  FeelInsight? _feelInsight;
  String? _displayName;
  String? _goalExercise;
  double _goalTargetWeight = 0;
  double _goalCurrentBest = 0;

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
        _feelInsight = FeelAnalysisService.analyse(workouts);
        _goalExercise = profile?.goalExercise;
        _goalTargetWeight = profile?.goalTargetWeight ?? 0;
        _goalCurrentBest =
            profile?.personalRecords[profile.goalExercise] ?? 0;
      });
    } catch (_) {
      // silently ignore load errors - the home screen remains usable
      // and the user can still navigate or sign out
    }
  }

  void _showPRDialog(List<String> exercises) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text('New Personal Record!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You hit a new best on:'),
            const SizedBox(height: 8),
            ...exercises.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(e,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nice!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GymConnect'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My Profile',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              if (mounted) _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await AuthService().signOut();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                final newPRs = await Navigator.push<List<String>>(
                  context,
                  MaterialPageRoute(builder: (_) => const LogWorkoutScreen()),
                );
                if (!mounted) return;
                _loadData();
                if (newPRs != null && newPRs.isNotEmpty) {
                  _showPRDialog(newPRs);
                }
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
            // shown only when a goal is set and loaded
            if (_goalExercise != null &&
                _goalExercise!.isNotEmpty &&
                _goalTargetWeight > 0) ...[
              _GoalCard(
                exercise: _goalExercise!,
                currentBest: _goalCurrentBest,
                targetWeight: _goalTargetWeight,
              ),
              const SizedBox(height: 12),
            ],
            // only shown once the recommendation has loaded from Firestore.
            if (_recommendation != null)
              _RecommendationCard(recommendation: _recommendation!),
            if (_feelInsight != null) ...[
              const SizedBox(height: 12),
              _FeelInsightCard(insight: _feelInsight!),
            ],
            const SizedBox(height: 32),
            const Divider(),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) => SwitchListTile(
                title: const Text('Dark Mode'),
                secondary: Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode
                      : Icons.light_mode,
                ),
                value: mode == ThemeMode.dark,
                onChanged: (on) {
                  themeModeNotifier.value =
                      on ? ThemeMode.dark : ThemeMode.light;
                  saveThemePreference(on);
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// Shows the user's single training goal with a progress bar.
class _GoalCard extends StatelessWidget {
  final String exercise;
  final double currentBest;
  final double targetWeight;

  const _GoalCard({
    required this.exercise,
    required this.currentBest,
    required this.targetWeight,
  });

  @override
  Widget build(BuildContext context) {
    final isLbs = weightUnitNotifier.value == 'lbs';
    final factor = isLbs ? 2.20462 : 1.0;
    final unit = isLbs ? 'lbs' : 'kg';
    final displayCurrent = currentBest * factor;
    final displayTarget = targetWeight * factor;
    final progress = (currentBest / targetWeight).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    final achieved = currentBest >= targetWeight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.07),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: Colors.deepPurple, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Training Goal',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (achieved)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text('Achieved!',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w600)),
                  ],
                )
              else
                Text('$percent%',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            exercise,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            currentBest > 0
                ? 'Current best: ${displayCurrent.toStringAsFixed(1)} $unit  •  Target: ${displayTarget.toStringAsFixed(displayTarget % 1 == 0 ? 0 : 1)} $unit'
                : 'Target: ${displayTarget.toStringAsFixed(displayTarget % 1 == 0 ? 0 : 1)} $unit  •  No attempts yet',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(
                achieved ? Colors.green : Colors.deepPurple,
              ),
            ),
          ),
        ],
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

// Shows a single insight derived from the user's session feel ratings.
class _FeelInsightCard extends StatelessWidget {
  final FeelInsight insight;

  const _FeelInsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (insight.type) {
      FeelInsightType.lowStreakWarning => (
          Icons.warning_amber_outlined,
          Colors.orange,
        ),
      FeelInsightType.performanceCorrelation => (
          Icons.insights,
          Colors.teal,
        ),
      FeelInsightType.bestDayOfWeek => (
          Icons.calendar_today,
          Colors.blue,
        ),
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
                  'Session Feel Insight',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
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

