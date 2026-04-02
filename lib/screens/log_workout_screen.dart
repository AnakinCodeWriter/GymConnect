import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';
import '../models/template_model.dart';
import '../services/workout_service.dart';
import '../services/template_service.dart';
import 'workout_templates_screen.dart';

class LogWorkoutScreen extends StatefulWidget {
  const LogWorkoutScreen({super.key});

  @override
  State<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends State<LogWorkoutScreen> {
  final WorkoutService _workoutService = WorkoutService();
  final TemplateService _templateService = TemplateService();

  final List<_ExerciseData> _exercises = [];
  // full workout history, sorted newest first — used for repeat and suggestions
  List<WorkoutModel> _workouts = [];
  // saved templates for this user, used to populate the Load Template dialog
  List<TemplateModel> _templates = [];
  // exercise names from history, used for chips and autocomplete suggestions
  List<String> _recentExercises = [];
  // maps exercise name -> last logged set, used to prefill weight/reps
  Map<String, WorkoutSet> _lastSets = {};

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // fetches workout history and templates in parallel, then derives
  // the exercise name list and last-set map from the workout history.
  Future<void> _loadHistory() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final workoutsFuture = _workoutService.getWorkouts(uid);
    final templatesFuture = _templateService.getTemplates(uid);
    final workouts = await workoutsFuture;
    final templates = await templatesFuture;
    setState(() {
      _workouts = workouts;
      _templates = templates;
      _recentExercises = _workoutService.extractExerciseNames(workouts);
      _lastSets = _workoutService.getLastSetsByExercise(workouts);
    });
  }

  // populates the screen with the exercises and sets from the most recent workout.
  // if exercises are already on screen, asks the user to confirm before replacing them.
  Future<void> _repeatLastWorkout() async {
    if (_workouts.isEmpty) return;

    if (_exercises.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current workout?'),
          content: const Text(
            'Loading the last workout will replace what you have entered. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final last = _workouts.first;
    setState(() {
      // dispose existing entries before replacing them
      for (final ex in _exercises) {
        ex.dispose();
      }
      _exercises.clear();

      // rebuild the exercise list from the last workout's data
      for (final entry in last.exercises) {
        final ex = _ExerciseData()..name = entry.name;
        for (final set in entry.sets) {
          ex.sets.add(_SetData.fromWorkoutSet(set));
        }
        _exercises.add(ex);
      }
    });
  }

  // populates the screen with exercises from the selected template.
  // uses the same confirmation dialog as _repeatLastWorkout if work is in progress.
  Future<void> _loadFromTemplate(TemplateModel template) async {
    if (_exercises.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current workout?'),
          content: const Text(
            'Loading this template will replace what you have entered. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      for (final ex in _exercises) {
        ex.dispose();
      }
      _exercises.clear();

      for (final entry in template.exercises) {
        final ex = _ExerciseData()..name = entry.name;
        for (final set in entry.sets) {
          ex.sets.add(_SetData.fromTemplateSet(set));
        }
        _exercises.add(ex);
      }
    });
  }

  // shows a dialog listing the user's saved templates for selection.
  Future<void> _showLoadTemplateDialog() async {
    final selected = await showDialog<TemplateModel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Load Template'),
        children: _templates
            .map(
              (t) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, t),
                child: Text(t.name),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) _loadFromTemplate(selected);
  }

  void _addExercise() {
    setState(() {
      _exercises.add(_ExerciseData());
    });
  }

  // adds a new exercise card with the name already filled in —
  // called when the user taps a chip in the Recent Exercises row.
  // also prefills the first set if this exercise has been logged before.
  void _addExerciseWithName(String name) {
    setState(() {
      final ex = _ExerciseData()..name = name;
      final lastSet = _lastSets[name];
      if (lastSet != null) {
        ex.sets.add(_SetData.fromWorkoutSet(lastSet));
      }
      _exercises.add(ex);
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
      final sets = _exercises[exerciseIndex].sets;
      if (sets.isNotEmpty) {
        // prefill the new set with the previous set's current values
        final prev = sets.last;
        sets.add(_SetData(
          weight: prev.weightController.text,
          reps: prev.repsController.text,
        ));
      } else {
        sets.add(_SetData());
      }
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
      if (ex.name.trim().isEmpty) {
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
        return ExerciseEntry(name: ex.name.trim(), sets: sets);
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
          // navigate to the templates screen; reload on return in case
          // the user created or edited a template while there.
          IconButton(
            icon: const Icon(Icons.playlist_add_check),
            tooltip: 'Manage Templates',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WorkoutTemplatesScreen()),
              );
              _loadHistory();
            },
          ),
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
          // chips row — only rendered once history has been loaded
          if (_recentExercises.isNotEmpty)
            _RecentExercisesRow(
              names: _recentExercises,
              onTap: _addExerciseWithName,
            ),
          // repeat button — only shown when the user has at least one previous workout
          if (_workouts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _repeatLastWorkout,
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Repeat Last Workout'),
                ),
              ),
            ),
          // load template button — only shown when saved templates exist
          if (_templates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showLoadTemplateDialog,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Load Template'),
                ),
              ),
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
                  // Autocomplete shows filtered suggestions from _recentExercises
                  // as the user types. initialValue pre-fills the field when a
                  // chip was tapped before this card was built.
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(text: ex.name),
                    optionsBuilder: (value) {
                      if (value.text.isEmpty) return const Iterable<String>.empty();
                      final query = value.text.toLowerCase();
                      return _recentExercises.where(
                        (name) => name.toLowerCase().contains(query),
                      );
                    },
                    // when the user selects a suggestion, update the stored name
                    // and prefill the first set if this exercise has been logged before.
                    onSelected: (value) => setState(() {
                      ex.name = value;
                      if (ex.sets.isEmpty) {
                        final lastSet = _lastSets[value];
                        if (lastSet != null) {
                          ex.sets.add(_SetData.fromWorkoutSet(lastSet));
                        }
                      }
                    }),
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        // keep ex.name in sync as the user types freely
                        onChanged: (value) => ex.name = value,
                        decoration: const InputDecoration(
                          labelText: 'Exercise name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.words,
                      );
                    },
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
  // name is stored as a plain string; the Autocomplete widget in the card
  // keeps it in sync via onChanged and onSelected callbacks.
  String name = '';
  final List<_SetData> sets = [];

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
  }
}

class _SetData {
  final TextEditingController weightController;
  final TextEditingController repsController;

  _SetData({String weight = '', String reps = ''})
      : weightController = TextEditingController(text: weight),
        repsController = TextEditingController(text: reps);

  // creates a _SetData pre-filled from a previously logged set.
  // whole-number weights are shown without a trailing .0 (e.g. 60 not 60.0).
  factory _SetData.fromWorkoutSet(WorkoutSet set) {
    final weight = set.weight % 1 == 0
        ? set.weight.toInt().toString()
        : set.weight.toString();
    return _SetData(weight: weight, reps: set.reps.toString());
  }

  // creates a _SetData from a template set.
  // weight is left blank if the template set had no weight defined.
  factory _SetData.fromTemplateSet(TemplateSet set) {
    final weight = set.weight == null
        ? ''
        : set.weight! % 1 == 0
            ? set.weight!.toInt().toString()
            : set.weight!.toString();
    return _SetData(weight: weight, reps: set.reps.toString());
  }

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}

// displays a horizontally scrollable row of chips showing the user's most
// frequently used exercise names. tapping a chip calls onTap with that name,
// which adds a new exercise card pre-filled with it.
class _RecentExercisesRow extends StatelessWidget {
  final List<String> names;
  final void Function(String) onTap;

  const _RecentExercisesRow({required this.names, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Recent Exercises',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: names.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ActionChip(
              label: Text(names[i]),
              onPressed: () => onTap(names[i]),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
