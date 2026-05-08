import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/workout_service.dart';
import '../services/leaderboard_service.dart';
import '../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestoreService = FirestoreService();
  final _workoutService = WorkoutService();
  final _leaderboardService = LeaderboardService();

  // account fields
  final _nameController = TextEditingController();
  String _experienceLevel = '';
  String _fitnessGoal = '';
  String _gymId = '';
  String _weightUnit = 'kg';

  // training goal fields
  final _goalExerciseController = TextEditingController();
  final _goalWeightController = TextEditingController();
  List<String> _recentExercises = [];

  double _totalVolumeLiftedKg = 0;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _experienceLevels = ['Beginner', 'Intermediate', 'Advanced'];
  static const _fitnessGoals = ['Build Muscle', 'Lose Weight', 'Improve Fitness'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalExerciseController.dispose();
    _goalWeightController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final profileFuture = _firestoreService.getUserProfile(uid);
      final workoutsFuture = _workoutService.getWorkouts(uid);
      final profile = await profileFuture;
      final workouts = await workoutsFuture;
      if (!mounted) return;
      setState(() {
        if (profile != null) {
          _nameController.text = profile.displayName;
          _experienceLevel = profile.experienceLevel;
          _fitnessGoal = profile.fitnessGoal;
          _goalExerciseController.text = profile.goalExercise;
          _gymId = profile.gymId;
          _weightUnit = profile.weightUnit.isNotEmpty
              ? profile.weightUnit
              : weightUnitNotifier.value;
          if (profile.goalTargetWeight > 0) {
            final displayGoal = _weightUnit == 'lbs'
                ? profile.goalTargetWeight * 2.20462
                : profile.goalTargetWeight;
            _goalWeightController.text =
                displayGoal.toStringAsFixed(displayGoal % 1 == 0 ? 0 : 1);
          }
        }
        _recentExercises = _workoutService.extractExerciseNames(workouts);
        _totalVolumeLiftedKg =
            _workoutService.getTotalVolumeLiftedKg(workouts);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Display name cannot be empty.');
      return;
    }

    // validate goal fields only if one of them is filled in
    final goalExercise = _goalExerciseController.text.trim();
    final goalWeightText = _goalWeightController.text.trim();
    double? goalWeight;

    if (goalExercise.isNotEmpty || goalWeightText.isNotEmpty) {
      if (goalExercise.isEmpty) {
        setState(() => _error = 'Enter an exercise name for your goal.');
        return;
      }
      goalWeight = double.tryParse(goalWeightText);
      if (goalWeight == null || goalWeight <= 0) {
        setState(() => _error = 'Enter a valid target weight.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await _firestoreService.updateProfileDetails(
        uid,
        displayName: name,
        experienceLevel: _experienceLevel,
        fitnessGoal: _fitnessGoal,
        weightUnit: _weightUnit,
      );
      weightUnitNotifier.value = _weightUnit;
      await saveWeightUnitPreference(_weightUnit);

      if (goalExercise.isNotEmpty && goalWeight != null) {
        final goalWeightKg =
            _weightUnit == 'lbs' ? goalWeight / 2.20462 : goalWeight;
        await _firestoreService.updateGoal(
          uid,
          exercise: goalExercise,
          targetWeight: goalWeightKg,
        );
      } else if (goalExercise.isEmpty && goalWeightText.isEmpty) {
        await _firestoreService.clearGoal(uid);
      }

      // keep the leaderboard entry's display name in sync
      if (_gymId.isNotEmpty) {
        await _leaderboardService.updateDisplayName(uid, _gymId, name);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save. Please try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader('Account'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Weight Unit',
                        style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'kg', label: Text('kg')),
                        ButtonSegment(value: 'lbs', label: Text('lbs')),
                      ],
                      selected: {_weightUnit},
                      onSelectionChanged: (v) =>
                          setState(() => _weightUnit = v.first),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _experienceLevel.isEmpty ? null : _experienceLevel,
                  decoration: const InputDecoration(
                    labelText: 'Experience Level',
                    border: OutlineInputBorder(),
                  ),
                  items: _experienceLevels
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setState(() => _experienceLevel = v ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _fitnessGoal.isEmpty ? null : _fitnessGoal,
                  decoration: const InputDecoration(
                    labelText: 'Primary Goal',
                    border: OutlineInputBorder(),
                  ),
                  items: _fitnessGoals
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => _fitnessGoal = v ?? ''),
                ),
                const SizedBox(height: 24),
                _sectionHeader('Lifetime Stats'),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final isLbs = _weightUnit == 'lbs';
                  final displayVolume = isLbs
                      ? _totalVolumeLiftedKg * 2.20462
                      : _totalVolumeLiftedKg;
                  final unit = _weightUnit;
                  final volumeStr = displayVolume >= 1000000
                      ? '${(displayVolume / 1000000).toStringAsFixed(2)}M $unit'
                      : displayVolume >= 1000
                          ? '${(displayVolume / 1000).toStringAsFixed(1)}k $unit'
                          : '${displayVolume.toStringAsFixed(0)} $unit';
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withAlpha(80),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bar_chart,
                            color:
                                Theme.of(context).colorScheme.primary,
                            size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Weight Lifted',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600),
                            ),
                            Text(
                              volumeStr,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
                _sectionHeader('Training Goal'),
                const SizedBox(height: 4),
                Text(
                  'Set a single exercise target to track your progress toward.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  initialValue:
                      TextEditingValue(text: _goalExerciseController.text),
                  optionsBuilder: (value) {
                    if (value.text.isEmpty) return const [];
                    return _recentExercises.where((e) => e
                        .toLowerCase()
                        .contains(value.text.toLowerCase()));
                  },
                  onSelected: (v) => _goalExerciseController.text = v,
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmitted) {
                    // keep our controller in sync with the Autocomplete controller
                    controller.text = _goalExerciseController.text;
                    controller.addListener(
                        () => _goalExerciseController.text = controller.text);
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Exercise (e.g. Bench Press)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _goalWeightController,
                  decoration: InputDecoration(
                    labelText: 'Target Weight ($_weightUnit)',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _goalExerciseController.clear();
                      _goalWeightController.clear();
                    }),
                    child: const Text('Clear goal'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
        ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}
