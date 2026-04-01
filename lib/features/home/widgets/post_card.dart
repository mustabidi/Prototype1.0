import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/post_model.dart';
import '../../services/firestore_service.dart';

class PostCard extends StatelessWidget {
  final PostModel post;
  final VoidCallback? onReport;
  final VoidCallback? onTap;
  final VoidCallback? onBlock;

  const PostCard({Key? key, required this.post, this.onReport, this.onTap, this.onBlock}) : super(key: key);

  Color _urgencyColor() {
    switch (post.urgencyLevel) {
      case 3:
        return Colors.red;
      case 2:
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _urgencyLabel() {
    switch (post.urgencyLevel) {
      case 3:
        return 'HIGH';
      case 2:
        return 'MEDIUM';
      default:
        return 'LOW';
    }
  }

  String _typeIcon() {
    switch (post.type) {
      case 'help':
        return '🆘';
      case 'update':
        return '📢';
      default:
        return '📝';
    }
  }

  String _timeAgo() {
    final now = DateTime.now();
    final postTime = post.timestamp.toDate();
    final diff = now.difference(postTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${postTime.day}/${postTime.month}/${postTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: type icon + area + time + urgency badge
            Row(
              children: [
                Text(_typeIcon(), style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${post.area}, ${post.city}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        _timeAgo(),
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _urgencyColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _urgencyColor().withOpacity(0.3)),
                  ),
                  child: Text(
                    _urgencyLabel(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _urgencyColor(),
                    ),
                  ),
                ),
              ],
            ),

            // Category chip
            if (post.category.isNotEmpty) ...[
              SizedBox(height: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  post.category,
                  style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                ),
              ),
            ],

            // Status badge for update posts
            if (post.type == 'update' && post.status != null) ...[
              SizedBox(height: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: post.status == 'resolved'
                      ? Colors.green[50]
                      : Colors.amber[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  post.status == 'resolved' ? '✅ Resolved' : '⚠️ Issue',
                  style: TextStyle(
                    fontSize: 11,
                    color: post.status == 'resolved'
                        ? Colors.green[700]
                        : Colors.amber[800],
                  ),
                ),
              ),
            ],

            // Content
            SizedBox(height: 12),
            Text(
              post.content,
              style: TextStyle(fontSize: 15, height: 1.4),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),

            // Images using cached_network_image lazy loading
            if (post.images.isNotEmpty) ...[
              SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.images.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: EdgeInsets.only(right: 8),
                      // if 1 image -> full width, if multiple -> 260px width
                      width: post.images.length == 1 ? MediaQuery.of(context).size.width - 64 : 260,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: post.images[index],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[200],
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Actions row
            SizedBox(height: 12),
            Row(
              children: [
                if (FirebaseAuth.instance.currentUser?.uid == post.userId)
                  GestureDetector(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Delete Post'),
                          content: Text('Are you sure you want to delete this post?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await FirestoreService().softDeletePost(post.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Post deleted')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete post')));
                          }
                        }
                      }
                    },
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('Delete', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                Spacer(),
                GestureDetector(
                  onTap: () async {
                    if (FirebaseAuth.instance.currentUser == null) return;
                    try {
                      await FirestoreService().upvotePost(
                        post.id, 
                        FirebaseAuth.instance.currentUser!.uid,
                        post.userId
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upvoted!')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
                      }
                    }
                  },
                  child: Row(
                    children: [
                      Icon(Icons.thumb_up_alt_outlined, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Text('Boost (${post.upvoteCount})', style: TextStyle(fontSize: 12, color: Colors.blue)),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                if (onBlock != null && FirebaseAuth.instance.currentUser?.uid != post.userId)
                  GestureDetector(
                    onTap: onBlock,
                    child: Row(
                      children: [
                        Icon(Icons.block, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('Block', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                SizedBox(width: 16),
                if (onReport != null && FirebaseAuth.instance.currentUser?.uid != post.userId)
                  GestureDetector(
                    onTap: onReport,
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('Report', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
