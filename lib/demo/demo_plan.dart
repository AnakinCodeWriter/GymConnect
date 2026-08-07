// Demo tagging and cleanup-selection rules (Phase 9).
//
// Pure Dart: shared by the in-app seeder (over FirestoreAdapter) and the
// CLI (over the Firestore REST API), so both paths tag and select demo
// documents identically. Safety rule: a document is demo data ONLY when it
// carries `isDemo: true`; anything else — including documents with missing
// or unrecognised tags — is never selected for deletion.

import 'demo_fixtures.dart';

/// Optional, backward-compatible fields added to seeded workout documents.
/// Normal workouts never carry them; `WorkoutModel.fromMap` ignores unknown
/// fields, so existing parsing is unaffected (docs/ARCHITECTURE.md).
const String demoFieldIsDemo = 'isDemo';
const String demoFieldScenario = 'demoScenario';
const String demoFieldBatchId = 'demoBatchId';
const String demoFieldGeneratedAt = 'demoGeneratedAt'; // ISO-8601 string

/// The tag fields for one seeded workout of [scenario] in [batchId].
Map<String, Object> demoTagFields({
  required DemoScenario scenario,
  required String batchId,
  required DateTime generatedAt,
}) => {
  demoFieldIsDemo: true,
  demoFieldScenario: scenario.key,
  demoFieldBatchId: batchId,
  demoFieldGeneratedAt: generatedAt.toUtc().toIso8601String(),
};

/// True only for documents explicitly tagged `isDemo: true` (strict bool —
/// "truthy" values do not count; when in doubt, it is not demo data).
bool isDemoDocument(Map<String, dynamic> data) => data[demoFieldIsDemo] == true;

/// Which documents a cleanup (or an idempotent pre-seed replace) would
/// touch. [selectedIds] preserves input order for stable summaries.
class DemoSelection {
  /// Demo documents matching the filter — the only deletable set.
  final List<String> selectedIds;

  /// Demo documents excluded by the batch filter (other batches survive).
  final int otherDemoDocuments;

  /// Untagged documents. Never selected, never deletable by demo tooling.
  final int normalDocuments;

  const DemoSelection({
    required this.selectedIds,
    required this.otherDemoDocuments,
    required this.normalDocuments,
  });
}

/// Selects demo documents from raw (id, data) pairs. With [batchId] set,
/// only that batch is selected; with it null, ALL demo documents are —
/// callers must reserve the null form for an explicit "remove all demo
/// data" request. Normal workouts are counted but never selected.
DemoSelection selectDemoDocuments(
  Iterable<(String, Map<String, dynamic>)> documents, {
  String? batchId,
}) {
  final selected = <String>[];
  var otherDemo = 0;
  var normal = 0;
  for (final (id, data) in documents) {
    if (!isDemoDocument(data)) {
      normal++;
    } else if (batchId == null || data[demoFieldBatchId] == batchId) {
      selected.add(id);
    } else {
      otherDemo++;
    }
  }
  return DemoSelection(
    selectedIds: selected,
    otherDemoDocuments: otherDemo,
    normalDocuments: normal,
  );
}
