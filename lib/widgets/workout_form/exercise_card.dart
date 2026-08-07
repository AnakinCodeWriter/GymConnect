import 'package:flutter/material.dart';

import '../../models/workout_draft.dart';
import '../../models/workout_model.dart';
import '../../utils/overload_hint.dart';
import '../../utils/units.dart';
import 'set_row_editor.dart';

/// One exercise being logged: autocomplete name field, progressive-overload
/// hint, set rows and the add-set control. Extracted from the log workout
/// screen in Phase 11; all state mutations flow back through callbacks so
/// the screen keeps sole ownership of the draft.
class ExerciseCard extends StatelessWidget {
  final DraftExercise exercise;

  /// Exercise names from history, used for autocomplete suggestions.
  final List<String> recentExercises;

  /// Working sets from the user's most recent session per exercise name -
  /// drives the overload hint. Looked up at build time so the hint follows
  /// the current name, matching the original inline behaviour.
  final List<WorkoutSet>? Function(String name) lastSessionSetsFor;

  /// 'kg' or 'lbs' display unit.
  final String unit;

  final void Function(String name) onNameChanged;
  final void Function(String name) onNameSelected;
  final VoidCallback onRemoveExercise;
  final VoidCallback onAddSet;
  final void Function(DraftSet set) onToggleWarmup;
  final void Function(int setIndex) onRemoveSet;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.recentExercises,
    required this.lastSessionSetsFor,
    required this.unit,
    required this.onNameChanged,
    required this.onNameSelected,
    required this.onRemoveExercise,
    required this.onAddSet,
    required this.onToggleWarmup,
    required this.onRemoveSet,
  });

  @override
  Widget build(BuildContext context) {
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
                  // Autocomplete shows filtered suggestions from history as
                  // the user types. initialValue pre-fills the field when a
                  // chip was tapped before this card was built.
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(text: exercise.name),
                    optionsBuilder: (value) {
                      if (value.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      final query = value.text.toLowerCase();
                      return recentExercises.where(
                        (name) => name.toLowerCase().contains(query),
                      );
                    },
                    onSelected: onNameSelected,
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onNameChanged,
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
                  onPressed: onRemoveExercise,
                  tooltip: 'Remove exercise',
                ),
              ],
            ),
            _buildOverloadHint(),
            const SizedBox(height: 8),
            ...List.generate(exercise.sets.length, (j) {
              final set = exercise.sets[j];
              final workingSetNumber =
                  exercise.sets.take(j).where((x) => !x.isWarmup).length + 1;
              return SetRowEditor(
                set: set,
                workingSetNumber: workingSetNumber,
                unit: unit,
                onToggleWarmup: () => onToggleWarmup(set),
                onRemove: () => onRemoveSet(j),
              );
            }),
            TextButton.icon(
              onPressed: onAddSet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Set'),
            ),
          ],
        ),
      ),
    );
  }

  // Progressive overload hint based on last session performance; wording
  // unchanged from the pre-Phase 11 screen.
  Widget _buildOverloadHint() {
    final hint = computeOverloadHint(lastSessionSetsFor(exercise.name.trim()));
    if (hint == null) return const SizedBox.shrink();

    final wStr = formatWeight(kgToDisplayUnit(hint.topWeightKg, unit));

    final String message;
    final Color hintColor;
    if (hint.strong) {
      final suggestedWStr = formatWeight(
        kgToDisplayUnit(hint.suggestedWeightKg, unit),
      );
      message =
          'Last: $wStr$unit × ${hint.firstReps} reps - solid session, try $suggestedWStr$unit today';
      hintColor = Colors.green.shade600;
    } else {
      // non-strong implies a multi-set session with dropped reps, so the
      // first→last arrow always applies (single sets are always "strong").
      final repStr = '${hint.firstReps}→${hint.lastReps}';
      message =
          'Last: $wStr$unit × $repStr reps - build to ${hint.firstReps} consistent reps at $wStr$unit first';
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
  }
}
