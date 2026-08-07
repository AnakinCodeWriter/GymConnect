// Argument parsing and configuration for tool/migrate_data.dart (Phase 12).
// Pure Dart (no dart:io) so every safety rule is unit-testable.
//
// Safety posture, deliberately stricter than the demo CLI: this tool
// touches REAL user records, so it is READ-ONLY unless `--apply` is passed
// (there is no "accidentally wrote" path), and `--apply` still requires a
// typed confirmation unless `--yes` is given. It never deletes anything.

/// Environment variables. The API key and project id are configuration,
/// never committed constants; credentials may be supplied for
/// non-interactive use or entered at the prompt.
const String envApiKey = 'GYMCONNECT_FIREBASE_API_KEY';
const String envProjectId = 'GYMCONNECT_FIREBASE_PROJECT_ID';
const String envEmail = 'GYMCONNECT_ACCOUNT_EMAIL';
const String envPassword = 'GYMCONNECT_ACCOUNT_PASSWORD';

const String migrationUsage =
    '''
GymConnect stored-value migration (opt-in, idempotent, never automatic).

Corrects values written before the formula/anonymity fixes:
  * personal records and leaderboard bests computed with the old uncapped
    formula (and, on the leaderboard, including warm-up sets)
  * leaderboard entries that still store a real display name while marked
    anonymous (pre-Phase-10 entries)

Usage: dart run tool/migrate_data.dart <command> [options]

Commands:
  inspect            Report what is stale. Always read-only.
  fix-records        Correct users/{uid}.personalRecords.
  fix-leaderboard    Correct this user's leaderboard bests + anonymous name.
  fix-all            Both of the above.

Options:
  --apply   Actually write. WITHOUT IT EVERY COMMAND IS A DRY RUN.
  --yes     Skip the typed confirmation (for scripts). Requires --apply.

Configuration (environment variables):
  $envApiKey    Firebase Web API key (Project settings > General).
  $envProjectId Firebase project id (e.g. my-project-id).
  $envEmail   Optional: account email (otherwise prompted).
  $envPassword   Optional: account password (otherwise prompted).

Safety:
  * Nothing is ever deleted; only stored values are corrected.
  * Only the signed-in user's own records are touched.
  * Records for exercises with no logged history are reported, never
    written.
  * Re-running after a successful apply reports no changes (idempotent).
  * The target project and account are printed before any write.
''';

/// What a command is allowed to touch.
enum MigrationTarget { personalRecords, leaderboard, both }

sealed class MigrationCommand {
  const MigrationCommand();
}

/// Read-only report; `--apply` is meaningless here and rejected.
class InspectCommand extends MigrationCommand {
  const InspectCommand();
}

class FixCommand extends MigrationCommand {
  final MigrationTarget target;

  /// False = dry run (the default). Writes happen only when true.
  final bool apply;

  /// Skips the typed confirmation; only meaningful with [apply].
  final bool assumeYes;

  const FixCommand({
    required this.target,
    required this.apply,
    required this.assumeYes,
  });

  bool get touchesRecords =>
      target == MigrationTarget.personalRecords ||
      target == MigrationTarget.both;

  bool get touchesLeaderboard =>
      target == MigrationTarget.leaderboard || target == MigrationTarget.both;
}

/// A parse failure with a user-facing message; the tool prints it plus
/// [migrationUsage] and exits non-zero without contacting anything.
class MigrationParseError extends MigrationCommand {
  final String message;

  const MigrationParseError(this.message);
}

MigrationCommand parseMigrationArguments(List<String> args) {
  if (args.isEmpty) return const MigrationParseError('No command given.');

  final command = args.first;
  var apply = false;
  var assumeYes = false;
  var dryRunRequested = false;

  for (final arg in args.sublist(1)) {
    switch (arg) {
      case '--apply':
        apply = true;
      case '--yes':
        assumeYes = true;
      case '--dry-run':
        // Accepted because the demo CLI has the flag; here it only names
        // the default. Combined with --apply it is contradictory, so the
        // safe reading (refuse and let the user restate) wins.
        dryRunRequested = true;
      default:
        return MigrationParseError('Unknown option "$arg".');
    }
  }

  if (dryRunRequested && apply) {
    return const MigrationParseError(
      '--dry-run and --apply contradict each other. Dry run is the default; '
      'pass --apply only when you intend to write.',
    );
  }

  if (assumeYes && !apply) {
    return const MigrationParseError(
      '--yes only makes sense with --apply (nothing is written without it).',
    );
  }

  switch (command) {
    case 'inspect':
      if (apply) {
        return const MigrationParseError(
          'inspect is always read-only; use fix-records, fix-leaderboard or '
          'fix-all with --apply to write.',
        );
      }
      return const InspectCommand();
    case 'fix-records':
      return FixCommand(
        target: MigrationTarget.personalRecords,
        apply: apply,
        assumeYes: assumeYes,
      );
    case 'fix-leaderboard':
      return FixCommand(
        target: MigrationTarget.leaderboard,
        apply: apply,
        assumeYes: assumeYes,
      );
    case 'fix-all':
      return FixCommand(
        target: MigrationTarget.both,
        apply: apply,
        assumeYes: assumeYes,
      );
    default:
      return MigrationParseError('Unknown command "$command".');
  }
}

/// Validated configuration (never committed; see [migrationUsage]).
class MigrationConfig {
  final String apiKey;
  final String projectId;
  final String? email;
  final String? password;

  const MigrationConfig({
    required this.apiKey,
    required this.projectId,
    this.email,
    this.password,
  });
}

/// Reads configuration from [environment]. Returns either a config or the
/// list of missing REQUIRED variable names (credentials stay optional -
/// the CLI prompts for them).
(MigrationConfig?, List<String>) readMigrationConfig(
  Map<String, String> environment,
) {
  String? nonEmpty(String key) {
    final v = environment[key]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final apiKey = nonEmpty(envApiKey);
  final projectId = nonEmpty(envProjectId);
  final missing = [
    if (apiKey == null) envApiKey,
    if (projectId == null) envProjectId,
  ];
  if (missing.isNotEmpty) return (null, missing);
  return (
    MigrationConfig(
      apiKey: apiKey!,
      projectId: projectId!,
      email: nonEmpty(envEmail),
      password: nonEmpty(envPassword),
    ),
    const [],
  );
}
