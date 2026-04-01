import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _codeSent = false;
  bool _isLoading = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  void _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('Enter a phone number');
      return;
    }
    setState(() => _isLoading = true);
    await _authService.sendOtp(
      phone,
      (verId) {
        setState(() {
          _codeSent = true;
          _isLoading = false;
        });
        _startResendTimer();
      },
      onError: (msg) {
        setState(() => _isLoading = false);
        _showError(msg);
      },
    );
  }

  void _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 6) {
      _showError('Enter a valid 6-digit OTP');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final userCred = await _authService.verifyOtp(otp);
      if (userCred != null && userCred.user != null) {
        bool exists = await _authService.userExists(userCred.user!.uid);
        if (exists) {
          context.go('/');
        } else {
          context.go('/onboarding');
        }
      } else {
        setState(() => _isLoading = false);
        _showError('Verification failed. Try again.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Invalid OTP. Please check and retry.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_codeSent) ...[
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(labelText: 'Phone Number (+91...)'),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _sendOtp,
                child: _isLoading
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Send OTP'),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                decoration: InputDecoration(labelText: 'Enter 6-digit OTP'),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                child: _isLoading
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Verify OTP'),
              ),
              SizedBox(height: 16),
              TextButton(
                onPressed: _canResend ? _sendOtp : null,
                child: Text(
                  _canResend ? 'Resend OTP' : 'Resend in ${_resendCountdown}s',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
