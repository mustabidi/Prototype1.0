import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

import 'package:go_router/go_router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'home/home_screen.dart';
import 'help/help_screen.dart';
import 'business/business_screen.dart';
import 'profile/profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  void _initializeNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 1. Setup tokens and permissions
      await _notificationService.initialize(user.uid);
      // 2. Start foreground listener for real-time notifications
      _notificationService.listenToForeground();
      
      // 3. Handle when app is opened from background notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data.containsKey('postId')) {
          context.push('/post/${message.data['postId']}');
        }
      });
      
      // 4. Handle if app was launched via notification from terminated state
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null && initialMessage.data.containsKey('postId')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.push('/post/${initialMessage.data['postId']}');
        });
      }
    }
  }

  final List<Widget> _screens = [
    HomeScreen(),
    HelpScreen(),
    BusinessScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.health_and_safety),
            label: 'Help',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront),
            label: 'Businesses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
