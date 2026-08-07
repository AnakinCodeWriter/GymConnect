// CLI argument parsing and configuration rules for tool/seed_data.dart
// (Phase 9). Pure Dart (no dart:io) so the parsing/planning logic is unit
// tested without touching Firebase or the local environment.

import 'demo_fixtures.dart';

/// Environment variables the CLI reads. The web API key and project id are
/// configuration, not committed constants; credentials may be supplied via
/// env for non-interactive use or entered at the prompt.
const String envApiKey = 'GYMCONNECT_FIREBASE_API_KEY';
const String envProjectId = 'GYMCONNECT_FIREBASE_PROJECT_ID';
const String envEmail = 'GYMCONNECT_DEMO_EMAIL';
const String envPassword = 'GYMCONNECT_DEMO_PASSWORD';

const String cliUsage =
    '''
GymConnect demo-data CLI (seeds clearly-tagged, reversible demo workouts).

Usage: dart run tool/seed_data.dart <command> [options]

Commands:
  list-scenarios                     Show every scenario with its workout count.
  seed --scenario <key>              Replace that scenario's demo batch for the
                                     signed-in user (idempotent).
  cleanup --batch <key> | --all      Delete tagged demo workouts only.
  inspect                            List the user's demo documents by batch.

Options:
  --scenario <key>   Scenario to seed (see list-scenarios).
  --batch <id>       Batch id to seed into / clean up (default: scenario key).
  --all              Cleanup: remove ALL demo batches for the user.
  --dry-run          Show what would be written/deleted; change nothing.
  --yes              Skip the interactive confirmation (for scripts).

Configuration (environment variables):
  $envApiKey    Firebase Web API key (Project settings > General).
  $envProjectId Firebase project id (e.g. my-project-id).
  $envEmail      Optional: account email (otherwise prompted).
  $envPassword   Optional: account password (otherwise prompted).

Safety: only documents tagged isDemo:true are ever deleted; normal workouts
are never touched. Every write/delete shows the target project, user and
counts, and requires confirmation unless --yes is passed.
''';

sealed class CliCommand {
  const CliCommand();
}

class ListScenariosCommand extends CliCommand {
  const ListScenariosCommand();
}

class SeedCommand extends CliCommand {
  final DemoScenario scenario;
  final String batchId;
  final bool dryRun;
  final bool assumeYes;

  const SeedCommand({
    required this.scenario,
    required this.batchId,
    required this.dryRun,
    required this.assumeYes,
  });
}

class CleanupCommand extends CliCommand {
  /// Null means ALL demo batches — only reachable via an explicit --all.
  final String? batchId;
  final bool dryRun;
  final bool assumeYes;

  const CleanupCommand({
    required this.batchId,
    required this.dryRun,
    required this.assumeYes,
  });
}

class InspectCommand extends CliCommand {
  const InspectCommand();
}

/// A parse failure with a user-facing message; the CLI prints it plus
/// [cliUsage] and exits non-zero without contacting anything.
class CliParseError extends CliCommand {
  final String message;

  const CliParseError(this.message);
}

CliCommand parseCliArguments(List<String> args) {
  if (args.isEmpty) return const CliParseError('No command given.');

  final command = args.first;
  final rest = args.sublist(1);

  String? scenarioKey;
  String? batchId;
  var all = false;
  var dryRun = false;
  var assumeYes = false;

  for (var i = 0; i < rest.length; i++) {
    switch (rest[i]) {
      case '--scenario':
        if (i + 1 >= rest.length) {
          return const CliParseError('--scenario needs a value.');
        }
        scenarioKey = rest[++i];
      case '--batch':
        if (i + 1 >= rest.length) {
          return const CliParseError('--batch needs a value.');
        }
        batchId = rest[++i];
      case '--all':
        all = true;
      case '--dry-run':
        dryRun = true;
      case '--yes':
        assumeYes = true;
      default:
        return CliParseError('Unknown option "${rest[i]}".');
    }
  }

  switch (command) {
    case 'list-scenarios':
      return const ListScenariosCommand();
    case 'inspect':
      return const InspectCommand();
    case 'seed':
      if (scenarioKey == null) {
        return const CliParseError('seed requires --scenario <key>.');
      }
      final scenario = DemoScenarioInfo.fromKey(scenarioKey);
      if (scenario == null) {
        return CliParseError(
          'Unknown scenario "$scenarioKey". Run list-scenarios.',
        );
      }
      return SeedCommand(
        scenario: scenario,
        batchId: batchId ?? scenario.key,
        dryRun: dryRun,
        assumeYes: assumeYes,
      );
    case 'cleanup':
      if (all && batchId != null) {
        return const CliParseError('Use either --batch <id> or --all.');
      }
      if (!all && batchId == null) {
        return const CliParseError(
          'cleanup requires --batch <id>, or --all to remove every '
          'demo batch.',
        );
      }
      return CleanupCommand(
        batchId: all ? null : batchId,
        dryRun: dryRun,
        assumeYes: assumeYes,
      );
    default:
      return CliParseError('Unknown command "$command".');
  }
}

/// Validated CLI configuration (never committed; see [cliUsage]).
class CliConfig {
  final String apiKey;
  final String projectId;
  final String? email;
  final String? password;

  const CliConfig({
    required this.apiKey,
    required this.projectId,
    this.email,
    this.password,
  });
}

/// Reads configuration from [environment]. Returns either a [CliConfig] or
/// the list of missing REQUIRED variable names (email/password stay
/// optional — the CLI prompts for them).
(CliConfig?, List<String>) readCliConfig(Map<String, String> environment) {
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
    CliConfig(
      apiKey: apiKey!,
      projectId: projectId!,
      email: nonEmpty(envEmail),
      password: nonEmpty(envPassword),
    ),
    const [],
  );
}
