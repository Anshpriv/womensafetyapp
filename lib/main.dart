import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/truck_monitoring_screen.dart';
import 'screens/shared_locations_screen.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/translation_service.dart';
import 'screens/splash_screen.dart';
import 'screens/intro_video_screen.dart'; // ✅ Intro video
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/emergency_contacts_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init (required on all platforms)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Initialize Notifications
  await NotificationService.initialize();

  // ✅ Initialize Translations
  await TranslationService.initialize();

  // App Check
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
    );
  }

  runApp(const TruckerApp());
}

class TruckerApp extends StatelessWidget {
  const TruckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'TRUCK SAFETY',
        
        // ✅ LIGHT THEME
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: Colors.grey.shade50,
        ),
        
        // ✅ DARK THEME
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: Colors.grey.shade900,
        ),
        
        // ✅ Follow system theme
        themeMode: ThemeMode.system,
        
        // ✅ Start with intro video
        initialRoute: '/intro', 
        
        routes: {
          '/': (_) => const SplashScreen(), 
          '/intro': (_) => const IntroVideoScreen(), // ✅ Intro video screen
          '/onboarding': (_) => const OnboardingScreen(),
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const HomeScreen(),
          '/profile': (_) => const ProfileSetupScreen(),
          '/contacts': (_) => const EmergencyContactsScreen(),
          '/monitoring': (_) => const TruckMonitoringScreen(),
          '/shared_locations': (_) => const SharedLocationsScreen(),
        },
      ),
    );
  }
}
