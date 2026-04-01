import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_states.dart';
import 'widgets/business_card.dart';
import 'create_business_screen.dart';

class BusinessScreen extends StatefulWidget {
  @override
  _BusinessScreenState createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<BusinessModel> _businesses = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  // User context
  String _userCity = '';
  String _userArea = '';

  // Filter
  String? _selectedCategory;
  
  // 12 Hardcoded Categories
  final List<String> _categories = [
    'Emergency',
    'Medical',
    'Food & Restaurants',
    'Groceries',
    'Pharmacy',
    'Electrician',
    'Plumber',
    'Mechanic',
    'Home Services',
    'Tuition & Education',
    'Delivery & Logistics',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserAndDirectory();
  }

  Future<void> _loadUserAndDirectory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestoreService.getUser(user.uid);
      _userCity = userDoc.city;
      _userArea = userDoc.area;
      await _loadBusinesses();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load directory';
      });
    }
  }

  Future<void> _loadBusinesses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshot = await _firestoreService
          .getApprovedBusinessesQuery(_userCity, category: _selectedCategory)
          .get();

      List<BusinessModel> fetched = snapshot.docs
          .map((doc) => BusinessModel.fromFirestore(doc))
          .toList();

      // Rule: Priority sorting locally (1. Same Area, 2. Others in City)
      fetched.sort((a, b) {
        if (a.area == _userArea && b.area != _userArea) return -1;
        if (a.area != _userArea && b.area == _userArea) return 1;
        // Fallback: descending by creation date (newest first)
        return b.createdAt.compareTo(a.createdAt);
      });

      setState(() {
        _businesses = fetched;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load businesses';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Local Directory'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Container(
            height: 50,
            padding: EdgeInsets.only(bottom: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text('All'),
                      selected: _selectedCategory == null,
                      onSelected: (selected) {
                        setState(() => _selectedCategory = null);
                        _loadBusinesses();
                      },
                    ),
                  );
                }
                
                final cat = _categories[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: _selectedCategory == cat,
                    onSelected: (selected) {
                      setState(() => _selectedCategory = selected ? cat : null);
                      _loadBusinesses();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(Icons.add_business),
        label: Text('List Business'),
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CreateBusinessScreen()),
          );
          if (result == true) {
            // Re-fetch directory if they listed something
            // Though it will be pending status, refreshing ensures clean state anyway
            _loadBusinesses();
          }
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView.builder(
        padding: EdgeInsets.all(8),
        itemCount: 4,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: SkeletonLoader(width: double.infinity, height: 100, borderRadius: 12),
        ),
      );
    }

    if (_errorMessage != null) {
      return NoInternetState(onRetry: _loadUserAndDirectory);
    }

    if (_businesses.isEmpty) {
      return EmptyListState(
        title: 'No businesses found',
        subtitle: _selectedCategory == null 
            ? 'Be the first to list a business in $_userCity!'
            : 'No $_selectedCategory found in $_userCity yet.',
        icon: Icons.store_mall_directory_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBusinesses,
      child: ListView.builder(
        padding: EdgeInsets.all(8),
        itemCount: _businesses.length,
        itemBuilder: (context, index) {
          final business = _businesses[index];
          
          // Inject an "In your area" header if this is the first item matching the user's area
          bool isFirstInArea = false;
          bool isFirstOutsideArea = false;
          
          if (index == 0 && business.area == _userArea) {
            isFirstInArea = true;
          } else if (business.area != _userArea && (index == 0 || _businesses[index - 1].area == _userArea)) {
            isFirstOutsideArea = true;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFirstInArea)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 16, bottom: 8),
                  child: Text('Near you ($_userArea)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ),
              if (isFirstOutsideArea)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 24, bottom: 8),
                  child: Text('Other areas in $_userCity', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                ),
              BusinessCard(business: business),
            ],
          );
        },
      ),
    );
  }
}
