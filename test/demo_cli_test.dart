import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/demo/demo_cli.dart';
import 'package:gymconnect/demo/demo_fixtures.dart';

void main() {
  group('parseCliArguments', () {
    test('no arguments and unknown commands are parse errors', () {
      expect(parseCliArguments([]), isA<CliParseError>());
      expect(parseCliArguments(['frobnicate']), isA<CliParseError>());
    });

    test('list-scenarios and inspect parse without options', () {
      expect(
        parseCliArguments(['list-scenarios']),
        isA<ListScenariosCommand>(),
      );
      expect(parseCliArguments(['inspect']), isA<InspectCommand>());
    });

    test('seed requires a known scenario', () {
      final missing = parseCliArguments(['seed']);
      expect(missing, isA<CliParseError>());
      expect((missing as CliParseError).message, contains('--scenario'));

      final unknown = parseCliArguments(['seed', '--scenario', 'nope']);
      expect(unknown, isA<CliParseError>());
      expect((unknown as CliParseError).message, contains('list-scenarios'));

      final dangling = parseCliArguments(['seed', '--scenario']);
      expect(dangling, isA<CliParseError>());
    });

    test('seed parses scenario, defaults the batch to the scenario key, and '
        'honours flags', () {
      final plain =
          parseCliArguments(['seed', '--scenario', 'plateau']) as SeedCommand;
      expect(plain.scenario, DemoScenario.plateau);
      expect(plain.batchId, 'plateau');
      expect(plain.dryRun, isFalse);
      expect(plain.assumeYes, isFalse);

      final custom =
          parseCliArguments([
                'seed',
                '--scenario',
                'volume-progressing',
                '--batch',
                'stand-b',
                '--dry-run',
                '--yes',
              ])
              as SeedCommand;
      expect(custom.scenario, DemoScenario.volumeProgressing);
      expect(custom.batchId, 'stand-b');
      expect(custom.dryRun, isTrue);
      expect(custom.assumeYes, isTrue);
    });

    test(
      'cleanup requires an explicit scope: --batch or --all, never both',
      () {
        expect(parseCliArguments(['cleanup']), isA<CliParseError>());
        expect(
          parseCliArguments(['cleanup', '--batch', 'a', '--all']),
          isA<CliParseError>(),
        );

        final one =
            parseCliArguments(['cleanup', '--batch', 'plateau'])
                as CleanupCommand;
        expect(one.batchId, 'plateau');

        final all = parseCliArguments(['cleanup', '--all']) as CleanupCommand;
        expect(all.batchId, isNull); // all batches - explicit --all only
      },
    );

    test('--yes is honoured only when explicitly provided', () {
      final without = parseCliArguments(['cleanup', '--all']) as CleanupCommand;
      expect(without.assumeYes, isFalse);
      final withYes =
          parseCliArguments(['cleanup', '--all', '--yes']) as CleanupCommand;
      expect(withYes.assumeYes, isTrue);
    });

    test('unknown options are rejected rather than ignored', () {
      expect(
        parseCliArguments(['seed', '--scenario', 'plateau', '--force']),
        isA<CliParseError>(),
      );
    });
  });

  group('readCliConfig', () {
    test('reports every missing required variable by name', () {
      final (config, missing) = readCliConfig(const {});
      expect(config, isNull);
      expect(missing, [envApiKey, envProjectId]);
    });

    test('whitespace-only values count as missing', () {
      final (config, missing) = readCliConfig(const {
        envApiKey: '  ',
        envProjectId: 'demo-project',
      });
      expect(config, isNull);
      expect(missing, [envApiKey]);
    });

    test('parses full configuration with optional credentials', () {
      final (config, missing) = readCliConfig(const {
        envApiKey: 'key-123',
        envProjectId: 'demo-project',
        envEmail: 'demo@example.com',
        envPassword: 'hunter2',
      });
      expect(missing, isEmpty);
      expect(config!.apiKey, 'key-123');
      expect(config.projectId, 'demo-project');
      expect(config.email, 'demo@example.com');
      expect(config.password, 'hunter2');
    });

    test('credentials stay optional (prompted interactively instead)', () {
      final (config, _) = readCliConfig(const {
        envApiKey: 'key-123',
        envProjectId: 'demo-project',
      });
      expect(config!.email, isNull);
      expect(config.password, isNull);
    });
  });
}
