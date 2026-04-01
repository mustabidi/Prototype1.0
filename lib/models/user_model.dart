import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String city;
  final String area;
  final String role;
  final bool verified;
  final List<String> fcmTokens;
  final double trustScore;
  final Timestamp? lastPostAt;
  final List<String> blockedUsers;

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.city,
    required this.area,
    required this.role,
    required this.verified,
    required this.fcmTokens,
    this.trustScore = 1.0,
    this.lastPostAt,
    this.blockedUsers = const [],
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      city: data['city'] ?? '',
      area: data['area'] ?? '',
      role: data['role'] ?? 'user',
      verified: data['verified'] ?? false,
      fcmTokens: List<String>.from(data['fcmTokens'] ?? []),
      trustScore: (data['trustScore'] ?? 1.0).toDouble(),
      lastPostAt: data['lastPostAt'],
      blockedUsers: List<String>.from(data['blockedUsers'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'city': city,
      'area': area,
      'role': role,
      'verified': verified,
      'fcmTokens': fcmTokens,
      'trustScore': trustScore,
      if (lastPostAt != null) 'lastPostAt': lastPostAt,
      if (blockedUsers.isNotEmpty) 'blockedUsers': blockedUsers,
    };
  }
}
