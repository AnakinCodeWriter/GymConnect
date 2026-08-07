import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'more_screen.dart';
import 'progress_screen.dart';
import 'weekly_review_screen.dart';

/// The authenticated application shell (Phase 5, decision D1 as refined):
/// a Material 3 bottom NavigationBar with four visible destinations -
/// Dashboard, Progress, Weekly Review (labelled "Review") and More
/// (Weekly Review added in Phase 8 as planned: one destination entry, no
/// restructuring).
///
/// Shown only after ProfileGate confirms a valid profile (see main.dart).
///
/// State preservation: destinations live in an IndexedStack, so switching
/// tabs neither recreates screens nor refetches their data. Secondary
/// screens are pushed on the root navigator, above the shell route.
///
/// Back behaviour (documented in docs/ARCHITECTURE.md):
/// - a pushed secondary screen closes first (it sits above the shell);
/// - Back at Progress/Review/More root returns to Dashboard;
/// - Back at Dashboard root defers to the system (app backgrounds);
/// - re-tapping the selected destination is a no-op (no duplicate routes).
/// Lets descendants switch the shell's selected tab (e.g. the Dashboard's
/// "view detailed progress" action selects the Progress tab instead of
/// pushing a duplicate route). No-ops when no shell is present (tests).
class AppShellTabs extends InheritedWidget {
  final void Function(int index) select;

  const AppShellTabs({super.key, required this.select, required super.child});

  static void switchTo(BuildContext context, int index) =>
      context.getInheritedWidgetOfExactType<AppShellTabs>()?.select(index);

  @override
  bool updateShouldNotify(AppShellTabs oldWidget) => false;
}

class AppShell extends StatefulWidget {
  /// Overrides the destination widgets - used by widget tests so the shell
  /// can be exercised without Firebase. Must have length 4.
  final List<Widget>? destinations;

  const AppShell({super.key, this.destinations});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  late final List<Widget> _destinations =
      widget.destinations ??
      const [
        HomeScreen(),
        ProgressScreen(),
        WeeklyReviewScreen(),
        MoreScreen(),
      ];

  static const _destinationSpecs = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Dashboard',
    ),
    NavigationDestination(icon: Icon(Icons.show_chart), label: 'Progress'),
    // The Weekly Review destination; short label so four destinations fit
    // narrow screens (the screen's own AppBar reads "Weekly Review").
    NavigationDestination(
      icon: Icon(Icons.reviews_outlined),
      selectedIcon: Icon(Icons.reviews),
      label: 'Review',
    ),
    NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: AppShellTabs(
        select: (i) => setState(() => _index = i),
        child: Scaffold(
          body: IndexedStack(index: _index, children: _destinations),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: _destinationSpecs,
          ),
        ),
      ),
    );
  }
}
