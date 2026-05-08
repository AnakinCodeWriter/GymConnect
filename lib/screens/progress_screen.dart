import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/workout_model.dart';
import '../services/workout_service.dart';
import '../services/firestore_service.dart';
import '../services/plateau_detector.dart';
import '../services/plateau_diagnosis_service.dart';
import '../utils/fitness_formulas.dart';
import '../main.dart';

// A flat record of one set from one exercise on one date — used for display.
class _SetRecord {
  final String workoutId;   // Firestore document ID — needed for deletion
  final int setIndex;       // index of this set within the exercise's set list
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

  double get estimated1RM => estimatedOneRepMax(weight, reps);
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final WorkoutService _workoutService = WorkoutService();
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _filterController = TextEditingController();

  List<_SetRecord> _allRecords = [];
  List<_SetRecord> _filtered = [];
  List<WorkoutModel> _allWorkouts = [];
  List<WorkoutModel> _filteredWorkouts = [];
  List<String> _exerciseNames = [];

  String? _goalExercise;
  double _goalTargetWeight = 0;
  double _goalCurrentBest = 0;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWorkouts();
    _filterController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkouts() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final workoutsFuture = _workoutService.getWorkouts(uid);
      final profileFuture = _firestoreService.getUserProfile(uid);
      final workouts = await workoutsFuture;
      final profile = await profileFuture;
      final records = _flattenToRecords(workouts);
      final names = records.map((r) => r.exerciseName).toSet().toList()..sort();
      setState(() {
        _allRecords = records;
        _filtered = records;
        _allWorkouts = workouts;
        _filteredWorkouts = workouts;
        _exerciseNames = names;
        _goalExercise = profile?.goalExercise;
        _goalTargetWeight = profile?.goalTargetWeight ?? 0;
        _goalCurrentBest =
            profile?.personalRecords[profile.goalExercise] ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load workouts.';
        _loading = false;
      });
    }
  }

  List<_SetRecord> _flattenToRecords(List<WorkoutModel> workouts) {
    final records = <_SetRecord>[];
    for (final workout in workouts) {
      final date = workout.date.toDate();
      for (final exercise in workout.exercises) {
        for (int i = 0; i < exercise.sets.length; i++) {
          final set = exercise.sets[i];
          if (set.isWarmup) continue; // exclude warm-ups from chart/plateau
          records.add(_SetRecord(
            workoutId: workout.id,
            setIndex: i,
            date: date,
            exerciseName: exercise.name,
            weight: set.weight,
            reps: set.reps,
          ));
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
        _filtered = _allRecords;
        _filteredWorkouts = _allWorkouts;
      } else {
        _filtered = _allRecords
            .where((r) => r.exerciseName.toLowerCase().contains(query))
            .toList();
        _filteredWorkouts = _allWorkouts
            .where((w) => w.exercises
                .any((ex) => ex.name.toLowerCase().contains(query)))
            .toList();
      }
    });
  }

  void _selectExercise(String name) {
    _filterController.text = name;
  }

  /// Returns one best-1RM value per training day for the currently selected
  /// exercise, sorted oldest → newest.  Returns null if no exercise is
  /// exactly selected.
  List<(DateTime, double)>? _getSessionData() {
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) return null;

    final matchedName = _exerciseNames.cast<String?>().firstWhere(
          (n) => n!.toLowerCase() == query,
          orElse: () => null,
        );
    if (matchedName == null) return null;

    // Best 1RM per calendar day.
    final byDate = <DateTime, double>{};
    for (final r in _filtered) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      final e1rm = r.estimated1RM;
      if (!byDate.containsKey(day) || byDate[day]! < e1rm) {
        byDate[day] = e1rm;
      }
    }

    return byDate.entries
        .map((e) => (e.key, e.value))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1)); // oldest → newest
  }

  PlateauResult? _plateauResultForCurrentFilter() {
    final sessions = _getSessionData();
    if (sessions == null) return null;
    return PlateauDetector.analyse(sessions);
  }

  PlateauDiagnosis? _diagnosisForCurrentFilter() {
    final result = _plateauResultForCurrentFilter();
    if (result == null) return null;
    if (result.status != PlateauStatus.plateau &&
        result.status != PlateauStatus.regressing) {
      return null;
    }

    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) return null;

    final matchedName = _exerciseNames.cast<String?>().firstWhere(
          (n) => n!.toLowerCase() == query,
          orElse: () => null,
        );
    if (matchedName == null) return null;

    return PlateauDiagnosisService.analyse(_allWorkouts, matchedName);
  }

  Widget _buildDiagnosisBanner() {
    final diagnosis = _diagnosisForCurrentFilter();
    if (diagnosis == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withAlpha(20),
        border: Border.all(color: Colors.deepPurple.withAlpha(80)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.psychology_outlined,
              color: Colors.deepPurple, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Likely Cause',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  diagnosis.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  diagnosis.message,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)))
              : _allRecords.isEmpty
                  ? const Center(
                      child: Text(
                        'No workouts logged yet.\nGo log your first workout!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : Column(
                      children: [
                        if (_goalExercise != null &&
                            _goalExercise!.isNotEmpty &&
                            _goalTargetWeight > 0)
                          _ProgressGoalCard(
                            exercise: _goalExercise!,
                            currentBest: _goalCurrentBest,
                            targetWeight: _goalTargetWeight,
                          ),
                        _buildFilterBar(),
                        _buildExerciseChips(),
                        _buildPlateauBanner(),
                        _buildDiagnosisBanner(),
                        _buildChart(),
                        Expanded(child: _buildWorkoutList()),
                      ],
                    ),
    );
  }

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
          final selected = _filterController.text.trim().toLowerCase() ==
              name.toLowerCase();
          return FilterChip(
            label: Text(name),
            selected: selected,
            onSelected: (_) => selected
                ? _filterController.clear()
                : _selectExercise(name),
          );
        },
      ),
    );
  }

  Widget _buildPlateauBanner() {
    final result = _plateauResultForCurrentFilter();
    if (result == null) return const SizedBox.shrink();

    final (icon, label, sublabel, color) = switch (result.status) {
      PlateauStatus.progressing => (
          Icons.trending_up,
          'Progressing',
          'Your 1RM is trending up — keep it up!',
          Colors.green,
        ),
      PlateauStatus.plateau => (
          Icons.trending_flat,
          'Plateau',
          'Your 1RM has been flat lately. Try adding weight or varying reps.',
          Colors.orange,
        ),
      PlateauStatus.regressing => (
          Icons.trending_down,
          'Regressing',
          'Your 1RM is trending down. Check recovery, form, or volume.',
          Colors.red,
        ),
      PlateauStatus.insufficientData => (
          Icons.hourglass_empty,
          'Not enough data',
          'Log at least 3 sessions for this exercise to see a trend.',
          Colors.grey,
        ),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                ),
                if (result.status != PlateauStatus.insufficientData)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Builder(builder: (_) {
                      final isLbs = weightUnitNotifier.value == 'lbs';
                      final slope = isLbs
                          ? result.slope * 2.20462
                          : result.slope;
                      final u = isLbs ? 'lbs' : 'kg';
                      return Text(
                        'Slope: ${slope >= 0 ? '+' : ''}${slope.toStringAsFixed(2)} $u/session',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      );
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final sessions = _getSessionData();
    // Need at least 2 points to draw a line.
    if (sessions == null || sessions.length < 2) return const SizedBox.shrink();

    final isLbs = weightUnitNotifier.value == 'lbs';
    final chartFactor = isLbs ? 2.20462 : 1.0;
    final chartUnit = isLbs ? 'lbs' : 'kg';

    // Build fl_chart spots: x = session index, y = best 1RM in display unit.
    final spots = [
      for (int i = 0; i < sessions.length; i++)
        FlSpot(i.toDouble(), sessions[i].$2 * chartFactor),
    ];

    final e1rmValues = sessions.map((s) => s.$2 * chartFactor).toList();
    final minY = (e1rmValues.reduce((a, b) => a < b ? a : b) - 5)
        .clamp(0, double.infinity)
        .toDouble();
    final maxY = e1rmValues.reduce((a, b) => a > b ? a : b) + 5;

    // How often to show an x-axis label: aim for at most 4 labels.
    final labelStep = (sessions.length / 4).ceil().clamp(1, sessions.length);

    final lineColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Y-axis title, rotated 90°.
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  'Est. 1RM ($chartUnit)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: false,
                          color: lineColor,
                          barWidth: 2,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                              radius: 4,
                              color: lineColor,
                              strokeWidth: 0,
                              strokeColor: Colors.transparent,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: lineColor.withAlpha(25),
                          ),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= sessions.length) {
                                return const SizedBox.shrink();
                              }
                              if (i != 0 &&
                                  i != sessions.length - 1 &&
                                  i % labelStep != 0) {
                                return const SizedBox.shrink();
                              }
                              final d = sessions[i].$1;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${d.day} ${_monthName(d.month)}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (value, meta) {
                              if (value != meta.min &&
                                  value != meta.max &&
                                  value !=
                                      ((meta.min + meta.max) / 2)
                                          .roundToDouble()) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                '${value.toStringAsFixed(0)}$chartUnit',
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: (maxY - minY) / 4,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Colors.grey.withAlpha(50),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // X-axis title.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Session Date',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSet(String workoutId, String exerciseName,
      int setIndex, double weight, int reps) async {
    final isLbs = weightUnitNotifier.value == 'lbs';
    final displayW = isLbs ? weight * 2.20462 : weight;
    final unit = isLbs ? 'lbs' : 'kg';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove ${displayW.toStringAsFixed(displayW % 1 == 0 ? 0 : 1)} $unit × $reps reps '
          '($exerciseName)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await _workoutService.deleteSet(uid, workoutId, exerciseName, setIndex);

      final workouts = await _workoutService.getWorkouts(uid);
      double bestE1RM = 0;
      for (final w in workouts) {
        for (final ex in w.exercises) {
          if (ex.name == exerciseName) {
            for (final s in ex.sets) {
              if (s.isWarmup) continue;
              final e = estimatedOneRepMax(s.weight, s.reps);
              if (e > bestE1RM) bestE1RM = e;
            }
          }
        }
      }
      await _firestoreService.updatePersonalRecords(
          uid, {exerciseName: bestE1RM});

      if (!mounted) return;
      final records = _flattenToRecords(workouts);
      final names =
          records.map((r) => r.exerciseName).toSet().toList()..sort();
      final profile = await _firestoreService.getUserProfile(uid);
      if (!mounted) return;
      setState(() {
        _allRecords = records;
        _allWorkouts = workouts;
        _exerciseNames = names;
        _goalCurrentBest =
            profile?.personalRecords[_goalExercise] ?? 0;
      });
      _applyFilter();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete entry.')),
        );
      }
    }
  }

  Widget _buildWorkoutList() {
    return RefreshIndicator(
      onRefresh: _loadWorkouts,
      child: _filteredWorkouts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No workouts logged yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _filteredWorkouts.length,
              itemBuilder: (_, i) => _buildWorkoutCard(_filteredWorkouts[i]),
            ),
    );
  }

  Widget _buildWorkoutCard(WorkoutModel workout) {
    final date = workout.date.toDate();
    final dateStr =
        '${date.day} ${_monthName(date.month)} ${date.year}';
    final exerciseCount = workout.exercises.length;
    final setCount =
        workout.exercises.fold(0, (s, ex) => s + ex.sets.length);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: _feelLeading(workout.feelRating),
        title: Text(
          workout.name.isNotEmpty ? workout.name : dateStr,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          workout.name.isNotEmpty
              ? '$dateStr  •  $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}  •  $setCount set${setCount == 1 ? '' : 's'}'
              : '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}  •  $setCount set${setCount == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          ...workout.exercises.asMap().entries.map((entry) =>
              _buildExerciseSection(
                  workout, entry.value, entry.key < workout.exercises.length - 1)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildExerciseSection(
      WorkoutModel workout, ExerciseEntry exercise, bool showDivider) {
    final isLbs = weightUnitNotifier.value == 'lbs';
    final factor = isLbs ? 2.20462 : 1.0;
    final unit = isLbs ? 'lbs' : 'kg';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exercise.name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          ...exercise.sets.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final displayW = s.weight * factor;
            final displayWStr = displayW.toStringAsFixed(displayW % 1 == 0 ? 0 : 1);
            final e1rmKg = estimatedOneRepMax(s.weight, s.reps);
            final displayE1rm = e1rmKg * factor;
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
                  onPressed: () => _deleteSet(
                      workout.id, exercise.name, i, s.weight, s.reps),
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
        Text('$rating',
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[month];
  }
}

// Goal progress card shown at the top of the progress screen.
class _ProgressGoalCard extends StatelessWidget {
  final String exercise;
  final double currentBest;
  final double targetWeight;

  const _ProgressGoalCard({
    required this.exercise,
    required this.currentBest,
    required this.targetWeight,
  });

  @override
  Widget build(BuildContext context) {
    final isLbs = weightUnitNotifier.value == 'lbs';
    final factor = isLbs ? 2.20462 : 1.0;
    final unit = isLbs ? 'lbs' : 'kg';
    final displayCurrent = currentBest * factor;
    final displayTarget = targetWeight * factor;
    final progress = (currentBest / targetWeight).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    final achieved = currentBest >= targetWeight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.07),
          border:
              Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined,
                    color: Colors.deepPurple, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Training Goal',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (achieved)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('Achieved!',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w600)),
                    ],
                  )
                else
                  Text('$percent%',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(exercise,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              currentBest > 0
                  ? 'Current best: ${displayCurrent.toStringAsFixed(1)} $unit  •  Target: ${displayTarget.toStringAsFixed(displayTarget % 1 == 0 ? 0 : 1)} $unit'
                  : 'Target: ${displayTarget.toStringAsFixed(displayTarget % 1 == 0 ? 0 : 1)} $unit  •  No attempts yet',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor:
                    Colors.deepPurple.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  achieved ? Colors.green : Colors.deepPurple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
