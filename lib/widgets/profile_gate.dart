import 'package:flutter/material.dart';

import 'state_views.dart';

// Routes a signed-in user based on whether their Firestore profile exists.
//
// Distinguishes four states: loading, profile exists, profile genuinely
// missing, and lookup failed. A failed lookup (network, permission, or other
// transient Firestore error) must NOT be treated as "no profile" - routing
// to onboarding on error would let the user overwrite an existing profile.
// Instead an error state is shown with retry and sign-out options.
//
// Dependencies are injected so this widget can be tested without Firebase.
class ProfileGate extends StatefulWidget {
  const ProfileGate({
    super.key,
    required this.checkProfileExists,
    required this.homeBuilder,
    required this.onboardingBuilder,
    required this.onSignOut,
  });

  /// Resolves to true if the user's profile document exists.
  final Future<bool> Function() checkProfileExists;

  final WidgetBuilder homeBuilder;
  final WidgetBuilder onboardingBuilder;

  /// Signs the user out; the auth-state listener above this widget is
  /// responsible for navigating back to the login screen.
  final Future<void> Function() onSignOut;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

enum _LookupState { loading, exists, missing, failed }

class _ProfileGateState extends State<ProfileGate> {
  _LookupState _state = _LookupState.loading;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _state = _LookupState.loading);
    try {
      final exists = await widget.checkProfileExists();
      if (!mounted) return;
      setState(
        () => _state = exists ? _LookupState.exists : _LookupState.missing,
      );
    } catch (_) {
      // Deliberately no detail shown to the user; see error state below.
      if (!mounted) return;
      setState(() => _state = _LookupState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LookupState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _LookupState.exists:
        return widget.homeBuilder(context);
      case _LookupState.missing:
        return widget.onboardingBuilder(context);
      case _LookupState.failed:
        return Scaffold(
          body: ErrorRetryView(
            title: 'Couldn\'t load your profile',
            message: 'Check your connection and try again.',
            onRetry: _check,
            secondaryActionLabel: 'Sign out',
            onSecondaryAction: () => widget.onSignOut(),
          ),
        );
    }
  }
}
