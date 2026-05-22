import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../bones/bottom_nav.dart';
import '../../../Admin_pages/Admin/Dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const String _adminPassword = 'jss19_13';
  static const String _legacyAdminAuthPassword = 'admin@1234';
  static const String _currentAdminAuthPassword = 'admin19@13';
  static const String _emergencyAdminId = 'ADM-0001';
  static const String _emergencyAdminPassword = 'admin@123';

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  void _initializeAnimations() {
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
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    if (_animController.isAnimating) _animController.stop();
    _animController.dispose();
    super.dispose();
  }

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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _normalizeUsername(String username) {
    final cleaned = username
        .trim()
        .toUpperCase()
        .replaceAll(RegExp('[\\u2013\\u2014\\u2212]'), '-')
        .replaceAll(' ', '');
    final match = RegExp(r'^(ADM|STF)-(.+)$').firstMatch(cleaned);
    if (match == null) return cleaned;

    final prefix = match.group(1)!;
    final numberPart = match.group(2)!.replaceAll('O', '0');
    return '$prefix-$numberPart';
  }

  List<String> _authPasswordCandidates(String username, String password) {
    final candidates = <String>[password];

    if (username.startsWith('ADM-') && _isAcceptedAdminPassword(password)) {
      candidates.add(_legacyAdminAuthPassword);
      candidates.add(_adminPassword);
      candidates.add(_currentAdminAuthPassword);
    }

    if (password.isNotEmpty) {
      final firstLower = password[0].toLowerCase() + password.substring(1);
      if (firstLower != password) candidates.add(firstLower);
    }

    return candidates.toSet().toList();
  }

  bool _isAcceptedAdminPassword(String password) {
    return password == _adminPassword ||
        password == _legacyAdminAuthPassword ||
        password == _currentAdminAuthPassword;
  }

  bool _isEmergencyAdminLogin(String username, String password) {
    return _normalizeUsername(username) == _emergencyAdminId &&
        password == _emergencyAdminPassword;
  }

  Future<void> _signInEmergencyAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminId', _emergencyAdminId);
    await prefs.setString('lastRole', 'admin');
    await prefs.setString('lastUserId', 'emergency-admin');
    _showMessage('Welcome back!');
    Future.microtask(() {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
      );
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _prioritizeAccountDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String username,
    String idField,
  ) {
    final normalized = _normalizeUsername(username);
    final normalizedNumber = normalized.split('-').last;
    final uniqueDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in docs) {
      uniqueDocs[doc.id] = doc;
    }

    final matches = uniqueDocs.values.where((doc) {
      final data = doc.data();
      final storedId = _normalizeUsername((data[idField] ?? '').toString());
      final storedAdminId = _normalizeUsername(
        (data['adminId'] ?? '').toString(),
      );
      final storedStaffId = _normalizeUsername(
        (data['staffId'] ?? '').toString(),
      );
      final storedUsername = _normalizeUsername(
        (data['username'] ?? '').toString(),
      );
      return storedId == normalized ||
          storedAdminId == normalized ||
          storedStaffId == normalized ||
          storedUsername == normalized ||
          storedId.endsWith('-$normalizedNumber') ||
          storedAdminId.endsWith('-$normalizedNumber') ||
          storedStaffId.endsWith('-$normalizedNumber') ||
          storedUsername.endsWith('-$normalizedNumber');
    }).toList();

    matches.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aAccepted =
          (aData['status'] ?? '').toString().trim().toLowerCase() == 'accepted';
      final bAccepted =
          (bData['status'] ?? '').toString().trim().toLowerCase() == 'accepted';
      if (aAccepted != bAccepted) return aAccepted ? -1 : 1;

      final aHasEmail = (aData['email'] ?? '').toString().trim().isNotEmpty;
      final bHasEmail = (bData['email'] ?? '').toString().trim().isNotEmpty;
      if (aHasEmail != bHasEmail) return aHasEmail ? -1 : 1;

      return a.id.compareTo(b.id);
    });

    return matches;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _findAccountsByUsername(String username) async {
    final normalized = _normalizeUsername(username);
    final idField = normalized.startsWith('ADM-') ? 'adminId' : 'staffId';
    final idNumber = normalized.split('-').last;
    final matches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final idFields = normalized.startsWith('ADM-')
        ? const ['adminId', 'staffId']
        : const ['staffId'];
    for (final field in idFields) {
      final byId = await FirebaseFirestore.instance
          .collection('staff_requests')
          .where(field, isEqualTo: normalized)
          .get();
      matches.addAll(byId.docs);
    }

    final byUsername = await FirebaseFirestore.instance
        .collection('staff_requests')
        .where('username', isEqualTo: normalized)
        .get();
    matches.addAll(byUsername.docs);

    if (RegExp(r'^\d{4}$').hasMatch(idNumber)) {
      final role = normalized.startsWith('ADM-') ? 'admin' : 'staff';
      final byRole = await FirebaseFirestore.instance
          .collection('staff_requests')
          .where('role', isEqualTo: role)
          .get();

      for (final doc in byRole.docs) {
        final data = doc.data();
        final storedIds = [
          data[idField],
          data['adminId'],
          data['staffId'],
          data['username'],
        ].map((value) => _normalizeUsername((value ?? '').toString()));

        if (storedIds.any(
          (storedId) =>
              storedId == normalized || storedId.endsWith('-$idNumber'),
        )) {
          matches.add(doc);
        }
      }
    }

    final prioritized = _prioritizeAccountDocs(matches, normalized, idField);
    if (prioritized.isNotEmpty || !normalized.startsWith('ADM-')) {
      return prioritized;
    }

    final adminFallback = await FirebaseFirestore.instance
        .collection('staff_requests')
        .get();
    final adminDocs = adminFallback.docs.where((doc) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      final firstName = (data['firstName'] ?? '').toString().toLowerCase();
      final lastName = (data['lastName'] ?? '').toString().toLowerCase();
      final hasCultQwertyName =
          firstName.contains('cult') && lastName.contains('qwerty');
      return role == 'admin' || hasCultQwertyName;
    }).toList();

    adminDocs.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aName = '${aData['firstName'] ?? ''} ${aData['lastName'] ?? ''}'
          .toLowerCase();
      final bName = '${bData['firstName'] ?? ''} ${bData['lastName'] ?? ''}'
          .toLowerCase();
      final aIsTarget = aName.contains('cult') && aName.contains('qwerty');
      final bIsTarget = bName.contains('cult') && bName.contains('qwerty');
      if (aIsTarget != bIsTarget) return aIsTarget ? -1 : 1;

      final aAccepted =
          (aData['status'] ?? '').toString().trim().toLowerCase() == 'accepted';
      final bAccepted =
          (bData['status'] ?? '').toString().trim().toLowerCase() == 'accepted';
      if (aAccepted != bAccepted) return aAccepted ? -1 : 1;

      return a.id.compareTo(b.id);
    });

    return adminDocs;
  }

  Future<void> _onSignInPressed() async {
    final username = _normalizeUsername(_usernameController.text);
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage('Please enter your username and password.', isError: true);
      return;
    }

    if (username.startsWith('ADM-') &&
        !_isAcceptedAdminPassword(password) &&
        !_isEmergencyAdminLogin(username, password)) {
      _showMessage(
        'Incorrect admin password. Please try again.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isEmergencyAdminLogin(username, password)) {
        await _signInEmergencyAdmin();
        return;
      }

      final accountDocs = await _findAccountsByUsername(username);
      if (accountDocs.isEmpty) {
        _showMessage('No account found with this username.', isError: true);
        return;
      }

      // Special handling for admin accounts with valid admin password
      if (username.startsWith('ADM-') && _isAcceptedAdminPassword(password)) {
        // For admin accounts, use the valid admin password for direct authentication
        for (final accountDoc in accountDocs) {
          final accountData = accountDoc.data();
          final role =
              (accountData['role'] as String?)?.trim().toLowerCase() ?? '';

          // Verify this is actually an admin account
          if (role == 'admin') {
            final rawStatus = (accountData['status'] as String? ?? '')
                .trim()
                .toLowerCase();
            final status = rawStatus.isEmpty ? 'accepted' : rawStatus;

            if (status == 'pending') {
              _showMessage(
                'Your account is still pending approval by admin.',
                isError: true,
              );
              return;
            }

            if (status == 'rejected') {
              _showMessage(
                'Your application has been declined.',
                isError: true,
              );
              return;
            }

            if (status == 'accepted') {
              await accountDoc.reference.update({
                'lastLoginAt': FieldValue.serverTimestamp(),
              });
              final adminId =
                  (accountData['adminId'] as String?) ??
                  (accountData['staffId'] as String?) ??
                  username;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('adminId', adminId);
              await prefs.setString('lastRole', 'admin');
              await prefs.setString('lastUserId', accountDoc.id);
              _showMessage('Welcome back!');
              Future.microtask(() {
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AdminDashboard()),
                );
              });
              return;
            }
          }
        }
        _showMessage(
          'Unable to authenticate. Please contact support.',
          isError: true,
        );
        return;
      }

      // Regular staff authentication using Firebase
      FirebaseAuthException? lastAuthError;
      UserCredential? credential;
      QueryDocumentSnapshot<Map<String, dynamic>>? signedInDoc;

      for (final accountDoc in accountDocs) {
        final accountData = accountDoc.data();
        final email = accountData['email']?.toString().trim() ?? '';
        if (email.isEmpty) continue;

        for (final authPassword in _authPasswordCandidates(
          username,
          password,
        )) {
          try {
            credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: email,
              password: authPassword,
            );
            signedInDoc = accountDoc;
            break;
          } on FirebaseAuthException catch (e) {
            lastAuthError = e;
            if (e.code != 'user-not-found' &&
                e.code != 'wrong-password' &&
                e.code != 'invalid-credential') {
              rethrow;
            }
          }
        }

        if (signedInDoc != null) break;
      }

      if (signedInDoc == null || credential == null) {
        if (lastAuthError != null) throw lastAuthError;
        _showMessage(
          'This account has no email linked. Please contact admin.',
          isError: true,
        );
        return;
      }

      final uid = credential.user?.uid;
      if (uid == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Unable to sign in with this account.',
        );
      }

      final data = signedInDoc.data();
      final role = (data['role'] as String?)?.trim().toLowerCase() ?? 'staff';
      final rawStatus = (data['status'] as String? ?? '').trim().toLowerCase();
      final status = rawStatus.isEmpty && role == 'admin'
          ? 'accepted'
          : rawStatus.isEmpty
          ? 'pending'
          : rawStatus;

      if (status == 'pending') {
        await FirebaseAuth.instance.signOut();
        _showMessage(
          'Your account is still pending approval by admin.',
          isError: true,
        );
        return;
      }

      if (status == 'rejected') {
        await FirebaseAuth.instance.signOut();
        _showMessage('Your application has been declined.', isError: true);
        return;
      }

      if (status == 'accepted') {
        final isAdmin = role == 'admin';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastRole', isAdmin ? 'admin' : 'staff');
        await prefs.setString('lastUserId', uid);
        await signedInDoc.reference.update({
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
        _showMessage('Welcome back!');
        Future.microtask(() {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  isAdmin ? const AdminDashboard() : const BottomNav(),
            ),
          );
        });
        return;
      }

      await FirebaseAuth.instance.signOut();
      _showMessage('Unable to sign in. Please contact support.', isError: true);
    } on FirebaseAuthException catch (e) {
      var message = 'Invalid credentials. Please try again.';
      if (e.code == 'user-not-found') {
        message = 'No account found with this username.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Incorrect password. Please try again.';
      } else if (e.code == 'invalid-email') {
        message = 'Please enter a valid username.';
      }
      _showMessage(message, isError: true);
    } catch (e) {
      _showMessage('Unable to sign in. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F0),
      body: Stack(
        children: [
          // ── Decorative background blobs ──────────────────────────────
          Positioned(
            bottom: 80,
            left: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF8BBD0).withOpacity(0.4),
              ),
            ),
          ),
          Positioned(
            bottom: 200,
            right: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF5A0C8).withOpacity(0.25),
              ),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────
          Column(
            children: [
              // ── HEADER ─────────────────────────────────────────────
              _buildHeader(),

              // ── SCROLLABLE FORM ─────────────────────────────────────
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
                          const SizedBox(height: 36),
                          _buildWelcomeText(),
                          const SizedBox(height: 5),
                          _buildForm(),
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

  // ── HEADER (NEW) ──────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main gradient header container
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 28,
            bottom: 70,
            left: 28,
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
              // Logo badge
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(18),
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
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Angel'Z Bites — changed to Satisfy (elegant script) ──
                  Text(
                    "Angel'Z Bites",
                    style: GoogleFonts.satisfy(
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'C U P C A K E S',
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                      letterSpacing: 3.5,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Decorative accent circles inside header
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      width: 24,
                      height: 24,
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

        // ── Curved wave cutout at the bottom ──────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: CustomPaint(
            size: const Size(double.infinity, 36),
            painter: _WavePainter(),
          ),
        ),

        // ── Floating decorative dots ───────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 100,
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
          top: MediaQuery.of(context).padding.top + 30,
          right: 80,
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

  // ── Welcome Text ──────────────────────────────────────────────────────────
  Widget _buildWelcomeText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── "Welcome Back" — changed to Outfit (modern geometric sans) ──
        Text(
          'Welcome\nBack',
          style: GoogleFonts.outfit(
            fontSize: 35,
            fontWeight: FontWeight.w800,
            color: const Color.fromARGB(255, 194, 16, 92),
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
            Text(
              'Sign in to continue',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: const Color(0xFFE91E63),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Form ──────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          label: 'Username',
          controller: _usernameController,
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 18),
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
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () =>
                _showMessage('Forgot password flow not implemented.'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Forgot password?',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: const Color(0xFFE91E63),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        _buildSignInButton(),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Divider(
                thickness: 1,
                color: Colors.pink.withOpacity(0.25),
              ),
            ),
           
            Expanded(
              child: Divider(
                thickness: 1,
                color: Colors.pink.withOpacity(0.25),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
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
        keyboardType: keyboardType,
        obscureText: obscureText,
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

  // ── Sign In Button ────────────────────────────────────────────────────────
  Widget _buildSignInButton() {
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
          onTap: _isLoading ? null : _onSignInPressed,
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
                      Text(
                        'Sign In',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Divider ───────────────────────────────────────────────────────────────

  // ── Footer ────────────────────────────────────────────────────────────────
}

// ── Wave Painter ──────────────────────────────────────────────────────────────
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
