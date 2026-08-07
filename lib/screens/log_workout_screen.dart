import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_draft.dart';
import '../models/workout_model.dart';
import '../models/template_model.dart';
import '../services/workout_service.dart';
import '../services/template_service.dart';
import '../utils/units.dart';
import '../widgets/status_banner.dart';
import '../widgets/workout_form/exercise_card.dart';
import '../widgets/workout_form/feel_rating_sheet.dart';
import '../widgets/workout_form/recent_exercises_row.dart';
import '../main.dart';
import 'workout_templates_screen.dart';

/// The workout logging form. Decomposed in Phase 11: draft state lives in
/// [DraftExercise]/[DraftSet] (models/workout_draft.dart), the per-exercise
/// UI in widgets/workout_form/, and the overload-hint rule in
/// utils/overload_hint.dart. [workoutService], [templateService] and
/// [uidProvider] are injectable so widget tests run without Firebase;
/// production call sites pass nothing and get the real services lazily.
class LogWorkoutScreen extends StatefulWidget {
  final WorkoutService? workoutService;
  final TemplateService? templateService;
  final String? Function()? uidProvider;

  const LogWorkoutScreen({
    super.key,
    this.workoutService,
    this.templateService,
    this.uidProvider,
  });

  @override
  State<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends State<LogWorkoutScreen> {
  // Lazily resolved so tests that inject fakes never construct the
  // Firebase-backed services.
  WorkoutService? _workoutServiceInstance;
  WorkoutService get _workoutService =>
      _workoutServiceInstance ??= widget.workoutService ?? WorkoutService();

  TemplateService? _templateServiceInstance;
  TemplateService get _templateService =>
      _templateServiceInstance ??= widget.templateService ?? TemplateService();

  static String? _defaultUid() => FirebaseAuth.instance.currentUser?.uid;

  final List<DraftExercise> _exercises = [];
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
  // true when loading history/templates failed - manual logging still works,
  // but suggestions, prefills and templates are unavailable until retried.
  bool _historyLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // fetches workout history and templates in parallel, then derives
  // the exercise name list and last-set map from the workout history.
  // A missing signed-in user is treated as a load failure (banner + retry)
  // rather than a crash; manual set entry stays available either way.
  Future<void> _loadHistory() async {
    try {
      final uid = (widget.uidProvider ?? _defaultUid)();
      if (uid == null) {
        setState(() => _historyLoadFailed = true);
        return;
      }
      final workoutsFuture = _workoutService.loadWorkouts();
      final templatesFuture = _templateService.loadTemplates(uid);
      final workouts = (await workoutsFuture).dataOrNull;
      final templates = (await templatesFuture).dataOrNull;
      if (!mounted) return;
      if (workouts == null || templates == null) {
        // typed data-access failure from either load
        setState(() => _historyLoadFailed = true);
        return;
      }
      setState(() {
        _workouts = workouts;
        _templates = templates;
        _recentExercises = _workoutService.extractExerciseNames(workouts);
        _lastSets = _workoutService.getLastSetsByExercise(workouts);
        _lastSessionSets = _workoutService.getLastSessionSetsByExercise(
          workouts,
        );
        _historyLoadFailed = false;
      });
    } catch (_) {
      // manual logging still works without history - show a banner so the
      // user knows why suggestions/templates are missing, with a retry.
      if (!mounted) return;
      setState(() => _historyLoadFailed = true);
    }
  }

  // shared confirmation before replacing on-screen exercises with a repeat
  // or template load.
  Future<bool> _confirmReplace(String content) async {
    if (_exercises.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace current workout?'),
        content: Text(content),
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
    return confirmed == true;
  }

  void _replaceExercises(Iterable<DraftExercise> replacement) {
    setState(() {
      for (final ex in _exercises) {
        ex.dispose();
      }
      _exercises
        ..clear()
        ..addAll(replacement);
    });
  }

  // populates the screen with the exercises and sets from the most recent
  // workout, asking for confirmation first if exercises are already on screen.
  Future<void> _repeatLastWorkout() async {
    if (_workouts.isEmpty) return;
    if (!await _confirmReplace(
      'Loading the last workout will replace what you have entered. Continue?',
    )) {
      return;
    }

    final unit = weightUnitNotifier.value;
    final last = _workouts.first;
    _replaceExercises([
      for (final entry in last.exercises)
        DraftExercise(name: entry.name)
          ..sets.addAll([
            for (final set in entry.sets)
              DraftSet.fromWorkoutSet(set, unit: unit),
          ]),
    ]);
  }

  // populates the screen with exercises from the selected template; each
  // exercise prefills from the user's last actual performance when history
  // exists, otherwise from the template's placeholder values.
  Future<void> _loadFromTemplate(TemplateModel template) async {
    if (!await _confirmReplace(
      'Loading this template will replace what you have entered. Continue?',
    )) {
      return;
    }

    final unit = weightUnitNotifier.value;
    _replaceExercises([
      for (final entry in template.exercises)
        DraftExercise(name: entry.name)
          ..sets.addAll(switch (_lastSessionSets[entry.name]) {
            final history? when history.isNotEmpty => [
              for (final set in history)
                DraftSet.fromWorkoutSet(set, unit: unit),
            ],
            _ => [
              for (final set in entry.sets)
                DraftSet.fromTemplateSet(set, unit: unit),
            ],
          }),
    ]);
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
      _exercises.add(DraftExercise());
    });
  }

  // called when the user taps a chip in the Recent Exercises row.
  // if the exercise already exists on screen, adds another set to it
  // (copying the last set's values). otherwise creates a new card.
  void _addExerciseWithName(String name) {
    setState(() {
      final existing = _exercises.indexWhere(
        (e) => e.name.trim().toLowerCase() == name.trim().toLowerCase(),
      );
      if (existing != -1) {
        // exercise card already present - just append a set
        _exercises[existing].addSet();
        return;
      }
      // new exercise - create a card and prefill the first set from history
      final ex = DraftExercise(name: name);
      final lastSet = _lastSets[name];
      if (lastSet != null) {
        ex.sets.add(
          DraftSet.fromWorkoutSet(lastSet, unit: weightUnitNotifier.value),
        );
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

  Future<void> _saveWorkout() async {
    setState(() {
      _error = null;
    });

    final validationError = validateWorkoutDraft(_exercises);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    // collect feel rating before showing the saving spinner -
    // the sheet must appear while the screen is still interactive.
    final feelRating = await showFeelRatingSheet(context);
    if (!mounted) return; // user may have navigated away during the sheet

    setState(() => _saving = true);

    final unit = weightUnitLabel(weightUnitNotifier.value);
    final exercises = buildExercisesFromDraft(_exercises, unit: unit);
    // Total working volume (excludes warm-ups), in kg for storage.
    final totalVolumeKg = workingVolumeKg(exercises);

    final workout = WorkoutModel(
      id: '',
      name: _workoutNameController.text.trim(),
      date: Timestamp.now(),
      exercises: exercises,
      feelRating: feelRating,
    );

    // Save + PR detection + leaderboard update are orchestrated by the
    // service (Phase 4); PR/leaderboard steps are best-effort there.
    final result = await _workoutService.saveWorkoutAndUpdateRecords(workout);
    final outcome = result.dataOrNull;
    if (outcome == null) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to save workout. Please try again.';
        _saving = false;
      });
      return;
    }
    final newPRs = outcome.newPersonalRecords;
    // tell alive tabs (dashboard/progress) that stored data changed.
    workoutDataVersion.value++;

    // Show total volume summary before navigating away.
    if (mounted && totalVolumeKg > 0) {
      final displayVolume = kgToDisplayUnit(totalVolumeKg, unit);
      final volumeStr = '${formatCompactWeight(displayVolume)} $unit';
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Session Complete!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              Text(
                'Total volume lifted',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                volumeStr,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
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
  }

  @override
  void dispose() {
    _workoutNameController.dispose();
    for (final ex in _exercises) {
      ex.dispose();
    }
    super.dispose();
  }

  // returns true if the screen has unsaved exercises
  bool get _hasUnsavedWork => _exercises.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedWork) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text(
          'You have unsaved exercises. Leave without saving?',
        ),
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
                    builder: (_) => const WorkoutTemplatesScreen(),
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_historyLoadFailed)
                InlineNotice(
                  message:
                      'Couldn\'t load workout history. You can still log '
                      'sets, but suggestions and templates are unavailable.',
                  actionLabel: 'Retry',
                  onAction: _loadHistory,
                ),
              // chips row - only rendered once history has been loaded
              if (_recentExercises.isNotEmpty)
                RecentExercisesRow(
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
                        itemBuilder: (context, i) => _buildExerciseCard(i),
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
    return ExerciseCard(
      exercise: ex,
      recentExercises: _recentExercises,
      lastSessionSetsFor: (name) => _lastSessionSets[name],
      unit: weightUnitLabel(weightUnitNotifier.value),
      // keep ex.name in sync as the user types freely (no rebuild needed)
      onNameChanged: (value) => ex.name = value,
      // when the user selects a suggestion, update the stored name and
      // prefill the first set if this exercise has been logged before.
      onNameSelected: (value) => setState(() {
        ex.name = value;
        if (ex.sets.isEmpty) {
          final lastSet = _lastSets[value];
          if (lastSet != null) {
            ex.sets.add(
              DraftSet.fromWorkoutSet(lastSet, unit: weightUnitNotifier.value),
            );
          }
        }
      }),
      onRemoveExercise: () => _removeExercise(i),
      onAddSet: () => setState(() => ex.addSet()),
      onToggleWarmup: (set) => setState(() => ex.toggleWarmup(set)),
      onRemoveSet: (j) => setState(() {
        ex.sets[j].dispose();
        ex.sets.removeAt(j);
      }),
    );
  }
}
