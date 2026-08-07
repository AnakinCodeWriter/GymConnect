import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/analytics.dart';
import '../models/dashboard.dart';
import '../models/user_model.dart';
import '../models/workout_model.dart';
import '../services/dashboard_service.dart';
import '../services/data_result.dart';
import '../services/feel_analysis_service.dart';
import '../services/firestore_service.dart';
import '../services/recommendation_service.dart';
import '../services/workout_service.dart';
import '../theme/app_tokens.dart';
import '../utils/dates.dart';
import '../utils/units.dart';
import '../widgets/goal_card.dart';
import '../widgets/insight_card.dart';
import '../widgets/state_views.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_banner.dart';
import '../main.dart';
import 'app_shell.dart';
import 'log_workout_screen.dart';

/// What the dashboard needs loaded: the workout history result plus the
/// profile (null when missing or when its load failed - the dashboard then
/// renders partially without greeting/goal rather than failing entirely).
class DashboardLoadResult {
  final DataResult<List<WorkoutModel>> workouts;
  final UserModel? profile;

  const DashboardLoadResult({required this.workouts, this.profile});
}

typedef DashboardLoader = Future<DashboardLoadResult> Function();

/// The Dashboard destination (Phase 6): typed metrics from DashboardService.
/// [loader] is injectable so widget tests run without Firebase.
class HomeScreen extends StatefulWidget {
  final DashboardLoader? loader;

  const HomeScreen({super.key, this.loader});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recommendationService = RecommendationService();

  DashboardData? _dashboard;
  UserModel? _profile;
  Recommendation? _recommendation;
  FeelInsight? _feelInsight;

  bool _loading = true;
  bool _initialLoadFailed = false;
  // refresh failed while last-known data stays visible below the banner.
  bool _refreshFailed = false;
  int _lastLoadedVersion = 0;

  @override
  void initState() {
    super.initState();
    workoutDataVersion.addListener(_onDataVersionChanged);
    _loadData();
  }

  @override
  void dispose() {
    workoutDataVersion.removeListener(_onDataVersionChanged);
    super.dispose();
  }

  // Another screen saved/deleted training or profile data - reload unless
  // this screen already loaded that version.
  void _onDataVersionChanged() {
    if (workoutDataVersion.value != _lastLoadedVersion) _loadData();
  }

  // Production loader; constructed lazily so tests injecting [widget.loader]
  // never touch Firebase.
  static Future<DashboardLoadResult> _productionLoader() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    UserModel? profile;
    if (uid != null) {
      try {
        profile = await FirestoreService().getUserProfile(uid);
      } catch (_) {
        profile = null; // non-critical: partial dashboard without goal
      }
    }
    final workouts = await WorkoutService().loadWorkouts();
    return DashboardLoadResult(workouts: workouts, profile: profile);
  }

  Future<void> _loadData() async {
    final version = workoutDataVersion.value;
    final result = await (widget.loader ?? _productionLoader)();
    if (!mounted) return;
    _lastLoadedVersion = version;

    final workouts = result.workouts.dataOrNull;
    if (workouts == null) {
      setState(() {
        if (_dashboard == null) {
          _initialLoadFailed = true;
        } else {
          _refreshFailed = true; // keep last-known data visible
        }
        _loading = false;
      });
      return;
    }

    final skipped = switch (result.workouts) {
      DataSuccess(:final skipped) => skipped.length,
      _ => 0,
    };
    setState(() {
      _dashboard = DashboardService.build(
        workouts,
        referenceDate: DateTime.now(),
        skippedRecords: skipped,
      );
      _profile = result.profile;
      _recommendation = _recommendationService.generate(workouts);
      _feelInsight = FeelAnalysisService.analyse(workouts);
      _loading = false;
      _initialLoadFailed = false;
      _refreshFailed = false;
    });
  }

  Future<void> _openLogWorkout() async {
    final newPRs = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const LogWorkoutScreen()),
    );
    // reload happens via the workoutDataVersion listener after a save.
    if (!mounted) return;
    if (newPRs != null && newPRs.isNotEmpty) _showPRDialog(newPRs);
  }

  void _showPRDialog(List<String> exercises) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text('New Personal Record!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You hit a new best on:'),
            const SizedBox(height: 8),
            ...exercises.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      e,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nice!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GymConnect')),
      body: _loading
          ? const LoadingView()
          : _initialLoadFailed && _dashboard == null
          ? ErrorRetryView(
              title: 'Couldn\'t load your dashboard',
              message: 'Check your connection and try again.',
              onRetry: () {
                setState(() {
                  _loading = true;
                  _initialLoadFailed = false;
                });
                _loadData();
              },
            )
          : _buildDashboard(_dashboard!),
    );
  }

  Widget _buildDashboard(DashboardData d) {
    final name = _profile?.displayName;
    final unit = weightUnitLabel(weightUnitNotifier.value);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: Insets.page,
        children: [
          Text(
            name != null && name.isNotEmpty
                ? 'Welcome back, $name!'
                : 'Welcome!',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'Week of ${formatDayMonth(d.currentWeek.start)} – ${formatDayMonth(d.currentWeek.end)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.lg),
          ElevatedButton.icon(
            onPressed: _openLogWorkout,
            icon: const Icon(Icons.fitness_center),
            label: const Text('Log Workout'),
          ),
          const SizedBox(height: Insets.lg),
          if (_refreshFailed) ...[
            StatusBanner(
              icon: Icons.cloud_off,
              title: 'Couldn\'t refresh your training data',
              message:
                  'Showing your last loaded data. Check your connection and retry.',
              actionLabel: 'Retry',
              onAction: _loadData,
            ),
            const SizedBox(height: Insets.md),
          ],
          if (d.skippedRecords > 0) ...[
            InlineNotice(
              message:
                  '${d.skippedRecords} workout record${d.skippedRecords == 1 ? '' : 's'} '
                  'couldn\'t be read and ${d.skippedRecords == 1 ? 'is' : 'are'} not included.',
            ),
            const SizedBox(height: Insets.md),
          ],
          if (d.status == TrainingStatus.noData)
            const EmptyView(
              icon: Icons.fitness_center,
              message:
                  'No workouts yet.\nLog your first workout to start tracking progress!',
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatCard(
                    icon: Icons.event_available,
                    label: 'Workouts this week',
                    value: '${d.activity.thisWeek}',
                    subtitle: _activitySubtitle(d.activity),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: StatCard(
                    icon: Icons.bar_chart,
                    label: 'Volume this week',
                    value:
                        '${formatCompactWeight(kgToDisplayUnit(d.volume.thisWeekKg, unit))} $unit',
                    subtitle: _volumeSubtitle(d.volume),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            _statusCard(d),
            const SizedBox(height: Insets.xs),
            Text(
              'Based on ${_qualityLabel(d.dataQuality)} data.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.md),
            if (_profile != null &&
                _profile!.goalExercise.isNotEmpty &&
                _profile!.goalTargetWeight > 0) ...[
              GoalCard(
                exercise: _profile!.goalExercise,
                currentBest:
                    _profile!.personalRecords[_profile!.goalExercise] ?? 0,
                targetWeight: _profile!.goalTargetWeight,
              ),
              const SizedBox(height: Insets.md),
            ],
            if (d.topExercises.isNotEmpty) ...[
              _listCard(
                title: 'Most trained (last 4 weeks) — tap to inspect',
                rows: [
                  for (final t in d.topExercises)
                    (
                      t.name,
                      '${t.workoutCount} workout${t.workoutCount == 1 ? '' : 's'}',
                    ),
                ],
                // preselect the exercise on the Progress tab (Phase 7)
                onRowTap: (name) {
                  progressExerciseRequest.value = name;
                  AppShellTabs.switchTo(context, 1);
                },
              ),
              const SizedBox(height: Insets.md),
            ],
            if (d.recentPersonalRecords.isNotEmpty) ...[
              _listCard(
                title: 'Recent personal records (last 2 weeks)',
                rows: [
                  for (final pr in d.recentPersonalRecords)
                    (
                      pr.exercise,
                      '${formatWeight(kgToDisplayUnit(pr.e1RmKg, unit))} $unit · ${formatDayMonth(pr.day)}',
                    ),
                ],
              ),
              const SizedBox(height: Insets.md),
            ],
            // rule-based recommendation kept for its balance/keep-going
            // advice; the plateau/regression branch is superseded by the
            // evidence-backed training status above (see docs/DECISIONS.md).
            if (_recommendation != null &&
                (_recommendation!.type == RecommendationType.balanceWorkout ||
                    _recommendation!.type == RecommendationType.keepGoing)) ...[
              _recommendationCard(_recommendation!),
              const SizedBox(height: Insets.md),
            ],
            if (_feelInsight != null) ...[
              _feelInsightCard(_feelInsight!),
              const SizedBox(height: Insets.md),
            ],
            OutlinedButton.icon(
              onPressed: () => AppShellTabs.switchTo(context, 1),
              icon: const Icon(Icons.show_chart),
              label: const Text('View detailed progress'),
            ),
          ],
        ],
      ),
    );
  }

  String _activitySubtitle(WeeklyActivity a) {
    if (a.change > 0) return '+${a.change} vs last week (${a.previousWeek})';
    if (a.change < 0) return '${a.change} vs last week (${a.previousWeek})';
    return 'same as last week (${a.previousWeek})';
  }

  String _volumeSubtitle(WeeklyVolume v) {
    final change = v.change.valueOrNull;
    if (change != null) {
      final sign = change.percent >= 0 ? '+' : '';
      return '$sign${change.percent.toStringAsFixed(0)}% vs last week';
    }
    return 'no comparison available';
  }

  Widget _statusCard(DashboardData d) {
    String warningEvidence() => d.trendWarnings
        .map(
          (w) =>
              '${w.exercise}: estimated 1RM looks '
              '${w.concern == TrendConcern.plateau ? 'flat' : 'to be declining'} '
              'across ${w.sessionCount} sessions.',
        )
        .join('\n');

    final (icon, color, title, message) = switch (d.status) {
      TrainingStatus.noData => (
        Icons.flag_outlined,
        Colors.blue,
        'No data yet',
        'Log a workout to get started.',
      ),
      TrainingStatus.gettingStarted => (
        Icons.directions_run,
        Colors.blue,
        'Getting started',
        'Trend analysis unlocks as you log more sessions - keep going!',
      ),
      TrainingStatus.possibleRegression => (
        Icons.trending_down,
        Colors.red,
        'Possible regression',
        '${warningEvidence()}\nWorth reviewing in Progress - recovery, form '
            'or volume could all play a part.',
      ),
      TrainingStatus.possiblePlateau => (
        Icons.trending_flat,
        Colors.orange,
        'Possible plateau',
        '${warningEvidence()}\nSee Progress for a possible explanation.',
      ),
      TrainingStatus.progressing => (
        Icons.trending_up,
        Colors.green,
        'Progressing',
        'Trending up: ${d.progressingExercises.join(', ')}. Keep it up!',
      ),
      TrainingStatus.activeWeek => (
        Icons.check_circle_outline,
        Colors.teal,
        'Active week',
        '${d.activity.thisWeek} workout${d.activity.thisWeek == 1 ? '' : 's'} '
            'logged this week.',
      ),
      TrainingStatus.needsMoreData => (
        Icons.hourglass_empty,
        Colors.blueGrey,
        'Keep logging',
        'No sessions yet this week, and not enough recent data for a trend.',
      ),
    };

    return InsightCard(
      icon: icon,
      color: color,
      label: 'Training Status',
      title: title,
      message: message,
    );
  }

  String _qualityLabel(DataQuality q) => switch (q) {
    DataQuality.insufficient => 'insufficient',
    DataQuality.limited => 'limited',
    DataQuality.moderate => 'moderate',
    DataQuality.strong => 'strong',
  };

  Widget _listCard({
    required String title,
    required List<(String, String)> rows,
    void Function(String label)? onRowTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(Corners.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: Insets.sm),
          for (final (label, value) in rows)
            InkWell(
              onTap: onRowTap != null ? () => onRowTap(label) : null,
              borderRadius: BorderRadius.circular(Corners.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (onRowTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recommendationCard(Recommendation recommendation) {
    final (icon, color) = switch (recommendation.type) {
      RecommendationType.startBeginner => (Icons.directions_run, Colors.blue),
      RecommendationType.balanceWorkout => (Icons.balance, Colors.orange),
      RecommendationType.plateauAdvice => (
        Icons.trending_flat,
        Colors.deepOrange,
      ),
      RecommendationType.keepGoing => (Icons.thumb_up, Colors.green),
    };
    return InsightCard(
      icon: icon,
      color: color,
      label: 'Recommended Next Step',
      title: recommendation.title,
      message: recommendation.message,
    );
  }

  Widget _feelInsightCard(FeelInsight insight) {
    final (icon, color) = switch (insight.type) {
      FeelInsightType.lowStreakWarning => (
        Icons.warning_amber_outlined,
        Colors.orange,
      ),
      FeelInsightType.performanceCorrelation => (Icons.insights, Colors.teal),
      FeelInsightType.bestDayOfWeek => (Icons.calendar_today, Colors.blue),
    };
    return InsightCard(
      icon: icon,
      color: color,
      label: 'Session Feel Insight',
      title: insight.title,
      message: insight.message,
    );
  }
}
