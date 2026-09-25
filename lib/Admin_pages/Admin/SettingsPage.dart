import 'dart:convert';
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
  String _adminId = 'ADM-0001';

  @override
  void initState() {
    super.initState();
    _loadAdminId();
  }

  Future<void> _loadAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAdminId = prefs.getString('adminId')?.trim();
    if (!mounted || savedAdminId == null || savedAdminId.isEmpty) return;
    setState(() => _adminId = savedAdminId);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F0F8),
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
              backgroundColor: const Color(0xFFD63384),
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
                            Color(0xFFAD1457),
                            Color(0xFFE91E8C),
                            Color(0xFFF48FB1),
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
                          color: const Color(0xFFF5F0F8),
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
                                FirebaseAuth.instance.currentUser?.uid != null
                                ? FirebaseFirestore.instance
                                      .collection('staff_requests')
                                      .doc(
                                        FirebaseAuth.instance.currentUser!.uid,
                                      )
                                      .snapshots()
                                : Stream<
                                    DocumentSnapshot<Map<String, dynamic>>
                                  >.empty(),
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
                                        adminId,
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
                    onTap: () => _showAccountInformation(context, null),
                  ),

                  const SizedBox(height: 6),

                  _sectionLabel("Transaction settings"),
                  _settingItem(
                    icon: Icons.discount_rounded,
                    title: "Discount Control",
                    subtitle: "Manage discount permissions",
                    iconColor: const Color(0xFFFF6F00),
                    iconBg: const Color(0xFFFFF8E1),
                    onTap: _showDiscountSettings,
                  ),
                  _settingItem(
                    icon: Icons.payments_rounded,
                    title: "Payment Settings",
                    subtitle: "Configure payment and cash drawer options",
                    iconColor: const Color(0xFF3949AB),
                    iconBg: const Color(0xFFE8EAF6),
                    onTap: _showPaymentSettings,
                  ),

                  const SizedBox(height: 6),

                  _sectionLabel("Access control"),
                  _settingItem(
                    icon: Icons.verified_user_rounded,
                    title: "Security and Approval",
                    subtitle: "Manage access and approvals",
                    iconColor: const Color(0xFF00897B),
                    iconBg: const Color(0xFFE0F2F1),
                    onTap: _showApprovalSettings,
                  ),

                  const SizedBox(height: 6),

                  _sectionLabel("System settings"),
                  _settingItem(
                    icon: Icons.info_rounded,
                    title: "About App",
                    subtitle: "Version & licenses",
                    iconColor: const Color(0xFF1E88E5),
                    iconBg: const Color(0xFFE3F2FD),
                    onTap: () => _showInfoDialog(
                      context,
                      'About App',
                      'Sales Tracker v1.0.0\nInventory, sales, staff allocation, notifications, coffee menu, and reports.',
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
                      "Sales Tracker  v1.0.0",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

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
    if (url.startsWith('data:image/')) {
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
                color: const Color(0xFFAD1457),
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
      if (mounted) setState(() => _isUploadingProfilePhoto = false);
    }
  }

  Future<String> _uploadProfilePhoto(Uint8List bytes, String uid) async {
    try {
      final imageRef = FirebaseStorage.instance.ref().child(
        'admin_profiles/$uid-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final upload = await imageRef
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 12));
      return upload.ref.getDownloadURL().timeout(const Duration(seconds: 12));
    } catch (_) {
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      if (dataUrl.length > 700000) rethrow;
      return dataUrl;
    }
  }

  Future<void> _showAccountInformation(
    BuildContext context,
    Map<String, dynamic>? incomingData,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var data = <String, dynamic>{...?incomingData};
    if (uid != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get();
      data = {...data, ...?snapshot.data()};
    }
    if (!mounted) return;

    final currentUser = FirebaseAuth.instance.currentUser;
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

    await showDialog<void>(
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
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: middleName,
                  decoration: const InputDecoration(labelText: 'Middle name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Gmail / email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: age,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Age'),
                ),
                const SizedBox(height: 10),
                TextField(
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
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () async {
                        if (uid == null) return;
                        await FirebaseFirestore.instance
                            .collection('staff_requests')
                            .doc(uid)
                            .set({
                              'firstName': firstName.text.trim(),
                              'middleName': middleName.text.trim(),
                              'lastName': lastName.text.trim(),
                              'email': email.text.trim(),
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
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          _showStyledSnackBar('Account information updated.');
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

  Widget _buildAccountInformationSummary() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const Text('No account information saved yet.');
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = _getFullName(data);
        final email = data['email']?.toString().trim() ?? '';
        final age = data['age']?.toString().trim() ?? '';
        final address = data['address']?.toString().trim() ?? '';
        final values = <String>[
          if (name != 'Admin User') name,
          if (email.isNotEmpty) email,
          if (age.isNotEmpty) 'Age: $age',
          if (address.isNotEmpty) address,
        ];

        return Text(
          values.isEmpty
              ? 'No account information saved yet.'
              : values.join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

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

  static Future<void> _showChangePassword(BuildContext context) async {
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
              if (user?.email == null) {
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
                activeThumbColor: const Color(0xFFE91E63),
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

  DocumentReference<Map<String, dynamic>>? get _settingsReference {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    return FirebaseFirestore.instance.collection('admin_settings').doc(uid);
  }

  Future<Map<String, dynamic>> _readAdminSettings() async {
    final reference = _settingsReference;
    if (reference == null) return {};
    final snapshot = await reference.get();
    return snapshot.data() ?? {};
  }

  Future<void> _showDiscountSettings() async {
    final data = await _readAdminSettings();
    if (!mounted) return;
    final discounts = ((data['discounts'] as List<dynamic>?) ?? [])
        .whereType<Map>()
        .map(
          (item) => <String, dynamic>{
            'name': item['name']?.toString() ?? 'Discount',
            'percent': (item['percent'] as num?)?.toDouble() ?? 0,
          },
        )
        .toList();
    if (discounts.isEmpty) {
      discounts.addAll([
        {'name': 'Senior', 'percent': 20.0},
        {'name': 'PWD', 'percent': 20.0},
      ]);
    }
    var enabled = data['discountsEnabled'] as bool? ?? true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Discount Control'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable discount'),
                    subtitle: const Text('Allow discounts during staff sales'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  const Divider(),
                  ...discounts.asMap().entries.map((entry) {
                    final discount = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(discount['name'].toString()),
                      subtitle: Text('${discount['percent']}% discount'),
                      trailing: IconButton(
                        tooltip: 'Remove discount',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () =>
                            setDialogState(() => discounts.removeAt(entry.key)),
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await _showAddDiscountDialog(context);
                        if (result != null) {
                          setDialogState(() => discounts.add(result));
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add discount type'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _settingsReference?.set({
                  'discountsEnabled': enabled,
                  'discounts': discounts,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) _showStyledSnackBar('Discount settings saved.');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showAddDiscountDialog(
    BuildContext parentContext,
  ) async {
    final nameController = TextEditingController();
    final percentController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: parentContext,
      builder: (context) => AlertDialog(
        title: const Text('Add discount type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Discount name'),
            ),
            TextField(
              controller: percentController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Percent'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final percent = double.tryParse(percentController.text.trim());
              if (name.isEmpty ||
                  percent == null ||
                  percent <= 0 ||
                  percent > 100) {
                return;
              }
              Navigator.pop(context, {'name': name, 'percent': percent});
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameController.dispose();
    percentController.dispose();
    return result;
  }

  Future<void> _showPaymentSettings() async {
    final data = await _readAdminSettings();
    if (!mounted) return;
    final methods = ((data['paymentMethods'] as List<dynamic>?) ?? [])
        .map((method) => method.toString())
        .where((method) => method.trim().isNotEmpty)
        .toList();
    if (methods.isEmpty) methods.addAll(['Cash', 'GCash', 'Maya']);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Payment Settings'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Payment methods available in staff sales.'),
                ),
                const SizedBox(height: 10),
                ...methods.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(entry.value),
                    trailing: IconButton(
                      tooltip: 'Remove payment method',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () =>
                          setDialogState(() => methods.removeAt(entry.key)),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final controller = TextEditingController();
                    final method = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Add payment method'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Method name',
                            hintText: 'Cards',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(context, controller.text.trim()),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    );
                    controller.dispose();
                    if (method != null && method.isNotEmpty) {
                      setDialogState(() => methods.add(method));
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add payment method'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _settingsReference?.set({
                  'paymentMethods': methods,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) _showStyledSnackBar('Payment settings saved.');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showApprovalSettings() async {
    final data = await _readAdminSettings();
    if (!mounted) return;
    var voidApproval = data['voidApproval'] as bool? ?? true;
    var refundApproval = data['refundApproval'] as bool? ?? true;
    var discountApproval = data['discountApproval'] as bool? ?? false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Security and Approval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Void approval'),
                subtitle: const Text('Require approval before voiding a sale'),
                value: voidApproval,
                onChanged: (value) =>
                    setDialogState(() => voidApproval = value),
              ),
              SwitchListTile(
                title: const Text('Refund approval'),
                subtitle: const Text(
                  'Require approval before processing refunds',
                ),
                value: refundApproval,
                onChanged: (value) =>
                    setDialogState(() => refundApproval = value),
              ),
              SwitchListTile(
                title: const Text('Discount approval'),
                subtitle: const Text('Require approval for staff discounts'),
                value: discountApproval,
                onChanged: (value) =>
                    setDialogState(() => discountApproval = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _settingsReference?.set({
                  'voidApproval': voidApproval,
                  'refundApproval': refundApproval,
                  'discountApproval': discountApproval,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) _showStyledSnackBar('Approval settings saved.');
              },
              child: const Text('Save'),
            ),
          ],
        ),
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
                    color: const Color(0xFFF5F0F8),
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
              colors: [Color(0xFFAD1457), Color(0xFFE91E8C), Color(0xFFF06292)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E8C).withOpacity(0.38),
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
                    colors: [Color(0xFFE91E8C), Color(0xFFF06292)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE91E8C).withOpacity(0.35),
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
                          color: const Color(0xFFF5F0F8),
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
                            colors: [Color(0xFFAD1457), Color(0xFFE91E8C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE91E8C).withOpacity(0.35),
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
