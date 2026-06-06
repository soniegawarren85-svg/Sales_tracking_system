import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../Admin_pages/Admin/Dashboard.dart';
import '../../../bones/bottom_nav.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  int _step = 0;
  String? _requestId;
  Map<String, dynamic>? _account;
  String? _accountDocId;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFC2105C) : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _queueOtpEmail({
    required String email,
    required String otp,
    required String requestId,
  }) async {
    await FirebaseFirestore.instance.collection('mail').add({
      'to': [email],
      'message': {
        'subject': 'Sales Tracker OTP Verification',
        'text':
            'Your Sales Tracker forgot password OTP is $otp. This code expires in 10 minutes.',
        'html': '''
          <div style="font-family: Arial, sans-serif; color: #2A1010;">
            <h2 style="color: #C2105C;">Sales Tracker OTP</h2>
            <p>Use this code to verify your forgot password request:</p>
            <div style="font-size: 28px; font-weight: 800; letter-spacing: 4px; color: #E91E63;">
              $otp
            </div>
            <p>This code expires in 10 minutes.</p>
            <p>If you did not request this, you can ignore this email.</p>
          </div>
        ''',
      },
      'otpRequestId': requestId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!email.contains('@')) {
      _snack('Enter the email linked to your account.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final accountSnap = await FirebaseFirestore.instance
          .collection('staff_requests')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (accountSnap.docs.isEmpty) {
        _snack('No account found with this email.', error: true);
        return;
      }

      final otp = (100000 + Random.secure().nextInt(900000)).toString();
      final requestRef =
          FirebaseFirestore.instance.collection('password_reset_otps').doc();
      await requestRef.set({
        'email': email,
        'otp': otp,
        'accountDocId': accountSnap.docs.first.id,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 10)),
        ),
        'used': false,
      });
      await _queueOtpEmail(email: email, otp: otp, requestId: requestRef.id);

      if (!mounted) return;
      setState(() {
        _requestId = requestRef.id;
        _accountDocId = accountSnap.docs.first.id;
        _account = accountSnap.docs.first.data();
        _step = 1;
      });
      _snack('OTP sent. Please check your Gmail inbox.');
    } catch (e) {
      _snack('Unable to send OTP: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final requestId = _requestId;
    if (requestId == null) return;
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('password_reset_otps')
          .doc(requestId)
          .get();
      final data = doc.data();
      final expiresAt = data?['expiresAt'];
      final expired =
          expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now());
      if (data == null ||
          data['used'] == true ||
          expired ||
          data['otp']?.toString() != _otpController.text.trim()) {
        _snack('Invalid or expired OTP.', error: true);
        return;
      }
      await doc.reference.update({
        'used': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _step = 2);
    } catch (e) {
      _snack('Unable to verify OTP: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithoutChanging() async {
    final data = _account ?? {};
    final role = data['role']?.toString().toLowerCase() ?? 'staff';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRole', role == 'admin' ? 'admin' : 'staff');
    await prefs.setString('lastUserId', _accountDocId ?? '');
    if (role == 'admin') {
      await prefs.setString(
        'adminId',
        data['adminId']?.toString() ?? data['staffId']?.toString() ?? 'ADM-0001',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => role == 'admin'
            ? const AdminDashboard()
            : const BottomNav(),
      ),
      (_) => false,
    );
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim().toLowerCase();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Password reset link sent to $email.');
    } catch (e) {
      _snack('Unable to send reset link: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE91E63),
        foregroundColor: Colors.white,
        title: const Text('Forgot Password'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _step == 0
                  ? 'Enter your account email'
                  : _step == 1
                  ? 'OTP Verification'
                  : 'Verified',
              style: const TextStyle(
                color: Color(0xFFC2105C),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            if (_step == 0) ...[
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _loading ? null : _sendOtp,
                child: Text(_loading ? 'Sending...' : 'Send OTP'),
              ),
            ] else if (_step == 1) ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit OTP',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _loading ? null : _verifyOtp,
                child: Text(_loading ? 'Checking...' : 'Verify OTP'),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _continueWithoutChanging,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Continue without changing password'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _sendResetLink,
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text('Send password reset link'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
