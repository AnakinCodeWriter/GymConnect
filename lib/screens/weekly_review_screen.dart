import 'package:flutter/material.dart';

import '../main.dart';
import '../models/analytics.dart';
import '../models/weekly_review.dart';
import '../models/workout_model.dart';
import '../services/data_result.dart';
import '../services/review_narrator.dart';
import '../services/weekly_review_service.dart';
import '../services/workout_service.dart';
import '../theme/app_tokens.dart';
import '../utils/dates.dart';
import '../utils/units.dart';
import '../widgets/evidence_panel.dart';
import '../widgets/insight_card.dart';
import '../widgets/state_views.dart';
import '../widgets/status_banner.dart';

typedef WeeklyReviewLoader = Future<DataResult<List<WorkoutModel>>> Function();

/// The Weekly Review destination (Phase 8): a deterministic, evidence-backed
/// summary of the review week built by WeeklyReviewService and phrased by
/// the template narrator. [loader] is injectable so widget tests run
/// without Firebase.
class WeeklyReviewScreen extends StatefulWidget {
  final WeeklyReviewLoader? loader;

  const WeeklyReviewScreen({super.key, this.loader});

  @override
  State<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends State<WeeklyReviewScreen> {
  static const _narrator = TemplateReviewNarrator();

  WeeklyReview? _review;
  bool _loading = true;
  bool _initialLoadFailed = false;
  // refresh failed while the last-known review stays visible below a banner.
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

  void _onDataVersionChanged() {
    if (workoutDataVersion.value != _lastLoadedVersion) _loadData();
  }

  // Constructed lazily so tests injecting [widget.loader] never touch
  // Firebase. Same underlying workout source as Dashboard and Progress.
  static Future<DataResult<List<WorkoutModel>>> _productionLoader() =>
      WorkoutService().loadWorkouts();

  Future<void> _loadData() async {
    final version = workoutDataVersion.value;
    final result = await (widget.loader ?? _productionLoader)();
    if (!mounted) return;
    _lastLoadedVersion = version;

    switch (result) {
      case DataFailure():
        setState(() {
          if (_review == null) {
            _initialLoadFailed = true;
          } else {
            _refreshFailed = true; // keep the last-known review visible
          }
          _loading = false;
        });
      case DataSuccess(:final data, :final skipped):
        setState(() {
          _review = WeeklyReviewService.build(
            data,
            referenceDate: DateTime.now(),
            skippedRecords: skipped.length,
          );
          _loading = false;
          _initialLoadFailed = false;
          _refreshFailed = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Review')),
      body: _loading
          ? const LoadingView()
          : _initialLoadFailed && _review == null
          ? ErrorRetryView(
              title: 'Couldn\'t load your weekly review',
              message: 'Check your connection and try again.',
              onRetry: () {
                setState(() {
                  _loading = true;
                  _initialLoadFailed = false;
                });
                _loadData();
              },
            )
          : _buildReview(_review!),
    );
  }

  Widget _buildReview(WeeklyReview review) {
    final unit = weightUnitLabel(weightUnitNotifier.value);
    final narration = _narrator.narrate(review, weightUnit: unit);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: Insets.page,
        children: [
          Text(
            'Week of ${formatDayMonth(review.week.start)} – '
            '${formatDayMonth(review.week.end)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: Insets.lg),
          if (_refreshFailed) ...[
            StatusBanner(
              icon: Icons.cloud_off,
              title: 'Couldn\'t refresh your weekly review',
              message:
                  'Showing your last loaded review. Check your connection '
                  'and retry.',
              actionLabel: 'Retry',
              onAction: _loadData,
            ),
            const SizedBox(height: Insets.md),
          ],
          if (review.skippedRecords > 0) ...[
            InlineNotice(
              message:
                  '${review.skippedRecords} workout '
                  'record${review.skippedRecords == 1 ? '' : 's'} couldn\'t '
                  'be read and ${review.skippedRecords == 1 ? 'is' : 'are'} '
                  'not included.',
            ),
            const SizedBox(height: Insets.md),
          ],
          if (review.availability == ReviewAvailability.noData)
            const EmptyView(
              icon: Icons.reviews_outlined,
              message:
                  'No workouts yet.\nLog your first workout and your weekly '
                  'review will appear here!',
            )
          else ...[
            _summaryCard(review, narration),
            const SizedBox(height: Insets.xs),
            Text(
              'Based on ${_qualityLabel(review.dataQuality)} data.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.lg),
            ..._section(
              'What improved',
              review.improvements,
              narration.improvements,
            ),
            ..._section('What stayed stable', review.stable, narration.stable),
            ..._section(
              'What may need attention',
              review.attention,
              narration.attention,
            ),
            ..._actionsSection(review.actions, narration.actions),
            EvidencePanel(facts: _evidenceFacts(review, unit)),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(WeeklyReview review, ReviewNarration narration) {
    final hasWarning = review.attention.any(
      (f) => f.severity == Severity.warning,
    );
    final hasCaution = review.attention.any(
      (f) => f.severity == Severity.caution,
    );
    final (icon, color) = hasWarning
        ? (Icons.trending_down, Colors.red)
        : hasCaution
        ? (Icons.warning_amber_outlined, Colors.orange)
        : review.improvements.isNotEmpty
        ? (Icons.trending_up, Colors.green)
        : (Icons.check_circle_outline, Colors.teal);
    return InsightCard(
      icon: icon,
      color: color,
      label: 'Weekly Summary',
      title: narration.headline,
      message: narration.summary,
    );
  }

  // One section: header + one row per finding, prose paired with the typed
  // finding's severity. Empty sections are omitted entirely.
  List<Widget> _section(
    String title,
    List<ReviewFinding> findings,
    List<String> lines,
  ) {
    if (findings.isEmpty) return const [];
    return [
      SectionHeader(title),
      const SizedBox(height: Insets.sm),
      for (var i = 0; i < findings.length; i++)
        _findingRow(findings[i], lines[i]),
      const SizedBox(height: Insets.lg),
    ];
  }

  Widget _findingRow(ReviewFinding finding, String line) {
    final (icon, color) = switch (finding.severity) {
      Severity.warning => (Icons.trending_down, Colors.red),
      Severity.caution => (Icons.warning_amber_outlined, Colors.orange),
      Severity.info => switch (finding.kind) {
        ReviewFindingKind.newPersonalRecord => (
          Icons.emoji_events_outlined,
          Colors.amber.shade700,
        ),
        ReviewFindingKind.workoutCountIncreased ||
        ReviewFindingKind.volumeIncreased ||
        ReviewFindingKind.exerciseProgressing ||
        ReviewFindingKind.feelImproved => (Icons.trending_up, Colors.green),
        _ => (Icons.horizontal_rule, Colors.blueGrey),
      },
    };
    return _row(icon, color, line);
  }

  List<Widget> _actionsSection(
    List<SuggestedAction> actions,
    List<String> lines,
  ) {
    if (actions.isEmpty) return const [];
    return [
      const SectionHeader('Suggested next steps'),
      const SizedBox(height: Insets.sm),
      for (var i = 0; i < actions.length; i++)
        _row(
          Icons.lightbulb_outline,
          Theme.of(context).colorScheme.primary,
          lines[i],
        ),
      const SizedBox(height: Insets.lg),
    ];
  }

  Widget _row(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Insets.md),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }

  // Human-readable facts derived from the typed review - the structured
  // evidence itself stays on the model; this is presentation only.
  List<String> _evidenceFacts(WeeklyReview r, String unit) {
    String vol(double kg) =>
        '${formatCompactWeight(kgToDisplayUnit(kg, unit))} $unit';

    final facts = <String>[
      'Week analysed: ${formatDayMonth(r.week.start)} – ${formatDayMonth(r.week.end)} '
          '(Monday–Sunday), compared with ${formatDayMonth(r.previousWeek.start)} '
          '– ${formatDayMonth(r.previousWeek.end)}.',
      'Workouts: ${r.workoutsThisWeek} this week, '
          '${r.workoutsPreviousWeek} last week, ${r.totalWorkouts} total.',
      'Weekly volume (eligible sets only): ${vol(r.volumeThisWeekKg)} this '
          'week vs ${vol(r.volumePreviousWeekKg)} last week'
          '${r.volumeChange.isAvailable ? '' : ' (no safe comparison: '
                    '${_reasonLabel(r.volumeChange)})'}.',
      _feelFact(r.feel),
      for (final f in [...r.improvements, ...r.stable, ...r.attention])
        if (f.exercise != null) ..._trendFacts(f),
      if (r.skippedRecords > 0)
        '${r.skippedRecords} unreadable record'
            '${r.skippedRecords == 1 ? '' : 's'} excluded from every number '
            'above.',
      'Data quality: ${_qualityLabel(r.dataQuality)} '
          '(${r.totalWorkouts} stored workouts).',
    ];
    // Deduplicate while preserving order (an exercise can back findings in
    // more than one section).
    return {...facts}.toList();
  }

  List<String> _trendFacts(ReviewFinding f) {
    for (final e in f.evidence) {
      if (e.metric == MetricType.workoutCount && e.observedValue != null) {
        return [
          '${f.exercise}: trend judged over '
              '${e.observedValue!.round()} logged sessions '
              '(minimum ${e.comparisonValue?.round() ?? '-'}).',
        ];
      }
    }
    return const [];
  }

  String _feelFact(FeelSummary feel) {
    final thisAvg = feel.averageThisWeek.valueOrNull;
    final prevAvg = feel.averagePreviousWeek.valueOrNull;
    final thisPart = thisAvg != null
        ? 'avg ${thisAvg.toStringAsFixed(1)}/5 from ${feel.ratedThisWeek} '
              'rated sessions'
        : 'not enough rated sessions (${feel.ratedThisWeek} of '
              '${WeeklyReviewService.minRatedSessionsForFeelAverage} needed)';
    final prevPart = prevAvg != null
        ? 'avg ${prevAvg.toStringAsFixed(1)}/5 from ${feel.ratedPreviousWeek}'
        : 'not enough rated sessions (${feel.ratedPreviousWeek})';
    return 'Session feel: this week $thisPart; last week $prevPart.';
  }

  String _reasonLabel(MetricResult<Object> result) => switch (result) {
    MetricUnavailable(:final reason) => switch (reason) {
      InsufficiencyReason.noData => 'no workouts last week',
      InsufficiencyReason.zeroBaseline => 'last week had zero volume',
      InsufficiencyReason.noMatchingExercise => 'no matching exercise',
      InsufficiencyReason.tooFewSessions => 'too few sessions',
    },
    MetricAvailable() => '',
  };

  String _qualityLabel(DataQuality q) => switch (q) {
    DataQuality.insufficient => 'insufficient',
    DataQuality.limited => 'limited',
    DataQuality.moderate => 'moderate',
    DataQuality.strong => 'strong',
  };
}
