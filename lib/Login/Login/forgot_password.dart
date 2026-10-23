import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../services/password_reset_account_lookup.dart';
import '../../services/password_reset_service.dart';
import 'Login.dart';

const _passwordResetContinueUrl =
    'https://sales-tracking-d8667-account.web.app/reset-complete.html'
    '?passwordReset=success';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _restoring = true;
  int _step = 0;
  DateTime? _resendAvailableAt;
  Duration _remaining = Duration.zero;
  Timer? _cooldownTimer;
  Timer? _completionTimer;
  bool _checkingCompletion = false;

  // Animations
  late final AnimationController _enter;
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _restoreResetSession();
    _completionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_step == 1 &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _checkCompletion();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _completionTimer?.cancel();
    _enter.dispose();
    _float.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _restoreResetSession();
  }

  Future<void> _restoreResetSession() async {
    try {
      final session = await PasswordResetSession.restore();
      if (!mounted) return;
      if (session != null) {
        _emailController.text = session.email;
        _resendAvailableAt = session.resendAvailableAt;
        _step = session.completed
            ? 2
            : session.shouldResumeAt(DateTime.now())
            ? 1
            : 0;
        _startCooldown();
        unawaited(_checkCompletion());
      }
    } catch (error) {
      debugPrint('Restore password reset session: $error');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _checkCompletion() async {
    if (_checkingCompletion) return;
    _checkingCompletion = true;
    try {
      final session = await PasswordResetSession.restore();
      if (session == null) return;
      var completed = session.completed;
      if (!completed &&
          passwordResetApiUrl.isNotEmpty &&
          session.statusToken != null) {
        final result = await passwordResetRequest('passwordResetStatus', {
          'statusToken': session.statusToken,
        });
        completed = result['status'] == 'completed';
        if (completed && session.requestId != null) {
          completed = await PasswordResetSession.markCompleted(
            session.requestId!,
          );
        }
      }
      if (completed && mounted) {
        _cooldownTimer?.cancel();
        setState(() => _step = 2);
      }
    } catch (error) {
      debugPrint('Reset completion check unavailable: $error');
    } finally {
      _checkingCompletion = false;
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCooldown(),
    );
    _updateCooldown();
  }

  void _updateCooldown() {
    final resendAvailableAt = _resendAvailableAt;
    if (resendAvailableAt == null) return;
    final remaining = resendAvailableAt.difference(DateTime.now());
    if (mounted) {
      setState(() {
        _remaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }
    if (remaining <= Duration.zero) _cooldownTimer?.cancel();
  }

  String get _cooldownText {
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _changeEmail() async {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _step = 0;
      _resendAvailableAt = null;
      _remaining = Duration.zero;
    });
  }

  Future<void> _returnToLogin() async {
    await PasswordResetSession.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _sendResetLink() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack('Enter a valid email address.', error: true);
      return;
    }
    if (_step == 1 && _remaining > Duration.zero) {
      _snack(
        'Please wait $_cooldownText before requesting another email.',
        error: true,
      );
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final remembered = await PasswordResetSession.restore();
      if (_step == 0 && remembered?.email == email && !remembered!.completed) {
        if (!mounted) return;
        setState(() {
          _step = 1;
          _resendAvailableAt = remembered.resendAvailableAt;
        });
        _startCooldown();
        unawaited(_checkCompletion());
        return;
      }
      if (passwordResetApiUrl.isNotEmpty) {
        final result = await passwordResetRequest('requestPasswordReset', {
          'email': email,
        });
        final session = PasswordResetSession(
          email: email,
          resendAvailableAt: DateTime.parse(result['expiresAt'] as String),
          requestId: PasswordResetSession.newRequestId(),
          statusToken: result['statusToken'] as String,
        );
        await session.persist();
        if (!mounted) return;
        setState(() {
          _step = 1;
          _resendAvailableAt = session.resendAvailableAt;
        });
        _startCooldown();
        return;
      }
      final account = await lookupPasswordResetAccount(
        firestore: FirebaseFirestore.instance,
        email: email,
      );
      switch (account.status) {
        case PasswordResetAccountStatus.emailChangePending:
          _snack(
            'Your Gmail change is still pending verification. Open the verification link sent to your new Gmail before requesting a password reset.',
            error: true,
          );
          return;
        case PasswordResetAccountStatus.contactEmailOnly:
          _snack(
            'Use your current verified email address to reset your password.',
            error: true,
          );
          return;
        case PasswordResetAccountStatus.superAdmin:
          _snack(
            'Password reset by email is not available for the Super Admin account.',
            error: true,
          );
          return;
        case PasswordResetAccountStatus.unavailable:
          _snack(
            'This account is not active. Contact an administrator for help.',
            error: true,
          );
          return;
        case PasswordResetAccountStatus.notFound:
          _snack(
            'No active staff or admin account is linked to this email.',
            error: true,
          );
          return;
        case PasswordResetAccountStatus.ready:
          break;
      }

      final requestId = PasswordResetSession.newRequestId();
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: account.authEmail!,
        actionCodeSettings: ActionCodeSettings(
          url: '$_passwordResetContinueUrl&requestId=$requestId',
          handleCodeInApp: false,
        ),
      );
      final resendAvailableAt = DateTime.now().add(passwordResetWindow);
      final session = PasswordResetSession(
        email: email,
        resendAvailableAt: resendAvailableAt,
        requestId: requestId,
      );
      try {
        await session.persist();
      } catch (error) {
        debugPrint('Save password reset resend cooldown: $error');
      }
      if (!mounted) return;
      setState(() {
        _step = 1;
        _resendAvailableAt = resendAvailableAt;
      });
      _startCooldown();
      _snack(
        'Password reset email sent. Check your Gmail inbox and spam folder.',
      );
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'Password reset Firebase Auth error: ${error.code} ${error.message ?? ''}',
      );
      _snack(_firebaseAuthErrorMessage(error.code), error: true);
    } on FirebaseException catch (error) {
      debugPrint('Password reset account lookup failed: ${error.code}');
      _snack(
        error.code == 'permission-denied'
            ? 'Unable to verify this account. Please contact an administrator.'
            : 'Unable to check the account right now. Check your internet connection and try again.',
        error: true,
      );
    } on StateError catch (error) {
      _snack(error.message.toString(), error: true);
    } catch (error, stackTrace) {
      debugPrint('Password reset failed: $error\n$stackTrace');
      _snack('Unable to send the reset email. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _firebaseAuthErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-not-found':
        return 'No account is registered with this email address.';
      case 'too-many-requests':
        return 'Too many requests. Please wait a while before trying again.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';
      case 'operation-not-allowed':
        return 'Password reset is currently unavailable for this project.';
      case 'quota-exceeded':
        return 'The reset email limit has been reached. Please try again later.';
      case 'unauthorized-continue-uri':
      case 'invalid-continue-uri':
        return 'Unable to open the reset link. Please contact your administrator.';
      case 'missing-android-pkg-name':
        return 'Unable to open the reset link on this device. Please contact your administrator.';
      default:
        return 'Unable to send the reset email. Please try again.';
    }
  }
  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  static const _titles = [
    'Forgot password?',
    'Check your email',
    'Password changed!',
  ];

  String get _subtitle {
    if (_step == 0) {
      return 'Enter the email linked to your account and we\'ll send you a password reset link.';
    }
    if (_step == 2)
      return 'Your new password is ready. You can now sign in with it.';
    return passwordResetApiUrl.isNotEmpty
        ? 'Open the email and save your new password within 3 minutes. This screen will update when your password is changed.'
        : 'Open the reset email and save your new password. Use the return link in that email page to come back here.';
  }

  IconData get _stepIcon {
    return _step == 2
        ? Icons.check_circle_rounded
        : _step == 0
        ? Icons.lock_reset_rounded
        : Icons.mark_email_unread_outlined;
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
                final isMobile = !isTablet;
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
                            isTablet ? 72 : 48,
                            isTablet ? 48 : 20,
                            24,
                          ),
                          child: _buildCard(wide: isTablet, mobile: isMobile),
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
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Image.asset(
                    'Assets/Image/ob.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.cake_rounded,
                      color: AppColors.primary,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'AngelZ Bite Cupcakes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Recover your account with a secure password reset link.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.85),
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                for (final item in const [
                  ['Enter your email', Icons.alternate_email_rounded],
                  [
                    'Open the link in your email',
                    Icons.mark_email_read_rounded,
                  ],
                  ['Choose a new password', Icons.lock_reset_rounded],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          item[1] as IconData,
                          color: Colors.white.withOpacity(.9),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item[0] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
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

  Widget _buildCard({required bool wide, bool mobile = false}) {
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
            padding: mobile
                ? EdgeInsets.symmetric(horizontal: pad, vertical: 32)
                : EdgeInsets.all(pad),
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
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: KeyedSubtree(
                    key: ValueKey('sub$_step'),
                    child: Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withOpacity(.6),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                if (_step == 1) ...[
                  const SizedBox(height: 16),
                  _buildResendCooldown(),
                ],
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
      children: List.generate(2, (i) {
        final active = i <= _step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 1 ? 0 : 8),
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
        child: Icon(_stepIcon, size: 40, color: AppColors.primary),
      ),
    );
  }

  Widget _buildResendCooldown() {
    final canResend = _remaining == Duration.zero;
    final progress =
        (_remaining.inMilliseconds / passwordResetWindow.inMilliseconds).clamp(
          0.0,
          1.0,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: canResend
            ? AppColors.primary.withOpacity(.07)
            : const Color(0xFFFFF3F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(.18)),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Icon(
                canResend
                    ? Icons.mark_email_read_outlined
                    : Icons.timer_outlined,
                color: AppColors.primaryDark,
                size: 20,
              ),
              Text(
                canResend ? 'You can resend now' : 'Resend available in',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!canResend) ...[
                Text(
                  _cooldownText,
                  key: ValueKey(_cooldownText),
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
          if (!canResend) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppColors.primary.withOpacity(.12),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        if (_restoring) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _loading ? null : _sendResetLink(),
              decoration: _fieldDecoration(
                label: 'Email',
                icon: Icons.email_outlined,
              ),
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Send reset link',
              loadingLabel: 'Sending link...',
              icon: Icons.send_rounded,
              loading: _loading,
              onPressed: _sendResetLink,
            ),
          ],
        );
      case 1:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PrimaryButton(
              label: _remaining > Duration.zero
                  ? 'Resend Email ($_cooldownText)'
                  : 'Resend Email',
              loadingLabel: 'Sending link...',
              icon: Icons.send_rounded,
              loading: _loading,
              enabled: _remaining == Duration.zero,
              onPressed: _sendResetLink,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _changeEmail,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Change email'),
              ),
            ),
          ],
        );
      case 2:
        return _PrimaryButton(
          label: 'Return to Login',
          icon: Icons.login_rounded,
          onPressed: _returnToLogin,
        );
      default:
        return const SizedBox.shrink();
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
    this.enabled = true,
  });

  final String label;
  final String? loadingLabel;
  final IconData? icon;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || !widget.enabled;
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
