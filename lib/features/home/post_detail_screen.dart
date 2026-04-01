import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/post_model.dart';
import '../../services/firestore_service.dart';
import '../../core/widgets/error_states.dart';
import 'widgets/post_card.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Future<PostModel?> _postFuture;

  @override
  void initState() {
    super.initState();
    _postFuture = FirestoreService().getPostById(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Post Details'),
      ),
      body: FutureBuilder<PostModel?>(
        future: _postFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return NoInternetState(onRetry: () {
              setState(() {
                _postFuture = FirestoreService().getPostById(widget.postId);
              });
            });
          }
          if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isActive == false) {
            return EmptyListState(
              title: 'Alert Resolved or Removed',
              subtitle: 'This community alert has been resolved or removed by moderation.',
              icon: Icons.check_circle_outline,
            );
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: PostCard(
                post: snapshot.data!,
                onReport: () => _reportPost(snapshot.data!),
              ),
            ),
          );
        },
      ),
    );
  }

  void _reportPost(PostModel post) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: Text('Report Post'),
          content: TextField(
            controller: reasonController,
            decoration: InputDecoration(hintText: 'Reason for reporting...'),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (reasonController.text.trim().isNotEmpty) {
                  try {
                    await FirestoreService().reportPost(
                      post.id,
                      user.uid,
                      reasonController.text.trim(),
                    );
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Report submitted')),
                      );
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
      },
    );
  }
}
