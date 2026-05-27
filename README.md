# GymConnect

A Flutter Android app for logging gym workouts and tracking strength progress. Built as my final year BSc Computer Science dissertation at Bournemouth University.

## What it does

- Log workouts with exercises, sets, reps and weight
- Track estimated 1RM progress over time with a chart
- Detects plateaus using weighted least squares regression
- Suggests possible causes when a plateau is detected
- Tracks how you felt each session and spots patterns
- Gym leaderboard to compare best lifts with others at the same gym
- Save custom workout templates
- Beginner starter plans

## Built with

- Flutter / Dart
- Firebase Auth
- Cloud Firestore
- fl_chart

## Running the app

1. Run `flutter pub get`
2. Connect an Android emulator or device
3. Run `flutter run`

The Firebase config (`firebase_options.dart` and `google-services.json`) is included in this submission so the app should run against the existing project without any extra setup.

## Running the tests

```
flutter test
```

There are 43 unit tests covering the plateau detector, plateau diagnosis, feel analysis and the Epley formula.
