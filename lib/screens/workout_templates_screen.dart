import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/template_model.dart';
import '../services/template_service.dart';

// maximum number of templates a user is allowed to save
const _maxTemplates = 5;

class WorkoutTemplatesScreen extends StatefulWidget {
  const WorkoutTemplatesScreen({super.key});

  @override
  State<WorkoutTemplatesScreen> createState() => _WorkoutTemplatesScreenState();
}

class _WorkoutTemplatesScreenState extends State<WorkoutTemplatesScreen> {
  final _templateService = TemplateService();

  List<TemplateModel> _templates = [];
  bool _loading = true;

  // editor state - active when the user is creating or editing a template
  bool _showEditor = false;
  String? _editingId; // null when creating a new template
  final _nameController = TextEditingController();
  final List<_TplExerciseData> _editorExercises = [];
  String? _editorError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final ex in _editorExercises) {
      ex.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final templates = await _templateService.getTemplates(uid);
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // switches to editor mode, optionally pre-filling with an existing template.
  // disposes any current editor data before replacing it.
  void _openEditor({TemplateModel? template}) {
    for (final ex in _editorExercises) {
      ex.dispose();
    }
    _editorExercises.clear();

    if (template != null) {
      for (final exercise in template.exercises) {
        final ex = _TplExerciseData();
        ex.nameController.text = exercise.name;
        for (final set in exercise.sets) {
          final weight = set.weight == null
              ? ''
              : set.weight! % 1 == 0
                  ? set.weight!.toInt().toString()
                  : set.weight!.toString();
          ex.sets.add(_TplSetData(reps: set.reps.toString(), weight: weight));
        }
        _editorExercises.add(ex);
      }
    }

    setState(() {
      _showEditor = true;
      _editingId = template?.id;
      _nameController.text = template?.name ?? '';
      _editorError = null;
    });
  }

  // returns to the list view without saving
  void _closeEditor() {
    for (final ex in _editorExercises) {
      ex.dispose();
    }
    setState(() {
      _editorExercises.clear();
      _showEditor = false;
      _editingId = null;
      _saving = false;
      _nameController.clear();
      _editorError = null;
    });
  }

  Future<void> _saveTemplate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _editorError = 'Enter a template name.');
      return;
    }
    if (_editorExercises.isEmpty) {
      setState(() => _editorError = 'Add at least one exercise.');
      return;
    }
    for (final ex in _editorExercises) {
      if (ex.nameController.text.trim().isEmpty) {
        setState(() => _editorError = 'Every exercise needs a name.');
        return;
      }
      if (ex.sets.isEmpty) {
        setState(() => _editorError = 'Every exercise needs at least one set.');
        return;
      }
      for (final s in ex.sets) {
        final reps = int.tryParse(s.repsController.text.trim());
        if (reps == null || reps <= 0) {
          setState(() => _editorError = 'Enter valid reps for all sets.');
          return;
        }
        final weightText = s.weightController.text.trim();
        if (weightText.isNotEmpty && double.tryParse(weightText) == null) {
          setState(() => _editorError = 'Enter a valid weight, or leave it blank.');
          return;
        }
      }
    }

    setState(() => _saving = true);

    final exercises = _editorExercises.map((ex) {
      final sets = ex.sets.map((s) {
        final weightText = s.weightController.text.trim();
        return TemplateSet(
          reps: int.parse(s.repsController.text.trim()),
          weight: weightText.isNotEmpty ? double.parse(weightText) : null,
        );
      }).toList();
      return TemplateExercise(name: ex.nameController.text.trim(), sets: sets);
    }).toList();

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      if (_editingId != null) {
        await _templateService.updateTemplate(
          uid,
          TemplateModel(id: _editingId!, name: name, exercises: exercises),
        );
      } else {
        await _templateService.createTemplate(
          uid,
          TemplateModel(id: '', name: name, exercises: exercises),
        );
      }
      await _loadTemplates();
      _closeEditor();
    } catch (e) {
      setState(() {
        _editorError = 'Failed to save. Please try again.';
        _saving = false;
      });
    }
  }

  Future<void> _deleteTemplate(String templateId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _templateService.deleteTemplate(uid, templateId);
    await _loadTemplates();
  }

  void _addEditorExercise() {
    setState(() => _editorExercises.add(_TplExerciseData()));
  }

  void _removeEditorExercise(int index) {
    setState(() {
      _editorExercises[index].dispose();
      _editorExercises.removeAt(index);
    });
  }

  void _addEditorSet(int exerciseIndex) {
    setState(() {
      final sets = _editorExercises[exerciseIndex].sets;
      if (sets.isNotEmpty) {
        // prefill new set from the previous set's values
        final prev = sets.last;
        sets.add(_TplSetData(
          reps: prev.repsController.text,
          weight: prev.weightController.text,
        ));
      } else {
        sets.add(_TplSetData());
      }
    });
  }

  void _removeEditorSet(int exerciseIndex, int setIndex) {
    setState(() {
      _editorExercises[exerciseIndex].sets[setIndex].dispose();
      _editorExercises[exerciseIndex].sets.removeAt(setIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showEditor
            ? (_editingId == null ? 'New Template' : 'Edit Template')
            : 'Workout Templates'),
        // in editor mode, replace the default back button with an explicit cancel
        leading: _showEditor
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Cancel',
                onPressed: _closeEditor,
              )
            : null,
        actions: _showEditor
            ? [
                TextButton(
                  onPressed: _saving ? null : _saveTemplate,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save', style: TextStyle(fontSize: 16)),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showEditor
              ? _buildEditor()
              : _buildList(),
    );
  }

  // ─── list view ────────────────────────────────────────────────────────────

  Widget _buildList() {
    final atLimit = _templates.length >= _maxTemplates;
    return Column(
      children: [
        Expanded(
          child: _templates.isEmpty
              ? const Center(
                  child: Text(
                    'No templates yet.\nCreate one to speed up logging.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _templates.length,
                  itemBuilder: (context, i) => _buildTemplateCard(_templates[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: atLimit ? null : () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('New Template'),
                ),
              ),
              if (atLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Maximum of $_maxTemplates templates reached.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateCard(TemplateModel template) {
    // show exercise names as a compact summary line
    final summary = template.exercises.map((e) => e.name).join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        summary,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => _openEditor(template: template),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () => _deleteTemplate(template.id),
            ),
          ],
        ),
      ),
    );
  }

  // ─── editor view ──────────────────────────────────────────────────────────

  Widget _buildEditor() {
    return Column(
      children: [
        if (_editorError != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_editorError!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Template name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              ...List.generate(
                _editorExercises.length,
                (i) => _buildEditorExerciseCard(i),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addEditorExercise,
              icon: const Icon(Icons.add),
              label: const Text('Add Exercise'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorExerciseCard(int i) {
    final ex = _editorExercises[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ex.nameController,
                    decoration: const InputDecoration(
                      labelText: 'Exercise name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeEditorExercise(i),
                  tooltip: 'Remove exercise',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (ex.sets.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Reps',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Weight (optional)',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    SizedBox(width: 36),
                  ],
                ),
              ),
              ...List.generate(ex.sets.length, (j) => _buildEditorSetRow(i, j)),
            ],
            TextButton.icon(
              onPressed: () => _addEditorSet(i),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Set'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorSetRow(int exerciseIndex, int setIndex) {
    final s = _editorExercises[exerciseIndex].sets[setIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('${setIndex + 1}. ',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Expanded(
            child: TextField(
              controller: s.repsController,
              decoration: const InputDecoration(
                hintText: '0',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'reps',
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: s.weightController,
              decoration: const InputDecoration(
                hintText: 'optional',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'kg',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: () => _removeEditorSet(exerciseIndex, setIndex),
            tooltip: 'Remove set',
          ),
        ],
      ),
    );
  }
}

// ─── private data classes ────────────────────────────────────────────────────

// holds the mutable state for one exercise row in the template editor
class _TplExerciseData {
  final TextEditingController nameController = TextEditingController();
  final List<_TplSetData> sets = [];

  void dispose() {
    nameController.dispose();
    for (final s in sets) {
      s.dispose();
    }
  }
}

// holds the mutable state for one set row in the template editor
class _TplSetData {
  final TextEditingController repsController;
  final TextEditingController weightController;

  _TplSetData({String reps = '', String weight = ''})
      : repsController = TextEditingController(text: reps),
        weightController = TextEditingController(text: weight);

  void dispose() {
    repsController.dispose();
    weightController.dispose();
  }
}
