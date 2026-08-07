import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/screens/more_screen.dart';

Widget _more({Future<void> Function()? signOut, bool? showDeveloperTools}) =>
    MaterialApp(
      home: MoreScreen(
        signOut: signOut ?? () async {},
        // widget tests run in debug mode, so the default (kDebugMode) shows
        // the Developer section; release hiding is asserted via `false`.
        showDeveloperTools: showDeveloperTools ?? true,
        routeOverrides: {
          MoreDestination.templates: (_) =>
              const Scaffold(body: Text('OPEN-TEMPLATES')),
          MoreDestination.starterPlans: (_) =>
              const Scaffold(body: Text('OPEN-STARTER')),
          MoreDestination.leaderboard: (_) =>
              const Scaffold(body: Text('OPEN-LEADERBOARD')),
          MoreDestination.profile: (_) =>
              const Scaffold(body: Text('OPEN-PROFILE')),
          MoreDestination.demoTools: (_) =>
              const Scaffold(body: Text('OPEN-DEMO-TOOLS')),
        },
      ),
    );

void main() {
  group('MoreScreen', () {
    testWidgets('shows every secondary destination, grouped, with no '
        'Weekly Review placeholder', (tester) async {
      await tester.pumpWidget(_more());

      expect(find.text('Training'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);

      expect(find.text('Workout Templates'), findsOneWidget);
      expect(find.text('Starter Plans'), findsOneWidget);
      expect(find.text('Gym Leaderboard'), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);

      expect(find.textContaining('Weekly'), findsNothing);
      expect(
        find.textContaining('coming soon', findRichText: true),
        findsNothing,
      );
    });

    for (final (label, marker) in const [
      ('Workout Templates', 'OPEN-TEMPLATES'),
      ('Starter Plans', 'OPEN-STARTER'),
      ('Gym Leaderboard', 'OPEN-LEADERBOARD'),
      ('My Profile', 'OPEN-PROFILE'),
    ]) {
      testWidgets('tapping "$label" opens the right screen', (tester) async {
        await tester.pumpWidget(_more());
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(marker), findsOneWidget);
      });
    }

    testWidgets('sign out invokes the callback', (tester) async {
      var signedOut = false;
      await tester.pumpWidget(_more(signOut: () async => signedOut = true));
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(signedOut, isTrue);
    });

    testWidgets('Developer section appears in debug mode and opens the demo '
        'tools (Phase 9)', (tester) async {
      await tester.pumpWidget(_more());
      await tester.scrollUntilVisible(find.text('Demo Data'), 100);
      expect(find.text('Developer (debug builds only)'), findsOneWidget);
      await tester.tap(find.text('Demo Data'));
      await tester.pumpAndSettle();
      expect(find.text('OPEN-DEMO-TOOLS'), findsOneWidget);
    });

    testWidgets('Developer section is absent when developer tools are '
        'disabled (release behaviour)', (tester) async {
      await tester.pumpWidget(_more(showDeveloperTools: false));
      expect(find.textContaining('Developer'), findsNothing);
      expect(find.text('Demo Data'), findsNothing);
    });

    testWidgets('long content scrolls on a short screen', (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_more());
      // Sign out sits at the bottom; scroll it into view and tap it.
      await tester.scrollUntilVisible(find.text('Sign out'), 100);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });
}
