# GymConnect — Release checklist

Status: added in Phase 12. A manual, repeatable pre-release procedure.

Nothing here is automated, and nothing in this repository deploys, signs
or publishes anything. CI (`.github/workflows/ci.yml`) runs verification
only; rules deployment stays manual (D5).

---

## 1. Verification (automated — must be green)

CI runs all of these on every push and pull request to `main`. Run them
locally before tagging as well:

- [ ] `dart format --output=none --set-exit-if-changed .` — clean
- [ ] `flutter analyze` — **0 issues** (the standing baseline since Phase 9)
- [ ] `flutter test` — all pass; record the exact count
- [ ] `npm --prefix test_rules test` — all pass (needs JDK 21+; Android
      Studio's bundled JBR works — see docs/FIRESTORE_SECURITY.md)

If the rules suite cannot run in the current environment, say so
explicitly in the release notes. Never record unrun tests as passing.

## 2. Secrets and configuration

- [ ] `git status` shows no `lib/firebase_options.dart`,
      `google-services.json`, service-account JSON, `.env`, or
      `test_rules/node_modules/`
- [ ] `git log -p` for this release contains no API key, refresh token or
      password
- [ ] No real user data in fixtures, screenshots or docs
- [ ] `tool/ci/firebase_options_stub.dart` still contains only placeholder
      values

## 3. Manual device checks

On a real device or emulator, signed into a test account:

- [ ] Register → onboarding → dashboard (new account, empty states)
- [ ] Log a multi-exercise workout: chips, autocomplete, add/remove sets,
      warm-up toggle, overload hint, feel rating, volume dialog, PR dialog
- [ ] Repeat last workout; load a template (prefill from last performance)
- [ ] Progress: select an exercise, chart renders, evidence panel expands,
      delete a set and confirm Dashboard/Review refresh
- [ ] Weekly Review: sections render; wording stays cautious ("possible",
      never a proven cause or medical claim)
- [ ] Leaderboard: appears for the gym; toggle anonymity ON — the entry
      shows `Anonymous`; toggle OFF — the real name returns
- [ ] Profile: kg/lbs toggle changes every screen's display; goal saves
- [ ] Airplane mode: initial-load failures show retry; refresh failures
      keep last-known data behind a banner
- [ ] Dark mode and 2× font scale on the main destinations
- [ ] Release build: More → Developer → Demo Data is **absent**
      (`kDebugMode`-gated)

## 4. Data-integrity steps (only if needed)

- [ ] `dart run tool/migrate_data.dart inspect` on the owner account
- [ ] If stale values are reported, follow docs/MIGRATION.md (dry run →
      `--apply` → re-inspect)
- [ ] Remove demo data from any account used for screenshots:
      `dart run tool/seed_data.dart cleanup --all --dry-run`, then without
      `--dry-run`

## 5. Firestore rules deployment (manual only — D5)

Follow the full pre-deployment checklist in docs/FIRESTORE_SECURITY.md.
Summary:

- [ ] Rules suite green locally
- [ ] Diff the deployed console rules against `firestore.rules`
- [ ] Confirm the target project id is correct
- [ ] Deploy manually, from a human's shell, with the command recorded in
      docs/FIRESTORE_SECURITY.md
- [ ] Smoke-test the live app afterwards: read own data, read the gym
      leaderboard, confirm cross-user reads fail

Never automate this and never add it to CI.

## 6. Build and release artefacts

- [ ] Version bumped in `pubspec.yaml`
- [ ] `flutter build apk --release` (or `appbundle`) succeeds
- [ ] Release build launched once on a device and smoke-tested
- [ ] Signing config supplied out-of-band; keystore never committed

## 7. Documentation

- [ ] `docs/TEST_PLAN.md` records the exact counts for this release
- [ ] `docs/BACKLOG.md` reflects what shipped and what deferred
- [ ] `docs/DECISIONS.md` has an entry for any decision made this cycle
- [ ] README setup instructions still work from a clean clone
- [ ] Known limitations in README are current

## 8. Post-release

- [ ] Tag the commit
- [ ] Note in the release entry which checks were run, which were skipped
      and why
- [ ] File anything deferred in docs/BACKLOG.md rather than leaving it
      implicit
