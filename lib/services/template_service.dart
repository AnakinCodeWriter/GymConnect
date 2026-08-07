import '../models/template_model.dart';
import 'data_result.dart';
import 'firestore_adapter.dart';

/// Workout-template data access. Collection path: users/{uid}/templates.
/// Reads are unordered (small collections, capped at 5 by the UI); no
/// ordering guarantee is documented or relied upon.
class TemplateService {
  final FirestoreAdapter _adapter;

  TemplateService({FirestoreAdapter? adapter})
    : _adapter = adapter ?? FirebaseFirestoreAdapter();

  List<String> _templatesPath(String uid) => ['users', uid, 'templates'];

  /// Loads the user's templates. Malformed documents are skipped and
  /// reported via [DataSuccess.skipped].
  Future<DataResult<List<TemplateModel>>> loadTemplates(String uid) async {
    try {
      final docs = await _adapter.getCollection(_templatesPath(uid));
      final templates = <TemplateModel>[];
      final skipped = <SkippedDocument>[];
      for (final doc in docs) {
        try {
          templates.add(TemplateModel.fromMap(doc.id, doc.data));
        } catch (e) {
          skipped.add(SkippedDocument(doc.id, e));
        }
      }
      return DataSuccess(templates, skipped: skipped);
    } catch (e) {
      return DataFailure(failureKindFor(e), e);
    }
  }

  // creates a new template; Firestore auto-generates the document ID
  Future<void> createTemplate(String uid, TemplateModel template) async {
    await _adapter.addDocument(_templatesPath(uid), template.toMap());
  }

  // overwrites an existing template document identified by template.id
  Future<void> updateTemplate(String uid, TemplateModel template) async {
    await _adapter.setDocument([
      ..._templatesPath(uid),
      template.id,
    ], template.toMap());
  }

  Future<void> deleteTemplate(String uid, String templateId) async {
    await _adapter.deleteDocument([..._templatesPath(uid), templateId]);
  }
}
