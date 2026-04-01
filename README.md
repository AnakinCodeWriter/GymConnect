# GymConnect

A Flutter Android application for tracking gym workouts and monitoring strength progress over time.

Built as a final year BSc Computer Science project at Bournemouth University.

## Tech Stack

- Flutter (Dart)
- Firebase Authentication
- Cloud Firestore
- fl_chart

## Project Structure

```
lib/
├── main.dart
├── firebase_options.dart
├── models/
│   ├── user_model.dart
│   └── workout_model.dart
├── screens/
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── onboarding_screen.dart
│   ├── home_screen.dart
│   ├── log_workout_screen.dart
│   └── progress_screen.dart
├── services/
│   ├── auth_service.dart
│   ├── firestore_service.dart
│   ├── workout_service.dart
│   └── plateau_detector.dart
└── widgets/
    └── auth_text_field.dart
```

## Getting Started

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Connect your own Firebase project:
   - Add your `google-services.json` to `android/app/`
   - Run `flutterfire configure` to regenerate `firebase_options.dart` (excluded from this repo for security)
4. Run on an Android device or emulator with `flutter run`

> **Note:** `firebase_options.dart` and `google-services.json` are excluded from version control as they contain Firebase API keys. You must generate these yourself using the FlutterFire CLI before running the app.
