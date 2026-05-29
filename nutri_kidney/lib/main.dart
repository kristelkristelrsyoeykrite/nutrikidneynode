import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login/login.dart';
import 'main/dashboard.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (!kIsWeb) {
    await PushNotificationService.initialize();
    await NotificationService.initialize();
    await NotificationService.canScheduleExactAlarms();
  }
  runApp(const NutriKidneyApp());
}

class NutriKidneyApp extends StatefulWidget {
  const NutriKidneyApp({super.key});

  @override
  State<NutriKidneyApp> createState() => _NutriKidneyAppState();
}

class _NutriKidneyAppState extends State<NutriKidneyApp> {
  late Future<Widget> _homePageFuture;

  @override
  void initState() {
    super.initState();
    _homePageFuture = _determineHomePage();
  }

  Future<Widget> _determineHomePage() async {
    // Check if user has a remembered session
    final hasRememberedSession = await AuthService.hasRememberedSession();
    
    if (hasRememberedSession) {
      if (!kIsWeb) {
        await PushNotificationService.syncTokenIfPossible();
      }
      // User has a valid remembered session - take them to dashboard
      return const DashboardPage();
    } else {
      // No remembered session - go to login.
      // hasRememberedSession() already clears any invalid persisted auth state.
      return const LoginPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nutri Kidney',
      home: FutureBuilder<Widget>(
        future: _homePageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show loading splash while determining home page
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DB6AC)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Nutri Kidney'),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            // Error occurred - default to login
            return const LoginPage();
          }

          // Return the appropriate home page
          return snapshot.data ?? const LoginPage();
        },
      ),
    );
  }
}
