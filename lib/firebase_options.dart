import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBZn7QDHNvXKMAQIEXAgh0Wui-GZK5oG7M',
      appId: '1:120788081219:web:ae4a74ff55c96d9aed12f6',
      messagingSenderId: '120788081219',
      projectId: 'prototype-ba1e6',
      storageBucket: 'prototype-ba1e6.firebasestorage.app',
    );
  }
}
