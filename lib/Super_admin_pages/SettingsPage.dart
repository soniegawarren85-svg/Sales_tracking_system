import 'dart:async';
import '../services/verified_email_sync.dart';
import 'dart:convert';
import '../services/super_admin.dart';
import '../services/session_actor.dart';
import '../services/password_policy.dart';
import '../services/verified_profile_email_change.dart';
import '../services/profile_email.dart';
import '../widgets/transaction_settings_dialog.dart';
import '../widgets/account_activity_logs_dialog.dart';
import '../services/account_login_session.dart';
import '../widgets/password_strength_checklist.dart';
import '../widgets/admin_page_skeleton.dart';
import '../widgets/logout_progress.dart';
import '../widgets/account_profile_editor_sheet.dart';
import '../services/catalog_image_service.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import '../services/public_item_id.dart';
import '../widgets/backup_restore_dialog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/Login/Login/Login.dart';

class SuperAdminSettingsPage extends StatefulWidget {
  const SuperAdminSettingsPage({
    this.onOpenStaff,
    this.onOpenReports,
    super.key,
    this.firestore,
  });
  final FirebaseFirestore? firestore;

  final VoidCallback? onOpenStaff;
  final VoidCallback? onOpenReports;

  @override
  State<SuperAdminSettingsPage> createState() => _SuperAdminSettingsPageState();
}

class _SuperAdminSettingsPageState extends State<SuperAdminSettingsPage>
    with WidgetsBindingObserver {
  bool _isUploadingProfilePhoto = false;
  String? _lastProfilePhotoUrl;
  Uint8List? _profilePreview;
  String _adminId = 'ADM-001';
  String _profileId = 'ADM-001';
  bool _profileReady = false;
  Timer? _emailRefresh;
  bool _syncingEmail = false;

  Future<void> _refreshVerifiedEmail() async {
    if (_syncingEmail || !_profileReady) return;
    _syncingEmail = true;
    try {
      await syncVerifiedProfileEmail(
        profile: (widget.firestore ?? FirebaseFirestore.instance)
            .collection('super_admin_profiles')
            .doc(_profileId),
        user: FirebaseAuth.instance.currentUser,
      );
    } catch (error) {
      debugPrint('Email status refresh: $error');
    } finally {
      _syncingEmail = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshVerifiedEmail();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailRefresh?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAdminId().then((_) => _refreshVerifiedEmail());
    WidgetsBinding.instance.addObserver(this);
    _emailRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        _refreshVerifiedEmail();
    });
  }

  Future<void> _loadAdminId() async {
    if (!mounted) return;
    setState(() {
      _profileReady = true;
      _adminId = SuperAdmin.id;
      _profileId = SuperAdmin.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_profileReady) {
      return const Scaffold(
        body: AdminPageSkeleton(kind: AdminSkeletonKind.settings),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            /// ===== PREMIUM HEADER =====
            SliverAppBar(
              automaticallyImplyLeading: false,
              expandedHeight: 200,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: AppColors.primary,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    /// Gradient Background
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryDark,
                            AppColors.primary,
                            AppColors.accent,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),

                    /// Decorative Circle Top Right
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                    ),

                    /// Decorative Circle Bottom Left
                    Positioned(
                      bottom: 20,
                      left: -20,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),

                    /// Wavy Clip at Bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipPath(
                        clipper: _WaveClipper(),
                        child: Container(
                          height: 36,
                          color: AppColors.background,
                        ),
                      ),
                    ),

                    /// Profile Content
                    Positioned(
                      bottom: 65,
                      left: 24,
                      right: 24,
                      child:
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream:
                                (widget.firestore ?? FirebaseFirestore.instance)
                                    .collection('super_admin_profiles')
                                    .doc(_profileId)
                                    .snapshots(),
                            builder: (context, snapshot) {
                              final data = snapshot.data?.data();
                              final fullName = _getFullName(data);
                              final confirmedEmail = confirmedProfileEmail(
                                data ?? {},
                              );
                              final pendingEmail =
                                  '${data?['pendingAuthEmail'] ?? ''}'.trim();
                              final email = confirmedEmail.isNotEmpty
                                  ? confirmedEmail
                                  : pendingEmail.isNotEmpty
                                  ? '$pendingEmail (Pending)'
                                  : 'No email';
                              final adminId =
                                  data?['adminId']?.toString() ??
                                  data?['staffId']?.toString() ??
                                  _adminId;
                              final role =
                                  data?['role']
                                      ?.toString()
                                      .trim()
                                      .toLowerCase() ??
                                  'admin';
                              final roleLabel = role == 'admin'
                                  ? 'Super admin'
                                  : 'Staff';
                              final photoUrl =
                                  data?['photoUrl']?.toString() ??
                                  data?['profileImageUrl']?.toString();

                              return Row(
                                children: [
                                  /// Avatar with Ring
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildAdminAvatar(photoUrl),
                                      const SizedBox(height: 3),
                                      Text(
                                        publicItemId(adminId),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          fullName,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          email,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            color: Colors.white.withOpacity(
                                              0.85,
                                            ),
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(
                                                0.4,
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            roleLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  /// Edit Icon
                                  GestureDetector(
                                    onTap: () =>
                                        _showAccountInformation(context, data),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.2),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.4),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.edit_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                    ),

                    /// Title (collapsed)
                  ],
                ),
              ),
            ),

            /// ===== CONTENT =====
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 6),

                  if (MediaQuery.sizeOf(context).width < 600 &&
                      widget.onOpenStaff != null &&
                      widget.onOpenReports != null) ...[
                    _sectionLabel("Others"),
                    _settingItem(
                      icon: Icons.people_rounded,
                      title: "Staff",
                      subtitle: "Manage staff accounts",
                      iconColor: const Color(0xFF7B1FA2),
                      iconBg: const Color(0xFFF3E5F5),
                      onTap: widget.onOpenStaff!,
                    ),
                    _settingItem(
                      icon: Icons.bar_chart_rounded,
                      title: "Reports",
                      subtitle: "View sales reports",
                      iconColor: const Color(0xFF3949AB),
                      iconBg: const Color(0xFFE8EAF6),
                      onTap: widget.onOpenReports!,
                    ),
                    const SizedBox(height: 6),
                  ],
                  _sectionLabel("Account"),
                  _settingItem(
                    icon: Icons.manage_accounts_rounded,
                    title: "Account information",
                    subtitle: "",
                    subtitleWidget: _buildAccountInformationSummary(),
                    iconColor: const Color(0xFF7B1FA2),
                    iconBg: const Color(0xFFF3E5F5),
                    onTap: () =>
                        _showAccountInformation(context, null, readOnly: true),
                  ),
                  _settingItem(
                    icon: Icons.lock_reset_rounded,
                    title: "Change Password",
                    subtitle: "Update your Super Admin login password",
                    iconColor: const Color(0xFF3949AB),
                    iconBg: const Color(0xFFE8EAF6),
                    onTap: () => _showChangePassword(context),
                  ),
                  _settingItem(
                    icon: Icons.history_rounded,
                    title: "Activity Logs",
                    subtitle: "Review sign-ins and account activity",
                    iconColor: const Color(0xFF00897B),
                    iconBg: const Color(0xFFE0F2F1),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const AccountActivityLogsDialog(
                        actorId: SuperAdmin.id,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  _sectionLabel("Transaction settings"),
                  _settingItem(
                    icon: Icons.discount_rounded,
                    title: "Discount Control",
                    subtitle: "Manage discount permissions",
                    iconColor: const Color(0xFFFF6F00),
                    iconBg: const Color(0xFFFFF8E1),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) =>
                          const TransactionSettingsDialog(kind: 'discounts'),
                    ),
                  ),
                  _settingItem(
                    icon: Icons.payments_rounded,
                    title: "Payment Settings",
                    subtitle: "Configure payment and cash drawer options",
                    iconColor: const Color(0xFF3949AB),
                    iconBg: const Color(0xFFE8EAF6),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) =>
                          const TransactionSettingsDialog(kind: 'payments'),
                    ),
                  ),
                  _settingItem(
                    icon: Icons.percent_rounded,
                    title: "Tax Configuration",
                    subtitle: "Set VAT status for each branch",
                    iconColor: const Color(0xFF00897B),
                    iconBg: const Color(0xFFE0F2F1),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) =>
                          const TransactionSettingsDialog(kind: 'tax'),
                    ),
                  ),

                  const SizedBox(height: 6),

                  _sectionLabel("Access control"),
                  _settingItem(
                    icon: Icons.verified_user_rounded,
                    title: "Security and Approval",
                    subtitle: "Manage access and approvals",
                    iconColor: const Color(0xFF00897B),
                    iconBg: const Color(0xFFE0F2F1),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const TransactionSettingsDialog(
                        kind: 'permissions',
                        separateRoles: true,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  _sectionLabel("System settings"),
                  _settingItem(
                    icon: Icons.backup_rounded,
                    title: 'Backup and Restore',
                    subtitle: 'Download a backup or restore from a file',
                    iconColor: AppColors.primaryDark,
                    iconBg: AppColors.blush,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const BackupRestoreDialog(),
                    ),
                  ),
                  _settingItem(
                    icon: Icons.info_rounded,
                    title: "About App",
                    subtitle: "About the sales tracking system",
                    iconColor: const Color(0xFF1E88E5),
                    iconBg: const Color(0xFFE3F2FD),
                    onTap: () => _showInfoDialog(
                      context,
                      'About App',
                      'Track sales and inventory across branches, allocate cash and products, manage staff and beverage bundles, monitor expiry, and review branch reports.',
                    ),
                  ),
                  const SizedBox(height: 28),

                  /// ===== LOGOUT BUTTON =====
                  const SizedBox.shrink(),

                  const SizedBox(height: 10),

                  /// App Version
                  Center(
                    child: Text(
                      "Sales Tracking",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  if (MediaQuery.sizeOf(context).width < 600) _LogoutButton(),
                  const SizedBox(height: 30),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminAvatar(String? photoUrl) {
    final url = photoUrl?.trim() ?? '';
    Widget avatar;
    if (_profilePreview != null) {
      avatar = Image.memory(_profilePreview!, fit: BoxFit.cover);
    } else if (url.startsWith('data:image/')) {
      final commaIndex = url.indexOf(',');
      final bytes = commaIndex == -1
          ? null
          : base64Decode(url.substring(commaIndex + 1));
      avatar = bytes == null
          ? const Icon(Icons.person_rounded, size: 38, color: Colors.white)
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (url.isNotEmpty) {
      avatar = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person_rounded, size: 38, color: Colors.white),
      );
    } else {
      avatar = const Icon(Icons.person_rounded, size: 38, color: Colors.white);
    }

    return GestureDetector(
      onTap: _pickAndUploadProfilePhoto,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: Container(
                width: 68,
                height: 68,
                color: AppColors.primaryDark,
                child: avatar,
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: 0,
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C42),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: _isUploadingProfilePhoto
                  ? const Padding(
                      padding: EdgeInsets.all(4),
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

  Future<void> _pickAndUploadProfilePhoto() async {
    final uid = _profileId;
    if (uid.isEmpty || _isUploadingProfilePhoto) return;
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
      if (mounted) setState(() => _profilePreview = bytes);
      final photoUrl = await _uploadProfilePhoto(bytes, uid);
      await (widget.firestore ?? FirebaseFirestore.instance)
          .collection('super_admin_profiles')
          .doc(uid)
          .set({
            'photoUrl': photoUrl,
            'profileImageUrl': photoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      _lastProfilePhotoUrl = photoUrl;
      if (FirebaseAuth.instance.currentUser?.uid == _profileId) {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(
          photoUrl.startsWith('data:image/') ? null : photoUrl,
        );
      }
      if (mounted) _showStyledSnackBar('Profile photo updated successfully.');
    } catch (_) {
      if (mounted) {
        _showStyledSnackBar(
          'Unable to upload profile photo. Please try another image.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProfilePhoto = false;
          _profilePreview = null;
        });
      }
    }
  }

  Future<String> _uploadProfilePhoto(Uint8List bytes, String uid) async {
    final url = await uploadCatalogImage(bytes, folder: 'admin_profiles');
    if (url == null) throw StateError('Unable to upload photo');
    return url;
  }

  Future<void> _showAccountInformation(
    BuildContext context,
    Map<String, dynamic>? incomingData, {
    bool readOnly = false,
  }) async {
    final uid = _profileId;
    final db = widget.firestore ?? FirebaseFirestore.instance;
    var data = <String, dynamic>{...?incomingData};
    final profile = db.collection('super_admin_profiles').doc(uid);
    final snapshot = await profile.get();
    data = {...data, ...?snapshot.data()};
    if (!mounted) return;

    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AccountProfileEditorSheet(
        profile: data,
        readOnly: readOnly,
        onSave: (values) async {
          var verificationSent = false;
          if (values.emailChanged || values.verifyPendingEmail) {
            final preferences = await SharedPreferences.getInstance();
            if (!await SuperAdmin.verifyPassword(
              values.currentPassword,
              preferences: preferences,
              database: db,
            )) {
              throw StateError('The current password is incorrect.');
            }
            verificationSent = await requestVerifiedProfileEmailChange(
              profile: profile,
              profileData: data,
              newEmail: values.email,
              currentPassword: values.currentPassword,
              allowInitialEmailSetup: true,
            );
            // Keep the linked session available for automatic verification refresh.
            await SuperAdmin.verifyPassword(
              values.currentPassword,
              database: db,
            );
          }

          await profile.set({
            'firstName': values.firstName,
            'middleName': values.middleName,
            'lastName': values.lastName,
            'age': values.age,
            'address': values.address,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          return verificationSent
              ? 'Profile saved. A verification link was sent to ${values.email}; the Gmail changes after you verify it.'
              : values.emailChanged || values.verifyPendingEmail
              ? 'Gmail verification is complete. Account information updated.'
              : 'Account information updated.';
        },
      ),
    );
    if (message != null && mounted) _showStyledSnackBar(message);
  }

  void _showStyledSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      ),
    );
  }

  Widget _buildAccountInformationSummary() => const Text('Manage information');

  String _getFullName(Map<String, dynamic>? data) {
    if (data == null) return 'Super admin';
    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final middleName = (data['middleName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';
    final fullName = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');
    return fullName.isEmpty ? 'Super admin' : fullName;
  }

  Future<void> _showChangePassword(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuperAdminChangePasswordDialog(
        database: widget.firestore ?? FirebaseFirestore.instance,
      ),
    );
    if (changed == true && mounted) {
      _showStyledSnackBar('Password updated.');
    }
  }

  static void _showNotificationSettings(BuildContext context) {
    final alerts = {
      'Reports': true,
      'Low Stock': true,
      'Expired Items': true,
      'Refunds': true,
      'Cash Drawer': true,
    };
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Manage Alerts'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: alerts.keys.map((key) {
              return SwitchListTile(
                value: alerts[key]!,
                title: Text(key),
                activeThumbColor: AppColors.primary,
                onChanged: (value) async {
                  setState(() => alerts[key] = value);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('admin_alert_$key', value);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static void _showDarkMode(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dark Mode'),
        content: const Text('Dark mode preference is saved for this device.'),
        actions: [
          Switch(
            value: false,
            onChanged: (value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('admin_dark_mode', value);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  static void _showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// ===== SECTION LABEL =====
  static Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 16, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// ===== SETTING ITEM =====
  static Widget _settingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? subtitleWidget,
    required Color iconColor,
    required Color iconBg,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          splashColor: iconColor.withOpacity(0.07),
          highlightColor: iconColor.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                /// Colored Icon Box
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),

                /// Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      subtitleWidget ??
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                    ],
                  ),
                ),

                /// Arrow
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey[400],
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

/// ===== LOGOUT BUTTON (StatefulWidget for press animation) =====
class _LogoutButton extends StatefulWidget {
  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1.0,
    )..value = 1.0;
    _scaleAnim = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _controller.reverse();
  void _onTapUp(_) => _controller.forward();
  void _onTapCancel() => _controller.forward();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () => _showLogoutDialog(context),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                AppColors.primaryDark,
                AppColors.primary,
                AppColors.accent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.38),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "Logout",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ===== LOGOUT CONFIRM DIALOG =====
  static void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// Icon Badge
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              /// Title
              const Text(
                "Logging Out?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),

              /// Subtitle
              Text(
                "You'll need to sign in again\nto access your account.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              /// Divider Line
              Divider(color: Colors.grey[100], thickness: 1.5),
              const SizedBox(height: 16),

              /// Buttons
              Row(
                children: [
                  /// Cancel
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            "Cancel",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  /// Logout Confirm
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await runWithLogoutProgress(context, () async {
                            await AccountLoginSession.close();
                            final prefs = await SharedPreferences.getInstance();
                            await clearPersistedAccountSession(prefs);
                            await FirebaseAuth.instance.signOut();
                          });
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Unable to complete logout: $error',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        if (!context.mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            "Logout",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===== WAVE CLIPPER =====
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.5);
    path.quadraticBezierTo(
      size.width * 0.25,
      0,
      size.width * 0.5,
      size.height * 0.5,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height,
      size.width,
      size.height * 0.5,
    );
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

class _SuperAdminChangePasswordDialog extends StatefulWidget {
  const _SuperAdminChangePasswordDialog({required this.database});
  final FirebaseFirestore database;

  @override
  State<_SuperAdminChangePasswordDialog> createState() =>
      _SuperAdminChangePasswordDialogState();
}

class _SuperAdminChangePasswordDialogState
    extends State<_SuperAdminChangePasswordDialog> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _error;
  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _newPassword.addListener(_passwordChanged);
  }

  void _passwordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newPassword.removeListener(_passwordChanged);
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newPassword = _newPassword.text;
    if (_currentPassword.text.isEmpty ||
        newPassword.isEmpty ||
        _confirmPassword.text.isEmpty) {
      setState(() => _error = 'Please complete all password fields.');
      return;
    }
    if (!PasswordStrength(newPassword).isAcceptable) {
      setState(
        () => _error =
            'Password is weak. Meet at least 3 of the 5 requirements to use a fair password.',
      );
      return;
    }
    if (newPassword == _currentPassword.text) {
      setState(
        () => _error = 'Choose a password different from your current one.',
      );
      return;
    }
    if (newPassword != _confirmPassword.text) {
      setState(() => _error = 'New password and confirmation do not match.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await SuperAdmin.verifyPassword(
        _currentPassword.text,
        preferences: prefs,
        database: widget.database,
      )) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = 'The current password is incorrect.';
          });
        }
        return;
      }

      await SuperAdmin.updatePassword(
        newPassword,
        preferences: prefs,
        database: widget.database,
        currentPassword: _currentPassword.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to update password: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .82;
    return PopScope(
      canPop: !_saving,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Change Password',
                  style: TextStyle(
                    color: Color(0xFF9D174D),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                PasswordEntryField(
                  controller: _currentPassword,
                  label: 'Current Password',
                  obscureText: _obscureCurrent,
                  onToggle: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                PasswordEntryField(
                  controller: _newPassword,
                  label: 'New Password',
                  obscureText: _obscureNew,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  enabled: !_saving,
                ),
                PasswordStrengthChecklist(password: _newPassword.text),
                const SizedBox(height: 12),
                PasswordEntryField(
                  controller: _confirmPassword,
                  label: 'Confirm New Password',
                  obscureText: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  enabled: !_saving,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF9D174D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(_saving ? 'Saving…' : 'Save Password'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
