// Unit tests for the migration CLI's parsing and configuration rules
// (Phase 12). These pin the safety posture: read-only by default, writes
// only behind an explicit --apply, and no contradictory combinations.

import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/migration/migration_cli.dart';

void main() {
  group('parseMigrationArguments', () {
    test('no arguments is a usage error', () {
      expect(parseMigrationArguments([]), isA<MigrationParseError>());
    });

    test('unknown commands and options are rejected', () {
      expect(parseMigrationArguments(['wipe']), isA<MigrationParseError>());
      expect(
        parseMigrationArguments(['fix-all', '--force']),
        isA<MigrationParseError>(),
      );
    });

    test('inspect is read-only', () {
      expect(parseMigrationArguments(['inspect']), isA<InspectCommand>());
    });

    test('inspect refuses --apply rather than silently writing', () {
      final result = parseMigrationArguments(['inspect', '--apply']);
      expect(result, isA<MigrationParseError>());
      expect((result as MigrationParseError).message, contains('read-only'));
    });

    test('fix commands default to a dry run', () {
      for (final name in ['fix-records', 'fix-leaderboard', 'fix-all']) {
        final result = parseMigrationArguments([name]);
        expect(result, isA<FixCommand>(), reason: name);
        expect((result as FixCommand).apply, isFalse, reason: name);
      }
    });

    test('--apply enables writing', () {
      final result =
          parseMigrationArguments(['fix-all', '--apply']) as FixCommand;
      expect(result.apply, isTrue);
      expect(result.assumeYes, isFalse);
    });

    test('--yes without --apply is refused (it would imply a write)', () {
      final result = parseMigrationArguments(['fix-all', '--yes']);
      expect(result, isA<MigrationParseError>());
    });

    test('--yes with --apply skips the confirmation', () {
      final result =
          parseMigrationArguments(['fix-all', '--apply', '--yes'])
              as FixCommand;
      expect(result.assumeYes, isTrue);
    });

    test('--dry-run with --apply is a contradiction, not a silent winner', () {
      final result = parseMigrationArguments([
        'fix-all',
        '--dry-run',
        '--apply',
      ]);
      expect(result, isA<MigrationParseError>());
    });

    test('--dry-run alone is accepted as naming the default', () {
      final result =
          parseMigrationArguments(['fix-all', '--dry-run']) as FixCommand;
      expect(result.apply, isFalse);
    });

    test('targets map to the right scopes', () {
      final records = parseMigrationArguments(['fix-records']) as FixCommand;
      expect(records.touchesRecords, isTrue);
      expect(records.touchesLeaderboard, isFalse);

      final board = parseMigrationArguments(['fix-leaderboard']) as FixCommand;
      expect(board.touchesRecords, isFalse);
      expect(board.touchesLeaderboard, isTrue);

      final both = parseMigrationArguments(['fix-all']) as FixCommand;
      expect(both.touchesRecords, isTrue);
      expect(both.touchesLeaderboard, isTrue);
    });
  });

  group('readMigrationConfig', () {
    test('reports every missing required variable', () {
      final (config, missing) = readMigrationConfig(const {});
      expect(config, isNull);
      expect(missing, [envApiKey, envProjectId]);
    });

    test('blank values count as missing', () {
      final (config, missing) = readMigrationConfig({
        envApiKey: '   ',
        envProjectId: 'p',
      });
      expect(config, isNull);
      expect(missing, [envApiKey]);
    });

    test('credentials are optional and trimmed', () {
      final (config, missing) = readMigrationConfig({
        envApiKey: ' key ',
        envProjectId: ' project ',
        envEmail: ' me@example.com ',
      });
      expect(missing, isEmpty);
      expect(config!.apiKey, 'key');
      expect(config.projectId, 'project');
      expect(config.email, 'me@example.com');
      expect(config.password, isNull);
    });

    test('usage documents the safety posture and required variables', () {
      expect(migrationUsage, contains(envApiKey));
      expect(migrationUsage, contains(envProjectId));
      expect(migrationUsage, contains('--apply'));
      expect(migrationUsage, contains('Nothing is ever deleted'));
    });
  });
}
