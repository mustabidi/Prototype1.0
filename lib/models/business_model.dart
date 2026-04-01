import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessModel {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String category;
  final String phone;
  final String city;
  final String area;
  final String status; // 'pending', 'approved', 'rejected'
  final String imageUrl; // Required business logo
  final Timestamp createdAt;
  // location.geopoint and location.geohash

  BusinessModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    required this.category,
    required this.phone,
    required this.city,
    required this.area,
    required this.status,
    required this.imageUrl,
    required this.createdAt,
  });

  factory BusinessModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return BusinessModel(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? 'Other',
      phone: data['phone'] ?? '',
      city: data['city'] ?? '',
      area: data['area'] ?? '',
      status: data['status'] ?? 'pending',
      imageUrl: data['imageUrl'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }
}
