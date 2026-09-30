import 'package:crypto/crypto.dart';
import '../../widgets/transaction_settings_dialog.dart';
import '../../services/catalog_image_service.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import '../../services/public_item_id.dart';
import 'dart:convert';
import '../../widgets/backup_restore_dialog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/Login/Login/Login.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isUploadingProfilePhoto = false;
  String? _lastProfilePhotoUrl;
  Uint8List? _profilePreview;
  String _adminId = 'ADM-001';
  String _profileId = 'ADM-001';
  bool _profileReady = false;

  @override
  void initState() {
    super.initState();
    _loadAdminId();
  }

  Future<void> _loadAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAdminId = prefs.getString('adminId')?.trim() ?? 'ADM-001';
    if (!mounted) return;
    setState(() {
      _profileReady = true;
      _adminId = savedAdminId;
      _profileId = prefs.getString('lastUserId') == 'emergency-admin'
          ? savedAdminId
          : FirebaseAuth.instance.currentUser?.uid ?? savedAdminId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_profileReady)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
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
                            stream: FirebaseFirestore.instance
                                .collection('staff_requests')
                                .doc(
                                  FirebaseAuth.instance.currentUser?.uid ??
                                      _adminId,
                                )
                                .snapshots(),
                            builder: (context, snapshot) {
                              final data = snapshot.data?.data();
                              final fullName = _getFullName(data);
                              final email =
                                  data?['email']?.toString() ?? 'No email';
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
                                  ? 'Administrator'
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
                      builder: (_) =>
                          const TransactionSettingsDialog(kind: 'permissions'),
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
                  _settingItem(
                    icon: Icons.lock_rounded,
                    title: "Change Password",
                    subtitle: "Update your credentials",
                    iconColor: const Color(0xFF8E24AA),
                    iconBg: const Color(0xFFF3E5F5),
                    onTap: () => _showChangePassword(context),
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
                  _LogoutButton(),
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
      if (mounted) setState(() => _profilePreview = bytes);
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
      if (FirebaseAuth.instance.currentUser?.uid == _profileId)
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(
          photoUrl.startsWith('data:image/') ? null : photoUrl,
        );
      if (mounted) _showStyledSnackBar('Profile photo updated successfully.');
    } catch (_) {
      if (mounted) {
        _showStyledSnackBar(
          'Unable to upload profile photo. Please try another image.',
          isError: true,
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isUploadingProfilePhoto = false;
          _profilePreview = null;
        });
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
    var data = <String, dynamic>{...?incomingData};
    if (uid != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get();
      data = {...data, ...?snapshot.data()};
    }
    if (!mounted) return;

    final authUser = FirebaseAuth.instance.currentUser;
    final currentUser = authUser?.uid == _profileId ? authUser : null;
    final firstName = TextEditingController(
      text: data['firstName']?.toString() ?? '',
    );
    final middleName = TextEditingController(
      text: data['middleName']?.toString() ?? '',
    );
    final lastName = TextEditingController(
      text: data['lastName']?.toString() ?? '',
    );
    final email = TextEditingController(
      text: data['email']?.toString() ?? currentUser?.email ?? '',
    );
    final age = TextEditingController(text: data['age']?.toString() ?? '');
    final address = TextEditingController(
      text: data['address']?.toString() ?? '',
    );

    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Account information',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                TextField(
                  readOnly: readOnly,
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  readOnly: readOnly,
                  controller: middleName,
                  decoration: const InputDecoration(labelText: 'Middle name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  readOnly: readOnly,
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  readOnly: readOnly,
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Gmail / email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  readOnly: readOnly,
                  controller: age,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Age'),
                ),
                const SizedBox(height: 10),
                TextField(
                  readOnly: readOnly,
                  controller: address,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(readOnly ? 'Close' : 'Cancel'),
                    ),
                    const SizedBox(width: 10),
                    if (!readOnly)
                      FilledButton(
                        onPressed: () async {
                          if (firstName.text.trim().isEmpty) {
                            _showStyledSnackBar(
                              'Enter your first name.',
                              isError: true,
                            );
                            return;
                          }
                          try {
                            await FirebaseFirestore.instance
                                .collection('staff_requests')
                                .doc(uid)
                                .set({
                                  'firstName': firstName.text.trim(),
                                  'middleName': middleName.text.trim(),
                                  'lastName': lastName.text.trim(),
                                  'email': email.text.trim(),
                                  if (currentUser?.email != null)
                                    'authEmail': currentUser!.email,
                                  'age': age.text.trim(),
                                  'address': address.text.trim(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                }, SetOptions(merge: true));
                            final updatedName = [
                              firstName.text.trim(),
                              middleName.text.trim(),
                              lastName.text.trim(),
                            ].where((part) => part.isNotEmpty).join(' ');
                            if (updatedName.isNotEmpty) {
                              await currentUser?.updateDisplayName(updatedName);
                            }
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext);
                            if (mounted) {
                              _showStyledSnackBar(
                                'Account information updated.',
                              );
                            }
                          } catch (error) {
                            if (mounted)
                              _showStyledSnackBar(
                                'Unable to save account information: $error',
                                isError: true,
                              );
                          }
                        },
                        child: const Text('Save'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    firstName.dispose();
    middleName.dispose();
    lastName.dispose();
    email.dispose();
    age.dispose();
    address.dispose();
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
    if (data == null) return 'Admin User';
    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final middleName = (data['middleName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';
    final fullName = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');
    return fullName.isEmpty ? 'Admin User' : fullName;
  }

  Future<void> _showChangePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (next.text.length < 6 || next.text != confirm.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Check the new password.')),
                );
                return;
              }
              if (user?.email == null || user?.uid != _profileId) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This admin account has no Firebase email.'),
                  ),
                );
                return;
              }
              try {
                final credential = EmailAuthProvider.credential(
                  email: user!.email!,
                  password: current.text,
                );
                await user.reauthenticateWithCredential(credential);
                await user.updatePassword(next.text);
                final prefs = await SharedPreferences.getInstance();
                final adminId = prefs.getString('adminId') ?? 'ADM-001';
                await FirebaseFirestore.instance
                    .collection('staff_requests')
                    .doc(user.uid)
                    .set({
                      'credentialsChangedAt': FieldValue.serverTimestamp(),
                      'adminId': adminId,
                      'role': 'admin',
                      'authEmail': user.email,
                    }, SetOptions(merge: true));
                final username = prefs.getString('offlineLogin.username');
                if (username != null)
                  await prefs.setString(
                    'offlineLogin.passwordHash',
                    sha256
                        .convert(utf8.encode('$username:${next.text}'))
                        .toString(),
                  );
                if (context.mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated.')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Unable to update password: $e')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
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
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('lastRole');
                        await prefs.remove('lastUserId');
                        await prefs.remove('adminId');
                        await FirebaseAuth.instance.signOut();
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
