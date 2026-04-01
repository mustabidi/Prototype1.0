import 'package:flutter/material.dart';
import 'feed_tabs/feed_tab.dart';
import 'create_post_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  void _openCreatePost() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreatePostScreen()),
    );

    // If post was created successfully, the tabs will refresh on next build
    // since FeedTab uses its own state
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Feed'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Local'),
              Tab(text: 'City'),
              Tab(text: 'India'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FeedTab(feedType: 'local'),
            FeedTab(feedType: 'city'),
            FeedTab(feedType: 'india'),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          child: Icon(Icons.add),
          onPressed: _openCreatePost,
        ),
      ),
    );
  }
}
