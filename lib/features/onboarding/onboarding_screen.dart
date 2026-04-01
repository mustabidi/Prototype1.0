import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Predefined lists — manual selection, no GPS errors
  String? _selectedCity;
  String? _selectedArea;

  // TODO: Replace with full list from backend or config
  final Map<String, List<String>> _cityAreaMap = {
    'Mumbai': ['Andheri', 'Bandra', 'Borivali', 'Dadar', 'Juhu', 'Kurla', 'Malad', 'Powai', 'Thane', 'Worli'],
    'Delhi': ['Connaught Place', 'Dwarka', 'Karol Bagh', 'Lajpat Nagar', 'Rohini', 'Saket'],
    'Bangalore': ['BTM Layout', 'HSR Layout', 'Indiranagar', 'Koramangala', 'Whitefield'],
    'Hyderabad': ['Banjara Hills', 'Gachibowli', 'HITEC City', 'Jubilee Hills', 'Madhapur'],
    'Chennai': ['Adyar', 'Anna Nagar', 'T. Nagar', 'Velachery'],
    'Pune': ['Hinjewadi', 'Kharadi', 'Koregaon Park', 'Viman Nagar'],
  };

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveUserData() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCity == null || _selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select your City and Area')),
      );
      return;
    }

    setState(() => _isLoading = true);
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      await FirestoreService().createUserProfile(currentUser.uid, {
        'name': _nameController.text.trim(),
        'phone': currentUser.phoneNumber ?? '',
        'city': _selectedCity,
        'area': _selectedArea,
        'role': 'user',
        'verified': false,
        'fcmTokens': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      });
      context.go('/');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save. Check your connection and retry.')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = _cityAreaMap.keys.toList();
    final areas = _selectedCity != null ? _cityAreaMap[_selectedCity]! : <String>[];

    return Scaffold(
      appBar: AppBar(title: Text('Setup Your Profile')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Full Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Name is required';
                  if (value.trim().length < 2) return 'Name too short';
                  return null;
                },
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCity,
                decoration: InputDecoration(labelText: 'City'),
                items: cities.map((city) => DropdownMenuItem(value: city, child: Text(city))).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCity = value;
                    _selectedArea = null; // reset area when city changes
                  });
                },
                validator: (value) => value == null ? 'Select a city' : null,
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedArea,
                decoration: InputDecoration(labelText: 'Local Area'),
                items: areas.map((area) => DropdownMenuItem(value: area, child: Text(area))).toList(),
                onChanged: (value) {
                  setState(() => _selectedArea = value);
                },
                validator: (value) => value == null ? 'Select an area' : null,
              ),
              SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveUserData,
                  child: _isLoading
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Complete Setup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
