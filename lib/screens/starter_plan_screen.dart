import 'package:flutter/material.dart';

// represents a single exercise within a plan, storing the name and sets/reps as a display string
class _Exercise {
  final String name;
  final String setsReps;

  const _Exercise(this.name, this.setsReps);
}

// represents a full workout plan with a title, description, and list of exercises
class _WorkoutPlan {
  final String title;
  final String description;
  final List<_Exercise> exercises;

  const _WorkoutPlan({
    required this.title,
    required this.description,
    required this.exercises,
  });
}

// hardcoded beginner plans — no database needed, all data lives locally in this file
const _plans = [
  _WorkoutPlan(
    title: 'Full Body Beginner',
    description: 'A simple full body routine. Great for your first few weeks.',
    exercises: [
      _Exercise('Squat', '3 × 8'),
      _Exercise('Bench Press', '3 × 8'),
      _Exercise('Bent Over Row', '3 × 8'),
      _Exercise('Overhead Press', '3 × 8'),
      _Exercise('Plank', '3 × 30 sec'),
    ],
  ),
  _WorkoutPlan(
    title: 'Upper Body Focus',
    description: 'Targets chest, shoulders, and back.',
    exercises: [
      _Exercise('Push Up', '3 × 12'),
      _Exercise('Dumbbell Chest Press', '3 × 10'),
      _Exercise('Lat Pulldown', '3 × 10'),
      _Exercise('Dumbbell Shoulder Press', '3 × 10'),
      _Exercise('Bicep Curl', '3 × 12'),
      _Exercise('Tricep Pushdown', '3 × 12'),
    ],
  ),
  _WorkoutPlan(
    title: 'Lower Body Focus',
    description: 'Builds leg and core strength.',
    exercises: [
      _Exercise('Squat', '3 × 10'),
      _Exercise('Romanian Deadlift', '3 × 10'),
      _Exercise('Leg Press', '3 × 12'),
      _Exercise('Leg Curl', '3 × 12'),
      _Exercise('Calf Raise', '3 × 15'),
      _Exercise('Ab Crunch', '3 × 15'),
    ],
  ),
];

// displays the list of starter plans as scrollable cards
class StarterPlanScreen extends StatelessWidget {
  const StarterPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starter Plans')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length,
        itemBuilder: (context, i) => _PlanCard(plan: _plans[i]),
      ),
    );
  }
}

// renders a single workout plan as a card showing the title, description, and exercise list
class _PlanCard extends StatelessWidget {
  final _WorkoutPlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              plan.description,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const Divider(height: 20),
            ...plan.exercises.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.name, style: const TextStyle(fontSize: 14)),
                    Text(
                      e.setsReps,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
