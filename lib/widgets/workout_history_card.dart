import 'package:flutter/material.dart';

import '../models/workout_model.dart';
import '../utils/dates.dart';
import '../utils/fitness_formulas.dart';
import '../utils/units.dart';

/// Callback for the per-set delete button: identifies the set by workout
/// document, exercise name and index; weight/reps are passed for the
/// confirmation wording.
typedef DeleteSetCallback =
    void Function(
      String workoutId,
      String exerciseName,
      int setIndex,
      double weight,
      int reps,
    );

/// One session in the Progress history list: an expandable card showing the
/// feel rating, session name/date summary and every exercise's sets with
/// per-set e1RM and a delete button. Extracted from the Progress screen in
/// Phase 11; layout and wording unchanged.
class WorkoutHistoryCard extends StatelessWidget {
  final WorkoutModel workout;

  /// 'kg' or 'lbs' display unit.
  final String unit;

  final DeleteSetCallback onDeleteSet;

  const WorkoutHistoryCard({
    super.key,
    required this.workout,
    required this.unit,
    required this.onDeleteSet,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = formatDayMonthYear(workout.date.toDate());
    final exerciseCount = workout.exercises.length;
    final setCount = workout.exercises.fold(0, (s, ex) => s + ex.sets.length);
    final countsStr =
        '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}  •  '
        '$setCount set${setCount == 1 ? '' : 's'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: _feelLeading(workout.feelRating),
        title: Text(
          workout.name.isNotEmpty ? workout.name : dateStr,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          workout.name.isNotEmpty ? '$dateStr  •  $countsStr' : countsStr,
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          ...workout.exercises.asMap().entries.map(
            (entry) => _buildExerciseSection(
              context,
              entry.value,
              entry.key < workout.exercises.length - 1,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildExerciseSection(
    BuildContext context,
    ExerciseEntry exercise,
    bool showDivider,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          ...exercise.sets.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final displayWStr = formatWeight(kgToDisplayUnit(s.weight, unit));
            final e1rmKg = estimatedOneRepMax(s.weight, s.reps);
            final displayE1rm = kgToDisplayUnit(e1rmKg, unit);
            return Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    s.isWarmup ? 'W' : 'Set ${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: s.isWarmup ? Colors.orange : Colors.grey,
                      fontWeight: s.isWarmup
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$displayWStr $unit × ${s.reps} reps',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (!s.isWarmup)
                  Text(
                    '${displayE1rm.toStringAsFixed(1)} $unit',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (s.isWarmup) const SizedBox(width: 48),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  tooltip: 'Delete entry',
                  onPressed: () => onDeleteSet(
                    workout.id,
                    exercise.name,
                    i,
                    s.weight,
                    s.reps,
                  ),
                ),
              ],
            );
          }),
          if (showDivider) const Divider(height: 12),
          if (!showDivider) const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _feelLeading(int? rating) {
    if (rating == null) {
      return const Icon(Icons.fitness_center, color: Colors.grey, size: 20);
    }
    final color = rating >= 4
        ? Colors.amber
        : rating <= 2
        ? Colors.orange
        : Colors.grey;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, color: color, size: 16),
        Text(
          '$rating',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
