import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../demo/demo_fixtures.dart';
import '../demo/demo_seeder.dart';
import '../main.dart';
import '../services/firestore_adapter.dart';
import '../theme/app_tokens.dart';
import '../widgets/state_views.dart';
import '../widgets/status_banner.dart';

/// Debug-only demo-data controls (Phase 9). Reached solely through the More
/// screen's Developer section, which exists only when `kDebugMode` is true —
/// release builds compile the entry point away entirely.
///
/// Uses the same generator, tagging and safety rules as the CLI: seeds are
/// idempotent per scenario batch, and cleanup can only ever select
/// documents tagged `isDemo: true`.
///
/// [seeder], [userLabel] and [projectLabel] are injectable so widget tests
/// run without Firebase; production call sites pass nothing.
class DemoToolsScreen extends StatefulWidget {
  final DemoSeeder? seeder;
  final String? userLabel;
  final String? projectLabel;

  const DemoToolsScreen({
    super.key,
    this.seeder,
    this.userLabel,
    this.projectLabel,
  });

  @override
  State<DemoToolsScreen> createState() => _DemoToolsScreenState();
}

class _DemoToolsScreenState extends State<DemoToolsScreen> {
  late final DemoSeeder _seeder =
      widget.seeder ??
      DemoSeeder(
        adapter: FirebaseFirestoreAdapter(),
        uid: FirebaseAuth.instance.currentUser!.uid,
      );

  late final String _userLabel =
      widget.userLabel ?? FirebaseAuth.instance.currentUser!.uid;

  late final String _projectLabel =
      widget.projectLabel ?? Firebase.app().options.projectId;

  bool _busy = false;

  Future<void> _runGuarded(Future<String> Function() action) async {
    setState(() => _busy = true);
    String message;
    try {
      message = await action();
      // other tabs (Dashboard/Progress/Review) reload via the version bump.
      workoutDataVersion.value++;
    } catch (e) {
      message = 'Failed: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm({required String title, required String body}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text('$body\n\nProject: $_projectLabel\nUser: $_userLabel'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _seed(DemoScenario scenario) async {
    final count = generateDemoWorkouts(
      scenario,
      referenceDate: DateTime.now(),
    ).length;
    final ok = await _confirm(
      title: 'Seed "${scenario.title}"?',
      body:
          'Writes $count clearly-tagged demo workouts, replacing any '
          'previous "${scenario.key}" demo batch. Normal workouts are '
          'never touched.',
    );
    if (!ok) return;
    await _runGuarded(() async {
      final result = await _seeder.seedScenario(scenario);
      return 'Seeded ${result.written} demo workouts '
          '(replaced ${result.replacedExisting}).';
    });
  }

  Future<void> _cleanupAll() async {
    final ok = await _confirm(
      title: 'Remove ALL demo data?',
      body:
          'Deletes every workout tagged as demo data, across all demo '
          'batches. Normal workouts are never touched.',
    );
    if (!ok) return;
    await _runGuarded(() async {
      final result = await _seeder.cleanup();
      return 'Deleted ${result.deleted} demo workouts; '
          '${result.normalDocumentsIgnored} normal workouts untouched.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Data (debug)')),
      body: ListView(
        padding: Insets.page,
        children: [
          const StatusBanner(
            icon: Icons.science_outlined,
            title: 'Development tool',
            message:
                'Available in debug builds only. Seeds deterministic, '
                'clearly-tagged demo workouts so every analytics state can '
                'be demonstrated. Cleanup removes only tagged demo data.',
          ),
          const SizedBox(height: Insets.sm),
          Text(
            'Project: $_projectLabel · User: $_userLabel',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.lg),
          const SectionHeader('Scenarios'),
          for (final scenario in DemoScenario.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(scenario.title),
              subtitle: Text(scenario.description),
              trailing: FilledButton(
                onPressed: _busy ? null : () => _seed(scenario),
                child: const Text('Seed'),
              ),
            ),
          const SizedBox(height: Insets.lg),
          const SectionHeader('Cleanup'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove all demo data'),
            subtitle: const Text(
              'Deletes only workouts tagged isDemo. Normal workouts are '
              'never touched.',
            ),
            enabled: !_busy,
            onTap: _cleanupAll,
          ),
        ],
      ),
    );
  }
}
