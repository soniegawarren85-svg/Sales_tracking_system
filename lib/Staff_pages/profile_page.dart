import 'package:sales_tracking/theme/app_colors.dart';
import '../services/staff_login_session.dart';
import '../services/profile_field_validation.dart';
import '../widgets/confirm_password_dialog.dart';
import '../services/account_password_service.dart';
import '../services/session_actor.dart';
import '../services/profile_email.dart';
import '../services/account_session_control.dart';
import '../widgets/email_pending_badge.dart';
import '../services/password_policy.dart';
import '../widgets/password_strength_checklist.dart';
import '../widgets/top_edge_refresh.dart';
import 'dart:async';
import '../widgets/branch_staff_activity_dialog.dart';
import '../services/public_item_id.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Login/Login/Login.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback onMessage;
  final GlobalKey? tourTargetKey;
  final GlobalKey? editProfileTourKey;

  const ProfilePage({
    super.key,
    required this.onMessage,
    this.tourTargetKey,
    this.editProfileTourKey,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── Pink palette ────────────────────────────────────────────────
  static const Color _pinkDark = AppColors.primaryDark;
  static const Color _pinkMid = AppColors.primary;
  static const Color _accent = Color(0xFFD4873A);
  static const Color _accentLight = Color(0xFFF0A855);
  static const Color _bg = AppColors.background;
  static const Color _cardBg = AppColors.surfaceTint;
  static const Color _border = AppColors.blush;
  static const Color _textSoft = AppColors.textMuted;
  String? _staffDocId;
  Map<String, dynamic>? _loadedProfile;
  String? _profileSnapshotUid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileSnapshotStream;
  String? _verifiedSessionEmail;
  bool _refreshingEmail = false;
  bool _hasPendingEmail = false;
  Timer? _emailRefreshTimer;
  bool _isUploadingProfilePhoto = false;
  String? _lastProfilePhotoUrl;
  // ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _verifiedSessionEmail = FirebaseAuth.instance.currentUser?.email;
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _loadStaffDocId();
    _emailRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          _hasPendingEmail &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _loadStaffDocId();
      }
    });
  }

  Future<void> _loadStaffDocId() async {
    if (_refreshingEmail) return;
    _refreshingEmail = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid =
          FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('lastStaffDocId') ??
          prefs.getString('lastUserId');
      if (!mounted) return;
      if (_staffDocId != uid) {
        setState(() {
          _staffDocId = uid;
          _loadedProfile = null;
          _profileSnapshotUid = null;
          _profileSnapshotStream = null;
        });
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != uid) return;
      try {
        await user.reload().timeout(const Duration(seconds: 10));
        final email = FirebaseAuth.instance.currentUser?.email;
        if (mounted && email != null)
          setState(() => _verifiedSessionEmail = email);
        final ref = FirebaseFirestore.instance
            .collection('staff_requests')
            .doc(uid);
        final profile = (await ref.get()).data();
        if (email != null &&
            profile?['pendingAuthEmail']?.toString().toLowerCase() ==
                email.toLowerCase()) {
          await ref.update({
            'email': email,
            'authEmail': email,
            'pendingAuthEmail': FieldValue.delete(),
          });
        }
      } catch (error) {
        debugPrint('Unable to refresh verified profile email: $error');
      }
    } finally {
      _refreshingEmail = false;
    }
  }

  Future<void> _refreshProfile() async {
    await _loadStaffDocId();
    final uid =
        FirebaseAuth.instance.currentUser?.uid ?? _staffDocId?.trim() ?? '';
    try {
      if (uid.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('staff_requests')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
      }
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Unable to refresh staff profile: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to refresh profile. Check your connection.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailRefreshTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStaffDocId();
  }

  String _profileEmail(Map<String, dynamic> data) {
    final pending = data['pendingAuthEmail']?.toString().trim() ?? '';
    _hasPendingEmail = pending.isNotEmpty;
    if (pending.isNotEmpty &&
        normalizedProfileEmail(pending) ==
            normalizedProfileEmail(_verifiedSessionEmail))
      return _verifiedSessionEmail!;
    return pending.isNotEmpty
        ? pending
        : data['email']?.toString() ?? 'No email';
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream(String uid) {
    if (_profileSnapshotUid != uid || _profileSnapshotStream == null) {
      _profileSnapshotUid = uid;
      _profileSnapshotStream = FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .snapshots();
    }
    return _profileSnapshotStream!;
  }

  bool _emailPending(Map<String, dynamic> data) {
    final pending = normalizedProfileEmail(data['pendingAuthEmail']);
    return pending.isNotEmpty &&
        pending != normalizedProfileEmail(_verifiedSessionEmail) &&
        pending != normalizedProfileEmail(data['authEmail']);
  }

  // ─── LOGOUT ──────────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final navigator = Navigator.of(context);
    final shouldLogout = await _showLogoutConfirmation(context);
    if (shouldLogout != true || !mounted) return;
    try {
      await StaffLoginSession.close();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save logout time. Please reconnect and try again.',
            ),
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await clearPersistedAccountSession(prefs);
    await FirebaseAuth.instance.signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<bool?> _showLogoutConfirmation(BuildContext currentContext) {
    return showDialog<bool>(
      context: currentContext,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final isTablet = size.width >= 700;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isTablet ? 40 : 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 520 : size.width),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _pinkDark.withOpacity(0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryDeep, _pinkDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Logging Out?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _cardBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: _pinkDark,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'You will need to sign in again to access your account.',
                                  style: TextStyle(
                                    color: _textSoft,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _pinkDark,
                                  side: const BorderSide(
                                    color: _border,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _pinkDark,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                child: const Text(
                                  'Sign Out',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── EDIT PROFILE — Half-Screen Bottom Sheet ──────────────────────────────
  Future<void> _showEditProfileSheet() async {
    final uid = _staffDocId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _showStyledSnackBar(
        'Please sign in again to edit your profile.',
        isError: true,
      );
      return;
    }
    final docRef = FirebaseFirestore.instance
        .collection('staff_requests')
        .doc(uid);
    final cached = _loadedProfile;
    final loading = cached == null
        ? docRef.get().timeout(const Duration(seconds: 10))
        : null;
    Widget? editor;
    Widget buildEditor(Map<String, dynamic> data) =>
        editor ??= _EditProfileSheet(
          docRef: docRef,
          firstNameController: TextEditingController(
            text: '${data['firstName'] ?? ''}',
          ),
          lastNameController: TextEditingController(
            text: '${data['lastName'] ?? ''}',
          ),
          emailController: TextEditingController(
            text: '${data['pendingAuthEmail'] ?? data['email'] ?? ''}',
          ),
          phoneController: TextEditingController(
            text: '${data['phone'] ?? ''}',
          ),
          addressController: TextEditingController(
            text: '${data['address'] ?? ''}',
          ),
          ageController: TextEditingController(text: '${data['age'] ?? ''}'),
          onSaved: _showStyledSnackBar,
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => cached != null
          ? buildEditor(cached)
          : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: loading,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.exists) {
                  return buildEditor(snapshot.data!.data()!);
                }
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _pinkDark,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (snapshot.connectionState == ConnectionState.done)
                        const Text(
                          'Unable to load your profile. Check your connection and reopen Edit Profile.',
                        )
                      else ...[
                        const LinearProgressIndicator(color: _pinkDark),
                        for (var i = 0; i < 3; i++)
                          Container(
                            height: 48,
                            margin: const EdgeInsets.only(top: 16),
                            decoration: BoxDecoration(
                              color: _border.withValues(alpha: .5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showChangePasswordSheet() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final uid =
        _staffDocId ??
        currentUser?.uid ??
        prefs.getString('lastStaffDocId') ??
        prefs.getString('lastUserId');
    if (!mounted) return;
    if (uid == null || uid.isEmpty) {
      _showStyledSnackBar(
        'Please sign in again to change your password.',
        isError: true,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) =>
          _ChangePasswordSheet(accountId: uid, onMessage: _showStyledSnackBar),
    );
  }

  void _showStyledSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFB71C1C) : _pinkDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid ?? _staffDocId;
    if (uid == null || uid.isEmpty || _isUploadingProfilePhoto) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 65,
      );
      if (picked == null) return;

      setState(() => _isUploadingProfilePhoto = true);
      final bytes = await picked.readAsBytes();
      final photoUrl = await _uploadProfilePhoto(bytes, uid);

      await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .set({
            'photoUrl': photoUrl,
            'profileImageUrl': photoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      _lastProfilePhotoUrl = photoUrl;
      if (!photoUrl.startsWith('data:image/')) {
        await currentUser?.updatePhotoURL(photoUrl);
      }

      if (!mounted) return;
      _showStyledSnackBar('Profile photo updated successfully.');
    } catch (e) {
      if (!mounted) return;
      _showStyledSnackBar(
        'Unable to upload profile photo. Please try another image.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUploadingProfilePhoto = false);
    }
  }

  String? _imageDataUrl(Uint8List bytes) {
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    if (dataUrl.length > 700000) return null;
    return dataUrl;
  }

  Uint8List? _bytesFromDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || commaIndex == -1) return null;
    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  Future<String> _uploadProfilePhoto(Uint8List bytes, String uid) async {
    try {
      final imageRef = FirebaseStorage.instance.ref().child(
        'staff_profiles/$uid-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final upload = await imageRef
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 12));
      return upload.ref.getDownloadURL().timeout(const Duration(seconds: 12));
    } catch (e) {
      final dataUrl = _imageDataUrl(bytes);
      if (dataUrl == null) rethrow;
      debugPrint('Storage profile upload unavailable, saved data URL: $e');
      return dataUrl;
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: TopEdgeRefresh(
            displacement: 24,
            color: _pinkMid,
            onRefresh: _refreshProfile,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 0),
                      _buildInfoCard(),
                      const SizedBox(height: 24),
                      _buildChangePassword(),
                      const SizedBox(height: 12),
                      _buildLogout(),
                      const SizedBox(height: 100),
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

  // ─── HEADER ──────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid ?? _staffDocId;
    if (uid == null || uid.isEmpty) return _buildHeaderError();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final cachedProfile = _loadedProfile;
          if (cachedProfile == null) return _buildHeaderLoading();
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          if (_loadedProfile != null) {
            return _buildHeaderFromData(context, uid, _loadedProfile!);
          }
          return _buildHeaderError();
        }

        final staffData = snapshot.data!.data() ?? {};
        _loadedProfile = Map<String, dynamic>.from(staffData);
        return _buildHeaderFromData(context, uid, staffData);
      },
    );
  }

  Widget _buildHeaderFromData(
    BuildContext context,
    String uid,
    Map<String, dynamic> staffData,
  ) {
    final firstName = staffData['firstName'] ?? 'Staff';
    final lastName = staffData['lastName'] ?? 'Member';
    final email = _verifiedSessionEmail ?? confirmedProfileEmail(staffData);
    final staffId = publicItemId('${staffData['staffId'] ?? 'N/A'}');
    final photoUrl =
        staffData['photoUrl']?.toString() ??
        staffData['profileImageUrl']?.toString() ??
        '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDeep,
            _pinkDark,
            _pinkMid,
            AppColors.accent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 60,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.07),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 500;
                    final identity = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$firstName $lastName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 18 : 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.60),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _accent.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _accent.withOpacity(0.60),
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                'Staff Member',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _accentLight,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (isCompact) ...[
                              const Spacer(),
                              _buildEditButton(compact: true),
                            ],
                          ],
                        ),
                      ],
                    );

                    if (isCompact) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildAvatar(photoUrl),
                          const SizedBox(width: 14),
                          Expanded(child: identity),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildAvatar(photoUrl),
                        const SizedBox(width: 16),
                        Expanded(child: identity),
                        const SizedBox(width: 10),
                        _buildEditButton(),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _accent.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 15,
                        color: _accentLight.withOpacity(0.75),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ID: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.50),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        staffId,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('staff_budget')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, budgetSnapshot) {
                    final data =
                        budgetSnapshot.data?.data() as Map<String, dynamic>?;
                    final start =
                        data?['dutyStartTime']?.toString().trim() ?? '';
                    final end = data?['dutyEndTime']?.toString().trim() ?? '';
                    if (start.isEmpty && end.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildWorkHoursChip(start, end),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkHoursChip(String start, String end) {
    final label = [
      if (start.isNotEmpty) start else '--:--',
      if (end.isNotEmpty) end else '--:--',
    ].join(' - ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withOpacity(0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 15,
            color: _accentLight.withOpacity(0.75),
          ),
          const SizedBox(width: 8),
          Text(
            'Work Hours: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.50),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderLoading() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDeep, _pinkDark, _pinkMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 52),
          Row(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 150,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 120,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildHeaderError() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDeep, _pinkDark, _pinkMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 28),
      child: const Text(
        'Unable to load profile',
        style: TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl) {
    return GestureDetector(
      onTap: _pickAndUploadProfilePhoto,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_accentLight, _accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.45),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipOval(
              child: Container(
                width: 78,
                height: 78,
                color: _pinkDark,
                child: _profilePhoto(photoUrl),
              ),
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: _isUploadingProfilePhoto
                  ? const Padding(
                      padding: EdgeInsets.all(5),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profilePhoto(String? photoUrl) {
    final incomingUrl = photoUrl?.trim() ?? '';
    if (incomingUrl.isNotEmpty) _lastProfilePhotoUrl = incomingUrl;
    final url = incomingUrl.isNotEmpty
        ? incomingUrl
        : (_lastProfilePhotoUrl?.trim() ?? '');
    if (url.startsWith('data:image/')) {
      final bytes = _bytesFromDataUrl(url);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      }
    }
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) => child,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person, size: 40, color: Colors.white54),
      );
    }
    return const Icon(Icons.person, size: 40, color: Colors.white54);
  }

  Widget _buildEditButton({bool compact = false}) {
    return Semantics(
      key: widget.editProfileTourKey,
      button: true,
      label: 'Edit Profile',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showEditProfileSheet,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accentLight, _accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_rounded, size: 13, color: Colors.white),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── INFO CARD ────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid ?? _staffDocId;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profileStream(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _pinkMid.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: const Text('No information available'),
            );
          }

          final staffData = snapshot.data!.data() ?? {};
          final email = _profileEmail(staffData);
          final firstName = staffData['firstName'] ?? 'N/A';
          final lastName = staffData['lastName'] ?? 'N/A';
          final address = staffData['address'] ?? 'N/A';
          final phone = staffData['phone'] ?? 'N/A';
          final age = staffData['age'] ?? 'N/A';
          final staffId = publicItemId('${staffData['staffId'] ?? 'N/A'}');
          final role = staffData['role'] ?? 'Staff Member';
          final createdAt = staffData['createdAt'];
          final memberSince = createdAt is Timestamp
              ? _formatProfileDate(createdAt.toDate())
              : 'N/A';

          return Column(
            children: [
              Transform.translate(
                offset: const Offset(0, -18),
                child: _buildProfileSummary(memberSince),
              ),
              const SizedBox(height: 2),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: _pinkMid.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 500;
                        final openActivityLogs = _staffDocId == null
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) => BranchStaffActivityDialog(
                                  branchId: '',
                                  branchName: '',
                                  userId: _staffDocId,
                                ),
                              );
                        return Row(
                          key: widget.tourTargetKey,
                          children: [
                            Container(
                              width: 4,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _pinkMid,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppColors.blush,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.person_outline_rounded,
                                color: _pinkDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Personal Information',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF2B1720),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'View and manage your personal details',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _textSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (compact)
                              IconButton(
                                tooltip: 'Activity Logs',
                                onPressed: openActivityLogs,
                                icon: const Icon(Icons.history),
                              )
                            else
                              TextButton.icon(
                                onPressed: openActivityLogs,
                                icon: const Icon(Icons.history),
                                label: const Text('Activity Logs'),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        final tileWidth = isWide
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                        final details = [
                          (Icons.badge_outlined, 'Staff ID', staffId),
                          (Icons.email_outlined, 'Email Address', email),
                          (
                            Icons.person_outline_rounded,
                            'First Name',
                            firstName,
                          ),
                          (Icons.phone_outlined, 'Phone Number', phone),
                          (Icons.person_outline_rounded, 'Last Name', lastName),
                          (Icons.shield_outlined, 'Role', role),
                          (Icons.location_on_outlined, 'Address', address),
                          (Icons.cake_outlined, 'Age', age.toString()),
                        ];

                        return Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: details.map((detail) {
                            return SizedBox(
                              width: tileWidth,
                              child: _buildDetailTile(
                                icon: detail.$1,
                                label: detail.$2,
                                value: detail.$3.toString(),
                                pending:
                                    detail.$2 == 'Email Address' &&
                                    _emailPending(staffData),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatProfileDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day.toString().padLeft(2, '0')}, ${value.year}';
  }

  Widget _buildProfileSummary(String memberSince) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _pinkMid.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryItem(
              Icons.badge_outlined,
              'Account Status',
              'Active',
              accent: Colors.green,
            ),
          ),
          Container(width: 1, height: 42, color: _border),
          Expanded(
            child: _buildSummaryItem(
              Icons.calendar_month_outlined,
              'Member Since',
              memberSince,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    IconData icon,
    String label,
    String value, {
    Color? accent,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.blush,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: _pinkDark),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _textSoft,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accent != null) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2B1720),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailTile({
    bool pending = false,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withOpacity(0.75)),
        boxShadow: [
          BoxShadow(
            color: _pinkMid.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.blush,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: _pinkDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _textSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF24141A),
                  ),
                ),
                if (pending) ...[
                  const SizedBox(height: 6),
                  const EmailPendingBadge(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.grey.shade300,
              ),
            ],
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 74),
            child: Divider(height: 1, color: Color(0xFFF5F5F5)),
          ),
      ],
    );
  }

  Widget _buildChangePassword() {
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _showChangePasswordSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: _pinkMid.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_reset_rounded, color: _pinkDark, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _pinkDark,
                      letterSpacing: 0.2,
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

  Widget _buildLogout() {
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _handleLogout,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_pinkMid, _pinkDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _pinkMid.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Sign Out',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
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

// ─────────────────────────────────────────────────────────────────────────────
// EDIT PROFILE BOTTOM SHEET (Separate StatefulWidget for clean animation)
// ─────────────────────────────────────────────────────────────────────────────
class _EditProfileSheet extends StatefulWidget {
  final DocumentReference docRef;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController ageController;
  final ValueChanged<String> onSaved;

  const _EditProfileSheet({
    required this.docRef,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    required this.addressController,
    required this.ageController,
    required this.onSaved,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late AnimationController _sheetAnimCtrl;
  late Animation<double> _sheetFade;
  late Animation<Offset> _sheetSlide;
  bool _isSaving = false;
  late final String _initialEmail;

  // ── Pink palette (local copy) ───────────────────────────────────
  static const Color _pinkDark = AppColors.primaryDark;
  static const Color _pinkMid = AppColors.primary;
  static const Color _accent = Color(0xFFD4873A);
  static const Color _accentLight = Color(0xFFF0A855);
  static const Color _border = AppColors.blush;
  // ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initialEmail = normalizedProfileEmail(widget.emailController.text);
    _sheetAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _sheetFade = CurvedAnimation(parent: _sheetAnimCtrl, curve: Curves.easeOut);
    _sheetSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _sheetAnimCtrl, curve: Curves.easeOutCubic),
        );
    _sheetAnimCtrl.forward();
  }

  @override
  void dispose() {
    _sheetAnimCtrl.dispose();
    widget.firstNameController.dispose();
    widget.lastNameController.dispose();
    widget.emailController.dispose();
    widget.phoneController.dispose();
    widget.addressController.dispose();
    widget.ageController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    final firstName = widget.firstNameController.text.trim();
    final lastName = widget.lastNameController.text.trim();
    final email = widget.emailController.text.trim();
    final phone = widget.phoneController.text.trim();
    final address = widget.addressController.text.trim();
    final ageText = widget.ageController.text.trim();
    final age = int.tryParse(ageText);
    var authUser = FirebaseAuth.instance.currentUser;
    var authEmail = authUser?.email?.trim() ?? '';
    final changingAuthEmail = normalizedProfileEmail(email) != _initialEmail;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final emailEdited = normalizedProfileEmail(email) != _initialEmail;
      if (emailEdited &&
          await profileEmailTaken(
            widget.docRef.firestore,
            email,
            widget.docRef.id,
          )) {
        if (mounted)
          _showSheetSnackBar(
            'This email is already used by another account.',
            isError: true,
          );
        return;
      }
      if (changingAuthEmail) {
        final password = await _requestCurrentPassword();
        if (password == null || !mounted) return;
        if (authUser?.uid != widget.docRef.id) {
          final profile =
              (await widget.docRef.get()).data() as Map<String, dynamic>? ?? {};
          final candidates = <String>{
            for (final field in ['pendingAuthEmail', 'authEmail', 'email'])
              if ('${profile[field] ?? ''}'.trim().isNotEmpty)
                '${profile[field]}'.trim(),
          };
          FirebaseAuthException? failure;
          for (final candidate in candidates) {
            try {
              final credential = await FirebaseAuth.instance
                  .signInWithEmailAndPassword(
                    email: candidate,
                    password: password,
                  );
              if (credential.user?.uid != widget.docRef.id) {
                await FirebaseAuth.instance.signOut();
                throw StateError(
                  'Please sign in to your staff account again before changing email.',
                );
              }
              authUser = credential.user;
              break;
            } on FirebaseAuthException catch (error) {
              failure = error;
              if (![
                'invalid-credential',
                'wrong-password',
                'user-not-found',
              ].contains(error.code))
                rethrow;
            }
          }
          if (authUser?.uid != widget.docRef.id) {
            if (failure != null) throw failure;
            throw StateError(
              'Please sign in again before changing your email.',
            );
          }
        } else {
          await authUser!.reauthenticateWithCredential(
            EmailAuthProvider.credential(email: authEmail, password: password),
          );
        }
        authEmail = authUser!.email!;
        await authUser.verifyBeforeUpdateEmail(email);
      }

      await widget.docRef.set({
        'firstName': firstName,
        'lastName': lastName,
        if (emailEdited) 'email': authEmail,
        if (emailEdited && authUser?.uid == widget.docRef.id) ...{
          'authEmail': authEmail,
          'pendingAuthEmail': changingAuthEmail ? email : FieldValue.delete(),
        },
        'phone': phone,
        'address': address,
        'age': age,
      }, SetOptions(merge: true));

      if (!mounted) return;
      widget.onSaved(
        changingAuthEmail
            ? 'Verification link sent to your new Gmail. Open it to activate your new sign-in and password-reset email, then sign in again.'
            : 'Profile updated successfully.',
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'wrong-password' ||
        'invalid-credential' => 'The current password is incorrect.',
        'email-already-in-use' =>
          'That Gmail is already linked to another account.',
        'invalid-email' => 'Enter a valid Gmail address.',
        'requires-recent-login' =>
          'Please sign in again, then retry changing your Gmail.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        'too-many-requests' =>
          'Too many attempts. Please wait before trying again.',
        'operation-not-allowed' =>
          'Email changes are unavailable for this account. Please contact your administrator.',
        _ => 'Unable to update your email (${error.code}). Please try again.',
      };
      _showSheetSnackBar(message, isError: true);
    } catch (e) {
      if (!mounted) return;
      _showSheetSnackBar('Error updating profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _requestCurrentPassword() => showDialog<String>(
    context: context,
    builder: (_) => const ConfirmPasswordDialog(),
  );
  void _showSheetSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFB71C1C) : _pinkDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: FadeTransition(
          opacity: _sheetFade,
          child: SlideTransition(
            position: _sheetSlide,
            child: Container(
              // Half screen + keyboard avoidance
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Drag handle ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // ── Gradient Header ───────────────────────────────────────
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryDeep, _pinkDark, _pinkMid],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: _pinkDark.withOpacity(0.28),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Deco circles
                        Positioned(
                          top: -20,
                          right: -10,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.07),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -30,
                          left: 40,
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _accent.withOpacity(0.08),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            // Avatar icon
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [_accentLight, _accent],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withOpacity(0.4),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Edit Profile',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Update your personal information',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.70),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Form Content ──────────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        bottomPadding + 16,
                      ),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: _buildAllFieldsContent(),
                      ),
                    ),
                  ),

                  // ── Action Buttons ────────────────────────────────────────
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      16 + MediaQuery.of(context).padding.bottom,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(
                          color: _border.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _pinkDark.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _pinkDark,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _border,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 17,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.check_rounded, size: 16),
                                    ],
                                  ),
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
      ),
    );
  }

  Widget _buildAllFieldsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Full Name Section ──
        _SectionLabel(icon: Icons.person_rounded, label: 'Full Name'),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: widget.firstNameController,
          label: 'First Name',
          hint: 'Enter first name',
          icon: Icons.drive_file_rename_outline_rounded,
          textCapitalization: TextCapitalization.words,
          validator: ProfileFieldValidation.name,
        ),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: widget.lastNameController,
          label: 'Last Name',
          hint: 'Enter last name',
          icon: Icons.drive_file_rename_outline_rounded,
          textCapitalization: TextCapitalization.words,
          validator: ProfileFieldValidation.name,
        ),
        const SizedBox(height: 24),

        // ── Contact Info Section ──
        _SectionLabel(icon: Icons.contact_mail_rounded, label: 'Contact Info'),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: widget.emailController,
          label: 'Email Address',
          hint: 'your@email.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: ProfileFieldValidation.gmail,
        ),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: widget.phoneController,
          label: 'Phone Number',
          hint: '09XX XXX XXXX',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          validator: ProfileFieldValidation.phone,
        ),
        const SizedBox(height: 24),

        // ── Personal Details Section ──
        _SectionLabel(icon: Icons.home_rounded, label: 'Personal Details'),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: widget.addressController,
          label: 'Home Address',
          hint: 'Street, Barangay, City',
          icon: Icons.location_on_outlined,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          validator: (value) {
            if (value?.trim().isEmpty ?? true) return 'This field is required.';
            return ProfileFieldValidation.wordLimit(value);
          },
        ),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: widget.ageController,
          label: 'Age',
          hint: 'e.g. 24',
          icon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          validator: ProfileFieldValidation.age,
        ),
        const SizedBox(height: 16),
        _FieldTip(
          text:
              'Review all fields before saving. Fill in all information accurately.',
        ),
      ],
    );
  }
}

// ─── Reusable Sheet Components ────────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  final String accountId;
  final void Function(String message, {bool isError}) onMessage;

  const _ChangePasswordSheet({
    required this.accountId,
    required this.onMessage,
  });

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  bool _logoutAll = false;
  bool _continuing = false;
  String? _logoutError;

  Future<void> _finishPasswordChange() async {
    if (_continuing) return;
    if (!_logoutAll) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _continuing = true;
      _logoutError = null;
    });
    try {
      await logOutAccountDevices(FirebaseFirestore.instance, widget.accountId);
      // The app-wide session listener also signs this device out.
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(
          () => _logoutError =
              'Unable to log out all devices. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  final _autofillUsername = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.email ?? '',
  );
  bool _saved = false;

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _error;
  void _showMessage(String message, {bool isError = false}) {
    if (isError) {
      if (mounted) setState(() => _error = message);
    } else {
      widget.onMessage(message);
    }
  }

  bool _isSaving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _currentPasswordController,
      _newPasswordController,
      _confirmPasswordController,
    ]) {
      controller.addListener(_passwordChanged);
    }
  }

  void _passwordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autofillUsername.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (_isSaving || _saved) return;

    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessage('Please complete all password fields.', isError: true);
      return;
    }

    if (!PasswordStrength(newPassword).isAcceptable) {
      _showMessage(
        'Password is weak. Meet at least 3 of the 5 requirements to use a fair password.',
        isError: true,
      );
      return;
    }

    if (newPassword != confirmPassword) {
      _showMessage('Passwords do not match.', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final ref = FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(widget.accountId);
      final data = (await ref.get(
        const GetOptions(source: Source.server),
      )).data();
      if (data == null)
        throw StateError('Staff account not found. Please sign in again.');
      final user = FirebaseAuth.instance.currentUser;
      if (data['passwordAuthMode'] != 'firestore' &&
          user?.uid == widget.accountId &&
          user?.email != null) {
        await user!.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: user.email!,
            password: currentPassword,
          ),
        );
        await user.updatePassword(newPassword);
        await ref.update({
          'mustChangePassword': false,
          'passwordChangedAt': FieldValue.serverTimestamp(),
          'credentialsChangedAt': FieldValue.serverTimestamp(),
          'passwordAuthMode': 'firebase',
          'passwordCredential': FieldValue.delete(),
          for (final field in legacyPasswordFields) field: FieldValue.delete(),
        });
      } else {
        await changeFirestoreAccountPassword(
          account: ref,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key
            in prefs
                .getKeys()
                .where(
                  (key) =>
                      key.startsWith('offlineAccount.') ||
                      key.startsWith('offlineLogin.'),
                )
                .toList()) {
          await prefs.remove(key);
        }
      } catch (error) {
        debugPrint(
          'Unable to clear remembered login after password change: $error',
        );
      }

      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      TextInput.finishAutofillContext(shouldSave: true);
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() {
        _saved = true;
      });
    } on FirebaseAuthException catch (e) {
      final message =
          e.code == 'wrong-password' || e.code == 'invalid-credential'
          ? 'Current password is incorrect.'
          : 'Unable to update password. Please try again.';
      if (mounted) _showMessage(message, isError: true);
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to update password. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _ProfilePageState._border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Change Password',
                  style: TextStyle(
                    color: _ProfilePageState._pinkDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                if (_saved) ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 42,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Password changed successfully. Use your new password the next time you sign in.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.blush.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          groupValue: _logoutAll,
                          activeColor: AppColors.primary,
                          onChanged: _continuing
                              ? null
                              : (value) => setState(() => _logoutAll = value!),
                          title: const Text('Stay logged in'),
                          subtitle: const Text('Continue using this device.'),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          groupValue: _logoutAll,
                          activeColor: AppColors.primary,
                          onChanged: _continuing
                              ? null
                              : (value) => setState(() => _logoutAll = value!),
                          title: const Text('Log out all devices'),
                          subtitle: const Text(
                            'Includes this device. Sign in again with your new password.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_logoutError != null)
                    Text(
                      _logoutError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: _continuing ? null : _finishPasswordChange,
                    child: Text(_continuing ? 'Logging out…' : 'Continue'),
                  ),
                ] else ...[
                  Offstage(
                    child: TextField(
                      controller: _autofillUsername,
                      autofillHints: const [AutofillHints.username],
                      readOnly: true,
                    ),
                  ),
                  PasswordEntryField(
                    controller: _currentPasswordController,
                    label: 'Current Password',
                    obscureText: _obscureCurrent,
                    onToggle: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                  const SizedBox(height: 12),
                  PasswordEntryField(
                    controller: _newPasswordController,
                    label: 'New Password',
                    obscureText: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  PasswordStrengthChecklist(
                    password: _newPasswordController.text,
                  ),
                  const SizedBox(height: 12),
                  PasswordEntryField(
                    controller: _confirmPasswordController,
                    label: 'Confirm New Password',
                    obscureText: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  const SizedBox(height: 18),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _isSaving || _saved ? null : _savePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ProfilePageState._pinkDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save Password',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _FieldTip extends StatelessWidget {
  final String text;
  const _FieldTip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 15,
            color: Color(0xFFF57C00),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE65100),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLines;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
  });

  static const Color _pinkDark = AppColors.primaryDark;
  static const Color _border = AppColors.blush;
  static const Color _cardBg = AppColors.surfaceTint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _pinkDark, size: 18),
        labelStyle: const TextStyle(color: _pinkDark, fontSize: 13),
        hintStyle: TextStyle(
          color: AppColors.textMuted.withOpacity(0.45),
          fontSize: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _pinkDark, width: 2),
        ),
        filled: true,
        fillColor: _cardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
