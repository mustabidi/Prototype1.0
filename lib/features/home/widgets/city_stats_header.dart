import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CityStatsHeader extends StatelessWidget {
  final String city;

  const CityStatsHeader({Key? key, required this.city}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (city.isEmpty) return SizedBox.shrink();

    final sanitizedCity = city.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

    // Using StreamBuilder to implicitly cache connection to 'stats/{city}'. 
    // It updates reactively when the Cloud Function changes the distributed counter.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('stats').doc(sanitizedCity).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final activePosts = data['activePosts'] ?? 0;

        if (activePosts <= 0) return SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Colors.blue[50],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights, size: 16, color: Colors.blue[700]),
              SizedBox(width: 8),
              Text(
                '🔥 $activePosts active posts in $city right now',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
