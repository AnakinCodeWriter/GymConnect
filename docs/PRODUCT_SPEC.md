# GymConnect — Product Specification

Status: living document. Sections are explicitly marked **Current** (implemented and
working in this repository today) or **Planned** (approved upgrade to
"GymConnect Coach", not yet implemented).

Last updated: 2026-07-04 (Phase 9).

## Product summary

GymConnect is an Android-focused Flutter strength-training tracker built as a
final-year BSc Computer Science dissertation project (Bournemouth University).
Its differentiator is **plateau detection with rule-based root-cause diagnosis**:
the app flags when an exercise's estimated 1RM trend has flattened or reversed
and offers a possible explanation derived from the user's own training data.

The approved upgrade turns the prototype into **GymConnect Coach**, a
portfolio-quality strength-training analytics application with a training
dashboard, richer exercise analytics, a deterministic weekly coaching review,
and explainable, evidence-backed recommendations.

## Current features (implemented)

### Accounts and profile
- Email/password registration and login (Firebase Authentication).
- Onboarding: display name + gym selection (fixed gym list, shared `gymId`).
- Profile: display name, experience level, primary goal, kg/lbs unit toggle
  (persisted to SharedPreferences and Firestore), lifetime total weight lifted,
  single training goal (exercise + target weight) with progress bars.

### Workout logging
- Multiple exercises per workout; multiple sets per exercise; weight + reps.
- Exercise-name autocomplete and "recent exercises" chips from history.
- Warm-up set flag (max one per exercise; excluded from analytics and PRs).
- Optional session name; 1–5 star session "feel" rating (skippable).
- Repeat last workout; load from saved template (prefilled from last actual
  performance); progressive-overload hint per exercise; post-save total-volume
  dialog; unsaved-work discard confirmation.

### History and progress
- Workout history grouped by session (expandable cards, feel icon, per-set
  e1RM, set deletion with PR recalculation).
- Exercise filter (text + chips).
- Estimated 1RM line chart per exercise (fl_chart, best e1RM per calendar day).
- Plateau banner: Progressing / Plateau / Regressing / Not enough data, plus a
  "Volume Progressing" state when e1RM is flat but session volume is rising.
- Plateau diagnosis ("Likely Cause") banner on plateau/regression.

### Insights
- Home-screen recommendation card (rule-based: get started / plateau advice /
  balance training / keep going).
- Feel insight card (low-feel streak, feel↔performance correlation, best
  training day of week).

### Social
- Gym leaderboard: best e1RM per exercise ranked across users at the same gym,
  with per-user anonymity toggle. Trust-based (no verification of entries).

### Other
- Personal records per exercise (best e1RM, warm-ups excluded).
- Up to 5 custom workout templates.
- Hardcoded beginner starter plans.
- Dark mode.

### Developer tooling (reworked Phase 9)
- `tool/seed_data.dart`: safe CLI over the pure demo generator
  (`lib/demo/`). Commands: `list-scenarios`, `seed --scenario <key>`,
  `cleanup --batch <id> | --all`, `inspect`; `--dry-run` and `--yes`
  supported. Configuration comes from environment variables
  (`GYMCONNECT_FIREBASE_API_KEY`, `GYMCONNECT_FIREBASE_PROJECT_ID`,
  optional `GYMCONNECT_DEMO_EMAIL`/`_PASSWORD`) — no committed keys; the
  target project/user and exact counts are always shown and writes/deletes
  require confirmation. Seeding is idempotent per scenario batch
  (deterministic ids + replace-own-batch); cleanup deletes only documents
  tagged `isDemo: true`.
- Debug builds only: More → Developer → Demo Data offers the same
  scenarios/cleanup in-app (confirmation dialogs, tagged writes, refresh
  via `workoutDataVersion`). The entry is gated on the compile-time
  `kDebugMode` constant and cannot appear in release builds.

## Planned features (approved, not yet implemented)

See docs/BACKLOG.md for the phase plan. Summary of the target product:

1. **Navigation shell** — DELIVERED (Phase 5; extended Phase 8): Material 3
   bottom NavigationBar with Dashboard, Progress, Weekly Review (bar label
   "Review") and More (leaderboard, templates, starter plans, profile, dark
   mode and sign-out live under More; Log Workout stays on the Dashboard).
2. **Training dashboard** — DELIVERED (Phase 6): workouts completed this
   week, weekly volume with safe week-over-week change, most-trained
   exercises (28 days), recent personal records (14 days, from history),
   evidence-backed possible-plateau/regression warnings, a deterministic
   training-status summary and a categorical data-quality indicator. Every
   value calculated from stored workout data; unavailable comparisons are
   shown as unavailable, never invented.
3. **Exercise analytics** — DELIVERED (Phase 7): e1RM trend, volume trend,
   training frequency, recent best with date, percentage change over
   documented 28-day windows, plateau status in plain English, an
   expandable "Why am I seeing this?" evidence panel showing exactly which
   calculations produced the classification, and a "Possible explanation"
   card grounded in the diagnosis rules. Wellness context appears via the
   dashboard feel-insight card; per-review wellness context arrives with
   the Phase 8 weekly review.
4. **Weekly coaching review** — DELIVERED (Phase 8): deterministic,
   rule-based structured review of the Monday–Sunday week: what improved,
   what stayed stable, what may need attention and cautious suggested next
   steps — every conclusion backed by typed evidence and a categorical
   data-quality indicator, with session-wide feel context (never presented
   as exercise-specific) and explicit insufficient-data statements instead
   of invented trends. A `ReviewNarrator` abstraction converts the typed
   review into copy; the deterministic template narrator is the only
   shipped implementation. An optional future LLM narrator could *rephrase*
   the deterministic report behind the same interface; the app remains
   fully functional without any external AI service, and a narrator may
   never invent measurements, diagnoses or recommendations.
5. **Explainable recommendations** — typed metric/evidence/recommendation
   structures throughout; no recommendation without supporting evidence.
6. **Demo-data mode** — DELIVERED (Phase 9): five deterministic scenarios
   (progressing incl. PR events and improving feel, plateau with a
   rep-monotony explanation, regression with declining feel, volume
   progression with sparse feel, insufficient data) engineered against the
   documented analytics thresholds and verified by tests. Available via the
   CLI and debug-build-only in-app controls; idempotent per batch, tagged
   `isDemo: true`, safe cleanup (tagged data only), explicit confirmation,
   never touches normal user data.
7. **UX and reliability** — consistent components and spacing, loading /
   empty / error / offline / insufficient-data states, accessibility, no
   overflow, no misleading charts.

## Non-goals and integrity constraints

- No medical claims; recommendations are training suggestions, not
  professional or medical advice.
- Plateau diagnoses are presented as *possible explanations*, never proven
  causes.
- No paid backend requirement; no dependency on temporary LLM API access; no
  secrets committed to the repository.
- No fabricated metrics: every displayed number must trace to stored workout
  data and a documented calculation (see docs/ANALYTICS_DEFINITIONS.md).
- Android is the primary platform.

## Users

- Primary: the student (developer/demonstrator) and dissertation assessors.
- Modelled end user: beginner-to-intermediate gym-goers who want plain-English
  feedback on whether their training is working.
