import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'dart:io';

import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';

class CreateBusinessScreen extends StatefulWidget {
  @override
  _CreateBusinessScreenState createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _phoneController = TextEditingController();

  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  File? _logoImage;
  String _selectedCategory = 'Home Services';

  // Strict 12 Categories rule
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
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Save bandwidth
    );
    if (image != null) {
      setState(() => _logoImage = File(image.path));
    }
  }

  Future<void> _submitBusiness() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_logoImage == null) {
      _showError('A business logo or image is required.');
      return;
    }

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      _showError('Not logged in');
      return;
    }

    try {
      // 1. Get user data for inheritance (city/area fallback)
      final userDoc = await _firestoreService.getUser(user.uid);
      final String userCity = userDoc.city;
      final String userArea = userDoc.area;

      // 2. Pre-generate ID to match Storage path requirement
      final String businessId = _firestoreService.getNewBusinessId();

      // 3. Upload Logo
      final String logoUrl = await _storageService.uploadBusinessLogo(
        userId: user.uid,
        businessId: businessId,
        imageFile: _logoImage!,
      );

      // 4. Build Document
      Map<String, dynamic> businessData = {
        'ownerId': user.uid,
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'phone': _phoneController.text.trim(),
        'category': _selectedCategory,
        'city': userCity,
        'area': userArea,
        'status': 'pending', // Requires admin approval
        'imageUrl': logoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 5. Append GPS if available
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        final geo = GeoFlutterFire();
        final GeoFirePoint myLoc = geo.point(latitude: position.latitude, longitude: position.longitude);
        businessData['location'] = myLoc.data;
      }

      // 6. Save to Firestore
      await _firestoreService.saveBusiness(businessId, businessData);

      if (mounted) {
        // Show the mandated UX
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Business Submitted ✅'),
            content: Text('Your business is under review. It will appear in the directory once approved.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context, true); // Close screen & refresh profile/feed
                },
                child: Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showError('Failed to list business. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('List Your Business'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submitBusiness,
            child: _isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Submit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo Picker
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                      image: _logoImage != null
                          ? DecorationImage(
                              image: FileImage(_logoImage!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _logoImage == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('Add Logo', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              SizedBox(height: 32),

              // Name
              Text('Business Name', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Sharma Plumbing Services',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 3) {
                    return 'Name must be at least 3 characters long';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Category Dropdown
              Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: _categories
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              SizedBox(height: 20),

              // Description
              Text('Description', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'What services do you provide? What are your timings?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 15) {
                    return 'Description must be at least 15 characters long';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Phone Number
              Text('Contact Number', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'e.g. 9876543210',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Contact number is required';
                  }
                  // Basic validation: must be digits and at least 10 chars
                  if (!RegExp(r'^\d{10,}$').hasMatch(value.trim())) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
