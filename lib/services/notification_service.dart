import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> initialize(String uid) async {
    // 1. Request Permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');

      // 2. Get Token
      String? token = await _fcm.getToken();
      if (token != null) {
        await _firestoreService.saveFcmToken(uid, token);
      }

      // 3. Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _firestoreService.saveFcmToken(uid, newToken);
      });

      // 4. Handle background messages
      // This part normally requires a background handler function in main.dart
    } else {
      debugPrint('User declined or has not accepted permission');
    }
  }

  // Client-side notification dedup set
  final Set<String> _receivedPostIds = {};
  bool _foregroundListenerActive = false;

  // Throttle: max 3 notifications per rolling hour
  static const int _maxNotificationsPerHour = 3;
  final List<DateTime> _notificationTimestamps = [];

  bool _isThrottled() {
    final now = DateTime.now();
    // Remove timestamps older than 1 hour
    _notificationTimestamps.removeWhere(
      (ts) => now.difference(ts).inMinutes >= 60,
    );
    return _notificationTimestamps.length >= _maxNotificationsPerHour;
  }

  void _recordNotification() {
    _notificationTimestamps.add(DateTime.now());
  }

  /// Listen for foreground messages with dedup + throttle
  void listenToForeground() {
    if (_foregroundListenerActive) return;
    _foregroundListenerActive = true;
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final postId = message.data['postId'];
      final authorId = message.data['authorId'];
      
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && authorId != null) {
        try {
          final userDoc = await _firestoreService.getUser(user.uid);
          if (userDoc.blockedUsers.contains(authorId)) {
            debugPrint('Duplicate notification suppressed: blocked author');
            return;
          }
        } catch (_) {}
      }
      
      // Client-side dedup: if we already showed this postId, skip
      if (postId != null && _receivedPostIds.contains(postId)) {
        debugPrint('Duplicate notification suppressed for post: $postId');
        return;
      }

      // Throttle: drop if already shown 3 notifications this hour
      if (_isThrottled()) {
        debugPrint('Notification throttled: max $_maxNotificationsPerHour/hour reached');
        return;
      }

      if (postId != null) {
        _receivedPostIds.add(postId);
        // Prevent memory leak: cap dedup set at 200 entries
        if (_receivedPostIds.length > 200) {
          _receivedPostIds.remove(_receivedPostIds.first);
        }
      }

      _recordNotification();
      debugPrint('Foreground Message: ${message.notification?.title}');
      // Here you could show a local notification snackbar
    });
  }

  /// Subscribe user to relevant topics based on location (Phase 6)
  Future<void> updateTopics(double lat, double lng, String city) async {
    try {
      final sanitizedCity = city.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      await _fcm.subscribeToTopic('city_$sanitizedCity');
      
      // We don't have direct geoflutterfire2 import here so use the one in firestore
      final point = _firestoreService.geo.point(latitude: lat, longitude: lng);
      final hash5 = point.hash.substring(0, 5); // 5 characters = ~5km x 5km box
      await _fcm.subscribeToTopic('geo_$hash5');
      
      debugPrint('Subscribed to topics: city_$sanitizedCity, geo_$hash5');
    } catch (e) {
      debugPrint('Failed to subscribe to topics: $e');
    }
  }
}
