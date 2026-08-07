import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/workout_model.dart';
import '../services/firestore_adapter.dart';
import 'demo_fixtures.dart';
import 'demo_plan.dart';

/// Seeds and cleans up tagged demo workouts for one user through the
/// standard [FirestoreAdapter] boundary (Phase 9). Used by the debug-only
/// in-app demo tools; the CLI performs the same operations over the
/// Firestore REST API with the same fixtures, tags and selection rules.
///
/// Safety invariants (docs/DECISIONS.md):
/// - writes go only to deterministic `demo-…` document ids, tagged
///   `isDemo: true` with scenario/batch/generatedAt fields;
/// - deletes only ever target documents selected by [selectDemoDocuments],
///   which requires the strict `isDemo: true` tag — normal workouts are
///   counted, reported and never touched;
/// - seeding the same batch twice replaces it (pre-delete + deterministic
///   ids), never duplicates it.
class DemoSeeder {
  final FirestoreAdapter adapter;
  final String uid;

  DemoSeeder({required this.adapter, required this.uid});

  List<String> get _workoutsPath => ['users', uid, 'workouts'];

  /// The stored document payload for [spec]: exactly the WorkoutModel.toMap
  /// shape (kg weights, Timestamp date, optional name/feelRating) plus the
  /// backward-compatible demo tag fields.
  static Map<String, dynamic> storedPayload(
    DemoWorkoutSpec spec, {
    required DemoScenario scenario,
    required String batchId,
    required DateTime generatedAt,
  }) => {
    ...toWorkoutModel(spec).toMap(),
    ...demoTagFields(
      scenario: scenario,
      batchId: batchId,
      generatedAt: generatedAt,
    ),
  };

  /// Converts a pure fixture spec into the app's workout model (used for
  /// payload building and for fixture-vs-analytics tests).
  static WorkoutModel toWorkoutModel(DemoWorkoutSpec spec) => WorkoutModel(
    id: spec.documentId,
    name: spec.name,
    date: Timestamp.fromDate(spec.date),
    feelRating: spec.feelRating,
    exercises: [
      for (final ex in spec.exercises)
        ExerciseEntry(
          name: ex.name,
          sets: [
            for (final s in ex.sets)
              WorkoutSet(weight: s.weight, reps: s.reps, isWarmup: s.isWarmup),
          ],
        ),
    ],
  );

  /// Replaces [scenario]'s batch for this user: deletes the batch's
  /// existing demo documents, then writes the freshly generated ones at
  /// their deterministic ids. Never touches normal workouts.
  Future<DemoSeedResult> seedScenario(
    DemoScenario scenario, {
    String? batchId,
    DateTime? referenceDate,
    DateTime? generatedAt,
  }) async {
    final batch = batchId ?? scenario.key;
    final now = referenceDate ?? DateTime.now();
    final specs = generateDemoWorkouts(scenario, referenceDate: now);

    final existing = await adapter.getCollection(_workoutsPath);
    final selection = selectDemoDocuments([
      for (final d in existing) (d.id, d.data),
    ], batchId: batch);
    for (final id in selection.selectedIds) {
      await adapter.deleteDocument([..._workoutsPath, id]);
    }

    final stamp = generatedAt ?? now;
    for (final spec in specs) {
      await adapter.setDocument(
        [..._workoutsPath, spec.documentId],
        storedPayload(
          spec,
          scenario: scenario,
          batchId: batch,
          generatedAt: stamp,
        ),
      );
    }

    return DemoSeedResult(
      scenario: scenario,
      batchId: batch,
      replacedExisting: selection.selectedIds.length,
      written: specs.length,
    );
  }

  /// Deletes tagged demo documents — one batch, or all of them when
  /// [batchId] is null (reserve that for an explicit "remove all" action).
  /// [dryRun] reports the selection without changing anything.
  Future<DemoCleanupResult> cleanup({
    String? batchId,
    bool dryRun = false,
  }) async {
    final existing = await adapter.getCollection(_workoutsPath);
    final selection = selectDemoDocuments([
      for (final d in existing) (d.id, d.data),
    ], batchId: batchId);

    if (!dryRun) {
      for (final id in selection.selectedIds) {
        await adapter.deleteDocument([..._workoutsPath, id]);
      }
    }

    return DemoCleanupResult(
      batchId: batchId,
      deleted: selection.selectedIds.length,
      otherDemoDocuments: selection.otherDemoDocuments,
      normalDocumentsIgnored: selection.normalDocuments,
      dryRun: dryRun,
    );
  }
}

class DemoSeedResult {
  final DemoScenario scenario;
  final String batchId;

  /// Same-batch demo documents replaced by this seed (0 on first run).
  final int replacedExisting;
  final int written;

  const DemoSeedResult({
    required this.scenario,
    required this.batchId,
    required this.replacedExisting,
    required this.written,
  });
}

class DemoCleanupResult {
  /// Null = all batches were targeted.
  final String? batchId;

  /// Selected (and deleted, unless [dryRun]) demo documents.
  final int deleted;

  /// Demo documents left alone because they belong to other batches.
  final int otherDemoDocuments;

  /// Untagged workouts observed and deliberately ignored.
  final int normalDocumentsIgnored;

  final bool dryRun;

  const DemoCleanupResult({
    required this.batchId,
    required this.deleted,
    required this.otherDemoDocuments,
    required this.normalDocumentsIgnored,
    required this.dryRun,
  });
}
