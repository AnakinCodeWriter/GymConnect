# GymConnect — Analytics Definitions

Authoritative definitions of every calculated metric. **Current** = implemented
today (with source file). **Planned** = approved but not yet implemented; each
planned metric must have its definition completed here (meaning, time period,
calculation, missing-data behaviour, tests) *before* implementation.

Baseline date: 2026-07-02.

## Typed analytics domain (current — added Phase 2)

Source: `lib/models/analytics.dart` (pure Dart, no serialization; prose never
lives in these types). Consumed by `ExerciseAnalyticsService` now and by the
dashboard/weekly review later.

- **`DatePeriod`** — inclusive range of local calendar days; inputs'
  time components are stripped. `lastDays(n, endingOn:)` = the reference day
  plus the n−1 days before it. `dayCount` is DST-safe (rounded from hours).
- **`MetricResult<T>`** (sealed) — `MetricAvailable(value)` (including a
  genuine zero) or `MetricUnavailable(reason, observedCount?, requiredCount?)`.
  Absence is never encoded as null or 0.
- **`InsufficiencyReason`** — `noData`, `noMatchingExercise`,
  `tooFewSessions`, `zeroBaseline`.
- **`PercentageChange`** — signed percent + baseline/current values and
  periods; `direction` derived (increase/decrease/unchanged). Undefined
  changes are represented as `MetricUnavailable`, never by this type.
- **`EvidenceItem`** — metric type, observed value, comparison value/threshold,
  period, data sufficiency. Answers: what was observed, against what, over
  what period, and whether data sufficed.
- **`DataQuality`** — categorical `insufficient | limited | moderate |
  strong`. Deliberately not numeric: no fabricated confidence percentages.
- **`Severity`** — `info | caution | warning`. Kept distinct from
  DataQuality (amount of data) and ChangeDirection (direction of change).
- **`ExerciseSession` / `ExerciseSeries`** — one exercise-day (best e1RM kg,
  volume kg, working-set count) / all such days ascending.

Typed `Insight`/`Recommendation` container types are deliberately deferred to
their first consumer phases (6–8) — see docs/DECISIONS.md.

## Conventions (current)

- All stored weights are kilograms. Display conversion: `lbs = kg × 2.20462`.
- "Working set" = a set with `isWarmup != true`. Warm-up sets are excluded
  from all analytics, PRs, charts and (since Phase 3) the leaderboard — see
  the eligibility table below.
- Workout lists from `WorkoutService.getWorkouts` are sorted newest-first;
  several services document and rely on that ordering.
  (`ExerciseAnalyticsService` does NOT rely on input order.)
- **Session definition** (per-exercise analytics): one *local calendar day*
  on which the exercise was performed. Multiple workouts on the same day —
  including duplicate timestamps — merge into one session: best e1RM = max
  across them, volume = sum. Distinct same-day workouts remain distinct
  documents in history; only the analytics view merges them (this matches
  the pre-Phase-2 chart/volume behaviour).
- **Exercise matching**: trimmed, case-insensitive, exact name equality.
- **Invalid data**: sets with `weight < 0` or `reps < 1` are ignored by
  analytics (the logging UI prevents them, but Firestore data is untrusted);
  zero weight is a valid value (e1RM 0, volume 0). A day with no valid
  working sets produces no session. Malformed records never distort valid
  ones.
- Timezone: analytics use the device-local `DateTime` from stored
  timestamps; "day" = local calendar date.

## Current: estimated one-rep max (e1RM) — canonical (Phase 3)

- Source: `lib/utils/fitness_formulas.dart` → `estimatedOneRepMax(weight, reps)`
  — the ONLY e1RM implementation in the repository. There are no
  leaderboard/recommendation/progress variants.
- Formula: Epley, `weight × (1 + r/30)` with `r = reps.clamp(1, 10)`.
  - Repetition range: any int accepted; clamped to [1, 10]. The cap at 10
    prevents high-rep sets producing inflated maxima; reps < 1 clamp to 1.
  - Weight range: any finite kg value ≥ 0 is meaningful; zero weight → 0.
    Negative/non-finite weights propagate mathematically — the formula does
    NOT gate inputs; **eligibility is the caller's responsibility** via
    `isEligibleForStrengthAnalytics` (below).
  - Precision: returns an **unrounded** double. Rounding happens only at
    display boundaries (per-screen formatting); comparisons — e.g. personal
    records and leaderboard "only when improved" — use the unrounded value
    with exact `>` (no tolerance).
- Strength-trend analyses use **one best e1RM per exercise per session day**.

## Current: warm-up / validity eligibility (Phase 3)

`isEligibleForStrengthAnalytics(set)` = not warm-up ∧ finite weight ≥ 0 ∧
reps ≥ 1. Applied by metric category:

| Category | Warm-ups | Malformed sets |
|---|---|---|
| Strength-performance (e1RM trends, PRs, leaderboard, recommendation comparisons, feel best-lift) | excluded | excluded |
| Training-volume (session volume, weekly/lifetime totals, save-dialog total) | excluded (pre-existing behaviour, preserved) | excluded (Phase 3) |
| Workout-history display and logging prefill | shown | shown |

## Current: units and formatting (Phase 3)

- Source: `lib/utils/units.dart` — the only definition of the conversion
  factor (`lbsPerKg = 2.20462`, unchanged compatibility baseline).
- Invariants: stored values are always kg at full double precision;
  analytics never convert to lbs internally; conversion happens once at the
  display boundary (`kgToDisplayUnit`) and once for input
  (`displayUnitToKg`). No repeated rounding during calculation.
- Display rounding (preserved per screen): weights use `formatWeight`
  (≤ 1 dp, trailing ".0" trimmed); e1RM readouts fixed 1 dp; trend slope
  signed 2 dp; chart axes 0 dp; large totals use `formatCompactWeight`
  (≥1M → "1.23M", ≥1k → "1.2k", else 0 dp). The log-workout volume dialog
  now shares the compact formatter and therefore gains the M tier
  (unreachable in practice) — the only intentional display unification.
- Non-finite values: formatting renders an em dash (never "NaN"/"Infinity");
  analytics exclude non-finite weights via the eligibility rule.

## Current: trend classification (plateau detection)

- Source: `lib/services/plateau_detector.dart` → `PlateauDetector.analyse`.
- Input: list of `(DateTime, double)` per-session best e1RM (any order; sorted
  internally). Volume trends reuse the same detector with volume values.
- Method: weighted least-squares linear regression of value against days since
  first session, with exponential recency weights `w_i = 0.85^(n-1-i)`
  (newest session weight 1.0).
- Minimum data: 5 sessions, else `insufficientData`.
- The slope is normalised by the weighted mean value (scale-invariant).
  Thresholds on the normalised slope per day:
  - `> +0.001` (≈ +0.7%/week) → `progressing`
  - `< −0.001` → `regressing`
  - otherwise → `plateau`
  - degenerate x-variance (all sessions same day) → `plateau`, slope 0.
- Output slope is raw units/day (kg/day for e1RM); UI shows it ×7 as per-week.

## Current: per-exercise session analytics (ExerciseAnalyticsService)

Source: `lib/services/exercise_analytics_service.dart` (Phase 2, extracted
from `progress_screen.dart`). Pure and deterministic; all time windows are
explicit `DatePeriod`s built by the caller, which injects "today".

- **Series** (`buildSeries`): per-calendar-day `ExerciseSession`s per the
  session/matching/invalid-data conventions above, ascending by day.
- **e1RM trend** (`e1RmTrend`): PlateauDetector over (day, best e1RM).
- **Volume trend** (`volumeTrend`): PlateauDetector over (day, session
  volume); zero-volume sessions excluded (preserved pre-extraction
  behaviour).
- **Training frequency** (`trainingFrequencyPerWeek`): sessions inside the
  period ÷ (period dayCount / 7). Genuine 0 when the exercise has history
  but none in the period; unavailable(noData) when the series is empty.
- **Recent best** (`bestE1RmIn`): max session e1RM within the period;
  unavailable(noData) when the period has no sessions.
- **Percentage change** (`percentageChange`): compares an aggregate between
  two explicit periods — best e1RM aggregates with **max**, volume with
  **sum**. `(current − baseline)/baseline × 100`. Either period empty →
  unavailable(noData); baseline aggregate 0 → unavailable(zeroBaseline)
  (never 0% or infinity); current 0 vs positive baseline → genuine −100%.

### Phase 2 behaviour corrections (defects fixed, regression-tested)

1. e1RM series previously substring-matched the filter (selecting
   "Bench Press" included "Incline Bench Press" sets); now exact matching,
   consistent with the volume series.
2. The volume series previously counted only the first of duplicate
   same-named exercise entries in a workout; now all entries count (the
   e1RM path already did).
3. Malformed sets (negative weight, reps < 1) were previously included; now
   ignored.

## Current: "Volume Progressing" combined state

- Source: gating logic in `progress_screen.dart` using
  `ExerciseAnalyticsService` trend results.
- Session volume = Σ(weight × reps) over working sets of the exercise per
  calendar day, in kg.
- If e1RM trend is plateau/regressing but the volume trend (same detector) is
  progressing, the UI shows "Volume Progressing" and suppresses the plateau
  diagnosis, on the rationale that rising volume is not a true stall.

## Current: plateau diagnosis rules

- Source: `lib/services/plateau_diagnosis_service.dart`. Fully deterministic:
  `analyse` requires a `referenceDate` argument anchoring the time-window
  rules (UI callers pass `DateTime.now()`); a session exactly 28 days before
  the reference date belongs to the *prior* window (`isAfter` is strict).
- Input: full workout list (newest-first) + exercise name (case-insensitive,
  trimmed match). Sessions with only warm-up sets are ignored.
- Requires ≥ 4 sessions of the exercise, else null.
- Rules produce (confidence, diagnosis); the highest confidence wins:
  1. **Frequency drop** — sessions in last 28 days vs prior 28 days (needs
     prior ≥ 2). ratio ≤ 0.4 → confidence 0.85; ≤ 0.6 → 0.75.
  2. **Rep monotony** — modal rep count identical in ≥ 5 of last 6 sessions
     (needs ≥ 5 recent) → 0.75.
  3. **Continuous escalation** — max session weight strictly increased across
     the last 5–6 sessions → 0.72.
  4. **No recovery week** — no session in the last 8 (needs ≥ 6) at ≤ 70% of
     the period's peak weight → 0.70.
- Presentation note: diagnoses are *possible explanations*. Current UI labels
  the banner "Likely Cause"; softening to "possible explanation" wording is
  approved (Phase 7).

## Current: feel (wellness) insights

- Source: `lib/services/feel_analysis_service.dart`.
- Requires ≥ 3 rated workouts (`feelRating` 1–5), else null. Priority order:
  1. **Low-feel streak** — the 3+ most recent rated sessions all rated ≤ 2.
  2. **Performance correlation** — mean best-e1RM on high-feel days (4–5) vs
     low-feel days (1–2); needs ≥ 3 workouts in each bucket; reported only if
     the rounded percentage difference is positive. Rating 3 is excluded.
  3. **Best day of week** — highest mean rating among weekdays with ≥ 2
     rated sessions.

## Current: home-screen recommendation

- Source: `lib/services/recommendation_service.dart`. First match wins:
  1. No workouts → "get started".
  2. Most-logged exercise classified plateau/regressing (uses the uncapped
     inline e1RM — inconsistency noted above) → plateau/progress alert.
  3. All logged exercises map (by keyword) to a single muscle group →
     "balance your training".
  4. Otherwise → "keep it up".
- A separate `suggestNextWorkout` (upper/lower/full-body from the last
  workout's exercise keywords) exists but is not currently rendered by any
  screen.

## Current: volume and lifetime stats

- Session/lifetime volume: Σ(weight_kg × reps) over working sets
  (`WorkoutService.getTotalVolumeLiftedKg`, save-flow total-volume dialog).
- Personal records: `users/{uid}.personalRecords[exercise]` = best capped
  e1RM over working sets; updated on save (only when improved) and
  recalculated after set deletion.

## Current: dashboard metrics (Phase 6)

Source: `lib/services/dashboard_service.dart` (pure; injected reference
date) returning `lib/models/dashboard.dart` types.

- **Week boundary**: Monday 00:00 – Sunday 23:59 in local calendar days
  (`DatePeriod.weekContaining`, DST-safe component arithmetic). All "this
  week / last week" metrics use it.
- **Weekly activity**: count of workout documents dated within each week;
  change = simple difference.
- **Weekly volume**: Σ(weight × reps) over ELIGIBLE sets (warm-ups and
  malformed sets excluded — the project-wide Phase 3 volume convention) of
  workouts in the week. Week-over-week change: previous week without
  workouts → unavailable(noData); with workouts but zero volume →
  unavailable(zeroBaseline); otherwise signed percent. Zero-volume workouts
  count toward activity and add 0 volume.
- **Top exercises**: distinct trimmed exercise names per workout over the
  last 28 days, ranked by number of workouts containing them (a workout
  counts once despite duplicate entries); ties broken by name ascending;
  top 3. Empty when no workouts in the window.
- **Recent personal records**: window = last 14 days. Built from history via
  `buildSeries` (canonical capped e1RM + eligibility). A PR = a session day
  in the window whose best e1RM STRICTLY exceeds every earlier session's
  best for that exercise; a first-ever session is not a record. Best
  qualifying day per exercise; newest first; capped at 5.
- **Trend warnings**: bounded to the ≤3 top exercises; full-history e1RM
  trend via PlateauDetector; plateau/regression warnings suppressed when the
  volume trend is progressing (same rule as the progress screen);
  insufficientData produces no warning (not a concern). Evidence carried:
  session count + slope kg/day. Presented as POSSIBLE, never certain.
- **Training status** (priority order): no workouts → noData; < 5 total →
  gettingStarted; any regression warning → possibleRegression; any plateau
  warning → possiblePlateau; any analysed trend progressing → progressing;
  ≥ 1 workout this week → activeWeek; else needsMoreData.
- **Data quality** (categorical, from total history size): 0 →
  insufficient; 1–4 → limited; 5–14 → moderate; ≥ 15 → strong. Skipped
  malformed records are carried separately (`skippedRecords`) and always
  surfaced in the UI as a notice (partial data, never silent).

## Current: per-exercise detail analytics (Phase 7)

Source: `ExerciseAnalyticsService.analyseExercise` → typed `ExerciseDetail`
(`lib/models/exercise_detail.dart`). Deterministic; all windows derive from
the injected reference date.

- **Windows**: recent = last 28 days ending on the reference date; baseline
  = the 28 days immediately before. Session = local calendar day, same-day
  merge (unchanged Phase 2 definition).
- **Strength trend / volume trend**: full-history PlateauDetector results
  (unchanged model and ±0.1%/day thresholds); the volume-progressing
  suppression rule matches the dashboard: a plateau/regression concern (and
  its diagnosis) is suppressed while the volume trend is progressing.
- **Recent best**: max session e1RM within the recent window plus its
  (latest) day; unavailable(noData) when the window has no sessions — never
  reported as zero.
- **Strength / volume change**: `percentageChange` between baseline and
  recent windows (max for e1RM, sum for volume; noData/zeroBaseline typed).
- **Frequency**: sessions ÷ 4 weeks over the recent window; genuine zero
  when history exists but none is recent.
- **Per-exercise data quality**: 0 sessions → insufficient; 1–4 → limited
  (below the 5-session trend minimum); 5–9 → moderate; ≥10 → strong.
- **Evidence** (typed `EvidenceItem`s on the result): session count vs the
  trend minimum (with sufficiency flag), e1RM change (observed vs baseline
  values + period), volume change, frequency. The UI's "Why am I seeing
  this?" panel renders these plus the analysis window, weekly slope, the
  plateau band, the suppression note, skipped-record count and data
  quality.
- **Possible explanations**: `PlateauDiagnosisService` output attached only
  for an unsuppressed plateau/regression, presented under the label
  "Possible explanation" (the "Likely Cause" wording was retired in
  Phase 7). Explanations are grounded in logged data and never presented as
  proven causes or medical advice.

## Current: weekly review (Phase 8)

Source: `lib/services/weekly_review_service.dart` (pure; injected reference
date; no Firebase/Flutter/network) returning typed
`lib/models/weekly_review.dart` structures. Copy is produced separately by
the narrator (below); every conclusion keeps its `EvidenceItem`s.

**Shared definitions — never recomputed differently:** the review calls
`DashboardService.build` for weekly activity, weekly volume (+safe change),
top exercises and data quality, `DashboardService.personalRecordsIn` (made
public in Phase 8) for records, and
`ExerciseAnalyticsService`/`PlateauDetector` for trends. A metric shown on
the Dashboard and in the Weekly Review is by construction the same number.

- **Review period**: the Monday–Sunday week containing the reference date
  (`DatePeriod.weekContaining`); comparisons use the immediately preceding
  week. The UI passes `DateTime.now()`.
- **Availability**: `noData` when no workout history exists (encouraging
  empty state); otherwise `available` — individual metrics inside an
  available review may still be `MetricUnavailable` with typed reasons.
- **Data quality**: the dashboard's total-history mapping, reused verbatim
  (0 → insufficient; 1–4 → limited; 5–14 → moderate; ≥ 15 → strong).
- **Workout-count findings**: increased = previous week > 0 and this week >
  previous (a first-ever training week is NOT "up" against an empty
  baseline); decreased = previous > 0 and 0 < this < previous; stable =
  equal and > 0; this week == 0 with any history → `noTrainingThisWeek`
  only (never also "decreased").
- **Weekly-volume findings**: require an available week-over-week change
  (noData/zeroBaseline produce NO volume finding — nothing is fabricated).
  Stable band ±10%: above +10% → improvement; below −10% → attention;
  inside → stable.
- **Personal records**: shared PR definition over the review week
  (strictly-beats-all-earlier, first-ever session never a record, warm-ups
  and malformed sets can never create one); capped at 3 findings.
- **Exercise-trend findings**: bounded to the dashboard's analysed (≤ 3 top)
  exercises; full-history e1RM trend. progressing → improvement;
  plateau/regressing with a progressing volume trend → *stable*
  "volume rising" finding (shared suppression rule); unsuppressed
  regression → attention (severity warning); unsuppressed plateau →
  attention (caution); insufficientData → no finding. Evidence: session
  count vs the 5-session minimum; the slope (kg/day) rides on the finding.
- **Repeated exercises**: names trained in BOTH weeks (trimmed,
  case-insensitive; first display casing kept), name-ascending, capped at
  3 — one stable consistency finding.
- **Session feel**: session-wide only (ratings attach to workouts) — never
  presented as exercise-specific. A weekly average needs ≥ 2 rated sessions
  (else typed noData/tooFewSessions — sparse data never becomes a trend).
  With both weekly averages available: difference ≥ +0.5 stars → improved;
  ≤ −0.5 → declined (caution); otherwise stable. A this-week average
  ≤ 2.5 stars → low-feel attention finding, reported only when the decline
  finding didn't already fire.
- **Insufficient history**: 0 < total workouts < 5 (the dashboard's
  getting-started boundary) → info-severity attention finding; trend-level
  conclusions are unreliable below it.
- **Skipped records**: count > 0 → caution attention finding AND the
  standing UI notice (partial data never silent).
- **Suggested actions** (closed typed set, fixed priority order, each
  carrying the triggering finding's evidence — no finding, no action):
  1. possible regression → *review recovery and technique* (per exercise;
     explicitly "not medical advice");
  2. possible plateau → *consider reviewing volume* (per exercise; by
     construction volume is not rising, or the plateau would be
     suppressed);
  3. progress detected (progressing trend or new PR) with NO plateau or
     regression findings → *maintain current structure*;
  4. total workouts < 5 → *log more sessions before judging trends*;
  5. trained this week but feel average unavailable → *keep logging feel*.
  No medical claims, no aggressive prescriptions, no claimed proven causes.
- **Ordering**: deterministic — fixed rule order within each section;
  per-exercise findings follow top-exercise rank; regressions precede
  plateaus. Identical input yields identical output.

### Narration (Phase 8)

`ReviewNarrator` (`lib/services/review_narrator.dart`) converts the typed
review into copy: headline, summary, and lists **parallel** to the typed
finding/action lists. Contract: narrators only rephrase supplied typed data
— never invent metrics, causes or recommendations — and must keep cautious
possible/may wording. `TemplateReviewNarrator` (deterministic, fixed
template per kind, display-unit passed in by the caller) is the only
shipped implementation; an optional future LLM narrator would sit behind
the same interface with no change to the review model (no API client,
secrets or network code exists in the repository).

## Planned metrics (definitions to be finalised before implementation)

For each, the implementing phase must fill in: exact meaning, time period,
calculation, missing/insufficient-data behaviour, and tests. Committed
decisions so far:

- **Week boundary**: Monday 00:00 to Sunday 23:59 local time, computed from an
  injected reference date (Phase 6).
- **Workouts this week**: count of workout documents dated within the current
  week.
- **Weekly training volume**: Σ(weight × reps) over working sets of workouts
  in the week, displayed in the user's unit.
- **Week-over-week change**: safe percentage change vs the previous complete
  week; undefined (not 0, not ∞) when the base is zero/absent — rendered as
  "no comparison available".
- **Training frequency (per exercise)**: sessions per week over a defined
  window (window to be fixed in Phase 7).
- **Recent best / recent PRs**: best capped e1RM per exercise within a defined
  recency window, from workout data (not the stored PR map).
- **Percentage change (e1RM / volume)**: implemented in Phase 2 (see
  ExerciseAnalyticsService above); dashboard/review consumers choose the
  periods.
- **Confidence / data quality**: the categorical `DataQuality` type exists
  (Phase 2); mappings are documented per consumer — dashboard (Phase 6),
  per-exercise detail (Phase 7), weekly review (Phase 8, reuses the
  dashboard mapping).
- ~~**Weekly review categories**~~ — delivered in Phase 8 (see the weekly
  review section above); every conclusion carries typed evidence.

## Demo fixtures and analytics thresholds (Phase 9)

The demo scenarios (`lib/demo/demo_fixtures.dart`) are deliberately
engineered against the definitions in this document — the ±0.1%/day trend
thresholds and 5-session minimum, the volume-progressing suppression rule,
the diagnosis rules (plateau scenario triggers rep monotony), the
weekly-review feel thresholds (±0.5 stars, ≥2 rated sessions) and the
strictly-beats-all-earlier PR rule. `test/demo_fixtures_test.dart` runs the
real services over the generated data, so a change to any threshold that
breaks a scenario's advertised behaviour fails tests rather than silently
degrading demos. Demo data must stay realistic (no impossible loads or
perfectly linear histories) so it never becomes a back-door relaxation of
these definitions.

## Integrity rules

- Never divide by zero; absent baselines produce explicit "insufficient data"
  results, not zeros.
- Duplicate same-day sessions collapse to best-per-day for trend analyses;
  volume aggregates sum across the day.
- No metric may be displayed without a documented definition here.
- No medical claims; diagnoses phrased as possibilities with evidence.
