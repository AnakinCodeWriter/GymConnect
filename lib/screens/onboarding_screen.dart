import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../widgets/auth_text_field.dart';
import 'home_screen.dart';

// hardcoded list of gyms available for selection during onboarding.
// using a fixed list ensures all users at the same gym share an identical
// gymId string, which is required for the leaderboard to work correctly.
const _gyms = [
  'PureGym Bournemouth Triangle',
  'PureGym Bournemouth Mallard Rd',
  'PureGym Poole',
  'PureGym Southampton',
  'Anytime Fitness Bournemouth',
  'Anytime Fitness Poole',
  'JD Gyms Bournemouth',
  'The Gym Group Bournemouth',
  'Nuffield Health Bournemouth',
  'DW Fitness First Bournemouth',
  'Other',
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _displayNameController = TextEditingController();
  final _firestoreService = FirestoreService();
  String? _selectedGym;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _saveProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final displayName = _displayNameController.text.trim();
    final gymId = _selectedGym;

    if (displayName.isEmpty || gymId == null) {
      setState(() {
        _errorMessage = 'Please fill in all fields.';
        _isLoading = false;
      });
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final user = UserModel(
        uid: uid,
        displayName: displayName,
        gymId: gymId,
        createdAt: Timestamp.now(),
      );
      await _firestoreService.createUserProfile(user);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save profile. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Up Your Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to GymConnect!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Complete your profile to continue.'),
            const SizedBox(height: 24),
            AuthTextField(
              controller: _displayNameController,
              label: 'Display Name',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedGym,
              decoration: const InputDecoration(
                labelText: 'Which gym do you attend?',
                border: OutlineInputBorder(),
              ),
              items: _gyms
                  .map((gym) => DropdownMenuItem(value: gym, child: Text(gym)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedGym = value),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _saveProfile,
                    child: const Text('Save Profile'),
                  ),
          ],
        ),
      ),
    );
  }
}
