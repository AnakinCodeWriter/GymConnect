import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/state_views.dart';
import 'demo_tools_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'starter_plan_screen.dart';
import 'workout_templates_screen.dart';

/// Secondary destinations reachable from the More tab.
enum MoreDestination {
  templates,
  starterPlans,
  leaderboard,
  profile,
  demoTools,
}

/// The More tab (Phase 5): grouped navigation to secondary features plus
/// app settings (dark mode) and sign out. Log Workout deliberately stays on
/// the Dashboard.
///
/// [routeOverrides] and [signOut] are injectable so widget tests can verify
/// navigation without Firebase; production call sites pass nothing.
///
/// [showDeveloperTools] gates the Developer section (demo-data tooling,
/// Phase 9). It defaults to the compile-time `kDebugMode` constant, so the
/// section — and the demo screens behind it — cannot appear in release
/// builds; tests pass it explicitly to verify both sides.
class MoreScreen extends StatelessWidget {
  final Map<MoreDestination, WidgetBuilder> routeOverrides;
  final Future<void> Function()? signOut;
  final bool showDeveloperTools;

  const MoreScreen({
    super.key,
    this.routeOverrides = const {},
    this.signOut,
    this.showDeveloperTools = kDebugMode,
  });

  WidgetBuilder _builderFor(MoreDestination destination) {
    final override = routeOverrides[destination];
    if (override != null) return override;
    switch (destination) {
      case MoreDestination.templates:
        return (_) => const WorkoutTemplatesScreen();
      case MoreDestination.starterPlans:
        return (_) => const StarterPlanScreen();
      case MoreDestination.leaderboard:
        return (_) => const LeaderboardScreen();
      case MoreDestination.profile:
        return (_) => const ProfileScreen();
      case MoreDestination.demoTools:
        return (_) => const DemoToolsScreen();
    }
  }

  void _open(BuildContext context, MoreDestination destination) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: _builderFor(destination)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: Insets.page,
        children: [
          const SectionHeader('Training'),
          ListTile(
            leading: const Icon(Icons.playlist_add_check),
            title: const Text('Workout Templates'),
            onTap: () => _open(context, MoreDestination.templates),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Starter Plans'),
            onTap: () => _open(context, MoreDestination.starterPlans),
          ),
          const SizedBox(height: Insets.lg),
          const SectionHeader('Community'),
          ListTile(
            leading: const Icon(Icons.leaderboard),
            title: const Text('Gym Leaderboard'),
            onTap: () => _open(context, MoreDestination.leaderboard),
          ),
          const SizedBox(height: Insets.lg),
          const SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('My Profile'),
            onTap: () => _open(context, MoreDestination.profile),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) => SwitchListTile(
              title: const Text('Dark Mode'),
              secondary: Icon(
                mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
              ),
              value: mode == ThemeMode.dark,
              onChanged: (on) {
                themeModeNotifier.value = on ? ThemeMode.dark : ThemeMode.light;
                saveThemePreference(on);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            // the auth-state stream above the shell returns to the login
            // screen once sign-out completes - no manual navigation needed.
            onTap: () => (signOut ?? () => AuthService().signOut())(),
          ),
          if (showDeveloperTools) ...[
            const SizedBox(height: Insets.lg),
            const SectionHeader('Developer (debug builds only)'),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Demo Data'),
              subtitle: const Text('Seed or remove tagged demo workouts'),
              onTap: () => _open(context, MoreDestination.demoTools),
            ),
          ],
        ],
      ),
    );
  }
}
