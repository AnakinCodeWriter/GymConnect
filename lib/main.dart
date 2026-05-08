import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/firestore_service.dart';

// Global notifier — any screen can read or toggle the theme without prop drilling
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

// Global notifier for weight unit preference ('kg' or 'lbs')
final weightUnitNotifier = ValueNotifier<String>('kg');

const _kThemeKey = 'dark_mode';
const _kWeightUnitKey = 'weight_unit';

Future<void> saveThemePreference(bool isDark) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kThemeKey, isDark);
}

Future<void> saveWeightUnitPreference(String unit) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kWeightUnitKey, unit);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // restore saved theme before the first frame
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool(_kThemeKey) ?? false;
  themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  weightUnitNotifier.value = prefs.getString(_kWeightUnitKey) ?? 'kg';
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'GymConnect',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

// istens to auth state. if logged in, checks for a firestore profile.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const ProfileChecker();
        }
        return const LoginScreen();
      },
    );
  }
}

// checks if the logged-in user already has a firestore profile.
class ProfileChecker extends StatelessWidget {
  const ProfileChecker({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FutureBuilder<bool>(
      future: FirestoreService().userProfileExists(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return const HomeScreen();
        }
        return const OnboardingScreen();
      },
    );
  }
}
