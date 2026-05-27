import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';
import '../models/template_model.dart';
import '../services/workout_service.dart';
import '../services/template_service.dart';
import '../services/firestore_service.dart';
import '../services/leaderboard_service.dart';
import '../utils/fitness_formulas.dart';
import '../main.dart';
import 'workout_templates_screen.dart';

class LogWorkoutScreen extends StatefulWidget {
  const LogWorkoutScreen({super.key});

  @override
  State<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends State<LogWorkoutScreen> {
  final WorkoutService _workoutService = WorkoutService();
  final TemplateService _templateService = TemplateService();
  final FirestoreService _firestoreService = FirestoreService();
  final LeaderboardService _leaderboardService = LeaderboardService();

  final List<_ExerciseData> _exercises = [];
  // full workout history, sorted newest first - used for repeat and suggestions
  List<WorkoutModel> _workouts = [];
  // saved templates for this user, used to populate the Load Template dialog
  List<TemplateModel> _templates = [];
  // exercise names from history, used for chips and autocomplete suggestions
  List<String> _recentExercises = [];
  // maps exercise name -> last logged set, used to prefill weight/reps
  Map<String, WorkoutSet> _lastSets = {};
  // maps exercise name -> all sets from the last session, used when loading
  // a template so every set reflects the user's most recent performance
  Map<String, List<WorkoutSet>> _lastSessionSets = {};

  final _workoutNameController = TextEditingController();

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
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final workoutsFuture = _workoutService.getWorkouts(uid);
      final templatesFuture = _templateService.getTemplates(uid);
      final workouts = await workoutsFuture;
      final templates = await templatesFuture;
      if (!mounted) return;
      setState(() {
        _workouts = workouts;
        _templates = templates;
        _recentExercises = _workoutService.extractExerciseNames(workouts);
        _lastSets = _workoutService.getLastSetsByExercise(workouts);
        _lastSessionSets =
            _workoutService.getLastSessionSetsByExercise(workouts);
      });
    } catch (_) {
      // silently ignore - the screen remains usable with empty state
    }
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
        final historySets = _lastSessionSets[entry.name];
        if (historySets != null && historySets.isNotEmpty) {
          // prefill from the user's last actual performance for this exercise
          for (final set in historySets) {
            ex.sets.add(_SetData.fromWorkoutSet(set));
          }
        } else {
          // no history yet - fall back to the template's placeholder values
          for (final set in entry.sets) {
            ex.sets.add(_SetData.fromTemplateSet(set));
          }
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

  // called when the user taps a chip in the Recent Exercises row.
  // if the exercise already exists on screen, adds another set to it
  // (copying the last set's values). otherwise creates a new card.
  void _addExerciseWithName(String name) {
    setState(() {
      final existing = _exercises.indexWhere(
          (e) => e.name.trim().toLowerCase() == name.trim().toLowerCase());
      if (existing != -1) {
        // exercise card already present - just append a set
        final sets = _exercises[existing].sets;
        if (sets.isNotEmpty) {
          final prev = sets.last;
          sets.add(_SetData(
            weight: prev.weightController.text,
            reps: prev.repsController.text,
          ));
        } else {
          sets.add(_SetData());
        }
        return;
      }
      // new exercise - create a card and prefill the first set from history
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

  // increments or decrements a text controller's numeric value by [delta].
  // clamps to [min]. uses integer formatting when [isInt] is true.
  void _adjustValue(
    TextEditingController ctrl,
    double delta, {
    required double min,
    required bool isInt,
  }) {
    setState(() {
      final current = double.tryParse(ctrl.text) ?? 0;
      final next = (current + delta).clamp(min, double.infinity);
      if (isInt) {
        ctrl.text = next.round().toString();
      } else {
        ctrl.text = next % 1 == 0
            ? next.toInt().toString()
            : next.toStringAsFixed(1);
      }
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

    // collect feel rating before showing the saving spinner -
    // the sheet must appear while the screen is still interactive.
    final feelRating = await _showFeelRatingSheet();
    if (!mounted) return; // user may have navigated away during the sheet

    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final isLbs = weightUnitNotifier.value == 'lbs';

      final exercises = _exercises.map((ex) {
        final sets = ex.sets.map((s) {
          final rawWeight = double.parse(s.weightController.text.trim());
          final weightKg = isLbs ? rawWeight / 2.20462 : rawWeight;
          return WorkoutSet(
            weight: weightKg,
            reps: int.parse(s.repsController.text.trim()),
            isWarmup: s.isWarmup,
          );
        }).toList();
        return ExerciseEntry(name: ex.name.trim(), sets: sets);
      }).toList();

      // Total working volume (excludes warm-ups), in kg for storage.
      double totalVolumeKg = 0;
      for (final ex in exercises) {
        for (final s in ex.sets) {
          if (!s.isWarmup) totalVolumeKg += s.weight * s.reps;
        }
      }

      final workout = WorkoutModel(
        id: '',
        name: _workoutNameController.text.trim(),
        date: Timestamp.now(),
        exercises: exercises,
        feelRating: feelRating,
      );

      await _workoutService.saveWorkout(uid, workout);

      // PR detection - warm-up sets excluded.
      final newPRs = <String>[];
      try {
        final profile = await _firestoreService.getUserProfile(uid);
        final stored = profile?.personalRecords ?? {};

        final improved = <String, double>{};
        for (final ex in workout.exercises) {
          double best = 0;
          for (final s in ex.sets) {
            if (s.isWarmup) continue;
            final e1rm = estimatedOneRepMax(s.weight, s.reps);
            if (e1rm > best) best = e1rm;
          }
          final previous = stored[ex.name] ?? 0;
          if (best > previous) {
            improved[ex.name] = best;
            newPRs.add(ex.name);
          }
        }

        if (improved.isNotEmpty) {
          await _firestoreService.updatePersonalRecords(uid, improved);
        }

        // update leaderboard using the same profile fetch result
        if (profile != null && profile.gymId.isNotEmpty) {
          _leaderboardService
              .updateUserBestLifts(
                uid, profile.gymId, profile.displayName,
                profile.isAnonymous, workout)
              .catchError((_) {});
        }
      } catch (_) {
        // PR / leaderboard failures do not block navigation - workout is saved
      }
      // Show total volume summary before navigating away.
      if (mounted && totalVolumeKg > 0) {
        final displayVolume =
            isLbs ? totalVolumeKg * 2.20462 : totalVolumeKg;
        final unit = isLbs ? 'lbs' : 'kg';
        final volumeStr = displayVolume >= 1000
            ? '${(displayVolume / 1000).toStringAsFixed(1)}k $unit'
            : '${displayVolume.toStringAsFixed(0)} $unit';
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Session Complete!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Total volume lifted',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  volumeStr,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }

      if (mounted) Navigator.pop(context, newPRs);
    } catch (e) {
      setState(() {
        _error = 'Failed to save workout. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  void dispose() {
    _workoutNameController.dispose();
    for (final ex in _exercises) {
      ex.dispose();
    }
    super.dispose();
  }

  Future<int?> _showFeelRatingSheet() {
    return showModalBottomSheet<int>(
      context: context,
      // isDismissible defaults to true - tapping outside returns null
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _FeelRatingSheet(),
    );
  }

  // returns true if the screen has unsaved exercises
  bool get _hasUnsavedWork => _exercises.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedWork) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text('You have unsaved exercises. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
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
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          // chips row - only rendered once history has been loaded
          if (_recentExercises.isNotEmpty)
            _RecentExercisesRow(
              names: _recentExercises,
              onTap: _addExerciseWithName,
            ),
          // repeat button - only shown when the user has at least one previous workout
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
          // load template button - only shown when saved templates exist
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
          // Optional session name field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: _workoutNameController,
              decoration: const InputDecoration(
                labelText: 'Session name (optional)',
                hintText: 'e.g. Push Day, Leg Day',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.label_outline, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
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
      ),
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
            // Progressive overload hint based on last session performance.
            Builder(builder: (_) {
              final name = ex.name.trim();
              final sessionSets = _lastSessionSets[name];
              if (sessionSets == null || sessionSets.isEmpty) {
                return const SizedBox.shrink();
              }

              final isLbs = weightUnitNotifier.value == 'lbs';
              final factor = isLbs ? 2.20462 : 1.0;
              final unit = isLbs ? 'lbs' : 'kg';

              // Highest working weight from that session.
              final topWeight = sessionSets
                  .map((s) => s.weight)
                  .reduce((a, b) => a > b ? a : b);
              final displayW = topWeight * factor;
              final wStr = displayW % 1 == 0
                  ? displayW.toInt().toString()
                  : displayW.toStringAsFixed(1);

              final firstReps = sessionSets.first.reps;
              final lastReps = sessionSets.last.reps;

              // Multi-set: strong if last set is >= 75% of first set reps.
              final bool strong = sessionSets.length == 1
                  ? true
                  : lastReps >= (firstReps * 0.75).floor();

              final suggestedW = (topWeight + 2.5) * factor;
              final suggestedWStr = suggestedW % 1 == 0
                  ? suggestedW.toInt().toString()
                  : suggestedW.toStringAsFixed(1);

              final String message;
              final Color hintColor;
              if (strong) {
                message =
                    'Last: $wStr$unit × $firstReps reps - solid session, try $suggestedWStr$unit today';
                hintColor = Colors.green.shade600;
              } else {
                final repStr = sessionSets.length > 1
                    ? '$firstReps→$lastReps'
                    : '$lastReps';
                message =
                    'Last: $wStr$unit × $repStr reps - build to $firstReps consistent reps at $wStr$unit first';
                hintColor = Colors.orange.shade700;
              }

              return Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: hintColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            if (ex.sets.isNotEmpty)
              ...List.generate(ex.sets.length, (j) => _buildSetRow(i, j)),
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
    final isLbs = weightUnitNotifier.value == 'lbs';
    final weightDelta = isLbs ? 5.0 : 2.5;
    final weightSuffix = isLbs ? 'lbs' : 'kg';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Tappable set number - tap to toggle warm-up flag.
          // Only one warm-up is allowed per exercise; toggling a second set
          // automatically clears the previous one.
          Tooltip(
            message: s.isWarmup
                ? 'Warm-up (tap to clear)'
                : 'Tap to mark as warm-up',
            child: GestureDetector(
              onTap: () => setState(() {
                if (!s.isWarmup) {
                  // Clear any existing warm-up in this exercise first.
                  for (final other in _exercises[exerciseIndex].sets) {
                    other.isWarmup = false;
                  }
                  s.isWarmup = true;
                } else {
                  s.isWarmup = false;
                }
              }),
              child: SizedBox(
                width: 24,
                child: Text(
                  s.isWarmup
                      ? 'W'
                      : '${_exercises[exerciseIndex].sets.take(setIndex).where((x) => !x.isWarmup).length + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    color: s.isWarmup ? Colors.orange : Colors.grey,
                    fontWeight:
                        s.isWarmup ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildStepper(
              controller: s.weightController,
              suffix: weightSuffix,
              onDecrement: () => _adjustValue(
                s.weightController, -weightDelta,
                min: 0, isInt: false,
              ),
              onIncrement: () => _adjustValue(
                s.weightController, weightDelta,
                min: 0, isInt: false,
              ),
              isInt: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStepper(
              controller: s.repsController,
              suffix: 'reps',
              onDecrement: () => _adjustValue(
                s.repsController, -1,
                min: 1, isInt: true,
              ),
              onIncrement: () => _adjustValue(
                s.repsController, 1,
                min: 1, isInt: true,
              ),
              isInt: true,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: () => _removeSet(exerciseIndex, setIndex),
            tooltip: 'Remove set',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper({
    required TextEditingController controller,
    required String suffix,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required bool isInt,
  }) {
    return Row(
      children: [
        _stepBtn(Icons.remove, onDecrement),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              suffixText: suffix,
              suffixStyle: const TextStyle(fontSize: 11),
            ),
            keyboardType: isInt
                ? TextInputType.number
                : const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        _stepBtn(Icons.add, onIncrement),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18),
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
  bool isWarmup;

  _SetData({String weight = '', String reps = '', this.isWarmup = false})
      : weightController = TextEditingController(text: weight),
        repsController = TextEditingController(text: reps);

  // Creates a _SetData pre-filled from a previously logged set.
  // Converts kg->display unit; preserves the warm-up flag.
  factory _SetData.fromWorkoutSet(WorkoutSet set) {
    final isLbs = weightUnitNotifier.value == 'lbs';
    final w = isLbs ? set.weight * 2.20462 : set.weight;
    final weight =
        w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
    return _SetData(
        weight: weight, reps: set.reps.toString(), isWarmup: set.isWarmup);
  }

  // Creates a _SetData from a template set (templates have no warm-up flag).
  factory _SetData.fromTemplateSet(TemplateSet set) {
    final isLbs = weightUnitNotifier.value == 'lbs';
    double? w = set.weight;
    if (w != null && isLbs) w = w * 2.20462;
    final weight = w == null
        ? ''
        : w % 1 == 0
            ? w.toInt().toString()
            : w.toStringAsFixed(1);
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

// feel rating sheet

class _FeelRatingSheet extends StatefulWidget {
  const _FeelRatingSheet();

  @override
  State<_FeelRatingSheet> createState() => _FeelRatingSheetState();
}

class _FeelRatingSheetState extends State<_FeelRatingSheet> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'How did that feel?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final value = i + 1;
              final filled = _selected != null && value <= _selected!;
              return IconButton(
                icon: Icon(
                  filled ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 40,
                ),
                onPressed: () {
                  setState(() => _selected = value);
                  Navigator.pop(context, value);
                },
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a star to rate  •  tap outside to skip',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
