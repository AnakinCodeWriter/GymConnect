# GymConnect — Stored-value migration

Status: implemented in Phase 12. Executes the migration half of **D3**
(docs/DECISIONS.md) and cleans up the historical anonymity leak documented
in Phase 10 (docs/FIRESTORE_SECURITY.md).

This tool is **opt-in and never runs automatically**. Nothing in the app
invokes it; it is a developer/owner command-line utility.

---

## What is stale, and why

Two independent groups of stored values can disagree with what the app
would compute today.

### 1. Values written before the Phase 3 formula fix (D3)

Before Phase 3, `leaderboard_service.dart` and `recommendation_service.dart`
each inlined their own **uncapped** Epley formula, and the leaderboard
calculation also counted **warm-up sets**. The canonical
`estimatedOneRepMax` caps reps at 10 and every consumer now excludes
warm-ups.

Affected fields:

| Path | Field |
|---|---|
| `users/{uid}` | `personalRecords` (exercise → best e1RM, kg) |
| `gyms/{gymId}/leaderboard/{uid}` | `bestLifts` (exercise → best e1RM, kg) |

Because both the app's PR detection and its leaderboard update only
overwrite a stored value when the newly computed number **beats** it, an
inflated historical value is never corrected by normal use — it stands
until it is beaten or migrated. A 100 kg × 20 rep set, for example, was
once stored as 166.7 kg and is 133.3 kg under the capped formula.

### 2. Leaderboard entries written before the Phase 10 anonymity fix

Security rules cannot redact fields from a readable document, so Phase 10
fixed anonymity at the **write path**: an anonymous entry now stores the
literal display name `Anonymous`. Entries written before that fix may
still hold a real display name while `isAnonymous == true`. Phase 10
deliberately did not rewrite them (no silent bulk edits); this tool does
it explicitly.

An anonymous entry self-heals on the owner's next workout save. The
migration exists for accounts that have not logged since.

---

## Safety model

The tool is deliberately stricter than the demo-data CLI, because it
touches real records rather than clearly-tagged demo data.

- **Read-only by default.** Every command is a dry run unless `--apply` is
  passed. There is no code path that writes without that flag.
- **Typed confirmation.** With `--apply`, the tool prints the target
  project and account and requires the operator to type `yes`, unless
  `--yes` is given for scripted use. `--yes` without `--apply` is rejected.
- **Nothing is ever deleted.** The tool only corrects field values. It has
  no delete call of any kind.
- **Own data only.** It signs in as one user and touches only that user's
  profile and leaderboard entry. The Phase 10 rules enforce this
  independently.
- **Uncertain values are left alone.** A stored record for an exercise
  with no eligible logged history (for example, the workouts were deleted)
  is reported as an *orphan* and carried through untouched — never
  rewritten, never removed.
- **No field-path hazard.** `personalRecords` and `bestLifts` are written
  as complete map fields, so exercise names never become Firestore field
  paths (the dot-notation bug fixed in Phase 1).
- **Idempotent.** Corrections are computed against a tolerance
  (`migrationToleranceKg`, 1e-6 kg), so re-running after a successful
  apply reports "nothing to do" rather than rewriting on floating-point
  noise. This is unit-tested.
- **One formula.** The tool recomputes with the same canonical
  `estimatedOneRepMax` and eligibility rule the app uses — shared via
  `lib/utils/strength_math.dart`, with a test asserting the tool and
  `LeaderboardService.bestEligibleE1RmPerExercise` agree exactly.

### Rules interaction worth knowing

If an entry is anonymous *and* still stores a real name, the Phase 10
rules reject **any** write that leaves that state intact. A bestLifts-only
correction on such an entry would therefore be denied. The planner handles
this: whenever a name leak is present, the display-name fix is written in
the same PATCH. There is a test for it.

---

## Usage

Configuration comes from the environment; no keys are committed.

```
set GYMCONNECT_FIREBASE_API_KEY=<web api key>       # Project settings > General
set GYMCONNECT_FIREBASE_PROJECT_ID=<project id>
set GYMCONNECT_ACCOUNT_EMAIL=<account email>        # optional, else prompted
set GYMCONNECT_ACCOUNT_PASSWORD=<account password>  # optional, else prompted
```

```
# 1. See what is stale. Always read-only.
dart run tool/migrate_data.dart inspect

# 2. Dry run of the corrections (still writes nothing).
dart run tool/migrate_data.dart fix-all

# 3. Apply, with a typed confirmation.
dart run tool/migrate_data.dart fix-all --apply

# 4. Confirm nothing remains.
dart run tool/migrate_data.dart inspect
```

Narrower scopes: `fix-records` (personal records only) and
`fix-leaderboard` (leaderboard bests + anonymous display name only).

### Reading the report

```
Personal records (users/{uid}.personalRecords):
  4 already correct
  2 to correct (2 lowered, 0 raised)
    Bench Press: 166.70 -> 133.30 kg
    Deadlift: 220.00 -> 200.00 kg
  1 record(s) with no logged history - LEFT UNTOUCHED:
    Old Machine Press: 90.00 kg
```

*Lowered* is the expected D3 case (an inflated legacy value). *Raised* is
also possible and legitimate — for example when a PR write failed after a
workout saved — and is reported separately so the two are never confused.

---

## Recommended procedure

1. Run `inspect` and read the report.
2. If it reports orphans you do not recognise, stop and investigate before
   applying; they are left alone either way, but they may indicate data you
   did not expect.
3. Run `fix-all` (dry run) and confirm the plan matches the inspection.
4. Run `fix-all --apply` and type `yes`.
5. Run `inspect` again; it should report no changes.
6. Pull-to-refresh or restart the app to see corrected values (there are no
   realtime listeners by design).

Per-user by design: the tool corrects one signed-in account at a time.
Correcting a whole gym's leaderboard would require privileged access
(Admin SDK / service-account credentials), which this repository
deliberately does not use or store.

---

## What it does not do

- It does not create records the app never wrote. Only exercises already
  present in `personalRecords` / `bestLifts` are considered.
- It does not touch workout documents, templates, profiles (beyond the
  `personalRecords` field) or any other user's data.
- It does not deploy rules, change schemas or delete anything.
- It cannot repair another user's leaderboard entry; each owner runs it for
  their own account.

---

## Tests

- `test/migration_plan_test.dart` — recomputation (warm-up exclusion, rep
  cap, best-across-history), agreement with the app's calculator,
  correction/orphan/unchanged classification, tolerance, idempotency,
  anonymity-leak detection and the combined-write rule.
- `test/migration_cli_test.dart` — read-only default, `--apply` gating,
  rejected flag combinations, configuration validation.

Both run in the normal `flutter test` suite and in CI. The tool's live
behaviour against a real project remains a manual check (see
docs/RELEASE_CHECKLIST.md).
