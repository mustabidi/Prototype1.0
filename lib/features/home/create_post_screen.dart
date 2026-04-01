import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'dart:io';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';

class CreatePostScreen extends StatefulWidget {
  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;

  // Selected images
  List<File> _selectedImages = [];

  // Post fields
  String _selectedType = 'normal';
  String _selectedCategory = 'General';
  int _selectedUrgency = 1;
  String? _selectedStatus; // only for 'update' type

  final List<String> _postTypes = ['normal', 'help', 'update'];
  final List<String> _categories = [
    'General',
    'Water',
    'Electricity',
    'Medical',
    'Safety',
    'Road',
    'Noise',
    'Other',
  ];

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      _showError('Not logged in');
      return;
    }

    // Rate limit check
    final isHelp = _selectedType == 'help';
    final rateLimitMsg = await _firestoreService.checkRateLimit(user.uid, isHelp: isHelp);
    if (rateLimitMsg != null) {
      setState(() => _isLoading = false);
      _showError(rateLimitMsg);
      return;
    }

    // Get user data for city/area
    final userDoc = await _firestoreService.getUser(user.uid);
    final String userCity = userDoc.city;
    final String userArea = userDoc.area;

    // Build post data
    final String postId = _firestoreService.getNewPostId();
    List<String> imageUrls = [];

    try {
      if (_selectedImages.isNotEmpty) {
        imageUrls = await _storageService.uploadPostImages(
          userId: user.uid,
          postId: postId,
          imageFiles: _selectedImages,
        );
      }

      final expiryHours = _selectedType == 'help' ? 24 : 48;
      final expiresAt = DateTime.now().add(Duration(hours: expiryHours));

      Map<String, dynamic> postData = {
        'userId': user.uid,
        'type': _selectedType,
        'content': _contentController.text.trim(),
        'category': _selectedCategory,
        'urgencyLevel': _selectedUrgency,
        'images': imageUrls,
        'city': userCity,
        'area': userArea,
        'timestamp': FieldValue.serverTimestamp(),
        'isActive': true,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'authorTrustScore': userDoc.trustScore,
        'upvoteCount': 0,
        'reportCount': 0,
      };

      // Add status only for update type
      if (_selectedType == 'update') {
        postData['status'] = _selectedStatus ?? 'issue';
      }

      // Add location if GPS is available
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        final geo = GeoFlutterFire();
        final GeoFirePoint myLoc = geo.point(latitude: position.latitude, longitude: position.longitude);
        postData['location'] = myLoc.data;
      }

      // Wait until images are fully uploaded to create the post
      await _firestoreService.savePost(postId, postData);

      // Update cooldown
      await _firestoreService.updateLastPostAt(user.uid);

      // Increment rate limit counters
      if (isHelp) {
        await _firestoreService.incrementHelpCount(user.uid);
      } else {
        await _firestoreService.incrementPostCount(user.uid);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post created successfully!')),
        );
        Navigator.of(context).pop(true); // Return true to trigger feed refresh
      }
    } catch (e) {
      _showError('Failed to create post. Check your connection.');
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
        title: Text('Create Post'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submitPost,
            child: _isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Post', style: TextStyle(fontWeight: FontWeight.bold)),
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
              // Post Type
              Text('Post Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              SegmentedButton<String>(
                segments: _postTypes.map((type) {
                  IconData icon;
                  switch (type) {
                    case 'help':
                      icon = Icons.health_and_safety;
                      break;
                    case 'update':
                      icon = Icons.campaign;
                      break;
                    default:
                      icon = Icons.edit_note;
                  }
                  return ButtonSegment(
                    value: type,
                    label: Text(type[0].toUpperCase() + type.substring(1)),
                    icon: Icon(icon),
                  );
                }).toList(),
                selected: {_selectedType},
                onSelectionChanged: (selected) {
                  setState(() {
                    _selectedType = selected.first;
                    // Auto-set urgency for help posts
                    if (_selectedType == 'help') {
                      _selectedUrgency = 3;
                    }
                    // Reset status if not update
                    if (_selectedType != 'update') {
                      _selectedStatus = null;
                    }
                  });
                },
              ),

              SizedBox(height: 20),

              // Category
              Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: _categories
                    .map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),

              SizedBox(height: 20),

              // Urgency
              Text('Urgency Level', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 1, label: Text('Low'), icon: Icon(Icons.arrow_downward)),
                  ButtonSegment(value: 2, label: Text('Medium'), icon: Icon(Icons.remove)),
                  ButtonSegment(value: 3, label: Text('High'), icon: Icon(Icons.arrow_upward)),
                ],
                selected: {_selectedUrgency},
                onSelectionChanged: (selected) {
                  setState(() => _selectedUrgency = selected.first);
                },
              ),

              // Status (only for update type)
              if (_selectedType == 'update') ...[
                SizedBox(height: 20),
                Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'issue', label: Text('⚠️ Issue')),
                    ButtonSegment(value: 'resolved', label: Text('✅ Resolved')),
                  ],
                  selected: {_selectedStatus ?? 'issue'},
                  onSelectionChanged: (selected) {
                    setState(() => _selectedStatus = selected.first);
                  },
                ),
              ],

              SizedBox(height: 20),

              // Content
              Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              TextFormField(
                controller: _contentController,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe what\'s happening...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Description is required';
                  if (value.trim().length < 10) return 'Please write at least 10 characters';
                  return null;
                },
              ),

              SizedBox(height: 20),

              // Image Selection
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Images (${_selectedImages.length}/3)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (_selectedImages.length < 3)
                    TextButton.icon(
                      icon: Icon(Icons.add_photo_alternate, size: 20),
                      label: Text('Add Photo'),
                      onPressed: () async {
                        final XFile? image = await _picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 70, // Compressing before upload
                        );
                        if (image != null) {
                          setState(() {
                            _selectedImages.add(File(image.path));
                          });
                        }
                      },
                    ),
                ],
              ),
              if (_selectedImages.isNotEmpty) ...[
                SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          Container(
                            margin: EdgeInsets.only(right: 12),
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: FileImage(_selectedImages[index]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 16,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.removeAt(index);
                                });
                              },
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],

              SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
