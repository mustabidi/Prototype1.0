import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String userId;
  final String type; // 'help', 'update', 'normal'
  final String content;
  final String category;
  final int urgencyLevel; // 1 = low, 2 = medium, 3 = high
  final String? status; // only for type == 'update': 'issue' / 'resolved'
  final List<String> images;
  final String city;
  final String area;
  final Timestamp timestamp;
  final bool isActive;
  final Timestamp? expiresAt;
  final double authorTrustScore;
  final int upvoteCount;
  final int reportCount;
  // location.geopoint and location.geohash handled separately via geoflutterfire2

  PostModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    required this.category,
    required this.urgencyLevel,
    this.status,
    required this.images,
    required this.city,
    required this.area,
    required this.timestamp,
    this.isActive = true,
    this.expiresAt,
    this.authorTrustScore = 1.0,
    this.upvoteCount = 0,
    this.reportCount = 0,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: data['type'] ?? 'normal',
      content: data['content'] ?? '',
      category: data['category'] ?? '',
      urgencyLevel: data['urgencyLevel'] ?? 1,
      status: data['status'],
      images: List<String>.from(data['images'] ?? []),
      city: data['city'] ?? '',
      area: data['area'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      isActive: data['isActive'] ?? true,
      expiresAt: data['expiresAt'],
      authorTrustScore: (data['authorTrustScore'] ?? 1.0).toDouble(),
      upvoteCount: data['upvoteCount'] ?? 0,
      reportCount: data['reportCount'] ?? 0,
    );
  }

  int get score {
    int urgencyScore = urgencyLevel * 50;

    int typeWeight = 10;
    if (type == 'help') typeWeight = 80;
    else if (type == 'update') typeWeight = 40;

    int freshnessScore = 0;
    final hours = DateTime.now().difference(timestamp.toDate()).inHours;
    if (hours < 1) freshnessScore = 60;
    else if (hours < 6) freshnessScore = 40;
    else if (hours < 24) freshnessScore = 20;
    else freshnessScore = 0;

    int upvoteScore = upvoteCount * 5;
    if (upvoteScore > 50) upvoteScore = 50;
    
    int trustScoreBonus = (authorTrustScore * 10).toInt();

    return urgencyScore + typeWeight + freshnessScore + upvoteScore + trustScoreBonus;
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'content': content,
      'category': category,
      'urgencyLevel': urgencyLevel,
      if (status != null) 'status': status,
      'images': images,
      'city': city,
      'area': area,
      'timestamp': timestamp,
      'isActive': isActive,
      if (expiresAt != null) 'expiresAt': expiresAt,
      'authorTrustScore': authorTrustScore,
      'upvoteCount': upvoteCount,
      'reportCount': reportCount,
    };
  }
}
