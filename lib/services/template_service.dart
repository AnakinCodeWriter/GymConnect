import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/template_model.dart';

class TemplateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // scoped reference to the user's templates subcollection -
  // same pattern as WorkoutService._workoutsRef
  CollectionReference _ref(String uid) =>
      _db.collection('users').doc(uid).collection('templates');

  Future<List<TemplateModel>> getTemplates(String uid) async {
    final snapshot = await _ref(uid).get();
    return snapshot.docs
        .map((doc) =>
            TemplateModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
  }

  // creates a new template; Firestore auto-generates the document ID
  Future<void> createTemplate(String uid, TemplateModel template) async {
    await _ref(uid).add(template.toMap());
  }

  // overwrites an existing template document identified by template.id
  Future<void> updateTemplate(String uid, TemplateModel template) async {
    await _ref(uid).doc(template.id).set(template.toMap());
  }

  Future<void> deleteTemplate(String uid, String templateId) async {
    await _ref(uid).doc(templateId).delete();
  }
}
