import 'package:sales_tracking/theme/app_colors.dart';
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../Admin_pages/Admin/Dashboard.dart';
import '../../../bones/bottom_nav.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  int _step = 0;
  String? _requestId;
  Map<String, dynamic>? _account;
  String? _accountDocId;

  // Animations
  late final AnimationController _enter;
  late final AnimationController _float;
  Timer? _cooldownTimer;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _enter.dispose();
    _float.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Logic (same behavior as before)
  // ---------------------------------------------------------------------------

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                error ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: error ? AppColors.primaryDark : Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _queueOtpEmail({
    required String email,
    required String otp,
    required String requestId,
  }) async {
    await FirebaseFirestore.instance.collection('mail').add({
      'to': [email],
      'message': {
        'subject': 'AngelZ Bite Cupcakes OTP Verification',
        'text':
            'Your AngelZ Bite Cupcakes forgot password OTP is $otp. This code expires in 10 minutes.',
        'html': '''
          <div style="font-family: Arial, sans-serif; color: #2A1010;">
            <h2 style="color: #C2105C;">AngelZ Bite Cupcakes OTP</h2>
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
    FocusScope.of(context).unfocus();
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
      _otpController.clear();
      setState(() {
        _requestId = requestRef.id;
        _accountDocId = accountSnap.docs.first.id;
        _account = accountSnap.docs.first.data();
        _step = 1;
      });
      _startCooldown();
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
    FocusScope.of(context).unfocus();
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
        builder: (_) =>
            role == 'admin' ? const AdminDashboard() : const BottomNav(),
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  static const _titles = ['Forgot password?', 'Check your email', 'Verified!'];

  String get _subtitle {
    switch (_step) {
      case 0:
        return 'Enter the email linked to your account and we\'ll send you a 6-digit code.';
      case 1:
        return 'We sent a code to ${_emailController.text.trim().toLowerCase()}. It expires in 10 minutes.';
      default:
        return 'Your identity is confirmed. Choose how you want to continue.';
    }
  }

  IconData get _stepIcon {
    switch (_step) {
      case 0:
        return Icons.lock_reset_rounded;
      case 1:
        return Icons.mark_email_unread_outlined;
      default:
        return Icons.verified_rounded;
    }
  }

  Animation<double> _interval(double begin, double end) => CurvedAnimation(
        parent: _enter,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 900;
                final isTablet = c.maxWidth >= 600;
                final content = isWide
                    ? Row(
                        children: [
                          Expanded(flex: 5, child: _buildHero()),
                          Expanded(
                            flex: 5,
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(32),
                                child: _buildCard(wide: true),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            isTablet ? 48 : 20,
                            72,
                            isTablet ? 48 : 20,
                            24,
                          ),
                          child: _buildCard(wide: isTablet),
                        ),
                      );
                return Stack(
                  children: [
                    content,
                    Positioned(
                      top: 8,
                      left: 12,
                      child: FadeTransition(
                        opacity: _interval(0, .5),
                        child: Material(
                          color: Colors.white.withOpacity(.18),
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: Colors.white,
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _float,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_float.value);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -80 + 40 * t,
                right: -60 + 30 * t,
                child: _blob(260, .12),
              ),
              Positioned(
                bottom: -100 + 50 * (1 - t),
                left: -70 + 30 * t,
                child: _blob(320, .10),
              ),
              Positioned(
                top: 220 - 30 * t,
                left: 40 + 20 * t,
                child: _blob(90, .10),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _blob(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      );

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: FadeTransition(
          opacity: _interval(.1, .7),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-.08, 0),
              end: Offset.zero,
            ).animate(_interval(.1, .7)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.18),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'AngelZ Bite Cupcakes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Recover your account in a few quick, secure steps.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.85),
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                for (final item in const [
                  ['Enter your email', Icons.alternate_email_rounded],
                  ['Verify with a 6-digit OTP', Icons.password_rounded],
                  ['Get back to your dashboard', Icons.dashboard_rounded],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(item[1] as IconData,
                            color: Colors.white.withOpacity(.9), size: 22),
                        const SizedBox(width: 12),
                        Text(
                          item[0] as String,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required bool wide}) {
    final pad = wide ? 36.0 : 24.0;
    final anim = _interval(.15, 1);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .08),
          end: Offset.zero,
        ).animate(anim),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.18),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepIndicator(),
                const SizedBox(height: 24),
                Center(child: _buildIconBadge()),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _titles[_step],
                    key: ValueKey('title$_step'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _subtitle,
                    key: ValueKey('sub$_step'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black.withOpacity(.6),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.12, 0),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey('step$_step'),
                      child: _buildStepBody(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (i) {
        final active = i <= _step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: active
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(.15),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildIconBadge() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, a) => ScaleTransition(
        scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
        child: FadeTransition(opacity: a, child: child),
      ),
      child: Container(
        key: ValueKey('icon$_step'),
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(.18),
              AppColors.primary.withOpacity(.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(
          _stepIcon,
          size: 40,
          color: _step == 2 ? Colors.green : AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _loading ? null : _sendOtp(),
              decoration: _fieldDecoration(
                label: 'Email',
                icon: Icons.email_outlined,
              ),
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Send OTP',
              loadingLabel: 'Sending...',
              icon: Icons.send_rounded,
              loading: _loading,
              onPressed: _sendOtp,
            ),
          ],
        );
      case 1:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _loading ? null : _verifyOtp(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 12,
                color: AppColors.primaryDark,
              ),
              decoration: _fieldDecoration(
                label: '6-digit OTP',
                icon: Icons.verified_user_outlined,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Verify OTP',
              loadingLabel: 'Checking...',
              icon: Icons.check_rounded,
              loading: _loading,
              onPressed: _verifyOtp,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _step = 0;
                            _otpController.clear();
                          }),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Change email'),
                ),
                TextButton(
                  onPressed: (_loading || _cooldown > 0) ? null : _sendOtp,
                  child: Text(
                    _cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend code',
                  ),
                ),
              ],
            ),
          ],
        );
      default:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PrimaryButton(
              label: 'Continue without changing password',
              icon: Icons.login_rounded,
              onPressed: _continueWithoutChanging,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _sendResetLink,
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text('Send password reset link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withOpacity(.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.primary.withOpacity(.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border(AppColors.primary.withOpacity(.25)),
      enabledBorder: border(AppColors.primary.withOpacity(.25)),
      focusedBorder: border(AppColors.primary, 2),
    );
  }
}

/// Primary button with press-scale + animated loading state.
class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loadingLabel,
    this.icon,
    this.loading = false,
  });

  final String label;
  final String? loadingLabel;
  final IconData? icon;
  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down && !disabled ? .97 : 1,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: disabled ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withOpacity(.6),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: widget.loading
                  ? Row(
                      key: const ValueKey('loading'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.loadingLabel != null) ...[
                          const SizedBox(width: 12),
                          Text(widget.loadingLabel!),
                        ],
                      ],
                    )
                  : Row(
                      key: const ValueKey('idle'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 20),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
