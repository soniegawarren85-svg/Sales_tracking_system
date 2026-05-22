import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// signup.dart — Angel'Z Bites Cupcakes
// ─────────────────────────────────────────────────────────────────────────────

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  // ── Controllers ─────────────────────────────────────────────────────────
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _ageController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String _selectedRole = 'staff';

  // ── Animations ───────────────────────────────────────────────────────────
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _ageController.dispose();
    _passwordController.dispose();
    _confirmPassController.dispose();
    if (_animController.isAnimating) _animController.stop();
    _animController.dispose();
    super.dispose();
  }

  // ── Snackbar helper ──────────────────────────────────────────────────────
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFC2105C)
            : const Color(0xFF4A7C59),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Generate Staff ID ────────────────────────────────────────────────────
  Future<String> _generateStaffId() async {
    final counterDocRef = FirebaseFirestore.instance
        .collection('_metadata')
        .doc('staff_id_counter');

    final transactionResult = await FirebaseFirestore.instance.runTransaction((
      transaction,
    ) async {
      final counterDoc = await transaction.get(counterDocRef);
      final currentCount = counterDoc.exists
          ? (counterDoc.data()?['count'] ?? 0) + 1
          : 1;

      transaction.set(counterDocRef, {
        'count': currentCount,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return currentCount;
    });

    return 'STF-${_pad(transactionResult, 4)}';
  }

  String _pad(int value, [int width = 2]) {
    return value.toString().padLeft(width, '0');
  }

  // ── Create Account handler ───────────────────────────────────────────────
  Future<void> _onCreatePressed() async {
    final email = _emailController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
    final age = _ageController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPass = _confirmPassController.text.trim();

    // ── Validation ──────────────────────────────────────────────────────
    if (email.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        phone.isEmpty ||
        address.isEmpty ||
        age.isEmpty ||
        password.isEmpty ||
        confirmPass.isEmpty) {
      _showMessage('Please fill in all required fields.', isError: true);
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(email)) {
      _showMessage('Please enter a valid email address.', isError: true);
      return;
    }

    final parsedAge = int.tryParse(age);
    if (parsedAge == null || parsedAge < 18 || parsedAge > 50) {
      _showMessage('Please enter a valid age (18-50).', isError: true);
      return;
    }

    if (!RegExp(r'^09\d{9}$').hasMatch(phone)) {
      _showMessage(
        'Phone number must start with 09 and contain 11 digits.',
        isError: true,
      );
      return;
    }

    // ── Create Firebase Auth user and staff request ─────────────────────────
    setState(() => _isLoading = true);
    UserCredential? userCredential;
    try {
      if (!RegExp(r'^(?=.*[0-9])(?=.*[!@#\$%^&*]).{8,}$').hasMatch(password)) {
        _showMessage(
          'Password must be at least 8 characters and include numbers plus at least one special character like *&#@.',
          isError: true,
        );
        return;
      }

      if (password != confirmPass) {
        _showMessage('Passwords do not match.', isError: true);
        return;
      }

      final staffId = await _generateStaffId();
      userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user?.uid;
      if (uid == null) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'Unable to create account. Please try again.',
        );
      }

      // ── Generate account ID based on selected role ───────────────
      final accountData = {
        'email': email,
        'role': 'staff',
        'firstName': firstName,
        'middleName': _middleNameController.text.trim(),
        'lastName': lastName,
        'age': parsedAge,
        'phone': phone,
        'address': address,
        'status': 'pending',
        'uid': uid,
        'userId': uid,
        'staffId': staffId,
        'username': staffId,
        'mustChangePassword': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .set(accountData);

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _showPendingApprovalDialog(staffId: staffId);
    } on FirebaseAuthException catch (e) {
      if (userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {}
      }

      debugPrint(
        'Signup failed [FirebaseAuthException]: ${e.code} — ${e.message}',
      );

      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'weak-password':
          message = 'Password must be at least 6 characters.';
          break;
        case 'network-request-failed':
          message =
              'Network error. Please check your connection and try again.';
          break;
        case 'operation-not-allowed':
          message = 'Email/password sign-in is not enabled.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled. Contact support.';
          break;
        case 'configuration-not-found':
          message =
              'Firebase auth configuration not found. Enable Email/Password sign-in in Firebase Console.';
          break;
        default:
          message = e.message == 'Error'
              ? 'Unable to create account. Please check your Firebase configuration.'
              : e.message ?? 'Account creation failed. Please try again.';
      }
      if (mounted) {
        _showMessage(message, isError: true);
      }
    } on FirebaseException catch (e) {
      if (userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {}
      }

      debugPrint('Signup failed [FirebaseException]: ${e.code} — ${e.message}');

      String message;
      switch (e.code) {
        case 'permission-denied':
          message =
              'Unable to save your request. Please contact the administrator.';
          break;
        case 'unavailable':
          message = 'Service temporarily unavailable. Please try again later.';
          break;
        case 'network-request-failed':
          message =
              'Network error. Please check your connection and try again.';
          break;
        default:
          message = e.message ?? 'Unable to create account. Please try again.';
      }

      if (mounted) {
        _showMessage(message, isError: true);
      }
    } catch (e) {
      if (userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {}
      }
      debugPrint('Signup failed [unknown]: $e');
      if (mounted) {
        _showMessage(
          'Unable to create account. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Pending Approval Dialog ──────────────────────────────────────────────
  void _showPendingApprovalDialog({required String staffId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF6F0),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E63).withOpacity(0.15),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon badge ──────────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE91E63), Color(0xFFF48FB1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE91E63).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),

              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────────────────
              Text(
                'Staff Account Submitted!',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFC2105C),
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ── Divider accent ───────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE91E63), Color(0xFFF48FB1)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8BBD0).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF48FB1).withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFE91E63),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please wait for admin approval. You will be notified once your account is approved.',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFFC2105C),
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              _CredentialPreview(label: 'Staff ID', value: staffId),

              const SizedBox(height: 24),

              // ── Back to Login button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE91E63), Color(0xFFC2105C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE91E63).withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(ctx).pop(); // close dialog
                        Navigator.of(context).pop(); // back to login
                      },
                      child: Center(
                        child: Text(
                          'Back to Login',
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F0),
      body: Stack(
        children: [
          // ── Decorative blobs ───────────────────────────────────────────
          Positioned(
            bottom: 100,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF8BBD0).withOpacity(0.35),
              ),
            ),
          ),
          Positioned(
            bottom: 280,
            right: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF5A0C8).withOpacity(0.2),
              ),
            ),
          ),

          // ── Main column ────────────────────────────────────────────────
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 32),
                          _buildTitleText(),
                          const SizedBox(height: 24),
                          _buildForm(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            bottom: 70,
            left: 20,
            right: 28,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFC2105C), Color(0xFFE91E63), Color(0xFFF48FB1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Back button ──────────────────────────────────────────
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // ── Logo badge ───────────────────────────────────────────
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'Assets/Image/ob.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.cake_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Angel'Z Bites",
                    style: GoogleFonts.satisfy(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'C U P C A K E S',
                    style: GoogleFonts.dmSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                      letterSpacing: 3.5,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // ── Decorative circles ───────────────────────────────────
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  Positioned(
                    top: 11,
                    left: 11,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Wave painter ─────────────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: CustomPaint(
            size: const Size(double.infinity, 36),
            painter: _WavePainter(),
          ),
        ),

        // ── Floating dots ─────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 90,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 28,
          right: 70,
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
        ),
      ],
    );
  }

  // ── Title Text ───────────────────────────────────────────────────────────
  Widget _buildTitleText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create\nStaff Account',
          style: GoogleFonts.outfit(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFC2105C),
            height: 1.05,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFFF48FB1)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sign up to continue',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: const Color(0xFFE91E63),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section: Personal Info ────────────────────────────────────────
        _buildSectionLabel('Personal Information', Icons.person_rounded),
        const SizedBox(height: 12),

        _buildInputField(
          label: 'First Name',
          controller: _firstNameController,
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Middle Name (Optional)',
          controller: _middleNameController,
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Last Name',
          controller: _lastNameController,
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Age',
          controller: _ageController,
          icon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Phone / Tel. Number',
          controller: _phoneController,
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Address',
          controller: _addressController,
          icon: Icons.location_on_outlined,
          keyboardType: TextInputType.streetAddress,
          maxLines: 2,
        ),

        const SizedBox(height: 24),

        // ── Section: Account Info ─────────────────────────────────────────
        _buildSectionLabel('Account Information', Icons.lock_rounded),
        const SizedBox(height: 12),

        _buildInputField(
          label: 'Email Address',
          controller: _emailController,
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Password',
          controller: _passwordController,
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFFF48FB1),
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 14),

        _buildInputField(
          label: 'Confirm Password',
          controller: _confirmPassController,
          icon: Icons.lock_outline_rounded,
          obscureText: _obscureConfirmPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFFF48FB1),
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Create Button ─────────────────────────────────────────────────
        _buildCreateButton(),

        const SizedBox(height: 24),

        // ── Already have account ──────────────────────────────────────────
        Center(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Already have an account? ',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF2A1010),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: 'Sign In',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFFE91E63),
                    fontWeight: FontWeight.w700,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Section Label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE91E63), Color(0xFFF48FB1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFC2105C),
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  // ── Role Selector ─────────────────────────────────────────────────────────
  // ignore: unused_element
  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildRoleCard(
            role: 'staff',
            label: 'Staff',
            icon: Icons.storefront_outlined,
            description: 'Manage orders & operations',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildRoleCard(
            role: 'admin',
            label: 'Admin',
            icon: Icons.admin_panel_settings_outlined,
            description: 'Full access & management',
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required String role,
    required String label,
    required IconData icon,
    required String description,
  }) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE91E63) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFE91E63)
                : const Color(0xFFF48FB1).withOpacity(0.4),
            width: isSelected ? 0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFE91E63).withOpacity(0.3)
                  : const Color(0xFFE91E63).withOpacity(0.06),
              blurRadius: isSelected ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : const Color(0xFFE91E63),
                  size: 22,
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFFF48FB1),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFFE91E63),
                          size: 12,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFFC2105C),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: isSelected
                    ? Colors.white.withOpacity(0.8)
                    : const Color(0xFF9E5070),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input Field ───────────────────────────────────────────────────────────
  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE91E63).withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLines: obscureText ? 1 : maxLines,
        style: GoogleFonts.dmSans(
          fontSize: 15,
          color: const Color(0xFF2A1010),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(
            fontSize: 13,
            color: const Color(0xFFF48FB1),
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: GoogleFonts.dmSans(
            fontSize: 12,
            color: const Color(0xFFE91E63),
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Icon(icon, color: const Color(0xFFF48FB1), size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE91E63), width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  // ── Create Button ─────────────────────────────────────────────────────────
  Widget _buildCreateButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFC2105C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE91E63).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _onCreatePressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Create Staff Account',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Wave Painter (same as login) ──────────────────────────────────────────────
class _CredentialPreview extends StatelessWidget {
  final String label;
  final String value;

  const _CredentialPreview({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF8BBD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: const Color(0xFF9E5070),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: const Color(0xFFC2105C),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFDF6F0);
    final path = Path();
    path.moveTo(0, size.height);
    path.cubicTo(
      size.width * 0.25,
      size.height,
      size.width * 0.25,
      0,
      size.width * 0.5,
      0,
    );
    path.cubicTo(
      size.width * 0.75,
      0,
      size.width * 0.75,
      size.height,
      size.width,
      size.height,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
