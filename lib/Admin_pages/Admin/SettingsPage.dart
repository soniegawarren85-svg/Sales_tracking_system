import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/Login/Login/Login.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseAuth.instance.currentUser?.uid != null
                            ? FirebaseFirestore.instance
                                .collection('staff_requests')
                                .doc(FirebaseAuth.instance.currentUser!.uid)
                                .snapshots()
                            : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty(),
                        builder: (context, snapshot) {
                          final data = snapshot.data?.data();
                          final fullName = _getFullName(data);
                          final email = data?['email']?.toString() ?? 'No email';
                          final role = data?['role']?.toString().trim().toLowerCase() ?? 'admin';
                          final roleLabel = role == 'admin' ? 'Administrator' : 'Staff';

                          return Row(
                            children: [
                              /// Avatar with Ring
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
                                    )
                                  ],
                                ),
                                child: const CircleAvatar(
                                  radius: 34,
                                  backgroundColor: Color(0xFFAD1457),
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 38,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        color: Colors.white.withOpacity(0.85),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.4),
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
                              Container(
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

                  /// --- SECTION: Account ---
                  _sectionLabel("Account"),
                  _settingItem(
                    icon: Icons.lock_rounded,
                    title: "Change Password",
                    subtitle: "Update your credentials",
                    iconColor: const Color(0xFF8E24AA),
                    iconBg: const Color(0xFFF3E5F5),
                    onTap: () => _showChangePassword(context),
                  ),
                  _settingItem(
                    icon: Icons.notifications_rounded,
                    title: "Notifications",
                    subtitle: "Manage alerts & sounds",
                    iconColor: const Color(0xFFE91E63),
                    iconBg: const Color(0xFFFCE4EC),
                    onTap: () => _showNotificationSettings(context),
                  ),
                  _settingItem(
                    icon: Icons.dark_mode_rounded,
                    title: "Dark Mode",
                    subtitle: "Toggle dark appearance",
                    iconColor: const Color(0xFF3949AB),
                    iconBg: const Color(0xFFE8EAF6),
                    onTap: () => _showDarkMode(context),
                  ),

                  const SizedBox(height: 6),

                  /// --- SECTION: Privacy ---
                  _sectionLabel("Privacy & Safety"),
                  _settingItem(
                    icon: Icons.security_rounded,
                    title: "Privacy & Security",
                    subtitle: "Data and permissions",
                    iconColor: const Color(0xFF00897B),
                    iconBg: const Color(0xFFE0F2F1),
                    onTap: () => _showInfoDialog(
                      context,
                      'Privacy & Security',
                      'Your account data is stored in Firebase. Keep your login details private and sign out on shared devices.',
                    ),
                  ),

                  const SizedBox(height: 6),

                  /// --- SECTION: Support ---
                  _sectionLabel("Support"),
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
                    icon: Icons.help_rounded,
                    title: "Help & Support",
                    subtitle: "FAQs and contact us",
                    iconColor: const Color(0xFFFF6F00),
                    iconBg: const Color(0xFFFFF8E1),
                    onTap: () => _showInfoDialog(
                      context,
                      'Help & Support',
                      'For login, password, inventory, cash drawer, or order issues, contact the system administrator.',
                    ),
                  ),

                  const SizedBox(height: 28),

                  /// ===== LOGOUT BUTTON =====
                  _LogoutButton(),

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

  String _getFullName(Map<String, dynamic>? data) {
    if (data == null) return 'Admin User';
    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final middleName = (data['middleName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';
    final fullName = [firstName, middleName, lastName]
        .where((part) => part.isNotEmpty)
        .join(' ');
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
                activeColor: const Color(0xFFE91E63),
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
        builder: (context, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
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
                              builder: (_) => const LoginScreen()),
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
