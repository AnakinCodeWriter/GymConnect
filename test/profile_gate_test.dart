import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/widgets/profile_gate.dart';

Widget _gate({
  required Future<bool> Function() check,
  Future<void> Function()? onSignOut,
}) {
  return MaterialApp(
    home: ProfileGate(
      checkProfileExists: check,
      homeBuilder: (_) => const Scaffold(body: Text('HOME')),
      onboardingBuilder: (_) => const Scaffold(body: Text('ONBOARDING')),
      onSignOut: onSignOut ?? () async {},
    ),
  );
}

void main() {
  group('ProfileGate', () {
    testWidgets('shows a loading indicator while the lookup is pending', (
      tester,
    ) async {
      final completer = Completer<bool>();
      await tester.pumpWidget(_gate(check: () => completer.future));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(find.text('ONBOARDING'), findsNothing);

      // Complete so the pending timer/future does not leak out of the test.
      completer.complete(true);
      await tester.pumpAndSettle();
    });

    testWidgets('routes to home when the profile exists', (tester) async {
      await tester.pumpWidget(_gate(check: () async => true));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('ONBOARDING'), findsNothing);
    });

    testWidgets(
      'routes to onboarding when the profile genuinely does not exist',
      (tester) async {
        await tester.pumpWidget(_gate(check: () async => false));
        await tester.pumpAndSettle();

        expect(find.text('ONBOARDING'), findsOneWidget);
        expect(find.text('HOME'), findsNothing);
      },
    );

    testWidgets(
      'shows the error state - NOT onboarding - when the lookup fails',
      (tester) async {
        await tester.pumpWidget(
          _gate(check: () async => throw Exception('firestore down')),
        );
        await tester.pumpAndSettle();

        expect(find.text('ONBOARDING'), findsNothing);
        expect(find.text('HOME'), findsNothing);
        expect(find.text('Couldn\'t load your profile'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);
        // No raw exception detail is surfaced.
        expect(find.textContaining('firestore down'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
      },
    );

    testWidgets('retry re-runs the lookup and can recover to home', (
      tester,
    ) async {
      var calls = 0;
      Future<bool> flaky() async {
        calls++;
        if (calls == 1) throw Exception('transient');
        return true;
      }

      await tester.pumpWidget(_gate(check: flaky));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('sign out from the error state invokes the callback', (
      tester,
    ) async {
      var signedOut = false;
      await tester.pumpWidget(
        _gate(
          check: () async => throw Exception('down'),
          onSignOut: () async => signedOut = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pump();

      expect(signedOut, isTrue);
    });
  });
}
