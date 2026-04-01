import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../models/business_model.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_states.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../business/widgets/business_card.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<UserModel> _userFuture;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userFuture = _firestoreService.getUser(user.uid);
    }
  }

  void _retry() {
    setState(() {
      _loadUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: EmptyListState(
          title: 'Not Logged In',
          subtitle: 'Please log in to view your profile',
          buttonText: 'Go to Login',
          onAction: () => context.go('/auth'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              _firestoreService.clearUserCache();
              await AuthService().signOut();
              context.go('/auth');
            },
          )
        ],
      ),
      body: FutureBuilder<UserModel>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 32),
                  SkeletonLoader(width: 100, height: 100, borderRadius: 50),
                  SizedBox(height: 16),
                  SkeletonLoader(width: 150, height: 24),
                  SizedBox(height: 8),
                  SkeletonLoader(width: 100, height: 16),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return NoInternetState(onRetry: _retry);
          }

          if (!snapshot.hasData) {
            return EmptyListState(
              title: 'Profile Not Found',
              subtitle: 'We could not find your profile data.',
              icon: Icons.person_off,
            );
          }

          final userData = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue[100],
                  child: Text(
                    userData.name.isNotEmpty ? userData.name[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 32, color: Colors.blue[900]),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      userData.name,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (userData.verified) ...[
                      SizedBox(width: 8),
                      Icon(Icons.verified, color: Colors.blue, size: 24),
                    ]
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '${userData.area}, ${userData.city}',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 8),
                Text(
                  userData.phone,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 32),
                Divider(),
                /*
                ListTile(
                  leading: Icon(Icons.history),
                  title: Text('My Posts'),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigate to user posts — Phase 3
                  },
                ),
                SizedBox(height: 16),
                */
                
                // My Businesses Section
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('My Businesses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                FutureBuilder<QuerySnapshot>(
                  future: _firestoreService.getUserBusinessesQuery(user.uid).get(),
                  builder: (context, bizSnapshot) {
                    if (bizSnapshot.connectionState == ConnectionState.waiting) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (bizSnapshot.hasError || !bizSnapshot.hasData || bizSnapshot.data!.docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('No businesses listed yet.', style: TextStyle(color: Colors.grey)),
                      );
                    }
                    
                    final businesses = bizSnapshot.data!.docs
                        .map((doc) => BusinessModel.fromFirestore(doc))
                        .toList();
                        
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: businesses.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: BusinessCard(
                            business: businesses[index],
                            showStatusBadge: true, // Always show status in Profile
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
