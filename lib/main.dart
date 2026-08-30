import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/theme_provider.dart';

import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/emergency_contacts_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/safe_zone_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Firebase init
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Supabase Storage init
  await Supabase.initialize(
    url: 'https://brqvinydqpbqfjurivgc.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJycXZpbnlkcXBicWZqdXJpdmdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwOTEyNzUsImV4cCI6MjEwMzY2NzI3NX0.lakQoZWJ8O9MaUM6j5P-yL33dJNOQMr6aEJ4he2ZCXQ',
  );

  runApp(const WomenSafetyApp());
}

class WomenSafetyApp extends StatelessWidget {
  const WomenSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),  // ✅ NEW
      ],
      child: Consumer<ThemeProvider>(  // ✅ NEW: Listen to theme changes
        builder: (context, themeProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: "Women Safety",
            
            // ✅ NEW: Dynamic theme
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            
            initialRoute: '/',
            routes: {
              '/': (_) => const SplashScreen(),
              '/onboarding': (_) => const OnboardingScreen(),
              '/login': (_) => const LoginScreen(),
              '/register': (_) => const RegisterScreen(),
              '/home': (_) => const HomeScreen(),
              '/profile': (_) => const ProfileSetupScreen(),
              '/contacts': (_) => const EmergencyContactsScreen(),
              '/recordings': (_) => const RecordingsScreen(),
              '/safe_zones': (_) => const SafeZoneManagementScreen(),
            },
          );
        },
      ),
    );
  }
}
