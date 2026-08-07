# GymConnect — Architecture

Sections marked **Current** describe the repository as of 2026-07-02 (Phase 0).
Sections marked **Planned** describe approved changes not yet implemented.

## Current: stack

- Flutter (Dart SDK ^3.11.3), toolchain Flutter 3.41.5 stable.
- Firebase Authentication (email/password) via `firebase_auth`.
- Cloud Firestore via `cloud_firestore`.
- Charts: `fl_chart` 0.66 (pinned; do not upgrade without a concrete need —
  see docs/DECISIONS.md D6).
- Local prefs: `shared_preferences` (theme, weight unit).
- Lints: `flutter_lints` 6 (default `analysis_options.yaml`).
- No state-management package: plain `StatefulWidget` state plus four
  global `ValueNotifier`s in `lib/main.dart` (`themeModeNotifier`,
  `weightUnitNotifier`, `workoutDataVersion` — bumped on data writes so
  IndexedStack-alive tabs reload instead of going stale (Phase 6) — and
  `progressExerciseRequest` — dashboard→Progress exercise preselection,
  Phase 7).
- Navigation: manual `Navigator.push` from the home screen.

## Current: layering

```
lib/
├── main.dart                    # Firebase init, theme/unit notifiers, AuthWrapper → ProfileChecker
├── firebase_options.dart        # generated, gitignored
├── models/                      # plain immutable-ish data classes, manual toMap/fromMap
│   ├── user_model.dart          # profile, goal, personalRecords, weightUnit
│   ├── workout_model.dart       # WorkoutModel / ExerciseEntry / WorkoutSet(isWarmup)
│   ├── template_model.dart
│   ├── analytics.dart           # typed analytics domain (Phase 2): DatePeriod, MetricResult, EvidenceItem, …
│   ├── workout_draft.dart       # log-form draft state: DraftExercise/DraftSet, validation, draft→model (Phase 11)
│   ├── dashboard.dart           # typed dashboard payload (Phase 6): WeeklyActivity/Volume, TrendWarning, TrainingStatus, …
│   ├── exercise_detail.dart     # typed per-exercise detail (Phase 7): ExerciseDetail, RecentBest
│   └── weekly_review.dart       # typed weekly review (Phase 8): WeeklyReview, ReviewFinding, SuggestedAction, ReviewNarration
├── services/
│   ├── auth_service.dart        # thin FirebaseAuth wrapper (intentionally untouched in Phase 4)
│   ├── data_result.dart         # sealed DataResult/DataFailureKind + error mapping (Phase 4)
│   ├── firestore_adapter.dart   # narrow DI boundary over Firestore + production impl (Phase 4)
│   ├── firestore_service.dart   # user profile CRUD, goal, personalRecords (fails on malformed - auth-critical)
│   ├── workout_service.dart     # typed loads, save/delete orchestration incl. PR + leaderboard, pure helpers
│   ├── template_service.dart    # templates CRUD (typed loads, skip-and-report)
│   ├── leaderboard_service.dart # gyms/{gymId}/leaderboard docs (typed loads, set-merge writes)
│   ├── dashboard_service.dart   # pure: weekly activity/volume, top exercises, recent PRs, warnings, status (Phase 6)
│   ├── weekly_review_service.dart # pure: evidence-backed weekly review over shared dashboard/trend metrics (Phase 8)
│   ├── review_narrator.dart     # ReviewNarrator boundary + deterministic TemplateReviewNarrator (Phase 8)
│   ├── exercise_analytics_service.dart # pure: per-exercise session series, trends, frequency, % change (Phase 2)
│   ├── plateau_detector.dart    # pure: WLS regression trend classification
│   ├── plateau_diagnosis_service.dart # pure: 4-rule root-cause analysis
│   ├── feel_analysis_service.dart     # pure: 3-priority feel insights
│   └── recommendation_service.dart    # legacy: dashboard card rules only; suggestNextWorkout deleted (Phase 11)
├── migration/                   # opt-in stored-value migration (Phase 12, executes D3)
│   ├── migration_plan.dart      # pure: recomputation + correction/orphan planning, idempotent
│   └── migration_cli.dart       # pure: argument parsing (read-only unless --apply) + env config
├── demo/                        # demo-data tooling (Phase 9)
│   ├── demo_fixtures.dart       # pure deterministic scenario generator (no Flutter/Firebase - CLI-safe)
│   ├── demo_plan.dart           # pure tag fields + cleanup selection rules (isDemo:true only)
│   ├── demo_cli.dart            # pure CLI argument parsing + env-config rules
│   └── demo_seeder.dart         # seed/cleanup over FirestoreAdapter (app/debug-UI path)
├── utils/
│   ├── fitness_formulas.dart    # re-exports strength_math's e1RM + adapts eligibility to WorkoutSet (Phase 3/12)
│   ├── units.dart               # kg↔lbs factor, display conversion, weight formatting (Phase 3)
│   ├── strength_math.dart       # canonical e1RM + eligibility over raw values, ZERO imports (Phase 12)
│   ├── dates.dart               # shared "4 Jul" / "4 Jul 2026" labels (Phase 11; replaced 3 private copies)
│   └── overload_hint.dart       # pure progressive-overload hint rule (Phase 11; extracted from log screen)
├── theme/
│   └── app_tokens.dart          # shared spacing/radius tokens (Phase 5)
├── widgets/
│   ├── auth_text_field.dart
│   ├── profile_gate.dart        # 4-state profile lookup (loading/exists/missing/failed), DI for tests
│   ├── goal_card.dart           # shared training-goal card (home + progress)
│   ├── insight_card.dart        # coloured label/title/message card (dashboard insights)
│   ├── state_views.dart         # LoadingView / EmptyView / ErrorRetryView / SectionHeader
│   ├── status_banner.dart       # StatusBanner (boxed) + InlineNotice (strip)
│   ├── stat_card.dart           # compact metric tile (Phase 6)
│   ├── evidence_panel.dart      # expandable "Why am I seeing this?" (Phase 7)
│   ├── e1rm_chart.dart          # best-e1RM-per-session line chart (Phase 11; from progress screen)
│   ├── workout_history_card.dart # expandable session card with per-set delete (Phase 11; from progress screen)
│   └── workout_form/            # log-form pieces (Phase 11; from log workout screen)
│       ├── exercise_card.dart   #   autocomplete name + hint + set rows (callback-driven, stateless)
│       ├── set_row_editor.dart  #   warm-up toggle + weight/reps steppers + remove
│       ├── stepper_field.dart   #   -/+ numeric field (labelled semantics/tooltips)
│       ├── recent_exercises_row.dart # history chips row
│       └── feel_rating_sheet.dart    # 1-5 star sheet + showFeelRatingSheet()
└── screens/
    ├── app_shell.dart           # authenticated shell: NavigationBar + IndexedStack, 4 destinations (Phases 5/8)
    ├── more_screen.dart         # grouped secondary navigation + settings + sign out (Phase 5)
    ├── weekly_review_screen.dart # Weekly Review destination (Phase 8)
    ├── demo_tools_screen.dart   # debug-only demo seeding/cleanup UI (Phase 9)
    ├── login_screen.dart, register_screen.dart, onboarding_screen.dart
    ├── home_screen.dart         # Dashboard destination: Log Workout, goal + insight cards
    ├── log_workout_screen.dart  # logging orchestration (decomposed Phase 11; injectable services)
    ├── progress_screen.dart     # per-exercise analytics + history (chart/history extracted Phase 11)
    ├── profile_screen.dart, leaderboard_screen.dart,
    ├── workout_templates_screen.dart, starter_plan_screen.dart
tool/
├── seed_data.dart               # thin dart:io/REST CLI over lib/demo (Phase 9; env config, no keys)
├── migrate_data.dart            # thin dart:io/REST CLI over lib/migration (Phase 12; never deletes)
└── ci/firebase_options_stub.dart # keyless placeholder config so CI can compile (Phase 12)
.github/workflows/ci.yml         # format + analyze + tests + rules emulator suite (Phase 12; no secrets, no deploy)
test/                            # 504 unit + widget tests (see docs/TEST_PLAN.md)
firestore.rules                  # security rules, emulator-tested, NOT deployed (Phase 10)
test_rules/                      # rules test harness: Node + @firebase/rules-unit-testing (33 tests)
```

The pure analytics services (`plateau_detector`, `plateau_diagnosis_service`,
`feel_analysis_service`, `recommendation_service`) take domain objects and
return results without Flutter or Firestore imports. Since Phase 1 the
diagnosis service is fully deterministic: time-window rules take a required
`referenceDate` supplied by the caller (UI passes `DateTime.now()`).

## Current: data model (Firestore)

- `users/{uid}` — profile document (`UserModel.toMap`): displayName, gymId,
  createdAt, isAnonymous, experienceLevel, fitnessGoal, goalExercise,
  goalTargetWeight (kg), personalRecords (map: exercise name → best e1RM, kg),
  weightUnit.
- `users/{uid}/workouts/{autoId}` — `date` (Timestamp), optional `name`,
  optional `feelRating` (1–5), `exercises`: [{name, sets: [{weight (kg),
  reps, optional isWarmup}]}].
- `users/{uid}/templates/{autoId}` — name, exercises with optional weights.
- `gyms/{gymId}/leaderboard/{uid}` — displayName, isAnonymous, bestLifts
  (map: exercise name → best e1RM, kg). Since Phase 10 anonymous entries
  store the literal displayName `'Anonymous'` — the readable document
  never contains the real name while anonymous (rules cannot redact
  fields; see docs/FIRESTORE_SECURITY.md).

Conventions:
- **All weights stored in kg**; converted to lbs only for display via
  `utils/units.dart`.
- **Stored aggregate values** (`personalRecords`, `bestLifts`) are written
  as complete map fields, never dot-notation field paths, and are only
  overwritten by the app when a new value beats the stored one. Values
  predating the Phase 3 formula fix are therefore corrected by the opt-in
  Phase 12 migration tool, not by normal use (docs/MIGRATION.md).
- Optional stored fields are written only when set and defaulted on read —
  new fields must follow this pattern (backward compatibility requirement).
  Numeric fields parse tolerantly via `num` (int/double both accepted).
- **Data access (Phase 4):** every Firestore call goes through the
  `FirestoreAdapter` boundary; services own paths/serialisation and return
  `DataResult`s for reads. Empty collections are successes; malformed
  documents in collection loads are skipped and reported (profile documents
  instead fail — auth-critical). Screens never parse Firebase errors.
- **Ordering:** workouts are served `date` descending (server) with a
  client-side stable re-sort tie-broken by document id ascending; documents
  missing `date` are omitted by the ordered query. Templates/leaderboard
  reads are unordered. All reads are unbounded (documented small-scale
  assumption; backlog #15).
- Remaining direct Firestore/Auth touchpoints in UI (intentional):
  `Timestamp.now()` model construction, and `currentUser` access under the
  authenticated shell. Since Phase 11 the log workout and progress screens
  take injectable services/uid providers and handle a missing user as a
  typed failure; `currentUser!.uid` remains only in
  leaderboard/profile/templates/onboarding screens (inside catch-guarded
  loaders under the authenticated shell) and in main.dart's ProfileChecker,
  which is only built when authStateChanges has a user (backlog #17).

## Current: known technical debt

Tracked in docs/BACKLOG.md; headline items (items fixed in Phase 1 removed):

1. ~~Epley formula duplicated inline in leaderboard/recommendation~~ — fixed
   in Phase 3 (canonical formula + shared eligibility rule; stored values
   written before the fix remain until beaten or migrated in Phase 12).
2. ~~Analytics orchestration inside `progress_screen.dart`~~ — fixed in
   Phase 2 (extracted to `ExerciseAnalyticsService`).
3. Insights/diagnoses/recommendations are pre-baked prose strings; no typed
   metric/evidence structures (Phases 2/7/8).
4. ~~kg↔lbs conversion + formatting duplicated ~20×~~ — fixed in Phase 3
   (`utils/units.dart`); the duplicated goal-card widget remains (Phase 5).
5. ~~No Firestore security rules in the repo~~ — fixed in Phase 10
   (`firestore.rules`, 33 emulator tests; deployment remains manual —
   docs/FIRESTORE_SECURITY.md).
6. ~~Widget tests exist only for ProfileGate~~ — Phases 5–11 added widget
   suites for the shell, dashboard, progress (incl. delete flow), weekly
   review, more, demo tools and the full log workout form; no end-to-end
   integration tests (out of scope until Phase 12+).
7. ~~`WorkoutService` untestable without Firebase~~ — fixed in Phase 4
   (FirestoreAdapter DI; fully unit-tested against the in-memory fake).
8. ~~Leaderboard screen misleading "No gym ID" on failure~~ — fixed in
   Phase 4 (typed failure state + retry; toggle reverts on failure).

## Planned: target architecture (approved, not yet implemented)

- **Navigation shell** — DONE in Phase 5; Weekly Review joined as the
  fourth destination in Phase 8 (one list entry, labelled "Review" on the
  bar — the screen itself is titled Weekly Review). `AuthWrapper` →
  `ProfileGate` → `AppShell` (PopScope + IndexedStack + Material 3
  NavigationBar). Visible destinations: Dashboard (home screen), Progress,
  Weekly Review, More (Templates, Starter Plans, Leaderboard, Profile,
  Dark Mode, Sign out). Back: pushed secondary screens pop first; any
  non-Dashboard root → Dashboard; Dashboard root → system. State preserved
  per destination via IndexedStack (screens initialise eagerly;
  data-bearing tabs reload via `workoutDataVersion`). Sign-out exits the
  shell purely via the auth stream. Shell destinations and More-screen
  routes are constructor-injectable for widget tests.
- **Typed analytics domain** — DONE in Phase 2 (`lib/models/analytics.dart` +
  `ExerciseAnalyticsService`); typed Insight/Recommendation containers arrive
  with their first consumers (Phases 6–8). Analytics services stay pure Dart:
  domain objects in, typed results out; no widgets, Firestore or
  BuildContext.
- **Single source of truth for formulas/units** (Phase 3):
  e1RM + rep cap, warm-up exclusion, kg/lbs conversion and formatting, safe
  percentage change, date/week boundaries (weeks are Monday–Sunday; reference
  date injected).
- **Services** — DONE: `ExerciseAnalyticsService` (Phases 2/7),
  `DashboardService` (Phase 6), `WeeklyReviewService` + `ReviewNarrator`
  interface with the deterministic `TemplateReviewNarrator` as the only
  shipped implementation (Phase 8). The narrator interface is the boundary
  where an optional future LLM rephrasing would plug in — no API client,
  secrets or network code exists in the repository, and the app is fully
  functional without any external AI service.
- **Demo fixtures** — DONE in Phase 9: `lib/demo/` pure deterministic
  generator + tagging/selection rules shared by the CLI (Firestore REST,
  env-var config, confirmation-gated) and the debug-only in-app controls
  (More → Developer, `kDebugMode`-gated so release builds compile it out).
  Seeded documents carry optional backward-compatible fields (`isDemo`,
  `demoScenario`, `demoBatchId`, `demoGeneratedAt`); cleanup can only
  select `isDemo: true` documents. Seeded data does NOT update the stored
  personalRecords map or the leaderboard (analytics read history, so all
  dashboards work; the profile PR map keeps only real lifts). CLI-seeded
  data appears in a running app after pull-to-refresh/restart (no realtime
  listeners by design).
- **Reusable UI components** — Phase 5 delivered `theme/app_tokens.dart`
  (Insets, Corners) and `widgets/`: GoalCard, InsightCard, ErrorRetryView,
  StatusBanner, InlineNotice, EmptyView, LoadingView, SectionHeader — each
  with current consumers. Metric cards / evidence panels / chart containers
  arrive with their consumers (Phases 6–7). Existing screens' literal
  paddings intentionally unmigrated.
- **State management**: none added yet. A lightweight solution may be proposed
  after the navigation and dashboard data flow are designed, only with a
  concrete problem statement, alternatives and migration impact (D6).

## Invariants (apply to all phases)

- Firebase project identifiers, application IDs and signing config are never
  changed. `firebase_options.dart` / `google-services.json` stay gitignored.
- Stored document formats remain backward compatible; new fields optional and
  safely defaulted.
- Deterministic calculations separate from presentation code.
- No secrets in the repository.
