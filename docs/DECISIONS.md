# GymConnect — Decision Log

Newest first. Each entry: context → decision → consequences. Decisions made
before this log existed are reconstructed from the code and marked
*(historical)*.

---

## 2026-07-02 — D1: Bottom NavigationBar shell

**Context:** Home screen navigates via a stack of buttons; the upgrade adds a
dashboard and weekly review that need first-class navigation.
**Decision:** Material 3 bottom `NavigationBar` with four destinations —
Dashboard, Progress, Weekly Review, More. Leaderboard, templates,
profile/settings and other secondary features live under More. The shell is
its own phase (Phase 5) before the dashboard rebuild; existing screen
behaviour is preserved and routed through it, with widget tests for
destination switching, state preservation and back-button behaviour.
**Consequences:** No new dependency; `home_screen.dart` stops being the
navigation hub.

## 2026-07-02 — D2: Demo data via CLI *and* debug-only in-app controls

**Decision:** Deterministic fixture generation lives in `lib/demo/` (pure,
unit-tested). Exposed through the CLI tool and through in-app controls that
are compiled/available only in debug builds and clearly labelled. Both paths
must: display the target user and Firebase project, require explicit
confirmation before writing, tag documents `isDemo: true`, be idempotent,
provide cleanup that deletes only tagged demo data, and never modify or
remove normal user workouts.
**Consequences:** Production builds expose no demo controls; demo state is
always identifiable and reversible.

## 2026-07-02 — D3: Correct leaderboard/recommendation e1RM; opt-in migration

**Context:** `leaderboard_service.dart` and `recommendation_service.dart`
inline an uncapped Epley formula; the leaderboard also includes warm-up sets.
The canonical `estimatedOneRepMax` caps reps at 10 and consumers elsewhere
exclude warm-ups.
**Decision:** Use the shared `estimatedOneRepMax` everywhere and exclude
warm-up sets from leaderboard calculations. Before the behaviour change, add
regression tests: warm-ups ignored; reps above the cap don't inflate e1RM;
leaderboard, progress analytics and recommendations agree for the same set;
empty/warm-up-only workouts are safe. Existing stored leaderboard/PR values
are corrected by a **documented, idempotent, opt-in migration/recalculation
tool** (Phase 12) — never run automatically, explicit confirmation required.
**Consequences:** Some stored bests are higher than the corrected formula
would produce; until migration they stand until beaten (new writes only
update when the corrected value beats the stored one).

## 2026-07-02 — D4: Commit the reworked seed tool without secrets

**Decision:** Rework `tool/seed_data.dart` (currently untracked) and commit
it. Remove the hard-coded API key; load configuration from environment
variables or the local gitignored Firebase config files
(`android/app/google-services.json`). Add setup instructions, config
validation and safe failure messages when configuration is unavailable.
**Consequences:** Tool becomes part of the reviewed codebase; no key material
enters git history.

## 2026-07-02 — D5: Firestore rules authored in-repo, tested on emulator, deployed manually

**Decision:** Add `firestore.rules` and `docs/FIRESTORE_SECURITY.md`
(access model, ownership rules, leaderboard behaviour, anonymity assumptions,
limitations, test/deploy instructions). Add Firestore emulator tests for
authorised and unauthorised access. **Never deploy rules or alter the live
Firebase project without explicit permission.**

## 2026-07-02 — D6: Dependency policy

**Decision:** Avoid unnecessary dependencies; propose one only with clear
architectural value. Do not upgrade `fl_chart` (0.66) without a specific
required feature or compatibility issue. `intl` is acceptable if justified
for locale-aware date formatting. A lightweight state-management solution may
be *proposed* after the navigation/dashboard data flow is designed — only
with the concrete problem it solves, alternatives considered and migration
impact; never "because it's common practice".

## 2026-07-02 — Approved 12-phase upgrade plan

The full revised phase plan (characterisation tests first, then domain
extraction, formula/unit consolidation, data-access cleanup, navigation
shell, dashboard, exercise analytics, weekly review, demo tooling, security
testing, broader refactoring, CI/migration/release) is recorded in
docs/BACKLOG.md. Standing rules: restate scope + acceptance criteria before
each phase; format/analyze/test and report exact results after; stop for
review between phases; preserve Firestore backward compatibility; no
deployments, migrations, data deletion or destructive commands without
explicit permission.

## 2026-07-02 — Personal-record field paths: set(merge) instead of dot-notation update (Phase 1)

**Context:** `updatePersonalRecords` built `update()` keys as
`'personalRecords.$exerciseName'`; `update()` parses `.` as a nested-field
separator, so an exercise name containing a period would corrupt the stored
map.
**Decision:** Write via `set({'personalRecords': {...}}, SetOptions(merge:
true))`. `set()` treats map keys literally and `merge: true` merges nested
maps field-by-field, preserving other exercises' records. Exercise names are
stored exactly as entered — no encoding or renaming. A `@visibleForTesting`
payload builder (`personalRecordsMergeData`) pins the shape in unit tests.
**Alternative considered:** `FieldPath(['personalRecords', name])` keys in
`update()` — viable, but set+merge is the better-documented SDK behaviour.
**Consequences:** stored data shape unchanged; the write now also succeeds if
the profile document is missing (creates it) where `update()` would throw —
acceptable since callers only run for onboarded users. Merge semantics to be
double-checked once the Firestore emulator harness exists (Phase 10).

## 2026-07-02 — Profile lookup modelled as four states in ProfileGate (Phase 1)

**Context:** a profile-read *failure* was previously routed to onboarding,
where saving `set()`s the profile document — a transient network error could
let a user overwrite their existing profile.
**Decision:** new `lib/widgets/profile_gate.dart` widget with explicit
loading / exists / missing / failed states; failure shows an error screen
with Retry and Sign out. Dependencies (profile lookup, home/onboarding
builders, sign-out) are injected so the widget is testable without Firebase.
`ProfileChecker` in `main.dart` is now a thin wrapper wiring the real
services.
**Also decided:** no shared service `Result<T>` type introduced in Phase 1 —
the gate's internal enum was the only place richer-than-null semantics were
required by this phase's fixes. Revisit in Phase 4 (data-access cleanup).

## 2026-07-02 — Phase 2: analytics domain shape and behaviour corrections

**Session definition:** for per-exercise analytics, a session is one local
calendar day; same-day workouts (including duplicate timestamps) merge (best
e1RM = max, volume = sum). This matches the pre-existing chart/volume
definition; workout documents themselves are never merged.
**Domain types:** small composable types in `lib/models/analytics.dart`
(DatePeriod, sealed MetricResult, PercentageChange, EvidenceItem,
DataQuality, Severity, ExerciseSession/Series). `DataQuality` is categorical
by design — no invented numeric confidence percentages. Typed
Insight/Recommendation containers are **deferred** to their first consumer
(Phases 6–8) to avoid designing them without a consumer. No serialization on
analytics types (never stored). The existing `PlateauResult`/`PlateauStatus`
vocabulary is reused for trends rather than duplicated.
**Service boundary:** `ExerciseAnalyticsService` is pure/static and takes
`WorkoutModel` (which carries a Firestore `Timestamp`), like the existing
pure services — full model decoupling was judged pre-emptive churn.
`WorkoutService` was not touched; Phase 2 did not need it.
**Invalid data policy:** analytics ignore sets with weight < 0 or reps < 1;
zero weight is valid. Documented in ANALYTICS_DEFINITIONS.
**Behaviour corrections (defects, regression-tested, no stored-data impact):**
(1) e1RM series now exact-matches the exercise name instead of
substring-matching via the filter (an "Incline Bench Press" no longer
pollutes "Bench Press" charts/trends); (2) duplicate same-named exercise
entries in one workout all count toward volume (previously only the first);
(3) malformed sets excluded. Intentionally preserved: zero-volume sessions
stay out of the *volume* trend; "Volume Progressing" gating unchanged.

## 2026-07-03 — Phase 3: canonical formulas, eligibility and units

**Canonical e1RM:** `estimatedOneRepMax` (capped Epley) is the single
implementation; the uncapped inline copies in LeaderboardService and
RecommendationService were removed (D3 executed). The formula returns
unrounded values and does not gate inputs; gating lives in the shared
`isEligibleForStrengthAnalytics` rule (not warm-up ∧ finite weight ≥ 0 ∧
reps ≥ 1), applied to strength-performance AND training-volume analytics
(volume already excluded warm-ups; malformed exclusion extends the approved
Phase 2 policy). History display/prefill still show warm-ups.
**Units:** `lib/utils/units.dart` is the only definition of the 2.20462
factor (unchanged baseline). Stored = kg full precision; convert once at the
display/input boundary; formatting helpers `formatWeight` (trim-zero ≤1 dp)
and `formatCompactWeight` (M/k tiers) preserve existing per-screen output.
The unit preference stays the existing 'kg'/'lbs' string — an enum would be
churn without benefit. Non-finite values format as an em dash.
**Intentional display unification:** the log-workout volume dialog now uses
the shared compact formatter and gains the (practically unreachable) M tier.
**Leaderboard testability:** smallest extraction —
`LeaderboardService.bestEligibleE1RmPerExercise` static pure calculator
(`@visibleForTesting`); no service redesign. Leaderboard document keys keep
using the stored exercise name unchanged.
**Historical stored-record limitation (documented, not repaired):** records
and leaderboard bests written before Phase 3 may be inflated (uncapped reps
or warm-up sets). They are not rewritten; new writes only replace them when
the corrected value is higher, so an old inflated record can remain
unbeatable until the opt-in Phase 12 migration recalculates stored values.

## 2026-07-03 — Phase 4: data-access boundaries

**Result model:** sealed `DataResult<T>` (`DataSuccess` with typed
`SkippedDocument` warnings / `DataFailure` with `DataFailureKind` + retained
cause). Empty collections are successes. Analytics insufficiency stays in
the Phase 2 types — pure analytics services were NOT converted.
**Error mapping:** one `failureKindFor` mapping Firebase codes to stable
categories with a conservative `unknown` fallback; UI never parses
exceptions.
**DI boundary:** a single narrow `FirestoreAdapter` interface (production
impl over `FirebaseFirestore`, handwritten in-memory fake for tests) instead
of per-service repositories or a DI package. Services own paths and
(de)serialisation. `WorkoutService` also takes a current-uid provider and
returns typed `unauthenticated` failures instead of asserting `currentUser!`.
**Malformed documents:** collection loads (workouts, templates, leaderboard)
skip-and-report; the progress screen shows a visible skipped-records notice.
Profile documents are auth-critical and fail the operation instead.
**Orchestration moved out of screens:** `saveWorkoutAndUpdateRecords`
(save → PR detection via the shared best-eligible-e1RM calculator →
non-blocking leaderboard update, best-effort semantics preserved) and
`deleteSetAndRecalculateRecord` (delete → PR recalc → returns fresh list).
**Ordering:** server orderBy('date' desc) plus client-side stable re-sort
(date desc, doc-id asc tie-break). Firestore omits documents missing `date`
from ordered queries — pre-existing, documented. Unbounded reads accepted at
current scale (backlog risk).
**Fixes:** leaderboard `setAnonymous` uses set-merge (no longer throws for
users without an entry; a flag-only doc stays invisible in rankings);
leaderboard screen failure state is distinct from "no gym ID"; anonymity
toggle reverts with a SnackBar on failure; templates load failure says so
instead of showing an empty list. **Accepted:** `updateUserBestLifts`
read-then-merge race on the user's own document (last-write-wins,
single-user writer; documented). **Removed dead code:**
`WorkoutService.getRecentExerciseNames` (no callers).
**Intentionally left in UI:** `Timestamp.now()` model construction and
`currentUser!.uid` for profile fetches under the authenticated shell
(full removal considered Phase 11 scope). `AuthService` untouched — a thin
FirebaseAuth passthrough with no paths or parsing.
**Test-fidelity caveat:** the fake adapter approximates set-merge/update
semantics; real merge, offline and security behaviour remain
emulator-verified (Phase 10).

## 2026-07-04 — Phase 5: navigation shell and shared visual foundations

**D1 refinement (approved):** the shell ships with THREE visible
destinations — Dashboard, Progress, More. Weekly Review remains the intended
fourth destination (added in Phase 8 by appending one entry to the shell's
lists — no restructuring), and no placeholder/"coming soon" screen is shown
until it has real content.
**Shell:** `AppShell` = PopScope + Scaffold(IndexedStack + NavigationBar),
shown only via ProfileGate's homeBuilder. **IndexedStack over nested
Navigators** because every screen pushes on the root navigator — per-tab
back stacks would add complexity for no benefit. Destinations injectable for
tests. Trade-offs (documented): all destinations initialise eagerly; the
Progress tab can be stale after logging a workout until pull-to-refresh
(previously recreated per push) — revisited in Phase 6.
**Back semantics:** pushed secondary screens pop first; Progress/More root →
Dashboard; Dashboard root → system handles (app backgrounds); re-tapping the
selected tab is a no-op.
**More screen:** grouped Training (Templates, Starter Plans) / Community
(Leaderboard) / Account (Profile, Dark Mode, Sign out); route builders and
sign-out injectable for tests. **Sign-out** now relies solely on the
auth-state stream (the old manual pushAndRemoveUntil(LoginScreen) removed).
**Home cleanup:** duplicate navigation removed (Progress/Leaderboard/Starter
buttons, AppBar profile+logout, dark-mode switch). Log Workout deliberately
stays on the Dashboard. No Dashboard↔More duplicates kept. Known behaviour:
after editing the profile from More, the Dashboard's goal card refreshes on
pull-to-refresh rather than automatically (was auto only for the old AppBar
route).
**Shared foundations:** `theme/app_tokens.dart` (Insets/Corners) + focused
widgets: GoalCard (de-duplicated from home+progress), InsightCard
(recommendation + feel cards), ErrorRetryView (profile gate, profile screen,
progress, leaderboard), StatusBanner (dashboard load/refresh failure),
InlineNotice (log-workout history failure, progress skipped-records),
EmptyView, LoadingView, SectionHeader (profile, More). Context-specific
wording preserved; failed-first-load vs failed-refresh vs empty vs
partial-success vs SnackBar distinctions kept. **Intentionally unmigrated:**
existing screens' literal paddings and the deepPurple/status colour accents
(theme-wide token adoption would be churn; ColorScheme values used where a
direct equivalent existed, e.g. onSurfaceVariant for muted text in new
widgets).

## 2026-07-04 — Phase 6: training dashboard

**Service/UI split:** pure `DashboardService.build(workouts, referenceDate,
skippedRecords)` → typed `DashboardData`; all prose lives in the dashboard
UI. Metric definitions in ANALYTICS_DEFINITIONS (weeks Monday–Sunday,
28-day top exercises, 14-day PRs, bounded 3-exercise trend scan,
documented status/data-quality rules).
**Stale-tab fix (closes backlog #19/#20):** `workoutDataVersion`
ValueNotifier in main.dart, bumped on workout save, set deletion and
profile/goal save; Dashboard and Progress listen and reload when the
version passes what they last loaded (self-writes guarded). No
state-management package. Refresh failure keeps last-known data behind a
StatusBanner; initial failure is a full ErrorRetryView; profile-load
failure degrades to a partial dashboard (no greeting/goal) rather than
failing everything.
**RecommendationService:** `suggestNextWorkout` stays deferred (weak
keyword heuristic; backlog #14 closed as deferred — revisit in Phase 8).
The `generate` card no longer renders its plateau/regression branch —
superseded by the evidence-backed training status/warnings; balance and
keep-going branches still render, and the start-beginner branch is covered
by the dedicated empty state. Service and its tests unchanged.
**Other user-visible changes:** dashboard replaces the old button-list
home; the greeting uses the profile display name only (no raw-email
fallback — FirebaseAuth left the build path so the screen is testable);
"View detailed progress" selects the Progress tab via a new
`AppShellTabs` inherited hook instead of pushing a duplicate route.

## 2026-07-05 — Phase 12: CI, migration tooling and release polish (executes D3's migration half)

**Formula sharing (enabling refactor):** `utils/strength_math.dart` now
holds the canonical `estimatedOneRepMax` and an eligibility rule expressed
over raw values, with ZERO imports; `utils/fitness_formulas.dart`
re-exports the formula and adapts eligibility to `WorkoutSet`. Rationale:
`fitness_formulas.dart` imported `workout_model.dart`, which imports
`cloud_firestore`, so a plain-Dart CLI could not use it - the migration
tool would otherwise have had to duplicate the formula, which D3 forbids.
Every existing call site is unchanged (the re-export keeps the same names)
and a test asserts the tool and `LeaderboardService` agree exactly.

**Migration tool (D3's migration half, plus the Phase 10 anonymity
leftover):** pure planning in `lib/migration/migration_plan.dart` +
`migration_cli.dart`, thin REST shell in `tool/migrate_data.dart`, same
layering as the Phase 9 demo CLI. Corrects `users/{uid}.personalRecords`
and `gyms/{gymId}/leaderboard/{uid}.bestLifts` written with the old
uncapped/warm-up-inclusive formula, and replaces a real display name still
stored on an anonymous leaderboard entry.

Safety posture, deliberately stricter than the demo CLI because this
touches real records rather than tagged demo data:
- **Read-only unless `--apply`** - there is no code path that writes
  without it; `--yes` without `--apply` and `--dry-run` with `--apply` are
  both refused rather than silently resolved.
- **Never deletes.** No delete call exists in the tool.
- **Orphans are left alone**: a stored record whose exercise has no
  eligible history is reported and carried through untouched - the
  "if uncertain, do not delete" rule applied to values.
- **Whole-map writes** so exercise names never become Firestore field
  paths (the Phase 1 dot-notation hazard).
- **Idempotent** via a 1e-6 kg tolerance; re-running reports nothing to do.
- **Per-account only.** Correcting a whole gym would need Admin SDK
  credentials, which this repo deliberately does not use or store.

**Rules interaction discovered while designing the write:** the Phase 10
rule `isAnonymous == true -> displayName == 'Anonymous'` evaluates the
POST-write document, so a `bestLifts`-only PATCH on a leaking anonymous
entry would be REJECTED. The planner therefore always writes the display
name in the same PATCH as any lift correction on such an entry; there is a
test for it. The rules themselves were NOT changed.

**CI:** `.github/workflows/ci.yml`, two jobs - format + analyze + full
Flutter suite; and the Firestore rules emulator suite (Node 20, Temurin
JDK 21 as firebase-tools 15 requires, offline `demo-gymconnect` project).
It references **no repository secrets** and contains **no deploy step**:
rules deployment stays manual per D5, and neither the demo nor the
migration CLI is ever invoked by CI.

**CI placeholder config:** `lib/firebase_options.dart` is gitignored (it
carries the project API key), so a fresh checkout cannot resolve the
import and `flutter analyze`/`flutter test` would fail. CI copies
`tool/ci/firebase_options_stub.dart` - fake values, committed knowingly -
into place when the file is absent. Nothing in analysis or the test suite
initialises Firebase, so placeholder values suffice, and the script never
overwrites an existing local file. Rejected alternatives: committing the
real file (leaks a key) or storing it as a CI secret (unnecessary, and
would add the first secret to a repo that has none).

**Repo-wide formatting:** 7 files predating Phase 11 were not
format-clean, which would have made the new CI gate fail on its first run.
They were formatted (whitespace only). From now on the whole repository -
not just changed files - must stay `dart format`-clean.

**Release polish:** README rewritten as the portfolio-facing document
(differentiator, architecture diagram, setup from a clean clone, tests, CI,
demo, migration, known limitations, documentation index, and an explicit
AI-assistance disclosure separating the submitted dissertation from the
post-submission upgrade). `docs/RELEASE_CHECKLIST.md` added as the manual
pre-release procedure; `docs/MIGRATION.md` documents the migration model.
Screenshots are NOT included - they are listed as a pending capture step in
the release checklist rather than fabricated.

**Not done, deliberately:** no migration was run against any live project;
no rules deployed; no release build signed or published; no screenshots
invented.

## 2026-07-05 — Phase 11: refactoring and test coverage

**Log workout decomposition (the phase's main target, 1029 → ~540 lines):**
draft state moved to `models/workout_draft.dart` (`DraftExercise`/`DraftSet`
with explicit-unit prefill factories, `validateWorkoutDraft` with the exact
pre-existing messages, `buildExercisesFromDraft` doing the single
display-unit→kg conversion, `workingVolumeKg`); the per-exercise UI moved to
`widgets/workout_form/` (ExerciseCard, SetRowEditor, StepperField,
RecentExercisesRow, FeelRatingSheet — stateless, callback-driven, the screen
keeps sole ownership of the draft); the overload-hint rule moved to
`utils/overload_hint.dart` as a pure function returning typed data.
Firestore document shape, validation wording, warm-up rules, prefill,
repeat/template flows, feel rating, volume dialog and `workoutDataVersion`
semantics all unchanged and now pinned by tests.

**Injection points (no DI package — optional constructor params only):**
`LogWorkoutScreen({workoutService, templateService, uidProvider})` and
`ProgressScreen({workoutService, profileLoader})` (loader already existed).
Production call sites pass nothing; real services are constructed lazily so
injected tests never touch Firebase.

**Auth assumptions (backlog #17, partial):** the log workout and progress
screens no longer use `currentUser!.uid` — a missing user is a typed
degraded state (history banner / null profile). Corrected defect in the
progress delete flow: previously a post-delete profile-fetch failure was
caught by the generic handler, showing "Failed to delete entry." for a
deletion that HAD succeeded and skipping the `workoutDataVersion` bump
(other tabs stayed stale). The profile fetch is now non-critical: the list
update and version bump always follow a successful delete. Remaining
`currentUser!.uid` uses (leaderboard/profile/templates/onboarding, and
main.dart's ProfileChecker which only builds when a user exists) are
documented and deferred — each sits under the authenticated shell and, in
the screens, inside catch-guarded loaders.

**RecommendationService (backlog #14 final):** `suggestNextWorkout` and
`NextWorkoutSuggestion` DELETED — unrendered since Phase 6, a last-workout
keyword heuristic that fails the evidence bar, fully superseded by the
Weekly Review's typed suggested actions. Its 4 characterisation tests were
removed with it. `generate` is KEPT as a documented legacy helper because
the dashboard still renders its balance/keep-going card; its doc comment
now forbids growing the class — new coaching advice belongs in the typed
weekly-review suggestion model. String-only recommendations stay out of
the core coaching surface.

**Shared cleanups:** `utils/dates.dart` replaces three drifted private
month-name tables (home/progress/weekly review); the Progress chart and
history card extracted to `widgets/e1rm_chart.dart` and
`widgets/workout_history_card.dart` (986 → ~700 lines, behaviour
unchanged). Dashboard and Weekly Review otherwise untouched.

**Accessibility (touched widgets only):** stepper -/+ buttons gained
tooltips + semantic button labels ("Increase weight"), the warm-up toggle
gained a semantic button label alongside its existing tooltip, feel-rating
stars gained "Rate N of 5" tooltips. Status is never colour-only (existing
text/wording carries it). Log workout gained narrow-width/2x-scale/dark
smoke tests matching the other destinations.

**Not rerun:** the Firestore rules emulator suite — no rules, leaderboard
write shapes or Firebase config changed this phase.

## 2026-07-05 — Phase 10: Firestore security rules and leaderboard anonymity (executes D5's authoring/testing half)

**Rules:** `firestore.rules` at the repo root, referenced from
`firebase.json`. Owner-only access for `users/{uid}` and its
workouts/templates subcollections; gym-membership-gated leaderboard
(membership = the caller's own profile `gymId`, one `get()` per
evaluation); deny-by-default for everything else; client deletes of
profiles and leaderboard entries denied (no app flow does either).
**Validation strictness:** required core fields + type checks on optional
fields for user-owned documents, with unknown extra fields tolerated
(keeps the project's backward-compatible storage rule deployable without
rules churn). The leaderboard is the exception — a CLOSED field set,
because those documents are cross-user readable. Deep workout internals
and per-value `bestLifts` typing are deliberately not rules-validated
(rules enforce ownership/shape, not truth; map values can't be iterated).
Demo fields are type-checked data with zero access semantics.
**Anonymity (write-path fix, not UI hiding, not rules redaction):** rules
cannot redact fields of readable documents, so anonymous entries must not
CONTAIN a real name. `LeaderboardService` now stores `'Anonymous'`
(`anonymousDisplayName`) whenever anonymous: `updateUserBestLifts`
substitutes it, `setAnonymous` gained a required `displayName` parameter
(ON sanitises, OFF restores the profile name — the leaderboard screen
passes the profile's display name it already loads), and
`updateDisplayName` no-ops on anonymous entries so profile renames cannot
leak. Rules enforce `isAnonymous == true → displayName == 'Anonymous'` as
a backstop. Historical anonymous entries keep their old name until the
owner's next write — accepted; bulk cleanup is Phase 12 migration scope.
**Harness:** `test_rules/` — Node built-in test runner +
`@firebase/rules-unit-testing` under
`firebase emulators:exec --project demo-gymconnect` (offline demo project;
no credentials; UI emulator disabled). 33 tests, run locally against
firestore-emulator 1.20.4. Environment note: firebase-tools ≥ 15 needs a
JDK 21+; the machine's system Java is 1.8, so the suite runs with
Android Studio's bundled JBR 21 (documented in FIRESTORE_SECURITY).
`test_rules/node_modules` gitignored; `package-lock.json` committed for
reproducibility.
**Not done, by design:** NO deployment (`firebase deploy` never run — the
live project still holds its console rules until the manual, explicitly
authorised deployment in docs/FIRESTORE_SECURITY.md); no live migration;
no auth-flow changes; no collection-group access enabled.

## 2026-07-04 — Phase 9: demo-data tooling (executes D2 and D4)

**Generator:** `lib/demo/demo_fixtures.dart` — pure Dart, zero Flutter/
Firebase/dart:io imports (the CLI compiles it under plain `dart run`), and
NO randomness at all: fixed weight/feel tables with hold-then-jump loading,
one back-off, warm-ups and rest-day gaps, so output is bit-identical for
the same reference date. Five scenarios (progressing+PRs+improving feel;
plateau with rep-monotony explanation while Squat/Deadlift still progress;
regression with declining feel while other lifts progress; volume-
progressing suppression with sparse feel; insufficient data), each
engineered against the documented thresholds and verified by tests that
run the REAL services over the generated data. Weekly-review week
comparisons are weekday-dependent; fixtures target the fixed Friday test
reference and read best seeded Wed–Sun (documented in the generator).
**Tagging (backward compatible):** seeded documents are the exact
WorkoutModel.toMap shape plus optional `isDemo: true`, `demoScenario`,
`demoBatchId`, `demoGeneratedAt` (ISO-8601 string, identical across the
adapter and REST paths). `fromMap` ignores unknown fields; production
documents never need them; no required-format change.
**Idempotency:** deterministic ids (`demo-<scenario>-<NN>`) PLUS
delete-own-batch-before-write — reseeding replaces the batch even if a
future fixture version shrinks, and can never duplicate.
**Cleanup safety:** selection (`selectDemoDocuments`, shared by both
paths) requires strict `isDemo == true` (a `'true'` string or other truthy
value does NOT count — when in doubt, not demo data); batch-scoped unless
the caller explicitly asks for all; normal documents are counted in the
summary and structurally undeletable by the tooling. Dry-run supported in
CLI and seeder.
**CLI (D4 executed):** `tool/seed_data.dart` rewritten as a thin dart:io/
REST shell over the pure modules. The old hard-coded web API key is gone —
and was never in git history (the old tool was untracked). Config via
`GYMCONNECT_FIREBASE_API_KEY` / `GYMCONNECT_FIREBASE_PROJECT_ID` (+
optional email/password env for scripts); missing config fails with the
usage text. Every mutating command prints project/user/counts and demands
a typed "yes" unless `--yes`. Output uses `stdout`/`stderr.writeln`, which
also cleared the 8 `avoid_print` infos — the analyzer baseline is now
**0 issues** (improvement, not suppression: no lints were disabled).
**Debug-only in-app controls (D2 executed, implemented not deferred):**
More gains a Developer section gated by the compile-time `kDebugMode`
const (tree-shaken from release builds), opening `DemoToolsScreen` — same
generator/tags/selection via `DemoSeeder` over the FirestoreAdapter,
confirmation dialogs showing project+user, and a `workoutDataVersion` bump
so Dashboard/Progress/Review refresh immediately.
**Known limitations (documented, accepted):** seeding does not update the
stored personalRecords map or the leaderboard (dashboards read history so
every analytics feature works; the profile PR map keeps only real lifts);
CLI-seeded data needs pull-to-refresh/restart in a running app; demo
fields' interaction with security rules is Phase 10 scope (rules must not
treat them specially).

## 2026-07-04 — Phase 8: weekly coaching review and narrator boundary

**Model/service:** typed `WeeklyReview` (findings in three sections +
suggested actions, each REQUIRING non-empty `EvidenceItem` lists — asserted
in the constructors) produced by pure `WeeklyReviewService.build(workouts,
referenceDate, skippedRecords)`. **Reuse over recomputation:** the review
consumes `DashboardService.build` for weekly activity/volume/top
exercises/data quality, the (newly public) `personalRecordsIn` for records
over the review week, and the same `ExerciseAnalyticsService`/
`PlateauDetector` calls the dashboard makes — the two screens cannot
disagree on a number. Documented thresholds: ±10% volume stable band,
±0.5-star feel change, ≥2 rated sessions per weekly feel average, low-feel
≤2.5 stars, <5 total workouts = insufficient history (dashboard's
getting-started boundary).
**Cautious-by-construction actions:** a closed `SuggestedActionKind` enum
(maintain / log more / review recovery+technique / consider volume review /
keep logging feel); every action inherits the evidence of the finding that
triggered it; regression advice carries "not medical advice"; the maintain
action is withheld whenever any plateau/regression finding exists. Feel is
session-wide and never attributed to an exercise; sparse feel is stated as
insufficient, never extrapolated.
**Narrator boundary:** `ReviewNarrator.narrate(review, weightUnit:)`
returning `ReviewNarration` with lists PARALLEL to the typed lists, so the
UI pairs prose with typed severity/evidence. `TemplateReviewNarrator`
(deterministic, fixed template per kind, no UI/clock/network access) is the
default and only shipped implementation. A future LLM narrator would
implement the same interface under the same only-rephrase contract; no API
client, key or network code was added, and none may be required for the app
to function (spec integrity constraint).
**Navigation:** Weekly Review added as the fourth destination exactly as
the Phase 5 design anticipated (one spec + one widget in `AppShell`; More
moves to index 3 — no code referenced the old index). The bar label is
**"Review"** (screen AppBar reads "Weekly Review") so four labels fit
narrow devices without truncation — flagged for user review as a naming
choice.
**RecommendationService (backlog #14 final):** option "keep as legacy
helper" chosen. `suggestNextWorkout` (last-workout keyword heuristic) and
`generate`'s balance branch were NOT integrated into the review: keyword
muscle-group matching cannot carry typed evidence and would dilute the
review's evidence bar. `generate` continues to power the dashboard card
(balance/keep-going branches only) unchanged; `suggestNextWorkout` remains
implemented, tested and unrendered — deletion deferred to Phase 11 cleanup
if still unused. String-only recommendations stay out of the review model.
**Screen:** same loader-injection, `workoutDataVersion`-listening,
last-known-data-on-refresh-failure pattern as the dashboard (deliberately
duplicated ~30 lines rather than extracting a shared loader mixin now —
three screens share the shape; extraction reconsidered in Phase 11 where
refactoring is in scope).

## 2026-07-04 — Phase 7: explainable exercise analytics

**Model/service:** typed `ExerciseDetail` (+`RecentBest`) produced by pure
`ExerciseAnalyticsService.analyseExercise`; 28-day recent vs prior-28-day
baseline windows; structured `EvidenceItem`s retained on the result — prose
built only in the UI. Diagnosis presentation adapter: the existing
`PlateauDiagnosisService` output is shown as "Possible explanation"
("Likely Cause" retired); no diagnosis rewrite — a fuller insight domain
waits for Phase 8.
**UI:** Progress reworked into one scrollable analytics page (selector →
strength-trend status card → metric grid → chart → EvidencePanel → possible
explanation → history). Old plateau/diagnosis banners replaced by strictly
richer equivalents; chart and history behaviour preserved; `fl_chart`
untouched. Injectable loader (like the dashboard) makes the screen
Firebase-free testable; the delete flow constructs services lazily.
Profile-load failure now degrades to "no goal card" instead of failing the
whole screen (aligned with the dashboard's partial-data policy).
**Preselection:** implemented via `progressExerciseRequest` ValueNotifier —
dashboard "Most trained" rows are tappable and switch to the Progress tab
with the exercise filtered; the Progress screen consumes and clears the
request. No navigation-structure change.
**Extractions:** `widgets/evidence_panel.dart` (reused by Phase 8); other
sections remain private builders — no extraction done purely for line
count.

---

## Historical decisions (reconstructed at Phase 0)

- *(historical)* **Weights stored in kg** everywhere; converted only for
  display. `weightUnit` preference stored in both SharedPreferences (fast
  startup) and the profile document.
- *(historical)* **Epley with rep cap 10** (`fitness_formulas.dart`) to avoid
  high-rep overestimation; one best e1RM per exercise per session day for
  trend analysis.
- *(historical)* **Plateau detector:** WLS regression, decay 0.85, minimum 5
  sessions (raised from 3), scale-invariant thresholds ±0.1%/day.
- *(historical)* **Diagnosis rules** return the single highest-confidence
  finding; require ≥ 4 sessions; warm-up-only sessions excluded.
- *(historical)* **"Volume Progressing"** state suppresses plateau diagnosis
  when session volume trends upward despite flat e1RM.
- *(historical)* **Leaderboard is trust-based** (self-reported lifts, no
  verification); per-user anonymity flag rendered client-side.
- *(historical)* **Fixed gym list** at onboarding so users at the same gym
  share an identical `gymId` string.
- *(historical)* **Warm-up sets** (max one per exercise) excluded from PRs,
  charts and analytics.
- *(historical)* **No state-management package**; `ValueNotifier` globals for
  theme and unit; manual `Navigator.push`.
- *(historical)* `google-services.json` / `firebase_options.dart` gitignored
  (README ships them for dissertation submission outside git).
