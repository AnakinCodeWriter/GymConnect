# GymConnect — Test Plan

## Baseline (recorded 2026-07-02, Phase 0 — before any upgrade work)

Toolchain:

```
Flutter 3.41.5 • channel stable
Dart 3.11.3 • DevTools 2.54.2
```

`flutter analyze` (exit 0):

```
8 issues found. (ran in 6.5s)
   info - avoid_print - tool\seed_data.dart (8 occurrences, lines 17–40)
```

No warnings or errors in `lib/` or `test/`. The 8 infos are `print` calls in
the CLI seed tool and will be resolved when the tool is reworked (Phase 9).

`flutter test` (exit 0):

```
00:00 +43: All tests passed!
```

Test inventory (43 tests, all pure unit tests):

| File | Covers |
|---|---|
| `test/fitness_formulas_test.dart` | Epley e1RM, rep cap at 10, 1-rep identity |
| `test/plateau_detector_test.dart` | insufficient data (<5), progressing/plateau/regressing classification, relative thresholds, slope sign, same-day sessions, unsorted input, training gaps |
| `test/plateau_diagnosis_service_test.dart` | <4 sessions → null, name matching, all 4 rules fire/don't-fire, warm-up exclusion, warm-up-only sessions |
| `test/feel_analysis_service_test.dart` | <3 rated → null, low-streak, performance correlation buckets, best day of week |

Known coverage gaps at baseline:
- No tests for `RecommendationService`, `WorkoutService` helpers,
  `LeaderboardService` e1RM computation, or any model serialisation.
- No widget tests, no integration tests, no Firestore rules/emulator tests.
- `PlateauDiagnosisService` Rule 1 depends on real `DateTime.now()`; existing
  tests construct dates relative to now.

## After Phase 1 (2026-07-02)

`flutter analyze`: 8 issues — identical to baseline (all `avoid_print` in
`tool/seed_data.dart`). `flutter test`: **66/66 passed** (43 baseline + 23
new).

New tests:
- `test/recommendation_service_test.dart` (10) — characterisation of
  `generate` rules and the currently-unused `suggestNextWorkout`
  (backlog #14). Fixtures deliberately use reps ≤ 10 so the tests stay valid
  when the service's uncapped inline e1RM is corrected in Phase 3 — the
  known defect is not locked in as desirable behaviour.
- `test/profile_gate_test.dart` (6 widget tests) — loading, exists→home,
  missing→onboarding, failure→error state (never onboarding, no raw
  exception text), retry recovery, sign-out callback.
- `test/personal_records_update_test.dart` (3) — merge-payload shape; names
  with `.`, `[]`, `*`, `/`, and whitespace preserved exactly; defensive copy.
- `test/plateau_diagnosis_service_test.dart` (+2) — 28-day window boundary
  (a session exactly 28 days before the reference date is "prior";
  `isAfter` is strict) and determinism for a fixed `referenceDate`; all
  existing calls updated for the new required parameter.
- `test/fitness_formulas_test.dart` (+2) — zero weight → 0; reps < 1 clamp
  to 1.

## After Phase 2 (2026-07-02)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**112/112 passed** (66 after Phase 1 + 46 new).

New tests:
- `test/analytics_domain_test.dart` (13) — DatePeriod inclusivity,
  normalisation, single-day, invalid ranges, lastDays semantics;
  MetricResult available-zero vs unavailable-with-reason;
  PercentageChange.direction; EvidenceItem structure.
- `test/exercise_analytics_service_test.dart` (33) — the full Phase 2
  matrix: empty history, no match, exact-match regression (substring defect),
  warm-up-only and warm-up exclusion, best-of-multiple-sets, multi-exercise
  workouts, duplicate same-named entries (volume `break` defect), same-day
  and identical-timestamp merging, deterministic ordering, rep-cap, zero
  weight, malformed sets (ignored, non-distorting, whole-session case),
  trend characterisation (flat→plateau, rising→progressing, volume-progressing
  state, zero-volume exclusion, <5 insufficient), frequency (empty vs
  genuine zero, week boundaries, non-multiple-of-7 periods, injected
  reference dates), recent best in/out of period, percentage change
  (up/down/unchanged/zero-baseline/−100%/empty period/volume-sum).

Note: the in-screen private calculations could not be unit-tested directly
before replacement (private methods on a Firebase-coupled widget); the
characterisation strategy was to encode their observable behaviour —
including the seed-data scenarios — as service tests, with the three
corrected defects asserted at their *corrected* behaviour and documented in
docs/DECISIONS.md.

## After Phase 3 (2026-07-03)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**150/150 passed** (112 after Phase 2 + 38 new).

New/extended tests:
- `test/units_test.dart` (17) — kg↔lbs conversion + factor, round trips
  within 1e-9, display round trip, zero/fractional/negative, unit labels,
  `formatWeight` trim-zero/1 dp/sign/non-finite→em dash,
  `formatCompactWeight` tiers and non-finite handling.
- `test/leaderboard_calculator_test.dart` (8) — the full D3 suite: warm-ups
  ignored (even when stronger), rep-cap non-inflation, leaderboard =
  analytics = formula for the same set, empty and warm-up-only workouts,
  malformed sets ignored, best-set selection, multi-exercise + duplicate
  entries.
- `test/fitness_formulas_test.dart` (+9) — fractional/negative/non-finite
  weight semantics; the eligibility rule's full truth table.
- `test/recommendation_service_test.dart` (+3) — warm-ups can't mask
  progressing working sets; reps above the cap no longer read as progress
  (discriminating fixture: flat weight, rising 11–16 reps → plateau);
  rising malformed zero-rep sets ignored.
- `test/exercise_analytics_service_test.dart` (+1) — tiny changes near
  display-rounding boundaries keep their true typed direction.

## After Phase 4 (2026-07-03)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**196/196 passed** (150 after Phase 3 + 46 new).

New tests (all pure unit tests over the handwritten
`test/fake_firestore_adapter.dart`; no Firebase required):
- `test/data_result_test.dart` (9) — success/empty/failure semantics, typed
  skipped documents, the full Firebase error-code mapping, parse-error →
  invalidData, conservative unknown fallback.
- `test/workout_service_test.dart` (19) — collection paths, exact stored
  payload format, newest-first ordering with id tie-breaking, empty history,
  legacy optional fields, int/double numeric coercion, malformed-document
  skip-and-report, unauthenticated/read/write/delete failures, PR
  improvement + no-lowering, leaderboard update on save, best-effort PR
  failure never blocking a save, delete → PR recalculation (including
  last-set document removal and PR-to-zero).
- `test/leaderboard_service_test.dart` (10) — load parse/skip/failure,
  setAnonymous merge fix (no-throw without an entry, field preservation),
  improve-only best-lift writes, warm-up-only no-op, displayName no-op/update.
- `test/template_service_test.dart` (9) — template round-trip, skip
  malformed, failure mapping, delete; FirestoreService profile: exists vs
  missing, legacy minimal parse, malformed profile fails (auth-critical),
  personal-record merge preserving siblings.

**Unit-tested vs emulator-dependent:** these tests verify service logic
against a fake whose set-merge/update semantics are approximations. Real
Firestore merge behaviour, offline errors, ordering-index behaviour and
security rules are emulator scope (Phase 10) — the unit suite does not claim
to verify them.

## After Phase 5 (2026-07-04)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**229/229 passed** (196 after Phase 4 + 33 new widget tests).

New tests:
- `test/app_shell_test.dart` (10) — initial Dashboard selection; exactly
  three destinations with no Weekly Review text; switching updates selection
  and content; no duplicated roots; state preservation across switches
  (stateful counter destination); re-tap no-op; system Back from
  Progress/More root returns to Dashboard; Back on Dashboard root defers to
  the system; Back closes a pushed secondary screen before changing tabs.
- `test/more_screen_test.dart` (7) — grouped items all visible, no Weekly
  Review/"coming soon"; each item opens its (injected) screen; sign-out
  callback; scrollability at a 400px-tall viewport.
- `test/shared_widgets_test.dart` (16) — LoadingView, EmptyView,
  ErrorRetryView (+secondary action), StatusBanner (+action/omitted action),
  InlineNotice, SectionHeader; dark-mode rendering and 2× text-scale
  overflow smoke tests for the four content-bearing widgets.

Not covered (impractical without Firebase fakes at screen level, deferred to
Phase 11): Dashboard-still-exposes-Log-Workout, Progress-tab content, and
sign-out-through-auth-stream as end-to-end flows. The More-screen and shell
tests cover their navigation contracts via injected builders instead.

## After Phase 6 (2026-07-04)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**265/265 passed** (229 after Phase 5 + 36 new).

New tests:
- `test/dashboard_service_test.dart` (27) — Monday–Sunday boundaries
  (Sunday-night vs Monday-morning workouts), injected reference dates,
  activity counts and increase/decrease/unchanged, volume eligibility
  (warm-up + malformed exclusion), noData vs zeroBaseline weekly change,
  signed volume changes, top-exercise ranking/window/tie-breaking/duplicate
  entries, recent-PR rules (beats-all-earlier, first-session-not-a-record,
  warm-up/cap/malformed cannot create PRs, newest-first ordering), trend
  warnings (insufficient data → none; plateau/regression with evidence;
  regression outranks plateau), progressing/activeWeek/needsMoreData
  statuses, data-quality mapping, skipped-record pass-through, stable
  output ordering for reversed input.
- `test/dashboard_screen_test.dart` (9) — loading, empty, populated
  (metrics/status/goal/actions, lazy sections scrolled into view),
  initial-failure + retry recovery, refresh-failure preserving last-known
  data behind a banner (triggered via workoutDataVersion), skipped-record
  notice, narrow-width overflow check, 2× text-scale and dark-mode smoke
  tests; all via the injectable loader, no Firebase.

## After Phase 7 (2026-07-04)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**309/309 passed** (265 after Phase 6 + 44 new).

New tests:
- `test/exercise_detail_test.dart` (22) — empty/no-match/warm-up-only/
  malformed histories; exact-match substring isolation; recent best
  (window, latest-day ties, unavailable-not-zero); frequency (2.0×/week,
  genuine zero); window changes (increase/decrease/unchanged/noData/
  zeroBaseline); statuses (progressing/plateau+diagnosis/regression/
  volume-progressing suppression/insufficient); per-exercise data-quality
  categories; evidence contents (count vs minimum, change observations with
  periods, absence explicit); injected reference-date shifts.
- `test/progress_screen_test.dart` (18) — loading/empty/failure+retry/
  skipped notice; chips; selection reveals status+metrics+evidence;
  substring non-pollution at UI level; plateau shows "Possible plateau" +
  "Possible explanation" (no "Likely Cause"); insufficient data stated with
  '—' metrics; evidence panel expands to the analysis basis; history
  section below analytics; pull-to-refresh and workoutDataVersion reloads;
  preselection request consumption; vanished-selection safety; narrow/2×
  text-scale/dark smoke; no Weekly Review.
- `test/dashboard_screen_test.dart` (+1) — tapping a Most-trained row sets
  the progress preselection request.

Note: the buildSeries-level cases in the Phase 7 spec (same-day merge,
duplicate entries, zero weight/reps, rep cap) are covered by the existing
Phase 2/3 suites (`exercise_analytics_service_test.dart`,
`leaderboard_calculator_test.dart`) and were not duplicated.

## After Phase 8 (2026-07-04)

`flutter analyze`: 8 issues — identical to baseline. `flutter test`:
**369/369 passed** (309 after Phase 7 + 60 new).

New tests:
- `test/weekly_review_service_test.dart` (35) — availability (noData/one/
  multiple workouts), shared data-quality mapping, Monday–Sunday boundary,
  injected reference date, workout-count increase/decrease/unchanged rules
  (first-ever week not "up"; zero week reports only noTrainingThisWeek),
  volume band rules incl. zero-baseline producing NO fabricated finding,
  PR-in-week (first-session and warm-up cannot create one), trend findings
  (progressing/plateau/regression severities + actions, volume-rising
  suppression, <5 sessions → nothing), repeated-exercises consistency
  (case-insensitive), feel rules (absent/sparse-stays-unavailable/
  declined-suppresses-low-feel/improved/low-feel-standalone/stable),
  skipped-record finding, every-finding-and-action-has-evidence, no
  unsupported action, regression-before-plateau ordering and identical
  output across identical builds.
- `test/review_narrator_test.dart` (10) — empty review still narrated;
  parallel list lengths; insufficient-data wording (observed count, no
  trend judgement); skipped-records narration; cautious possible/may
  wording with no certainty/proven-cause phrasing and the medical
  disclaimer present; unavailable volume produces no volume sentence or
  percent; narrated actions map 1:1 to typed actions; deterministic
  output; kg/lbs unit parameter honoured; severity-driven headlines.
- `test/weekly_review_screen_test.dart` (12) — loading, encouraging empty
  state, populated sections + data-quality note, initial-failure retry
  recovery, refresh-failure preserving the last-known review,
  skipped-record notice, evidence-panel expansion, pull-to-refresh,
  workoutDataVersion reload, narrow-width / 2× text-scale / dark-mode
  smoke tests; all via the injectable loader, no Firebase.
- `test/app_shell_test.dart` (13, was 10) — four-destination assertion
  replaces the three-destination/no-placeholder test; new: selecting
  Review shows its content at index 2, Back from Review root returns to
  Dashboard, re-selecting Review duplicates nothing; all previous
  behaviours re-verified with four destinations.

## After Phase 9 (2026-07-04)

`flutter analyze`: **0 issues** — better than the 8-info baseline: the
CLI rewrite replaced `print` with `stdout`/`stderr.writeln`, clearing the
`avoid_print` infos without disabling any lint. `flutter test`:
**425/425 passed** (369 after Phase 8 + 56 new).

New tests:
- `test/demo_fixtures_test.dart` (29) — per scenario: deterministic
  output, chronological validity (ascending, before the reference date),
  realism bounds (weights/reps ranges, ≤1 warm-up per exercise, non-empty
  names), stored-format round-trips; scenario differentiation and
  no-id-collision; tag payload contents + parse-compatibility; and the
  real services over generated data: progressing → progressing status,
  week PRs, improving feel, substring name pair; plateau → bench plateau
  without suppression + repMonotony diagnosis while Squat/Deadlift
  progress; regression → OHP regressing + declining feel; volume-
  progressing → suppression finding, no plateau warning, sparse-feel
  action; insufficient → gettingStarted, no trend findings.
- `test/demo_seeder_test.dart` (10) — strict-tag selection (truthy
  strings rejected), batch filtering, orphan-tag handling; seeding writes
  tagged parseable docs at deterministic ids; double-seed never
  duplicates; normal workouts and other batches survive reseeds; cleanup
  by batch / all / dry-run with correct counts; untagged docs undeletable
  even by --all.
- `test/demo_cli_test.dart` (11) — command/flag parsing incl. required
  --scenario/--batch|--all, unknown options rejected, --yes only when
  explicit; env-config reading with per-variable missing reporting and
  optional credentials.
- `test/demo_tools_screen_test.dart` (4) — warning/context/scenarios/
  cleanup rendering; confirmation required (cancel = no writes, no
  version bump); confirmed seed writes tagged docs + bumps
  workoutDataVersion; cleanup removes only tagged data.
- `test/more_screen_test.dart` (+2) — Developer section opens the demo
  tools in debug mode; absent when developer tools are disabled
  (release behaviour).

Not covered (documented): the CLI's dart:io/REST shell (sign-in, HTTP,
prompts) is untested by design — all decision logic lives in the tested
pure modules; REST behaviour is exercised manually and via Phase 10's
emulator work where relevant.

## After Phase 10 (2026-07-05)

`flutter analyze`: **0 issues** (the Phase 9 baseline holds).
`flutter test`: **429/429 passed** (425 after Phase 9 + 4 new).
Firestore rules suite: **33/33 passed** on the local emulator
(cloud-firestore-emulator 1.20.4, offline `demo-gymconnect` project).

New Dart tests (`test/leaderboard_service_test.dart`, +4 net):
- anonymity write-path guarantees: anonymous saves store the safe display
  value and never the real name; non-anonymous saves store the real name;
  `setAnonymous` ON sanitises / OFF restores (both transitions, lifts
  preserved via merge); a profile rename cannot leak a real name onto an
  anonymous entry.

New emulator suite (`test_rules/firestore_rules.test.mjs`, 33 tests):
unauthenticated denial across profiles/workouts/templates/leaderboard;
own-profile create/read/update, cross-user read/update denial, malformed
profile writes denied, profile delete denied; workout own-CRUD, cross-user
get/list/write/delete denial, demo-field typing, demo-fields-grant-no-
access, date/exercises/feelRating validation; template own-CRUD,
cross-user and unauthenticated denial, malformed denial; leaderboard
own-gym read + own-entry write, wrong-owner/wrong-gym/no-profile denial,
anonymity invariant (real-name-while-anonymous denied; safe value
allowed; both toggle merge shapes compliant; pre-Phase-10 flag-only
toggle rejected), closed field set and type checks, delete denied;
deny-by-default for unknown top-level collections, unknown nested paths
and `gyms/{gymId}` documents.

**Unit-tested vs emulator-tested:** the Dart suite proves what the app
WRITES (fake adapter — no real merge semantics); the emulator suite
proves what the rules ACCEPT/REJECT, including real set-merge post-states.
The set-merge caveat from Phase 4 is now emulator-covered for the
leaderboard toggle shapes. Live-console rules remain untested until the
manual deployment (docs/FIRESTORE_SECURITY.md).

Run the rules suite (requires Node 18+, firebase-tools, JDK 21+ — e.g.
Android Studio's JBR; see docs/FIRESTORE_SECURITY.md):

```
npm --prefix test_rules install   # once
npm --prefix test_rules test
```

### Pending regression tests (documented, deliberately not written yet)

- ~~Leaderboard e1RM correctness (D3)~~ — **landed in Phase 3** via the
  extracted `bestEligibleE1RmPerExercise` calculator (see above).
- ~~`WorkoutService` helper characterisation~~ — **closed in Phase 4**: the
  service is constructible with the fake adapter; its data paths are fully
  unit-tested. (The pure helpers' behaviour is exercised indirectly via the
  log/progress flows and can gain direct tests opportunistically.)
- **set(merge) semantics**: unit tests pin payloads and exercise the fake's
  approximation; that real `merge: true` preserves sibling
  `personalRecords`/leaderboard entries is SDK behaviour, verified manually
  now and by emulator test in Phase 10.

## After Phase 11 (2026-07-05)

`flutter analyze`: **0 issues** (baseline holds).
`flutter test`: **465/465 passed** (429 after Phase 10, +40 new, -4
deleted with `suggestNextWorkout`).
Firestore rules suite: **not rerun — not modified.** Phase 11 changed no
rules, no leaderboard write shapes and no Firebase config, so the Phase 10
result (33/33) stands.

New unit tests:
- `test/workout_draft_test.dart` (13): validation wording for every failure
  case (zero-weight bodyweight sets allowed), draft→model conversion for
  kg/lbs (single conversion, trimmed names, warm-up flags preserved),
  working-volume calculation, add-set copy behaviour, the one-warm-up-per-
  exercise toggle rule, and the DraftSet prefill factories (workout +
  template, blank-weight templates).
- `test/overload_hint_test.dart` (6): no-history, single-set-always-strong,
  75%-floored rep threshold (hold vs drop), session-max top weight, +2.5 kg
  suggestion; plus the shared date-label helpers.

New widget tests (`test/log_workout_screen_test.dart`, 17 — the screen's
first tests ever, via injected services over the fake adapter):
empty form state; history-load failure banner with retry while manual
logging stays usable; missing signed-in user degrades to the banner (no
crash); chip prefill from the last WORKING set (warm-up ignored); chip
re-tap appends to the existing card; add/remove sets with value copying;
warm-up toggle marks W and moves under the single-warm-up rule; lbs
preference converts the prefill and the save converts back to kg;
validation errors for empty form/unnamed/setless/invalid sets; save
success (feel rating stored, volume dialog, workoutDataVersion bump, pop
back); save failure shows the error and stays; template prefill from last
actual performance beating placeholders; repeat-last restores warm-up
flags and confirms before replacing; overload hint wording; narrow-width,
2x-text-scale and dark-mode smoke tests.

Extended (`test/progress_screen_test.dart`, +4 → 22): warm-up-only
exercise excluded from chips/analytics; delete-set flow (injectable since
Phase 11) — confirmed deletion removes the document, refreshes the screen
and bumps `workoutDataVersion`; cancelled confirmation changes nothing;
failed deletion shows the snackbar and keeps data.

Removed (`test/recommendation_service_test.dart`, -4): the
`suggestNextWorkout` characterisation group went with the deleted method
(docs/DECISIONS.md Phase 11); the 9 `generate` tests remain.

## After Phase 12 (2026-07-05)

`flutter analyze`: **0 issues** (baseline holds).
`flutter test`: **504/504 passed** (465 after Phase 11 + 39 new).
Firestore rules suite: **33/33 passed**, unchanged; re-verified because CI
now runs it as a job.
`dart format --output=none --set-exit-if-changed .`: **clean repo-wide**
(newly enforceable - see below).

New unit tests:
- `test/migration_plan_test.dart` (24): recomputation across history
  (best-of-all-sessions, warm-up exclusion, rep cap at 10, malformed and
  warm-up-only exercises produce no entry, empty history); **agreement
  with the app** - the CLI-safe recomputation returns exactly what
  `LeaderboardService.bestEligibleE1RmPerExercise` returns for the same
  sets, and the tool's copied `'Anonymous'` constant equals
  `LeaderboardService.anonymousDisplayName`; correction classification
  (lowered vs raised), unchanged counting, tolerance
  (`migrationToleranceKg`), orphan records never rewritten but carried
  through, never inventing unstored exercises, deterministic ordering,
  **idempotency** (applying a plan makes the next plan empty) for both
  personal records and the leaderboard; anonymity-leak detection, the
  already-safe and non-anonymous no-op cases, and the rule that a leaking
  entry must write `displayName` in the same PATCH as `bestLifts`.
- `test/migration_cli_test.dart` (15): read-only default (no `--apply` =
  dry run for every fix command), `inspect --apply` refused, `--yes`
  without `--apply` refused, `--dry-run` with `--apply` refused as
  contradictory, unknown command/option rejection, target scoping, and
  configuration validation (missing/blank required vars, optional trimmed
  credentials, usage text documenting the safety posture).

Repo-wide formatting: 7 files predating Phase 11 were not
`dart format`-clean (`lib/models/template_model.dart`,
`lib/models/user_model.dart`, `lib/screens/login_screen.dart`,
`lib/services/auth_service.dart`, `lib/services/plateau_detector.dart`,
`test/feel_analysis_service_test.dart`,
`test/plateau_detector_test.dart`). They were formatted so the CI gate can
enforce formatting; whitespace only, no behaviour change, all tests still
pass.

CI (`.github/workflows/ci.yml`) runs exactly these checks on push/PR to
`main`: one job for format + analyze + test, one for the rules emulator
suite (Node 20, Temurin JDK 21, `firebase-tools@15`, offline
`demo-gymconnect` project). It references no secrets and deploys nothing.

CI-path verification performed locally: the real (gitignored)
`lib/firebase_options.dart` was backed up and checksum-verified, replaced
with `tool/ci/firebase_options_stub.dart`, and analyze/format/tests were
re-run green against the placeholder before restoring the original
byte-identically. This proves a fresh checkout compiles in CI.

The migration CLI was also exercised offline (`dart run
tool/migrate_data.dart` with no args, `inspect --apply`,
`fix-all --dry-run --apply`, and a missing-config run): each printed the
expected refusal and exited 64/78 without contacting any project,
confirming the pure modules load under plain `dart run` (no Flutter
plugins).

### Not covered by automated tests (documented)

The migration tool's live REST behaviour against a real Firestore project
is manual-only, like the demo CLI's: the planner and CLI rules are unit
tested, but signing in, reading a real profile and PATCHing corrected
values is verified by hand per docs/RELEASE_CHECKLIST.md. No test in this
repository writes to a live project.

## Standing rules for all future phases

- Preserve all existing tests; a phase that breaks one must fix the regression
  or explicitly justify and document the behavioural change in
  docs/DECISIONS.md.
- Every new analytics calculation ships with unit tests covering: empty input,
  insufficient data, duplicate dates/sessions, zero weight / zero reps,
  date boundaries (week start/end, DST-safe day math), and safe percentage /
  division behaviour.
- Analytics tests inject reference dates/clocks; no test may depend on the
  wall clock.
- Do not rely on Firestore ordering in logic under test unless the query
  explicitly orders.
- After each phase: `dart format` on changed files, `flutter analyze`,
  targeted tests, then the full suite; exact results reported, failures never
  concealed.

## Planned test additions by phase (see docs/BACKLOG.md for phase scope)

- **Phase 1** — characterisation tests freezing current analytics behaviour
  (including quirks) before refactoring; tests for onboarding-on-error fix,
  clock injection, exercise-name field-path safety.
- **Phase 2** — unit tests for typed analytics models and extracted
  session-series/orchestration services (must reproduce characterisation
  results).
- **Phase 3** — consistency tests proving leaderboard, progress analytics and
  recommendations produce identical e1RM for the same set; warm-up exclusion;
  rep-cap non-inflation; empty/warm-up-only workouts; unit conversion and
  formatting; safe percentage change; week-boundary helpers.
- **Phase 4** — service result-pattern tests (success/empty/error paths).
- **Phase 5** — widget tests: NavigationBar destination switching, state
  preservation across tabs, back-button behaviour; core shared widgets
  (metric card, status banner, empty/error/loading states).
- **Phase 6** — DashboardService unit tests (Monday–Sunday boundaries,
  injected reference date, empty/partial data, week-over-week safe change);
  dashboard widget states.
- **Phase 7** — exercise analytics unit + widget tests (evidence panel,
  insufficiency reasons, softened diagnosis wording).
- **Phase 8** — WeeklyReviewService rule tests (each category, evidence
  presence, confidence/data-quality), narrator template determinism,
  narrator-constraint tests (output built only from supplied analytics).
- **Phase 9** — fixture generator unit tests (deterministic output, all
  scenario datasets); idempotent seed + cleanup integration tests where
  practical; cleanup-deletes-only-tagged-data tests.
- **Phase 10** — Firestore emulator tests: own-profile read/update, denial of
  cross-user workout/template access, leaderboard read/write scope,
  malformed/unauthenticated requests, demo fields not weakening rules.
- **Phase 11** — widget tests for major user states of the big screens,
  integration tests (auth, onboarding, logging, progress, weekly review),
  small-screen overflow, dark mode, kg/lbs display, accessibility semantics.
- **Phase 12** — CI running format check, analyze, unit + widget tests, and
  emulator tests where practical; migration tooling tests (idempotency,
  opt-in, no destructive default).
