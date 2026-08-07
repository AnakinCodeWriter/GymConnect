# GymConnect — Backlog

Approved 2026-07-02. Phases run strictly in order; each ends with
format/analyze/tests, a report, and a stop for review. **Status key:**
`done` / `in progress` / `pending`.

## Phase plan

### Phase 0 — Baseline and documentation — **done (2026-07-02)**
Create docs/ (PRODUCT_SPEC, ARCHITECTURE, ANALYTICS_DEFINITIONS, TEST_PLAN,
DECISIONS, BACKLOG, FIRESTORE_SECURITY); record analyzer/test baseline
(analyze: 8 infos in tool/ only; tests: 43/43 pass). No code changes.

### Phase 1 — Characterisation tests and critical reliability fixes — **done (2026-07-02)**
- Characterisation tests added: RecommendationService (10 tests incl.
  suggestNextWorkout), Epley edge cases; existing 43 tests preserved.
  Leaderboard e1RM regression tests documented as pending until Phase 3
  extracts the computation (see docs/TEST_PLAN.md).
- Onboarding-on-profile-error fixed via `ProfileGate`
  (loading/exists/missing/failed + retry/sign-out; 6 widget tests).
- Silent catches replaced with visible error/retry states on home,
  log-workout and profile screens.
- `PlateauDiagnosisService.analyse` now requires an injected `referenceDate`;
  28-day boundary + determinism tests added.
- Personal-record updates switched from dot-notation `update()` to
  `set(merge: true)`; payload tests cover `.`, `[]`, `*`, `/`, whitespace.
- Result-type decision: none needed this phase (see docs/DECISIONS.md).
- Post-phase: analyze = 8 baseline infos (tool/ only); tests 66/66 pass.

### Phase 2 — Shared domain and analytics architecture — **done (2026-07-02)**
- `lib/models/analytics.dart`: DatePeriod, sealed MetricResult +
  InsufficiencyReason, PercentageChange/ChangeDirection, EvidenceItem,
  MetricType, categorical DataQuality, Severity, ExerciseSession/Series.
  Insight/Recommendation containers deferred to first consumers (Phases 6–8).
- `lib/services/exercise_analytics_service.dart`: buildSeries, e1RM/volume
  trends, trainingFrequencyPerWeek, bestE1RmIn, percentageChange — pure,
  deterministic, explicit DatePeriods.
- `progress_screen.dart` now delegates all series/trend/diagnosis-gating
  calculations to the service; ~100 lines of private calculation code and
  the unused `_filtered` record list removed.
- Three defects corrected with regression tests (substring match, duplicate
  entry `break`, malformed sets) — see docs/DECISIONS.md.
- Post-phase: analyze = 8 baseline infos; tests **112/112** pass (+46).

### Phase 3 — Formula and unit consistency — **done (2026-07-03)**
- Canonical capped Epley is the only e1RM implementation; shared
  `isEligibleForStrengthAnalytics` rule applied across leaderboard,
  recommendations, PR paths, feel analysis, exercise analytics and volume
  metrics. `lib/utils/units.dart` owns the 2.20462 factor, conversions and
  the trim-zero / compact formatting helpers; all 15 inline conversion
  sites migrated.
- D3 regression suite landed (`test/leaderboard_calculator_test.dart`) via
  the extracted pure `bestEligibleE1RmPerExercise` calculator.
- Stored PR/leaderboard values NOT rewritten (see DECISIONS: historical
  stored-record limitation; migration stays in Phase 12).
- Post-phase: analyze = 8 baseline infos; tests **150/150** pass (+38).

### Phase 4 — Data-access cleanup — **done (2026-07-03)**
- Sealed `DataResult` + `DataFailureKind` + `failureKindFor` mapping;
  `FirestoreAdapter` DI boundary with production impl and in-memory test
  fake; all four Firestore services injected and unit-tested.
- WorkoutService decoupled (Phase 1 deferral closed): typed results,
  internal uid resolution, deterministic date-desc/id-asc ordering,
  skip-and-report malformed documents, save/delete orchestration moved out
  of screens; dead `getRecentExerciseNames` removed.
- Fixes: setAnonymous set-merge; leaderboard failure ≠ "no gym ID"; toggle
  revert + SnackBar; templates failure surfaced; tolerant int/double
  numeric parsing in WorkoutSet.
- Post-phase: analyze = 8 baseline infos; tests **196/196** pass (+46).

### Phase 5 — Navigation shell and shared design system — **done (2026-07-04)**
- `AppShell` (IndexedStack + Material 3 NavigationBar): Dashboard, Progress,
  More visible; Weekly Review deferred to Phase 8 per the D1 refinement (no
  placeholder). Documented back semantics; injectable destinations.
- `MoreScreen` with grouped secondary navigation (Templates, Starter Plans,
  Leaderboard, Profile, Dark Mode, Sign out via auth stream); home screen
  de-duplicated (keeps Log Workout + goal/insight cards).
- Shared foundations: app_tokens (Insets/Corners), GoalCard, InsightCard,
  ErrorRetryView, StatusBanner, InlineNotice, EmptyView, LoadingView,
  SectionHeader — every one with current consumers; Phase 1/4 error states
  migrated with wording preserved.
- Post-phase: analyze = 8 baseline infos; tests **229/229** pass (+33
  widget tests: shell 10, More 7, shared widgets 16).

### Phase 6 — Training dashboard — **done (2026-07-04)**
- Pure `DashboardService` + typed `dashboard.dart` models: weekly activity
  and volume with safe week-over-week change, top exercises (28d), recent
  PRs (14d, from history), bounded trend warnings with evidence,
  documented training-status and data-quality rules; Monday–Sunday weeks,
  injected reference date.
- Dashboard UI rebuilt on shared widgets with loading / empty / populated /
  initial-failure / refresh-failure(last-known data) / skipped-records
  states; injectable loader for Firebase-free widget tests.
- `workoutDataVersion` notifier closes backlog #19/#20 (stale tabs).
- Post-phase: analyze = 8 baseline infos; tests **265/265** pass (+36:
  27 service, 9 widget).

### Phase 7 — Exercise analytics — **done (2026-07-04)**
- Typed `ExerciseDetail` via pure `analyseExercise` (28d windows, recent
  best + day, strength/volume changes, frequency, per-exercise data
  quality, typed evidence, suppression-aware possible explanation).
- Progress screen reworked: status card, metric grid, chart, expandable
  "Why am I seeing this?" `EvidencePanel`, "Possible explanation" card
  (softened wording), history preserved; injectable loader for
  Firebase-free widget tests; partial-data profile policy aligned with the
  dashboard.
- Dashboard→Progress preselection shipped (`progressExerciseRequest` +
  tappable Most-trained rows).
- Wellness/feel context deferred to Phase 8's weekly review (feel data is
  cross-exercise, not per-exercise).
- Post-phase: analyze = 8 baseline infos; tests **309/309** pass (+44:
  22 detail service, 18 progress widget, +3 fixed-up dashboard incl.
  preselection).

### Phase 8 — Weekly coaching review — **done (2026-07-04)**
- Typed `WeeklyReview` (pure `WeeklyReviewService`, injected reference
  date): improvements / stable areas / attention areas / suggested actions,
  every finding and action with typed evidence; availability, shared
  dashboard data-quality mapping, typed insufficiency reasons,
  skipped-record warnings. Reuses DashboardService (weekly
  activity/volume/top exercises/PRs — `personalRecordsIn` made public) and
  the shared trend/suppression rules; no metric recomputed differently.
- Session-feel summary (weekly averages need ≥2 rated sessions; ±0.5-star
  change threshold; low-feel ≤2.5): session-wide only, sparse data stated
  as insufficient, never an invented trend.
- `ReviewNarrator` interface + deterministic `TemplateReviewNarrator`
  (only shipped implementation; parallel narrated lists; cautious wording;
  future LLM narrator would implement the same interface — no API
  client/secrets/network code added).
- Weekly Review shipped as the fourth shell destination (bar label
  "Review"); loading/empty/populated/initial-failure/refresh-failure
  (last-known kept)/skipped-records states; pull-to-refresh +
  `workoutDataVersion` reloads; evidence panel reused.
- RecommendationService: kept as a legacy helper, NOT integrated into the
  review (keyword heuristics don't meet the evidence bar — see
  docs/DECISIONS.md); `suggestNextWorkout` stays unused (#14 final).
- Post-phase: analyze = 8 baseline infos; tests **369/369** pass (+60:
  35 review service, 10 narrator, 12 review widget, +3 shell).

### Phase 9 — Demo tooling — **done (2026-07-04)**
- `lib/demo/` pure deterministic generator (no randomness, CLI-safe):
  five scenarios — progressing (+week PRs, improving feel, substring
  exercise pair), plateau (rep-monotony explanation; other lifts still
  progress), regression (declining feel), volume-progressing
  (suppression; sparse feel), insufficient data — each verified by tests
  running the real analytics services over the generated data.
- Tagging: optional backward-compatible `isDemo`/`demoScenario`/
  `demoBatchId`/`demoGeneratedAt` fields; idempotent seeding
  (deterministic ids + replace-own-batch); cleanup selects strictly
  `isDemo: true` documents only (batch-scoped or explicit all; dry-run).
- CLI rewritten per D4: env-var config (no hard-coded key — the old one
  was never committed), shows project/user/counts, typed-"yes"
  confirmation or explicit `--yes`; commands list-scenarios / seed /
  cleanup / inspect. `stdout.writeln` output cleared the 8 `avoid_print`
  infos → analyzer now at 0 issues.
- Debug-only in-app controls per D2 (implemented): More → Developer →
  Demo Data, `kDebugMode`-gated; same seeder; confirmations;
  `workoutDataVersion` bump refreshes Dashboard/Progress/Review.
- Post-phase: analyze = **0 issues** (improved baseline); tests
  **425/425** pass (+56: 29 fixtures, 10 seeder, 11 CLI, 4 demo UI,
  +2 More).

### Phase 10 — Security and emulator testing — **done (2026-07-05)**
- `firestore.rules` authored in-repo: owner-only users/workouts/templates,
  gym-membership-gated leaderboard (own entry, own gym only),
  deny-by-default elsewhere; conservative-but-flexible validation (typed
  optional fields, closed leaderboard field set, demo fields typed with
  zero access semantics); client profile/entry deletes denied.
- Leaderboard anonymity fixed at the WRITE path (rules can't redact):
  anonymous entries now store `'Anonymous'` — `updateUserBestLifts`
  substitutes, `setAnonymous(displayName:)` sanitises/restores on toggle,
  `updateDisplayName` no-ops while anonymous; rules enforce the invariant
  as a backstop. Historical anonymous entries self-correct on the owner's
  next write; bulk cleanup deferred to Phase 12 (documented).
- `test_rules/` emulator harness (Node test runner +
  @firebase/rules-unit-testing, offline demo project): **33/33 passing**
  locally. NO deployment performed (D5: manual only; checklist in
  docs/FIRESTORE_SECURITY.md).
- Post-phase: analyze = 0 issues; Flutter tests **429/429** pass (+4
  anonymity unit tests); rules tests **33/33** pass.

### Phase 11 — Broader refactoring and test coverage — **done (2026-07-05)**
- Log workout screen decomposed (1029 → ~540 lines): draft state →
  `models/workout_draft.dart` (validation, unit conversion, warm-up rule,
  volume — all unit-tested); per-exercise UI → `widgets/workout_form/`
  (ExerciseCard/SetRowEditor/StepperField/RecentExercisesRow/
  FeelRatingSheet, callback-driven); overload-hint rule →
  `utils/overload_hint.dart` (pure, tested). Behaviour and document shape
  unchanged.
- Injection without a DI package: `LogWorkoutScreen({workoutService,
  templateService, uidProvider})`, `ProgressScreen({workoutService,
  profileLoader})`; production defaults constructed lazily.
- Progress screen slimmed (986 → ~700): chart → `widgets/e1rm_chart.dart`,
  history card → `widgets/workout_history_card.dart`; delete-set flow now
  injectable and tested (success/cancel/failure). Corrected defect: a
  post-delete profile-fetch failure no longer mis-reports the successful
  deletion or skip the tab-refresh notification.
- #17 partial: log/progress screens handle a missing user as a typed
  degraded state; `suggestNextWorkout` deleted (#14 closed); shared
  `utils/dates.dart` replaced 3 private month tables.
- Accessibility on touched widgets (stepper/warm-up/star semantics +
  tooltips); log workout narrow/2x-scale/dark smoke tests.
- Post-phase: analyze = 0 issues; tests **465/465** pass (+40 new: 13
  draft, 6 hint/dates, 17 log workout widget, 4 progress delete/warm-up;
  -4 deleted with `suggestNextWorkout`). Rules suite not rerun (nothing
  security-relevant changed).
- Deliberately out of scope (unchanged): integration/e2e tests, realtime
  listeners, tablet layouts; home/leaderboard/profile/templates screens
  kept as-is (no clear testability win this phase).

### Phase 12 — CI, migration tooling and release polish — **done (2026-07-05)**
- CI (`.github/workflows/ci.yml`): two jobs - format check + `flutter
  analyze` + full Flutter suite, and the Firestore rules emulator suite
  (Node 20, Temurin JDK 21, firebase-tools 15, offline `demo-gymconnect`
  project). No repository secrets, no deploy step, neither CLI invoked.
  A committed keyless stub (`tool/ci/firebase_options_stub.dart`) stands in
  for the gitignored `lib/firebase_options.dart` so a fresh checkout
  compiles; verified locally by swapping it in and restoring the real file
  byte-identically.
- Repo-wide `dart format` (7 files predating Phase 11) so the CI format
  gate can pass; whitespace only. The whole repo must now stay clean, not
  just changed files.
- Migration tool (executes D3, closes #13; also clears the Phase 10
  historical anonymity leftover): pure planner + CLI rules in
  `lib/migration/`, REST shell in `tool/migrate_data.dart`. Read-only
  unless `--apply`, typed confirmation, **never deletes**, orphaned records
  reported but left untouched, whole-map writes (no field-path hazard),
  idempotent within a 1e-6 kg tolerance, per-account only. A leaking
  anonymous entry always gets its display name written in the same PATCH as
  lift corrections, because the Phase 10 rules would otherwise reject the
  write.
- Enabling refactor: `utils/strength_math.dart` (zero imports) holds the
  canonical e1RM + eligibility rule; `fitness_formulas.dart` re-exports it.
  This keeps ONE formula shared by the app and a plain-Dart CLI, which D3
  requires; a test asserts the tool and `LeaderboardService` agree exactly.
- Docs: README rewritten (portfolio framing, architecture diagram, clean-
  clone setup, tests, CI, demo, migration, known limitations, docs index,
  AI-assistance disclosure), plus `docs/MIGRATION.md` and
  `docs/RELEASE_CHECKLIST.md`.
- Post-phase: analyze = 0 issues; tests **504/504** pass (+39: 24 planner,
  15 CLI); rules suite 33/33 unchanged; format clean repo-wide.
- Deliberately NOT done: no migration run against a live project, no rules
  deployed, no release build signed/published, no screenshots fabricated
  (capture step listed in the release checklist).

## Known issues register (baseline 2026-07-02)

| # | Issue | Planned fix |
|---|---|---|
| 1 | Uncapped inline Epley in leaderboard + recommendation services; leaderboard includes warm-ups | **fixed in Phase 3** (canonical formula + eligibility rule) |
| 2 | Analytics orchestration embedded in `progress_screen.dart` | **fixed in Phase 2** (ExerciseAnalyticsService) |
| 3 | Prose-string insights; no typed evidence | Phases 2, 7, 8 |
| 4 | kg↔lbs factor + formatting duplicated ~20×; goal card duplicated | conversions **fixed in Phase 3**; goal card **de-duplicated in Phase 5** (shared GoalCard) |
| 5 | Silent `catch (_)` on loads (home/log/profile) | **fixed in Phase 1**; leaderboard + templates screens **fixed in Phase 4** |
| 6 | Profile-check error routes to onboarding; `set()` can overwrite profile | **fixed in Phase 1** (ProfileGate) |
| 7 | Exercise names in Firestore dot-notation field paths | **fixed in Phase 1** (set+merge) |
| 8 | No Firestore rules in repo | **fixed in Phase 10** (`firestore.rules` + 33 emulator tests; deployment stays manual per D5) |
| 9 | `DateTime.now()` inside diagnosis Rule 1 | **fixed in Phase 1** (injected referenceDate) |
| 10 | Seed tool: hard-coded key, not idempotent, no cleanup, untracked | **fixed in Phase 9** (env config, idempotent batches, tagged cleanup; ready to commit) |
| 11 | No widget/integration/rules tests | widget suites Phases 5–11 (all destinations + log workout); rules tests Phase 10; e2e integration tests remain out of scope |
| 12 | 8 `avoid_print` infos in `tool/seed_data.dart` | **fixed in Phase 9** (stdout/stderr writeln; analyzer baseline now 0 issues) |
| 13 | Stored leaderboard/PR values computed with old formula | **tooling shipped in Phase 12** (`tool/migrate_data.dart`, docs/MIGRATION.md): opt-in, read-only unless `--apply`, idempotent, never deletes. Running it on the owner's live account is a manual step, not yet performed |
| 14 | `RecommendationService.suggestNextWorkout` implemented but unused | **deleted in Phase 11** (still unused, superseded by Weekly Review typed actions); `generate` kept as documented legacy for the dashboard card |
| 15 | Unbounded collection reads (workouts, leaderboard) — fine at current scale, no pagination | documented Phase 4; revisit if usage grows |
| 16 | Leaderboard `updateUserBestLifts` read-then-merge race on own doc (last-write-wins) | accepted Phase 4; transaction only if a real consistency need appears |
| 17 | `currentUser!.uid` still used in screens for profile fetches | **partial in Phase 11**: log/progress screens injectable + null-safe; remaining uses (leaderboard/profile/templates/onboarding, ProfileChecker) sit under the authenticated shell inside guarded loaders — documented, revisit opportunistically |
| 18 | Skipped-document notices only on the progress screen; other screens use valid records without a notice | `InlineNotice` exists (Phase 5); wire remaining screens opportunistically in Phases 6–7 |
| 19 | Progress tab stale after logging a workout | **fixed in Phase 6** (workoutDataVersion listener) |
| 20 | Dashboard stale after profile edits from More | **fixed in Phase 6** (profile save bumps workoutDataVersion) |
| 21 | Remaining stale case: data changed on ANOTHER device only appears after pull-to-refresh or app restart (no realtime listeners by design) | documented; acceptable for a single-device dissertation app |
