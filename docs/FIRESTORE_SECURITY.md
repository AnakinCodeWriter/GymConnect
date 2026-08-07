# GymConnect — Firestore Security

Status (2026-07-05, Phase 10): **rules are authored in this repository
(`firestore.rules`), fully emulator-tested (33/33 passing), and NOT
deployed.** The live project (`gymconnect-77806`) still runs whatever rules
its console holds; deployment is a manual, explicitly-authorised step (D5)
— see the checklist at the bottom.

## Implemented access model (`firestore.rules`)

Everything under `users/{uid}` belongs to exactly one user; the leaderboard
is shared within a gym; everything else is denied by default (no matching
rule = deny).

| Path | Read | Create/Update | Delete |
|---|---|---|---|
| `users/{uid}` | owner only | owner only, validated | nobody (no client flow deletes profiles) |
| `users/{uid}/workouts/{id}` | owner only | owner only, validated | owner only |
| `users/{uid}/templates/{id}` | owner only | owner only, validated | owner only |
| `gyms/{gymId}/leaderboard/{uid}` | authenticated members of that gym only | own entry only, own gym only, validated | nobody (no client flow deletes entries) |
| anything else | denied | denied | denied |

Gym membership = the caller's own `users/{uid}.gymId` equals the gym
segment of the path (one `get()` per evaluation). Consequence: a signed-in
user with no profile document cannot touch any leaderboard — consistent
with the app, where ProfileGate guarantees a profile before the shell.

### What the rules validate (and what stays flexible)

Validated on every write (post-merge document state):

- **Profiles**: `displayName` string, `gymId` string, `createdAt`
  timestamp required; optional fields type-checked when present
  (`isAnonymous` bool, `experienceLevel`/`fitnessGoal`/`goalExercise`/
  `weightUnit` strings, `goalTargetWeight` number, `personalRecords` map).
  Unknown extra fields are tolerated (backward-compatible evolution).
- **Workouts**: `date` timestamp and `exercises` list required; optional
  `name` string, `feelRating` int 1–5; Phase 9 demo fields type-checked
  when present (`isDemo` bool, `demoScenario`/`demoBatchId`/
  `demoGeneratedAt` strings) and **grant no access whatsoever**. Unknown
  extra fields tolerated. Set/rep internals are NOT deep-validated —
  rules enforce ownership and shape, not truth (lifts are self-reported
  by product decision).
- **Templates**: `name` string and `exercises` list required.
- **Leaderboard entries**: field set is **closed**
  (`displayName`/`isAnonymous`/`bestLifts` only — these documents are
  cross-user readable, so no unexpected fields are accepted);
  `displayName` string and `isAnonymous` bool required, `bestLifts` a map
  when present; **anonymity invariant**: `isAnonymous == true` requires
  `displayName == 'Anonymous'`. Individual `bestLifts` values are not
  per-entry type-checked (rules cannot iterate map values — documented
  gap; the client already skips malformed entries on read).

## Leaderboard anonymity design (Phase 10)

**Why rules alone cannot fix anonymity:** Firestore rules grant or deny
access to WHOLE documents — they cannot redact a field from a readable
document. Since every gym member may read every entry in their gym, an
anonymous entry must simply never *contain* the real display name.

Safe-to-expose fields on a leaderboard document: `bestLifts` (self-reported
numbers), `isAnonymous`, and `displayName` **only when it is either the
user's chosen public name (not anonymous) or the literal safe value
`Anonymous`**. The document id is the owner's uid — an opaque identifier
that does not reveal the display name (accepted).

`LeaderboardService` (changed in Phase 10) now guarantees this at the
write path, and the rules enforce it as a backstop:

- `updateUserBestLifts` stores `'Anonymous'` instead of the real name
  whenever the user is anonymous;
- `setAnonymous(..., displayName:)` — toggling ON overwrites the readable
  name with `'Anonymous'`; toggling OFF restores the profile display name
  (which the caller legitimately holds);
- `updateDisplayName` (profile rename sync) no-ops while the entry is
  anonymous, so a rename can never leak onto an anonymous entry;
- UI hiding still exists but is no longer the enforcement mechanism.

**Historical limitation (accepted, not migrated):** entries written before
Phase 10 while anonymous may still hold a real `displayName`. They are
corrected by the owner's next write (any workout save or anonymity
toggle). No bulk rewrite of live data is performed; if any such documents
remain, cleanup belongs to the Phase 12 migration tooling.

## Local emulator testing

Harness: `test_rules/` — Node's built-in test runner +
`@firebase/rules-unit-testing` against the Firestore emulator, using the
offline `demo-gymconnect` project id (no live credentials, no network
project access, nothing to deploy).

Requirements: Node 18+, `firebase-tools`, and a **JDK 21+** on the path
(firebase-tools ≥ 15 refuses older JVMs). On a machine with Android
Studio, its bundled JBR works:

```powershell
# one-time
npm --prefix test_rules install

# run the security suite (PowerShell)
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
npm --prefix test_rules test
```

Suite contents (33 tests, all passing 2026-07-05): unauthenticated denial
everywhere; profile own-CRUD vs cross-user denial and malformed-write
denial; workout own-CRUD, cross-user get/list/write denial, demo-field
typing and no-privilege checks, feelRating bounds; template own-CRUD and
denial; leaderboard own-gym read/write, wrong-gym and wrong-owner denial,
anonymity invariant in both directions (including the exact merge shapes
`LeaderboardService` writes, and the pre-Phase-10 flag-only toggle shape
being rejected), closed field set, no-profile denial; deny-by-default for
unknown top-level and nested paths and for `gyms/{gymId}` documents.

## Known limitations

- Leaderboard values are self-reported; no verification (trust-based by
  product decision — accepted).
- Pre-Phase-10 anonymous entries may hold a real name until the owner's
  next write (see above; Phase 12 migration).
- `bestLifts` map values are not per-value type-checked by rules.
- Firebase Auth email/password without email verification.
- The emulator suite tests rules behaviour, not the live console rules;
  until deployment the live project remains on its console-managed rules.

## Deployment — MANUAL ONLY (not performed)

**No deployment has been performed in any phase.** Nothing in this
repository's tooling, tests or CI may deploy rules or modify the live
project automatically.

Pre-deployment checklist:

1. Run the emulator suite: `npm --prefix test_rules test` — must be 33/33.
2. Run the Flutter suite: `flutter test` — the leaderboard anonymity unit
   tests must pass (the app must be on the Phase 10+ write paths BEFORE
   the rules go live, or pre-Phase-10 builds' flag-only anonymity toggles
   would be rejected by the anonymity invariant).
3. In the Firebase console, copy the CURRENT live rules somewhere safe for
   rollback.
4. Verify no other clients (e.g. old seed tools) rely on write shapes the
   rules now reject.
5. Deploy from an authorised machine, with explicit project-owner
   permission:

   ```
   firebase deploy --only firestore:rules --project gymconnect-77806
   ```

6. Smoke-test with a real account: profile read, workout save, template
   save, leaderboard read/toggle — plus one cross-user read attempt from a
   second account to confirm denial.

Compatibility assumptions: all app write paths as of Phase 10 satisfy the
rules (emulator tests replicate their exact shapes); documents created
before Phase 10 are unaffected until next written, at which point the
post-merge state must validate (all current app flows produce compliant
post-merge states).
