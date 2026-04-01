import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';
import '../services/workout_service.dart';

class LogWorkoutScreen extends StatefulWidget {
  const LogWorkoutScreen({super.key});

  @override
  State<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends State<LogWorkoutScreen> {
  final WorkoutService _workoutService = WorkoutService();

  // Each exercise is a map with a name controller and a list of set rows.
  // set row = {weightController, repsController}
  final List<_ExerciseData> _exercises = [];

  bool _saving = false;
  String? _error;

  void _addExercise() {
    setState(() {
      _exercises.add(_ExerciseData());
    });
  }

  void _removeExercise(int index) {
    setState(() {
      _exercises[index].dispose();
      _exercises.removeAt(index);
    });
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      _exercises[exerciseIndex].sets.add(_SetData());
    });
  }

  void _removeSet(int exerciseIndex, int setIndex) {
    setState(() {
      _exercises[exerciseIndex].sets[setIndex].dispose();
      _exercises[exerciseIndex].sets.removeAt(setIndex);
    });
  }

  Future<void> _saveWorkout() async {
    setState(() {
      _error = null;
    });

    // Validate
    if (_exercises.isEmpty) {
      setState(() => _error = 'Add at least one exercise.');
      return;
    }
    for (final ex in _exercises) {
      if (ex.nameController.text.trim().isEmpty) {
        setState(() => _error = 'Every exercise needs a name.');
        return;
      }
      if (ex.sets.isEmpty) {
        setState(() => _error = 'Every exercise needs at least one set.');
        return;
      }
      for (final s in ex.sets) {
        final weight = double.tryParse(s.weightController.text.trim());
        final reps = int.tryParse(s.repsController.text.trim());
        if (weight == null || reps == null || weight < 0 || reps <= 0) {
          setState(() => _error = 'Enter valid weight and reps for all sets.');
          return;
        }
      }
    }

    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final exercises = _exercises.map((ex) {
        final sets = ex.sets.map((s) {
          return WorkoutSet(
            weight: double.parse(s.weightController.text.trim()),
            reps: int.parse(s.repsController.text.trim()),
          );
        }).toList();
        return ExerciseEntry(name: ex.nameController.text.trim(), sets: sets);
      }).toList();

      final workout = WorkoutModel(
        id: '',
        date: Timestamp.now(),
        exercises: exercises,
      );

      await _workoutService.saveWorkout(uid, workout);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'Failed to save workout. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  void dispose() {
    for (final ex in _exercises) {
      ex.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Workout'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveWorkout,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _exercises.isEmpty
                ? const Center(
                    child: Text(
                      'No exercises yet.\nTap + to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _exercises.length,
                    itemBuilder: (context, i) =>
                        _buildExerciseCard(i),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Add Exercise'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseCard(int i) {
    final ex = _exercises[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ex.nameController,
                    decoration: const InputDecoration(
                      labelText: 'Exercise name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeExercise(i),
                  tooltip: 'Remove exercise',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (ex.sets.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(width: 8),
                    Expanded(child: Text('Weight (kg)', style: TextStyle(fontSize: 12, color: Colors.grey))),
                    SizedBox(width: 8),
                    Expanded(child: Text('Reps', style: TextStyle(fontSize: 12, color: Colors.grey))),
                    SizedBox(width: 36),
                  ],
                ),
              ),
              ...List.generate(ex.sets.length,
                  (j) => _buildSetRow(i, j)),
            ],
            TextButton.icon(
              onPressed: () => _addSet(i),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Set'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetRow(int exerciseIndex, int setIndex) {
    final s = _exercises[exerciseIndex].sets[setIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('${setIndex + 1}. ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Expanded(
            child: TextField(
              controller: s.weightController,
              decoration: const InputDecoration(
                hintText: '0',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'kg',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: s.repsController,
              decoration: const InputDecoration(
                hintText: '0',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'reps',
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: () => _removeSet(exerciseIndex, setIndex),
            tooltip: 'Remove set',
          ),
        ],
      ),
    );
  }
}

class _ExerciseData {
  final TextEditingController nameController = TextEditingController();
  final List<_SetData> sets = [];

  void dispose() {
    nameController.dispose();
    for (final s in sets) {
      s.dispose();
    }
  }
}

class _SetData {
  final TextEditingController weightController = TextEditingController();
  final TextEditingController repsController = TextEditingController();

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}
