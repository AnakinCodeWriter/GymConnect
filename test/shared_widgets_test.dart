import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/widgets/state_views.dart';
import 'package:gymconnect/widgets/status_banner.dart';

Widget _host(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  themeMode: mode,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
  ),
  darkTheme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    ),
  ),
  home: Scaffold(body: child),
);

void main() {
  group('LoadingView', () {
    testWidgets('shows a progress indicator', (tester) async {
      await tester.pumpWidget(_host(const LoadingView()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('EmptyView', () {
    testWidgets('shows message and optional icon', (tester) async {
      await tester.pumpWidget(
        _host(const EmptyView(message: 'Nothing here yet', icon: Icons.inbox)),
      );
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsOneWidget);
    });
  });

  group('ErrorRetryView', () {
    testWidgets('shows title, message and a working Retry action', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        _host(
          ErrorRetryView(
            title: 'Load failed',
            message: 'Try again.',
            onRetry: () => retried = true,
          ),
        ),
      );
      expect(find.text('Load failed'), findsOneWidget);
      expect(find.text('Try again.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('optional secondary action renders and fires', (tester) async {
      var secondary = false;
      await tester.pumpWidget(
        _host(
          ErrorRetryView(
            title: 'Load failed',
            message: 'Try again.',
            onRetry: () {},
            secondaryActionLabel: 'Sign out',
            onSecondaryAction: () => secondary = true,
          ),
        ),
      );
      await tester.tap(find.text('Sign out'));
      expect(secondary, isTrue);
    });
  });

  group('StatusBanner', () {
    testWidgets('shows title, message, icon and optional action', (
      tester,
    ) async {
      var acted = false;
      await tester.pumpWidget(
        _host(
          StatusBanner(
            icon: Icons.cloud_off,
            title: 'Couldn\'t refresh',
            message: 'Showing last data.',
            actionLabel: 'Retry',
            onAction: () => acted = true,
          ),
        ),
      );
      expect(find.text('Couldn\'t refresh'), findsOneWidget);
      expect(find.text('Showing last data.'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(acted, isTrue);
    });

    testWidgets('action is omitted when no label is given', (tester) async {
      await tester.pumpWidget(
        _host(
          const StatusBanner(title: 'Notice', message: 'Something to know.'),
        ),
      );
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('InlineNotice', () {
    testWidgets('shows message and optional action', (tester) async {
      var acted = false;
      await tester.pumpWidget(
        _host(
          InlineNotice(
            message: '2 records skipped.',
            actionLabel: 'Retry',
            onAction: () => acted = true,
          ),
        ),
      );
      expect(find.text('2 records skipped.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(acted, isTrue);
    });
  });

  group('SectionHeader', () {
    testWidgets('renders its title', (tester) async {
      await tester.pumpWidget(_host(const SectionHeader('Account')));
      expect(find.text('Account'), findsOneWidget);
    });
  });

  group('theming and text scale', () {
    final samples = <String, Widget>{
      'ErrorRetryView': ErrorRetryView(
        title: 'Load failed',
        message: 'Check your connection and try again.',
        onRetry: () {},
      ),
      'EmptyView': const EmptyView(
        message: 'No workouts logged yet.',
        icon: Icons.fitness_center,
      ),
      'StatusBanner': const StatusBanner(
        title: 'Couldn\'t refresh your training data',
        message: 'Showing your last loaded data.',
      ),
      'InlineNotice': const InlineNotice(message: '1 record skipped.'),
    };

    for (final entry in samples.entries) {
      testWidgets('${entry.key} renders in dark mode', (tester) async {
        await tester.pumpWidget(_host(entry.value, mode: ThemeMode.dark));
        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key} survives 2x text scale without overflow '
          'exceptions', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Scaffold(body: entry.value),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
