import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.length < 6) {
      _showError('Enter a valid email and password (6+ chars)');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      UserCredential? userCred;
      if (_isLogin) {
        userCred = await _authService.signInWithEmail(email, password);
      } else {
        userCred = await _authService.signUpWithEmail(email, password);
      }
      
      if (userCred?.user != null) {
        bool exists = await _authService.userExists(userCred!.user!.uid);
        if (exists) {
          if (context.mounted) context.go('/');
        } else {
          if (context.mounted) context.go('/onboarding');
        }
      } else {
        setState(() => _isLoading = false);
        _showError('Authentication failed.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(_isLogin ? 'Login failed. Invalid credentials?' : 'Registration failed. Email in use?');
    }
  }

  void _showError(String msg) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login' : 'Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email Address'),
              keyboardType: TextInputType.emailAddress,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
              child: _isLoading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isLogin ? 'Login Securely' : 'Sign Up Securely'),
            ),
            SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(
                _isLogin ? "Don't have an account? Sign Up" : "Already have an account? Login",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
