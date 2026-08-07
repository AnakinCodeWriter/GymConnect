import 'package:flutter/material.dart';

import '../../models/workout_draft.dart';
import 'stepper_field.dart';

/// One editable set row: tappable set number (warm-up toggle), weight and
/// reps steppers, and a remove button. Extracted from the log workout screen
/// in Phase 11; behaviour unchanged (lbs steps by 5, kg by 2.5, reps by 1,
/// at most one warm-up per exercise - enforced by the parent's callback).
class SetRowEditor extends StatelessWidget {
  final DraftSet set;

  /// 1-based number among the exercise's working (non-warm-up) sets.
  final int workingSetNumber;

  /// 'kg' or 'lbs' - drives the weight suffix and step size.
  final String unit;

  final VoidCallback onToggleWarmup;
  final VoidCallback onRemove;

  const SetRowEditor({
    super.key,
    required this.set,
    required this.workingSetNumber,
    required this.unit,
    required this.onToggleWarmup,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isLbs = unit == 'lbs';
    final weightDelta = isLbs ? 5.0 : 2.5;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Tooltip(
            message: set.isWarmup
                ? 'Warm-up (tap to clear)'
                : 'Tap to mark as warm-up',
            child: Semantics(
              button: true,
              label: set.isWarmup
                  ? 'Warm-up set, tap to clear'
                  : 'Set $workingSetNumber, tap to mark as warm-up',
              child: GestureDetector(
                onTap: onToggleWarmup,
                child: SizedBox(
                  width: 24,
                  child: Text(
                    set.isWarmup ? 'W' : '$workingSetNumber',
                    style: TextStyle(
                      fontSize: 13,
                      color: set.isWarmup ? Colors.orange : Colors.grey,
                      fontWeight: set.isWarmup
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: StepperField(
              controller: set.weightController,
              suffix: isLbs ? 'lbs' : 'kg',
              delta: weightDelta,
              min: 0,
              isInt: false,
              valueLabel: 'weight',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StepperField(
              controller: set.repsController,
              suffix: 'reps',
              delta: 1,
              min: 1,
              isInt: true,
              valueLabel: 'reps',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: onRemove,
            tooltip: 'Remove set',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
