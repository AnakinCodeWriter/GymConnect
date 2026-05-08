import '../models/workout_model.dart';

enum DiagnosisType {
  frequencyDrop,
  repMonotony,
  continuousEscalation,
  noRecoveryWeek,
}

class PlateauDiagnosis {
  final DiagnosisType type;
  final String title;
  final String message;

  const PlateauDiagnosis({
    required this.type,
    required this.title,
    required this.message,
  });
}

/// Rule-based root-cause analysis for a plateau or regression on a single exercise.
///
/// Each rule computes a confidence score (0–1). The highest-confidence rule
/// that fires is returned. Returns null if no rule fires, or if there is not
/// enough data to draw a conclusion.
class PlateauDiagnosisService {
  // workouts must be sorted newest-first (as returned by WorkoutService).
  static PlateauDiagnosis? analyse(
      List<WorkoutModel> workouts, String exerciseName) {
    // Build a (date, workingSets) list for this exercise, newest first.
    // Warm-up sets are excluded — they don't reflect working capacity.
    final sessions = <(DateTime, List<WorkoutSet>)>[];
    for (final w in workouts) {
      for (final ex in w.exercises) {
        if (ex.name.trim().toLowerCase() ==
            exerciseName.trim().toLowerCase()) {
          final working = ex.sets.where((s) => !s.isWarmup).toList();
          if (working.isNotEmpty) {
            sessions.add((w.date.toDate(), working));
          }
          break;
        }
      }
    }

    if (sessions.length < 4) return null;

    final candidates = <(double, PlateauDiagnosis)>[];

    final freq = _checkFrequencyDrop(sessions);
    if (freq != null) candidates.add(freq);

    final rep = _checkRepMonotony(sessions);
    if (rep != null) candidates.add(rep);

    final esc = _checkContinuousEscalation(sessions);
    if (esc != null) candidates.add(esc);

    final deload = _checkNoRecoveryWeek(sessions);
    if (deload != null) candidates.add(deload);

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return candidates.first.$2;
  }

  // ── Rule 1 ─────────────────────────────────────────────────────────────────
  // Frequency drop: sessions in the last 28 days are significantly fewer
  // than in the prior 28-day window.
  static (double, PlateauDiagnosis)? _checkFrequencyDrop(
      List<(DateTime, List<WorkoutSet>)> sessions) {
    final now = DateTime.now();
    final recent = sessions
        .where((s) => s.$1.isAfter(now.subtract(const Duration(days: 28))))
        .length;
    final prior = sessions
        .where((s) =>
            s.$1.isAfter(now.subtract(const Duration(days: 56))) &&
            !s.$1.isAfter(now.subtract(const Duration(days: 28))))
        .length;

    if (prior < 2) return null;

    final ratio = recent / prior;
    final double confidence;
    if (ratio <= 0.4) {
      confidence = 0.85;
    } else if (ratio <= 0.6) {
      confidence = 0.75;
    } else {
      return null;
    }

    final target = (prior / 4).ceil();
    return (
      confidence,
      PlateauDiagnosis(
        type: DiagnosisType.frequencyDrop,
        title: 'Training frequency has dropped',
        message: 'You\'ve hit this exercise $recent time${recent == 1 ? '' : 's'} '
            'in the last 4 weeks, down from $prior the previous 4 weeks. '
            'Plateaus often follow a dip in consistency — try aiming for '
            '$target session${target == 1 ? '' : 's'} per week to rebuild momentum.',
      ),
    );
  }

  // ── Rule 2 ─────────────────────────────────────────────────────────────────
  // Rep monotony: the modal rep count has been identical across the last
  // 5+ sessions, indicating the user has not varied their rep range.
  static (double, PlateauDiagnosis)? _checkRepMonotony(
      List<(DateTime, List<WorkoutSet>)> sessions) {
    final recent = sessions.take(6).toList();
    if (recent.length < 5) return null;

    int modalReps(List<WorkoutSet> sets) {
      final counts = <int, int>{};
      for (final s in sets) {
        counts[s.reps] = (counts[s.reps] ?? 0) + 1;
      }
      return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    final modals = recent.map((s) => modalReps(s.$2)).toList();

    // Find the rep count that appears most often across all recent sessions,
    // not just the most recent one. Anchoring to modals.first was a bug:
    // one outlier session at a different rep count would suppress the rule
    // even if the other five sessions were all identical.
    final modalCounts = <int, int>{};
    for (final r in modals) {
      modalCounts[r] = (modalCounts[r] ?? 0) + 1;
    }
    final dominant =
        modalCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final matchCount = modals.where((r) => r == dominant).length;

    if (matchCount < 5) return null;

    final lower = (dominant - 2).clamp(1, 99);
    final higher = dominant + 3;
    return (
      0.75,
      PlateauDiagnosis(
        type: DiagnosisType.repMonotony,
        title: 'Rep range hasn\'t varied',
        message: 'Your last ${recent.length} sessions all used $dominant reps. '
            'Staying in the same rep range for too long is a common plateau trigger. '
            'Try a week at $lower reps with heavier weight, or $higher reps '
            'at a lighter load — varying the stimulus often restarts progress.',
      ),
    );
  }

  // ── Rule 3 ─────────────────────────────────────────────────────────────────
  // Continuous escalation: weight increased in every single recent session
  // without ever repeating a load — a sign of progression outpacing adaptation.
  static (double, PlateauDiagnosis)? _checkContinuousEscalation(
      List<(DateTime, List<WorkoutSet>)> sessions) {
    final recent = sessions.take(6).toList();
    if (recent.length < 5) return null;

    // Max weight per session. sessions[0] is newest, so we reverse for
    // chronological order before checking the direction of change.
    final maxWeights = recent
        .map((s) => s.$2.map((w) => w.weight).reduce((a, b) => a > b ? a : b))
        .toList()
        .reversed
        .toList(); // oldest → newest

    for (int i = 1; i < maxWeights.length; i++) {
      if (maxWeights[i] <= maxWeights[i - 1]) return null;
    }

    return (
      0.72,
      PlateauDiagnosis(
        type: DiagnosisType.continuousEscalation,
        title: 'Weight added every session',
        message: 'You\'ve added weight in each of your last ${recent.length} sessions '
            'without repeating a load. Strength needs time to consolidate — '
            'try holding at your current weight for one more session, '
            'focusing on quality reps before pushing the number higher.',
      ),
    );
  }

  // ── Rule 4 ─────────────────────────────────────────────────────────────────
  // No recovery week: across the last 8 sessions no single session had a
  // significantly lower max weight, suggesting the user has never taken a deload.
  static (double, PlateauDiagnosis)? _checkNoRecoveryWeek(
      List<(DateTime, List<WorkoutSet>)> sessions) {
    if (sessions.length < 6) return null;

    final recent = sessions.take(8).toList();
    final maxWeights = recent
        .map((s) => s.$2.map((w) => w.weight).reduce((a, b) => a > b ? a : b))
        .toList();

    final overallMax = maxWeights.reduce((a, b) => a > b ? a : b);
    final threshold = overallMax * 0.70;

    if (maxWeights.any((w) => w <= threshold)) return null;

    final oldest = recent.last.$1;
    final newest = recent.first.$1;
    final weeks =
        (newest.difference(oldest).inDays / 7).round().clamp(1, 52);

    return (
      0.70,
      PlateauDiagnosis(
        type: DiagnosisType.noRecoveryWeek,
        title: 'No easy week in $weeks week${weeks == 1 ? '' : 's'}',
        message: 'You\'ve trained at high intensity for $weeks weeks without a '
            'lighter session. A planned deload — dropping to around 60–70% of '
            'your usual weight for one session — lets your body recover and '
            'often triggers a breakthrough the week after.',
      ),
    );
  }
}