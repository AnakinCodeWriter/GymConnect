import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/analytics.dart';
import '../models/exercise_detail.dart';
import '../models/user_model.dart';
import '../models/workout_model.dart';
import '../services/data_result.dart';
import '../services/exercise_analytics_service.dart';
import '../services/firestore_service.dart';
import '../services/plateau_detector.dart';
import '../services/workout_service.dart';
import '../theme/app_tokens.dart';
import '../utils/dates.dart';
import '../utils/units.dart';
import '../widgets/e1rm_chart.dart';
import '../widgets/evidence_panel.dart';
import '../widgets/goal_card.dart';
import '../widgets/insight_card.dart';
import '../widgets/state_views.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_banner.dart';
import '../widgets/workout_history_card.dart';
import '../main.dart';

// A flat record of one set from one exercise on one date - used for display.
class _SetRecord {
  final String workoutId; // Firestore document ID - needed for deletion
  final int setIndex; // index of this set within the exercise's set list
  final DateTime date;
  final String exerciseName;
  final double weight;
  final int reps;

  _SetRecord({
    required this.workoutId,
    required this.setIndex,
    required this.date,
    required this.exerciseName,
    required this.weight,
    required this.reps,
  });
}

/// What the Progress screen needs loaded: the workout history result plus
/// the profile (null when missing/failed - the goal card is then omitted
/// rather than failing the screen).
class ProgressLoadResult {
  final DataResult<List<WorkoutModel>> workouts;
  final UserModel? profile;

  const ProgressLoadResult({required this.workouts, this.profile});
}

typedef ProgressLoader = Future<ProgressLoadResult> Function();

/// The Progress destination (reworked in Phase 7): per-exercise analytics
/// with status, metrics, chart, evidence and possible explanations.
/// [loader], [workoutService] and [profileLoader] are injectable so widget
/// tests - including the delete-set flow (Phase 11) - run without Firebase.
class ProgressScreen extends StatefulWidget {
  final ProgressLoader? loader;

  /// Used by the delete-set flow; production default is the real service.
  final WorkoutService? workoutService;

  /// Re-fetches the profile after a deletion so the goal card's current
  /// best reflects the recalculated PR. Null result = goal best unknown.
  final Future<UserModel?> Function()? profileLoader;

  const ProgressScreen({
    super.key,
    this.loader,
    this.workoutService,
    this.profileLoader,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final TextEditingController _filterController = TextEditingController();

  // Lazily resolved so tests that inject fakes never construct the
  // Firebase-backed service.
  WorkoutService? _workoutServiceInstance;
  WorkoutService get _workoutService =>
      _workoutServiceInstance ??= widget.workoutService ?? WorkoutService();

  List<_SetRecord> _allRecords = [];
  List<WorkoutModel> _allWorkouts = [];
  List<WorkoutModel> _filteredWorkouts = [];
  List<String> _exerciseNames = [];

  String? _goalExercise;
  double _goalTargetWeight = 0;
  double _goalCurrentBest = 0;

  bool _loading = true;
  String? _error;
  // number of stored workout documents that couldn't be read (malformed) -
  // surfaced in a notice so skipped data is never silent.
  int _skippedCount = 0;

  // last workoutDataVersion this screen loaded; guards against reloading in
  // response to its own writes (Phase 6 stale-tab fix).
  int _lastLoadedVersion = 0;

  @override
  void initState() {
    super.initState();
    workoutDataVersion.addListener(_onDataVersionChanged);
    progressExerciseRequest.addListener(_onExerciseRequested);
    _loadWorkouts();
    _filterController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    workoutDataVersion.removeListener(_onDataVersionChanged);
    progressExerciseRequest.removeListener(_onExerciseRequested);
    _filterController.dispose();
    super.dispose();
  }

  void _onDataVersionChanged() {
    if (workoutDataVersion.value != _lastLoadedVersion) _loadWorkouts();
  }

  // The dashboard requested an exercise preselection (Phase 7).
  void _onExerciseRequested() {
    final name = progressExerciseRequest.value;
    if (name == null) return;
    progressExerciseRequest.value = null; // consume
    _filterController.text = name;
  }

  // Production loader; constructed lazily so tests injecting
  // [widget.loader] never touch Firebase. A profile failure is non-critical
  // (goal card omitted), matching the dashboard's partial-data policy.
  static Future<ProgressLoadResult> _productionLoader() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    UserModel? profile;
    if (uid != null) {
      try {
        profile = await FirestoreService().getUserProfile(uid);
      } catch (_) {
        profile = null;
      }
    }
    final workouts = await WorkoutService().loadWorkouts();
    return ProgressLoadResult(workouts: workouts, profile: profile);
  }

  // Default post-deletion profile fetch. A missing user or a failed fetch
  // yields null (goal best treated as unknown) instead of crashing or
  // mis-reporting the successful deletion (Phase 11, backlog #17).
  static Future<UserModel?> _productionProfileLoader() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      return await FirestoreService().getUserProfile(uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadWorkouts() async {
    _lastLoadedVersion = workoutDataVersion.value;
    final result = await (widget.loader ?? _productionLoader)();
    if (!mounted) return;

    final workouts = result.workouts.dataOrNull;
    if (workouts == null) {
      setState(() {
        _error = 'Failed to load workouts.';
        _loading = false;
      });
      return;
    }
    final skipped = switch (result.workouts) {
      DataSuccess(:final skipped) => skipped.length,
      _ => 0,
    };
    final profile = result.profile;
    final records = _flattenToRecords(workouts);
    final names = records.map((r) => r.exerciseName).toSet().toList()..sort();
    setState(() {
      _allRecords = records;
      _allWorkouts = workouts;
      _exerciseNames = names;
      _skippedCount = skipped;
      _goalExercise = profile?.goalExercise;
      _goalTargetWeight = profile?.goalTargetWeight ?? 0;
      _goalCurrentBest = profile?.personalRecords[profile.goalExercise] ?? 0;
      _loading = false;
      _error = null;
    });
    _applyFilter();
  }

  List<_SetRecord> _flattenToRecords(List<WorkoutModel> workouts) {
    final records = <_SetRecord>[];
    for (final workout in workouts) {
      final date = workout.date.toDate();
      for (final exercise in workout.exercises) {
        for (int i = 0; i < exercise.sets.length; i++) {
          final set = exercise.sets[i];
          if (set.isWarmup) continue; // history filter uses working sets
          records.add(
            _SetRecord(
              workoutId: workout.id,
              setIndex: i,
              date: date,
              exerciseName: exercise.name,
              weight: set.weight,
              reps: set.reps,
            ),
          );
        }
      }
    }
    // Newest first
    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  void _applyFilter() {
    final query = _filterController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredWorkouts = _allWorkouts;
      } else {
        _filteredWorkouts = _allWorkouts
            .where(
              (w) => w.exercises.any(
                (ex) => ex.name.toLowerCase().contains(query),
              ),
            )
            .toList();
      }
    });
  }

  void _selectExercise(String name) {
    _filterController.text = name;
  }

  // The typed analytics detail for the exactly-matched filter exercise, or
  // null when the filter text doesn't exactly match a known exercise name.
  ExerciseDetail? _detailForCurrentFilter() {
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) return null;

    final matchedName = _exerciseNames.cast<String?>().firstWhere(
      (n) => n!.toLowerCase() == query,
      orElse: () => null,
    );
    if (matchedName == null) return null;

    return ExerciseAnalyticsService.analyseExercise(
      _allWorkouts,
      matchedName,
      referenceDate: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorRetryView(
              title: 'Couldn\'t load your workouts',
              message: 'Check your connection and try again.',
              onRetry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadWorkouts();
              },
            )
          : _allRecords.isEmpty
          ? const EmptyView(
              icon: Icons.fitness_center,
              message: 'No workouts logged yet.\nGo log your first workout!',
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final detail = _detailForCurrentFilter();

    return RefreshIndicator(
      onRefresh: _loadWorkouts,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_goalExercise != null &&
              _goalExercise!.isNotEmpty &&
              _goalTargetWeight > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GoalCard(
                exercise: _goalExercise!,
                currentBest: _goalCurrentBest,
                targetWeight: _goalTargetWeight,
              ),
            ),
          if (_skippedCount > 0)
            InlineNotice(
              message:
                  '$_skippedCount workout record${_skippedCount == 1 ? '' : 's'} '
                  'couldn\'t be read and ${_skippedCount == 1 ? 'is' : 'are'} not shown.',
            ),
          _buildFilterBar(),
          _buildExerciseChips(),
          if (detail != null) ..._buildAnalyticsSections(detail),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SectionHeader(
              detail != null ? 'History: ${detail.exerciseName}' : 'History',
            ),
          ),
          if (_filteredWorkouts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No matching workouts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  for (final w in _filteredWorkouts)
                    WorkoutHistoryCard(
                      workout: w,
                      unit: weightUnitLabel(weightUnitNotifier.value),
                      onDeleteSet: _deleteSet,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Analytics sections (Phase 7)
  // ---------------------------------------------------------------------

  List<Widget> _buildAnalyticsSections(ExerciseDetail detail) {
    final unit = weightUnitLabel(weightUnitNotifier.value);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: _statusCard(detail, unit),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: _metricGrid(detail, unit),
      ),
      E1rmChart(sessions: detail.series.sessions, unit: unit),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: EvidencePanel(facts: _evidenceFacts(detail, unit)),
      ),
      if (detail.possibleExplanation != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: InsightCard(
            icon: Icons.psychology_outlined,
            color: Colors.deepPurple,
            label: 'Possible explanation',
            title: detail.possibleExplanation!.title,
            message: detail.possibleExplanation!.message,
          ),
        ),
    ];
  }

  Widget _statusCard(ExerciseDetail d, String unit) {
    final slopePerWeek = kgToDisplayUnit(d.strengthSlopeKgPerDay, unit) * 7;
    final trendLine =
        'Trend: ${slopePerWeek >= 0 ? '+' : ''}${slopePerWeek.toStringAsFixed(2)} $unit/week.';

    final (icon, color, title, message) = switch ((
      d.strengthStatus,
      d.volumeProgressionSuppressed,
    )) {
      (PlateauStatus.insufficientData, _) => (
        Icons.hourglass_empty,
        Colors.blueGrey,
        'Not enough data yet',
        'Log at least ${PlateauDetector.minSessions} sessions of this '
            'exercise to see a strength trend.',
      ),
      (PlateauStatus.progressing, _) => (
        Icons.trending_up,
        Colors.green,
        'Progressing',
        'Estimated 1RM is trending up, based on the logged data. $trendLine',
      ),
      (_, true) => (
        Icons.show_chart,
        Colors.teal,
        'Volume progressing',
        'Peak strength looks flat, but total volume is rising - strength '
            'gains often follow.',
      ),
      (PlateauStatus.plateau, _) => (
        Icons.trending_flat,
        Colors.orange,
        'Possible plateau',
        'Estimated 1RM has been flat lately, based on the logged data. '
            '$trendLine',
      ),
      (_, _) => (
        Icons.trending_down,
        Colors.red,
        'Possible regression',
        'Estimated 1RM may be declining, based on the logged data. '
            'Recovery, form or volume could all play a part. $trendLine',
      ),
    };

    return InsightCard(
      icon: icon,
      color: color,
      label: 'Strength Trend',
      title: title,
      message: message,
    );
  }

  String _reasonLabel(MetricResult<Object> result) {
    if (result is! MetricUnavailable) return '';
    return switch ((result as MetricUnavailable).reason) {
      InsufficiencyReason.zeroBaseline => 'no usable baseline',
      InsufficiencyReason.noMatchingExercise => 'exercise not found',
      _ => 'not enough data',
    };
  }

  String _changeValue(MetricResult<PercentageChange> change) {
    final c = change.valueOrNull;
    if (c == null) return '—';
    return '${c.percent >= 0 ? '+' : ''}${c.percent.toStringAsFixed(0)}%';
  }

  Widget _metricGrid(ExerciseDetail d, String unit) {
    final recentBest = d.recentBest.valueOrNull;
    final frequency = d.sessionsPerWeek.valueOrNull;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.emoji_events_outlined,
                label: 'Recent best (est. 1RM)',
                value: recentBest != null
                    ? '${formatWeight(kgToDisplayUnit(recentBest.e1RmKg, unit))} $unit'
                    : '—',
                subtitle: recentBest != null
                    ? formatDayMonth(recentBest.day)
                    : 'no sessions in last 4 weeks',
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: StatCard(
                icon: Icons.event_repeat,
                label: 'Frequency',
                value: frequency != null
                    ? '${frequency.toStringAsFixed(1)}×/week'
                    : '—',
                subtitle: frequency != null
                    ? 'last 4 weeks'
                    : _reasonLabel(d.sessionsPerWeek),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.fitness_center,
                label: 'Strength change',
                value: _changeValue(d.strengthChange),
                subtitle: d.strengthChange.isAvailable
                    ? 'vs previous 4 weeks'
                    : _reasonLabel(d.strengthChange),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: StatCard(
                icon: Icons.bar_chart,
                label: 'Volume change',
                value: _changeValue(d.volumeChange),
                subtitle: d.volumeChange.isAvailable
                    ? 'vs previous 4 weeks'
                    : _reasonLabel(d.volumeChange),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _evidenceFacts(ExerciseDetail d, String unit) {
    final slopePerWeek = kgToDisplayUnit(d.strengthSlopeKgPerDay, unit) * 7;
    final strength = d.strengthChange.valueOrNull;
    final volume = d.volumeChange.valueOrNull;
    final frequency = d.sessionsPerWeek.valueOrNull;

    return [
      '${d.totalSessions} valid session${d.totalSessions == 1 ? '' : 's'} '
          'analysed across the full history; '
          '${d.sessionsInWindow} in the last 4 weeks. Trends need at least '
          '${PlateauDetector.minSessions}.',
      'Comparison window: the last 4 weeks vs the 4 weeks before.',
      if (d.strengthStatus != PlateauStatus.insufficientData)
        'Estimated 1RM trend: ${slopePerWeek >= 0 ? '+' : ''}'
            '${slopePerWeek.toStringAsFixed(2)} $unit/week. The plateau band '
            'is ±0.1% per day of your average.',
      if (strength != null)
        'Best estimated 1RM went from '
            '${formatWeight(kgToDisplayUnit(strength.baselineValue, unit))} to '
            '${formatWeight(kgToDisplayUnit(strength.currentValue, unit))} $unit '
            '(${_changeValue(d.strengthChange)}).'
      else
        'Strength change unavailable: ${_reasonLabel(d.strengthChange)}.',
      if (volume != null)
        'Total volume went from '
            '${formatCompactWeight(kgToDisplayUnit(volume.baselineValue, unit))} to '
            '${formatCompactWeight(kgToDisplayUnit(volume.currentValue, unit))} $unit '
            '(${_changeValue(d.volumeChange)}).'
      else
        'Volume change unavailable: ${_reasonLabel(d.volumeChange)}.',
      if (frequency != null)
        'Training frequency: ${frequency.toStringAsFixed(1)} sessions/week '
            'over the last 4 weeks.',
      if (d.volumeProgressionSuppressed)
        'A plateau concern was NOT raised because total volume is rising.',
      if (_skippedCount > 0)
        '$_skippedCount unreadable workout record'
            '${_skippedCount == 1 ? ' was' : 's were'} skipped.',
      'Data quality: ${_qualityLabel(d.dataQuality)}. Warm-up and invalid '
          'sets are excluded from all calculations.',
    ];
  }

  String _qualityLabel(DataQuality q) => switch (q) {
    DataQuality.insufficient => 'insufficient',
    DataQuality.limited => 'limited',
    DataQuality.moderate => 'moderate',
    DataQuality.strong => 'strong',
  };

  // ---------------------------------------------------------------------
  // Filter + chips
  // ---------------------------------------------------------------------

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _filterController,
        decoration: InputDecoration(
          labelText: 'Filter by exercise',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _filterController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear filter',
                  onPressed: () => _filterController.clear(),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildExerciseChips() {
    if (_exerciseNames.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _exerciseNames.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final name = _exerciseNames[i];
          final selected =
              _filterController.text.trim().toLowerCase() == name.toLowerCase();
          return FilterChip(
            label: Text(name),
            selected: selected,
            onSelected: (_) =>
                selected ? _filterController.clear() : _selectExercise(name),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Deletion + history list (behaviour unchanged)
  // ---------------------------------------------------------------------

  Future<void> _deleteSet(
    String workoutId,
    String exerciseName,
    int setIndex,
    double weight,
    int reps,
  ) async {
    final unit = weightUnitLabel(weightUnitNotifier.value);
    final displayW = kgToDisplayUnit(weight, unit);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove ${formatWeight(displayW)} $unit × $reps reps '
          '($exerciseName)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // The service performs the delete + PR recalculation and returns the
      // fresh workout list (Phase 4) - no data orchestration in the screen.
      final result = await _workoutService.deleteSetAndRecalculateRecord(
        workoutId: workoutId,
        exerciseName: exerciseName,
        setIndex: setIndex,
      );
      final workouts = result.dataOrNull;
      if (workouts == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete entry.')),
          );
        }
        return;
      }

      if (!mounted) return;
      final records = _flattenToRecords(workouts);
      final names = records.map((r) => r.exerciseName).toSet().toList()..sort();
      final profile =
          await (widget.profileLoader ?? _productionProfileLoader)();
      if (!mounted) return;
      setState(() {
        _allRecords = records;
        _allWorkouts = workouts;
        _exerciseNames = names;
        _goalCurrentBest = profile?.personalRecords[_goalExercise] ?? 0;
      });
      _applyFilter();
      // notify other alive tabs; pre-set our version so the synchronous
      // notification doesn't make this screen reload its own write.
      _lastLoadedVersion = workoutDataVersion.value + 1;
      workoutDataVersion.value++;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete entry.')),
        );
      }
    }
  }
}
