import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/post_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/location_service.dart';
import '../../../services/notification_service.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/error_states.dart';
import '../widgets/post_card.dart';
import '../widgets/city_stats_header.dart';

class FeedTab extends StatefulWidget {
  final String feedType; // 'local', 'city', 'india'

  const FeedTab({Key? key, required this.feedType}) : super(key: key);

  @override
  _FeedTabState createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> with AutomaticKeepAliveClientMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  final ScrollController _scrollController = ScrollController();
  
  StreamSubscription<QuerySnapshot>? _liveSubscription;
  StreamSubscription<List<PostModel>>? _geoSubscription;

  List<PostModel> _livePosts = [];
  List<PostModel> _olderPosts = [];

  bool _isLoading = true;
  bool _topicsUpdated = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _needsLocationPrompt = false;
  
  DocumentSnapshot? _lastLiveDoc;
  DocumentSnapshot? _lastOlderDoc;
  
  String? _errorMessage;

  // User data for queries
  String _userCity = '';
  String _userArea = '';
  List<String> _blockedUsers = [];
  
  double? _userLat;
  double? _userLng;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadUserAndFeed();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _liveSubscription?.cancel();
    _geoSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isLoading) {
      _loadMore();
    }
  }

  Future<void> _loadUserAndFeed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (widget.feedType == 'local') {
        bool hasPerm = await _locationService.hasPermission();
        if (!hasPerm) {
          setState(() {
            _needsLocationPrompt = true;
            _isLoading = false;
          });
          return;
        }
      }

      final userDoc = await _firestoreService.getUser(user.uid);
      _userCity = userDoc.city;
      _userArea = userDoc.area;
      _blockedUsers = userDoc.blockedUsers;
      
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        // Phase 6: Sync location and      // Call topic subscription ONCE location is known
        if (!_topicsUpdated) {
          NotificationService().updateTopics(_userLat!, _userLng!, _userCity);
          _topicsUpdated = true;
        }
      }
      
      if (widget.feedType == 'local' && _userLat != null) {
        _initGeoStream();
      } else {
        _initLiveStream();
      }
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load feed';
        });
      }
    }
  }

  Query _getBaseQuery() {
    switch (widget.feedType) {
      case 'city':
        return _firestoreService.getCityFeedQuery(_userCity);
      case 'india':
        return _firestoreService.getIndiaFeedQuery();
      case 'local':
      default:
        // Local uses geo queries ideally — falling back to city+area for now
        return _firestoreService.getLocalFallbackQuery(_userCity, _userArea);
    }
  }

  void _initLiveStream() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final query = _getBaseQuery();

    _liveSubscription = query.snapshots().listen((snapshot) {
      if (!mounted) return;

      final posts = snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();

      setState(() {
        _livePosts = posts;
        _isLoading = false;
        
        if (snapshot.docs.isNotEmpty) {
          _lastLiveDoc = snapshot.docs.last;
        }
      });
    }, onError: (e) {
      debugPrint('Live Stream Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_livePosts.isEmpty && _olderPosts.isEmpty) {
            _errorMessage = 'Failed to load live feed';
          }
        });
      }
    });
  }

  void _initGeoStream() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    _geoSubscription?.cancel();
    _geoSubscription = _firestoreService.getGeoFeedStream(_userLat!, _userLng!, radiusParams: 5.0).listen(
      (posts) {
        if (!mounted) return;
        
        // geoflutterfire handles sorting by distance, but we might want them sorted by timestamp 
        // to match standard feeds, so we sort them here.
        posts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        setState(() {
          _livePosts = posts;
          _isLoading = false;
          _hasMore = false; // Geo streams pull everything in radius, pagination bypassed.
        });
      },
      onError: (e) {
        debugPrint('Geo Stream Error: $e');
        if (mounted) {
          // Fallback to standard feed logic if geo crashes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _initLiveStream(); 
          });
        }
      }
    );
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    if (widget.feedType == 'local' && _userLat != null) return; // Geo stream doesn't paginate
    
    // Determine the cursor: start after the last older doc if we have older posts,
    // otherwise start after the last live doc.
    final cursorDoc = _olderPosts.isNotEmpty ? _lastOlderDoc : _lastLiveDoc;
    if (cursorDoc == null) return; // Top 20 hasn't even loaded full 20 yet likely.

    setState(() => _isLoadingMore = true);

    try {
      final query = _firestoreService.paginateQuery(_getBaseQuery(), cursorDoc);
      final snapshot = await query.get();
      
      final newPosts = snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();

      if (mounted) {
        setState(() {
          _olderPosts.addAll(newPosts);
          _isLoadingMore = false;
          _hasMore = snapshot.docs.length >= 20;
          if (snapshot.docs.isNotEmpty) {
            _lastOlderDoc = snapshot.docs.last;
          }
        });
      }
    } catch (e) {
      debugPrint('Pagination Error: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    _olderPosts.clear();
    _lastOlderDoc = null;
    _hasMore = true;
    _liveSubscription?.cancel();
    _geoSubscription?.cancel();
    
    if (widget.feedType == 'local' && _userLat != null) {
      _initGeoStream();
    } else {
      _initLiveStream();
    }
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
      setState(() => _blockedUsers.add(blockedUid));
      _refresh(); 
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
                          if (shouldBlock) _refresh();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_needsLocationPrompt) {
      return EmptyListState(
        title: 'Location Needed',
        subtitle: 'We use your location to show nearby community updates.',
        icon: Icons.location_on,
        buttonText: 'Enable Location',
        onAction: () async {
          bool granted = await _locationService.requestPermission();
          if (granted) {
            setState(() {
              _needsLocationPrompt = false;
              _isLoading = true;
            });
            _loadUserAndFeed();
          }
        },
      );
    }

    if (_isLoading) {
      return ListSkeleton(count: 3);
    }

    if (_errorMessage != null) {
      return NoInternetState(onRetry: () {
        _errorMessage = null;
        _loadUserAndFeed();
      });
    }

    // Merge and deduplicate logic
    final Set<String> ids = {};
    final List<PostModel> merged = [];
    final now = DateTime.now();
    
    for (var post in _livePosts) {
      if (!post.isActive) continue;
      if (post.expiresAt != null && post.expiresAt!.toDate().isBefore(now)) continue;
      if (_blockedUsers.contains(post.userId)) continue;

      if (ids.add(post.id)) {
        merged.add(post);
      }
    }
    for (var post in _olderPosts) {
      if (!post.isActive) continue;
      if (post.expiresAt != null && post.expiresAt!.toDate().isBefore(now)) continue;
      if (_blockedUsers.contains(post.userId)) continue;

      if (ids.add(post.id)) {
        merged.add(post);
      }
    }

    // Intelligent feed ranking
    merged.sort((a, b) => b.score.compareTo(a.score));

    if (merged.isEmpty) {
      return EmptyListState(
        title: 'No posts yet',
        subtitle: widget.feedType == 'local'
            ? 'Be the first to post in your area!'
            : 'No posts found.',
        icon: Icons.article_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: AlwaysScrollableScrollPhysics(),
        itemCount: merged.length + 1 + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return CityStatsHeader(city: _userCity);
          }
          
          final postIndex = index - 1;
          
          if (postIndex == merged.length) {
            return Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return PostCard(
            post: merged[postIndex],
            onReport: () => _reportPost(merged[postIndex]),
            onBlock: () => _blockUser(merged[postIndex].userId),
            onTap: () async {
              await context.push('/post/${merged[postIndex].id}');
              if (mounted) _refresh();
            },
          );
        },
      ),
    );
  }
}
