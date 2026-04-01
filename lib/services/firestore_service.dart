import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';

/// Centralized Firestore operations.
/// All read/write logic goes through here — never call Firestore directly from UI.
class FirestoreService {
  // Singleton pattern to ensure caching works globally
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final geo = GeoFlutterFire();

  // ─── USERS ───────────────────────────────────────────────

  UserModel? _cachedUser;

  void clearUserCache() {
    _cachedUser = null;
  }

  Future<UserModel> getUser(String uid) async {
    if (_cachedUser != null && _cachedUser!.uid == uid) {
      return _cachedUser!;
    }

    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('User profile not found');
    }
    
    _cachedUser = UserModel.fromFirestore(doc);
    return _cachedUser!;
  }

  Future<void> updateLastActive(String uid) {
    return _db.collection('users').doc(uid).update({
      'lastActive': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateLastPostAt(String uid) async {
    await _db.collection('users').doc(uid).update({
      'lastPostAt': FieldValue.serverTimestamp(),
    });
    clearUserCache();
  }

  Future<void> blockUser(String currentUserId, String blockedUserId) async {
    if (currentUserId == blockedUserId) return;
    await _db.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayUnion([blockedUserId])
    });
    clearUserCache(); // Force refetch so blocked posts vanish immediately
  }

  Future<void> saveFcmToken(String uid, String token) {
    return _db.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  Future<void> createUserProfile(String uid, Map<String, dynamic> userData) async {
    userData.remove('uid'); // Ensure redundant uid isn't stored in document body
    if (!userData.containsKey('trustScore')) {
      userData['trustScore'] = 1.0;
    }
    if (!userData.containsKey('createdAt')) {
      userData['createdAt'] = FieldValue.serverTimestamp();
    }
    await _db.collection('users').doc(uid).set(userData);
    _cachedUser = null; // Clear cache to be safe
  }

  // ─── FEED QUERIES ────────────────────────────────────────

  /// Geo Radius Feed (Phase 5): Get all posts within a certain radius (default 5km)
  Stream<List<PostModel>> getGeoFeedStream(double lat, double lng, {double radiusParams = 5}) {
    final collectionReference = _db.collection('posts').where('isActive', isEqualTo: true);
    final GeoFirePoint center = geo.point(latitude: lat, longitude: lng);

    return geo.collection(collectionRef: collectionReference)
        .within(center: center, radius: radiusParams, field: 'location', strictMode: true)
        .map((docs) => docs.map((d) => PostModel.fromFirestore(d)).toList());
  }

  /// City feed: posts matching user's city, sorted by urgency + time.
  Query getCityFeedQuery(String city) {
    return _db
        .collection('posts')
        .where('city', isEqualTo: city)
        .where('isActive', isEqualTo: true)
        .orderBy('urgencyLevel', descending: true)
        .orderBy('timestamp', descending: true)
        .limit(20);
  }

  /// India feed: all posts nationally, sorted by urgency + time.
  Query getIndiaFeedQuery() {
    return _db
        .collection('posts')
        .where('isActive', isEqualTo: true)
        .orderBy('urgencyLevel', descending: true)
        .orderBy('timestamp', descending: true)
        .limit(20);
  }

  /// City feed fallback for Local tab (when GPS is unavailable).
  Query getLocalFallbackQuery(String city, String area) {
    return _db
        .collection('posts')
        .where('city', isEqualTo: city)
        .where('area', isEqualTo: area)
        .where('isActive', isEqualTo: true)
        .orderBy('urgencyLevel', descending: true)
        .orderBy('timestamp', descending: true)
        .limit(20);
  }

  /// Paginate: get next page after the last document.
  Query paginateQuery(Query baseQuery, DocumentSnapshot lastDoc) {
    return baseQuery.startAfterDocument(lastDoc);
  }

  // ─── POST CREATION ──────────────────────────────────────

  /// Get a new document reference ID before uploading.
  String getNewPostId() {
    return _db.collection('posts').doc().id;
  }

  /// Create a new post with a pre-generated ID.
  Future<void> savePost(String postId, Map<String, dynamic> postData) async {
    await _db.collection('posts').doc(postId).set(postData);
  }

  /// Get a single post by ID (used for deep linking notifications)
  Future<PostModel?> getPostById(String postId) async {
    try {
      final doc = await _db.collection('posts').doc(postId).get();
      if (doc.exists) {
        return PostModel.fromFirestore(doc);
      }
    } catch (e) {
      debugPrint('Error getting post: $e');
    }
    return null;
  }

  /// Soft delete a post
  Future<void> softDeletePost(String postId) {
    return _db.collection('posts').doc(postId).update({'isActive': false});
  }

  // ─── RATE LIMITING ──────────────────────────────────────

  /// Get today's activity counts for a user.
  Future<Map<String, dynamic>?> getUserActivity(String uid) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final docId = '${uid}_$today';
    final doc = await _db.collection('user_activity').doc(docId).get();
    return doc.exists ? doc.data() : null;
  }

  /// Check if user can post (returns null if OK, or error message if blocked).
  Future<String?> checkRateLimit(String uid, {bool isHelp = false}) async {
    try {
      final userDoc = await getUser(uid);
      if (userDoc.lastPostAt != null) {
        final diff = DateTime.now().difference(userDoc.lastPostAt!.toDate());
        if (diff.inSeconds < 60) {
          final wait = 60 - diff.inSeconds;
          return 'Please wait $wait seconds before posting again.';
        }
      }
    } catch (e) {
      // ignore user fetch error here, proceed to limits
    }

    final activity = await getUserActivity(uid);
    if (activity == null) return null; // No activity today — allowed

    final postCount = activity['postCount'] ?? 0;
    final helpCount = activity['helpCount'] ?? 0;

    if (postCount >= AppConstants.MAX_POSTS_PER_DAY) {
      return 'Daily post limit reached (${AppConstants.MAX_POSTS_PER_DAY}/day). Try again tomorrow.';
    }
    if (isHelp && helpCount >= AppConstants.MAX_HELP_PER_DAY) {
      return 'Daily help request limit reached (${AppConstants.MAX_HELP_PER_DAY}/day). Try again tomorrow.';
    }
    return null;
  }

  /// Increment post count for today.
  Future<void> incrementPostCount(String uid) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final docId = '${uid}_$today';
    final ref = _db.collection('user_activity').doc(docId);
    final doc = await ref.get();

    if (doc.exists) {
      await ref.update({'postCount': FieldValue.increment(1)});
    } else {
      await ref.set({
        'userId': uid,
        'date': today,
        'postCount': 1,
        'helpCount': 0,
      });
    }
  }

  /// Increment help request count for today.
  Future<void> incrementHelpCount(String uid) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final docId = '${uid}_$today';
    final ref = _db.collection('user_activity').doc(docId);
    final doc = await ref.get();

    if (doc.exists) {
      await ref.update({
        'postCount': FieldValue.increment(1),
        'helpCount': FieldValue.increment(1),
      });
    } else {
      await ref.set({
        'userId': uid,
        'date': today,
        'postCount': 1,
        'helpCount': 1,
      });
    }
  }

  // ─── BUSINESS DIRECTORY ─────────────────────────────────

  /// Get a new document reference ID for a business.
  String getNewBusinessId() {
    return _db.collection('businesses').doc().id;
  }

  /// Create a new business profile.
  Future<void> saveBusiness(String businessId, Map<String, dynamic> data) {
    return _db.collection('businesses').doc(businessId).set(data);
  }

  /// Fetch approved businesses for a specific city, optionally filtered by category.
  Query getApprovedBusinessesQuery(String city, {String? category}) {
    Query query = _db
        .collection('businesses')
        .where('city', isEqualTo: city)
        .where('status', isEqualTo: 'approved');
        
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    
    // Sort logic (pre-geo): descending creation time. 
    // Area priority will be handled natively in the UI list building.
    return query.orderBy('createdAt', descending: true).limit(20);
  }

  /// Fetch all businesses submitted by a user for their profile.
  Query getUserBusinessesQuery(String uid) {
    return _db
        .collection('businesses')
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
  }

  // ─── UPVOTES & REPORTS ──────────────────────────────────
  
  Future<void> upvotePost(String postId, String voterId, String postOwnerId) async {
    if (voterId == postOwnerId) {
      throw Exception('Cannot upvote your own post');
    }
    
    // Eligibility: trust >= 1 and account age > 24h
    final voterDoc = await getUser(voterId);
    if (voterDoc.trustScore < 1) {
      throw Exception('Your trust score is too low to upvote');
    }
    final voterUserDoc = await _db.collection('users').doc(voterId).get();
    final createdAt = voterUserDoc.data()?['createdAt'] as Timestamp?;
    if (createdAt != null) {
      final ageHours = DateTime.now().difference(createdAt.toDate()).inHours;
      if (ageHours < 24) {
        throw Exception('Your account must be at least 24 hours old to upvote');
      }
    }
    
    final voteRef = _db.collection('post_votes').doc('${postId}_$voterId');
    final voteDoc = await voteRef.get();
    
    if (voteDoc.exists) {
      throw Exception('You already upvoted this post');
    }
    
    // Write vote and increment counter
    await voteRef.set({
      'postId': postId,
      'userId': voterId,
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    await _db.collection('posts').doc(postId).update({
      'upvoteCount': FieldValue.increment(1)
    });
  }

  Future<void> reportPost(String postId, String reportedBy, String reason) async {
    // Gate: trust >= 1 required to report
    final reporter = await getUser(reportedBy);
    if (reporter.trustScore < 1) {
      throw Exception('Your trust score is too low to report posts');
    }

    // Rate limit: max 1 report per minute
    final recentReports = await _db.collection('reports')
        .where('reportedBy', isEqualTo: reportedBy)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (recentReports.docs.isNotEmpty) {
      final lastReport = recentReports.docs.first.data()['createdAt'] as Timestamp?;
      if (lastReport != null) {
        final diff = DateTime.now().difference(lastReport.toDate());
        if (diff.inSeconds < 60) {
          throw Exception('Please wait before reporting again');
        }
      }
    }

    // Rate limit: max 5 reports per day
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final dailyReports = await _db.collection('reports')
        .where('reportedBy', isEqualTo: reportedBy)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .get();
    if (dailyReports.docs.length >= 5) {
      throw Exception('Daily report limit reached (5/day)');
    }

    // Uniqueness: 1 report per user per post
    final reportRef = _db.collection('reports').doc('${postId}_$reportedBy');
    final doc = await reportRef.get();
    if (doc.exists) {
      throw Exception('You have already reported this post');
    }

    await reportRef.set({
      'postId': postId,
      'reportedBy': reportedBy,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
