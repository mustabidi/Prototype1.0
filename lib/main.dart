import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';

import 'features/auth/auth_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/main_navigation_screen.dart';
import 'features/home/post_detail_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Connect to the generic dummy Firebase config so the APK boots without crashing
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Phase 6: Automatic Crash Reporting (guarded against pre-init)
  FlutterError.onError = (errorDetails) {
    try {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    } catch (e) {
      debugPrint('Crashlytics not initialized: $e');
    }
  };

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (e) {
      debugPrint('Crashlytics not initialized: $e');
    }
    return true;
  };

  runApp(ProviderScope(child: MyApp()));
}

final GoRouter _router = GoRouter(
  initialLocation: '/auth',
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isOnAuth = state.matchedLocation == '/auth';

    // If logged in and trying to access auth, redirect to home
    if (user != null && isOnAuth) return '/';
    // If not logged in and not on auth, redirect to auth (unless they are onboarding)
    if (user == null && !isOnAuth && state.matchedLocation != '/onboarding') return '/auth';
    return null;
  },
  routes: [
    GoRoute(
      path: '/auth',
      builder: (context, state) => AuthScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => OnboardingScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => MainNavigationScreen(),
    ),
    GoRoute(
      path: '/post/:id',
      builder: (context, state) {
        final postId = state.pathParameters['id']!;
        return PostDetailScreen(postId: postId);
      },
    ),
  ],
);

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Community Support',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
