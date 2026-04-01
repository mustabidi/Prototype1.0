import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/create_post_screen.dart';
import '../../models/post_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../core/widgets/error_states.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../home/widgets/post_card.dart';

class HelpScreen extends StatefulWidget {
  @override
  _HelpScreenState createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  
  StreamSubscription<List<PostModel>>? _helpSubscription;
  List<PostModel> _helpPosts = [];
  bool _isLoading = true;
  bool _needsLocationPrompt = false;
  String? _errorMessage;
  List<String> _blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _initHelpStream();
  }

  @override
  void dispose() {
    _helpSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initHelpStream() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _needsLocationPrompt = false;
    });

    try {
      bool hasPerm = await _locationService.hasPermission();
      if (!hasPerm) {
        setState(() {
          _needsLocationPrompt = true;
          _isLoading = false;
        });
        return;
      }

      final pos = await _locationService.getCurrentPosition();
      if (pos == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Location access required for nearby help requests.';
        });
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await _firestoreService.getUser(user.uid);
        _blockedUsers = userDoc.blockedUsers;
      }

      _helpSubscription?.cancel();
      // Using a slightly wider radius for help (10km) or stick to 5km per user instruction?
      // User said "Radius: 5 km (default)". Let's stick to 5km.
      _helpSubscription = _firestoreService
          .getGeoFeedStream(pos.latitude, pos.longitude, radiusParams: 5.0)
          .listen((posts) {
        if (!mounted) return;
        
        // Filter for 'help' type only, exclude blocked users
        final helpRequests = posts.where((p) => p.type == 'help' && !_blockedUsers.contains(p.userId)).toList();
        helpRequests.sort((a, b) {
          int urgencyComp = b.urgencyLevel.compareTo(a.urgencyLevel);
          if (urgencyComp != 0) return urgencyComp;
          return b.timestamp.compareTo(a.timestamp);
        });

        setState(() {
          _helpPosts = helpRequests;
          _isLoading = false;
        });
      }, onError: (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load help requests.';
        });
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nearby Help Requests'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _initHelpStream,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        label: Text('Request Help'),
        icon: Icon(Icons.add_alert),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePostScreen())),
      ),
    );
  }

  Widget _buildBody() {
    if (_needsLocationPrompt) {
      return EmptyListState(
        title: 'Location Needed',
        subtitle: 'We use your location to show nearby help requests from neighbors.',
        icon: Icons.location_on,
        buttonText: 'Enable Location',
        onAction: () async {
          bool granted = await _locationService.requestPermission();
          if (granted) {
            _initHelpStream();
          }
        },
      );
    }

    if (_isLoading) {
      return ListSkeleton(count: 3);
    }

    if (_errorMessage != null) {
      return NoInternetState(onRetry: _initHelpStream);
    }

    if (_helpPosts.isEmpty) {
      return EmptyListState(
        title: 'No urgent requests nearby',
        subtitle: 'When people around you need help, it will appear here.',
        icon: Icons.health_and_safety,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: 80), // Space for FAB
      itemCount: _helpPosts.length,
      itemBuilder: (context, index) {
        return PostCard(
          post: _helpPosts[index],
          onReport: () => _reportPost(_helpPosts[index]),
          onBlock: () => _blockUser(_helpPosts[index].userId),
        );
      },
    );
  }

  void _blockUser(String blockedUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block User'),
        content: Text('You will no longer see posts or receive notifications from this user.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Block', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    
    if (confirm == true) {
      await _firestoreService.blockUser(user.uid, blockedUid);
      setState(() {
        _blockedUsers.add(blockedUid);
      });
      _initHelpStream(); // refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User blocked')));
      }
    }
  }

  void _reportPost(PostModel post) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bool shouldBlock = false;

    showDialog(
      context: context,
      builder: (ctx) {
        final reasonController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Report Post'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(hintText: 'Reason for reporting...'),
                    maxLines: 3,
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: shouldBlock,
                        onChanged: (val) {
                          setDialogState(() {
                            shouldBlock = val ?? false;
                          });
                        },
                      ),
                      Text('Also block this user', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
                TextButton(
                  onPressed: () async {
                    if (reasonController.text.trim().isNotEmpty) {
                      try {
                        await _firestoreService.reportPost(
                          post.id,
                          user.uid,
                          reasonController.text.trim(),
                        );
                        
                        if (shouldBlock) {
                          await _firestoreService.blockUser(user.uid, post.userId);
                          setState(() => _blockedUsers.add(post.userId));
                        }
                        
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Report submitted')),
                          );
                          if (shouldBlock) _initHelpStream();
                        }
                      } catch (e) {
                        debugPrint(e.toString());
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to submit report')),
                          );
                        }
                      }
                    }
                  },
                  child: Text('Submit'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
