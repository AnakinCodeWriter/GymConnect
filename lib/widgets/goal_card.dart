import 'package:flutter/material.dart';

import '../main.dart';
import '../theme/app_tokens.dart';
import '../utils/units.dart';

/// The user's single training goal with a progress bar. Shared by the
/// dashboard and progress screens (previously duplicated in both).
/// Values are kg; display conversion happens here.
class GoalCard extends StatelessWidget {
  final String exercise;
  final double currentBest;
  final double targetWeight;

  const GoalCard({
    super.key,
    required this.exercise,
    required this.currentBest,
    required this.targetWeight,
  });

  @override
  Widget build(BuildContext context) {
    final unit = weightUnitLabel(weightUnitNotifier.value);
    final displayCurrent = kgToDisplayUnit(currentBest, unit);
    final displayTarget = kgToDisplayUnit(targetWeight, unit);
    final progress = (currentBest / targetWeight).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    final achieved = currentBest >= targetWeight;

    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.07),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(Corners.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                color: Colors.deepPurple,
                size: 18,
              ),
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
                    Text(
                      'Achieved!',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                ? 'Current best: ${displayCurrent.toStringAsFixed(1)} $unit  •  Target: ${formatWeight(displayTarget)} $unit'
                : 'Target: ${formatWeight(displayTarget)} $unit  •  No attempts yet',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.sm),
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
