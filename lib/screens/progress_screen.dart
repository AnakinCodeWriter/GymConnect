import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/workout_model.dart';
import '../services/workout_service.dart';
import '../services/plateau_detector.dart';

// A flat record of one set from one exercise on one date — used for display.
class _SetRecord {
  final DateTime date;
  final String exerciseName;
  final double weight;
  final int reps;

  _SetRecord({
    required this.date,
    required this.exerciseName,
    required this.weight,
    required this.reps,
  });

  // Epley formula: weight * (1 + reps / 30)
  double get estimated1RM => weight * (1 + reps / 30);
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final WorkoutService _workoutService = WorkoutService();
  final TextEditingController _filterController = TextEditingController();

  List<_SetRecord> _allRecords = [];
  List<_SetRecord> _filtered = [];
  List<String> _exerciseNames = [];

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
      final workouts = await _workoutService.getWorkouts(uid);
      final records = _flattenToRecords(workouts);
      final names = records.map((r) => r.exerciseName).toSet().toList()..sort();
      setState(() {
        _allRecords = records;
        _filtered = records;
        _exerciseNames = names;
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
        for (final set in exercise.sets) {
          records.add(_SetRecord(
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
      _filtered = query.isEmpty
          ? _allRecords
          : _allRecords
              .where((r) => r.exerciseName.toLowerCase().contains(query))
              .toList();
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
                        _buildFilterBar(),
                        _buildExerciseChips(),
                        _buildPlateauBanner(),
                        _buildChart(),
                        Expanded(child: _buildRecordList()),
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
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                if (result.status != PlateauStatus.insufficientData)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Slope: ${result.slope >= 0 ? '+' : ''}${result.slope.toStringAsFixed(2)} kg/session',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
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

    // Build fl_chart spots: x = session index, y = best 1RM.
    final spots = [
      for (int i = 0; i < sessions.length; i++)
        FlSpot(i.toDouble(), sessions[i].$2),
    ];

    final e1rmValues = sessions.map((s) => s.$2).toList();
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
                  'Est. 1RM (kg)',
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
                                '${value.toStringAsFixed(0)}kg',
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

  Widget _buildRecordList() {
    if (_filtered.isEmpty) {
      return const Center(
        child: Text('No entries match your filter.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _filtered.length,
      itemBuilder: (context, i) => _buildRecordCard(_filtered[i]),
    );
  }

  Widget _buildRecordCard(_SetRecord record) {
    final date = record.date;
    final dateStr = '${date.day} ${_monthName(date.month)} ${date.year}';
    final e1rm = record.estimated1RM;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.exerciseName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(dateStr,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${record.weight} kg × ${record.reps} reps',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  'Est. 1RM: ${e1rm.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
