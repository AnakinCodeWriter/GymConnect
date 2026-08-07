import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/screens/app_shell.dart';

// Stateful destination used to prove IndexedStack preserves state.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('count: $count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: const Text('increment'),
        ),
      ],
    );
  }
}

// Destination that pushes a secondary route, to test back behaviour.
class _Pusher extends StatelessWidget {
  const _Pusher();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('SECONDARY')),
        ),
      ),
      child: const Text('open secondary'),
    );
  }
}

Widget _shell() => const MaterialApp(
  home: AppShell(
    destinations: [
      Text('DEST-DASHBOARD'),
      _Counter(),
      Text('DEST-REVIEW'),
      _Pusher(),
    ],
  ),
);

Future<bool> _systemBack(WidgetTester tester) async {
  // Simulates the Android system back button.
  final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
  final result = await widgetsAppState.didPopRoute() as bool;
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('AppShell', () {
    testWidgets('Dashboard is selected initially', (tester) async {
      await tester.pumpWidget(_shell());
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
    });

    testWidgets('shows exactly the four visible destinations including the '
        'Weekly Review ("Review") destination (Phase 8)', (tester) async {
      await tester.pumpWidget(_shell());
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 4);
    });

    testWidgets('selecting the Review destination shows its content', (
      tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('DEST-REVIEW'), findsOneWidget);
      expect(find.text('DEST-DASHBOARD'), findsNothing); // offstage
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 2);
    });

    testWidgets('Back from Review root returns to Dashboard', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      final handled = await _systemBack(tester);
      expect(handled, isTrue); // consumed by the shell
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
    });

    testWidgets('Review destination root is not duplicated by reselection', (
      tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('DEST-REVIEW'), findsOneWidget);
    });

    testWidgets('destination switching updates selection and content', (
      tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('count: 0'), findsOneWidget);
      expect(find.text('DEST-DASHBOARD'), findsNothing); // offstage
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
    });

    testWidgets('destination roots are not duplicated', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
    });

    testWidgets('destination state is preserved across switches', (
      tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('increment'));
      await tester.pump();
      expect(find.text('count: 1'), findsOneWidget);

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('count: 1'), findsOneWidget);
    });

    testWidgets('re-tapping the current destination pushes nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('Back from Progress root returns to Dashboard', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      final handled = await _systemBack(tester);
      expect(handled, isTrue); // consumed by the shell
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
    });

    testWidgets('Back from More root returns to Dashboard', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      final handled = await _systemBack(tester);
      expect(handled, isTrue);
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
    });

    testWidgets('Back on Dashboard root defers to the system', (tester) async {
      await tester.pumpWidget(_shell());
      final handled = await _systemBack(tester);
      // false = nothing popped; the OS handles it (app backgrounds).
      expect(handled, isFalse);
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
    });

    testWidgets('Back closes a pushed secondary screen before changing tabs', (
      tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open secondary'));
      await tester.pumpAndSettle();
      expect(find.text('SECONDARY'), findsOneWidget);

      final handled = await _systemBack(tester);
      expect(handled, isTrue);
      // secondary closed; still on the More tab, not Dashboard
      expect(find.text('SECONDARY'), findsNothing);
      expect(find.text('open secondary'), findsOneWidget);

      // a second Back now returns to Dashboard
      await _systemBack(tester);
      expect(find.text('DEST-DASHBOARD'), findsOneWidget);
    });
  });
}
