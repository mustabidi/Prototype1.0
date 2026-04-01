import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'dummy-api-key-for-testing',
      appId: '1:1234567890:android:abcdef1234567',
      messagingSenderId: '1234567890',
      projectId: 'dummy-project',
      storageBucket: 'dummy-project.appspot.com',
    );
  }
}
