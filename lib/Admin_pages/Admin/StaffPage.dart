import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _headerAnimController;
  late AnimationController _buttonAnimController;
  late AnimationController _adminPanelController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _buttonScale;
  late Animation<double> _buttonFade;
  late Animation<Offset> _adminPanelSlide;
  late Animation<double> _adminPanelFade;

  bool _showAdminPanel = false;
  bool _isCreatingStaff = false;
  final _createStaffFormKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ─── STREAMS ──────────────────────────────────────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> get _staffStream =>
      FirebaseFirestore.instance.collection('staff_requests').snapshots();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Header animation
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _headerFade =
        CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.18),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOutCubic));

    // Button animation
    _buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _buttonScale = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _buttonAnimController, curve: Curves.elasticOut));
    _buttonFade =
        CurvedAnimation(parent: _buttonAnimController, curve: Curves.easeOut);

    // Admin panel slide animation
    _adminPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _adminPanelSlide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _adminPanelController, curve: Curves.easeOutCubic));
    _adminPanelFade =
        CurvedAnimation(parent: _adminPanelController, curve: Curves.easeOut);

    _headerAnimController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _buttonAnimController.forward();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _headerAnimController.dispose();
    _buttonAnimController.dispose();
    _adminPanelController.dispose();
    super.dispose();
  }

  void _toggleAdminPanel() {
    setState(() {
      _showAdminPanel = !_showAdminPanel;
    });
    if (_showAdminPanel) {
      _adminPanelController.forward();
    } else {
      _adminPanelController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F9),
      body: Stack(
        children: [
          // ── Background decorative blobs ──
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF48FB1).withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFCDD2).withOpacity(0.15),
              ),
            ),
          ),

          // ── Main Staff Content ──
          Column(
            children: [
              SlideTransition(
                position: _headerSlide,
                child: FadeTransition(
                  opacity: _headerFade,
                  child: _buildHeader(context),
                ),
              ),
              const SizedBox(height: 16),
              FadeTransition(
                opacity: _buttonFade,
                child: ScaleTransition(
                  scale: _buttonScale,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildStaffManagementButton(context),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Column(
                  children: [
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _staffStream,
                      builder: (context, snapshot) {
                        final docs = snapshot.data?.docs ?? [];
                        final pendingCount = docs
                            .map((doc) => StaffApplicant.fromDoc(doc))
                            .where(
                              (a) =>
                                  a.status == 'pending' &&
                                  a.role.toLowerCase() == 'staff',
                            )
                            .length;
                        return _buildTabBar(pendingCount: pendingCount);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPendingTab(const []),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _staffStream,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFF48FB1),
                                    strokeWidth: 2.5,
                                  ),
                                );
                              }

                              final docs = snapshot.data?.docs ?? [];
                              final accepted = docs
                                  .map((doc) => StaffApplicant.fromDoc(doc))
                                  .where(
                                    (a) =>
                                        a.status == 'accepted' &&
                                        a.role.toLowerCase() == 'staff',
                                  )
                                  .toList();
                              return _buildAcceptedTab(accepted);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Staff Panel Overlay (slide from right) ──
          if (_showAdminPanel)
            SlideTransition(
              position: _adminPanelSlide,
              child: FadeTransition(
                opacity: _adminPanelFade,
                child: _buildAdminPanel(context),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ─── ADMIN PANEL (Full overlay inside same page) ────────
  // ═══════════════════════════════════════════════════════════
  Widget _buildAdminPanel(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F0FF),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _staffStream,
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final staff = docs
              .map((d) => AdminModel.fromDoc(d))
              .where((member) => member.isValidStaff)
              .toList();
          final visibleStaff = staff
              .where((member) => member.status == 'accepted')
              .toList();
          final deactivatedStaff = staff
              .where((member) => member.status == 'deactivated')
              .toList();

          final totalStaff = visibleStaff.length;
          final activeStaff = visibleStaff
              .where((a) => a.status == 'accepted' && !a.isInactiveByLogin)
              .length;
          const pendingStaff = 0;
          final inactiveStaff = visibleStaff
              .where((a) => a.status == 'accepted' && a.isInactiveByLogin)
              .length;

          return Stack(
            children: [
              // Purple blobs background
              Positioned(
                top: -80,
                right: -60,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7C3AED).withOpacity(0.07),
                  ),
                ),
              ),
              Positioned(
                bottom: 100,
                left: -70,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBC2B8A).withOpacity(0.06),
                  ),
                ),
              ),

              Column(
                children: [
                  _buildAdminHeader(context),
                  const SizedBox(height: 18),

                  // Stats row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildStatsRow(
                      total: totalStaff,
                      active: activeStaff,
                      pending: pendingStaff,
                      deactivated: inactiveStaff,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildDeactivatedStaffButton(deactivatedStaff),
                  ),
                  const SizedBox(height: 18),

                  // Section label
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6A11CB), Color(0xFFBC2B8A)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'All Staff',
                          style: TextStyle(
                            color: Color(0xFF2D1B5E),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Admin list
                  Expanded(
                    child: visibleStaff.isEmpty &&
                            snapshot.connectionState != ConnectionState.waiting
                        ? _buildAdminEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: visibleStaff.length,
                            itemBuilder: (context, index) {
                              return _AnimatedAdminCard(
                                index: index,
                                admin: visibleStaff[index],
                                isInactiveByLogin:
                                    visibleStaff[index].isInactiveByLogin,
                                onDeactivate: () =>
                                    _updateAdminStatus(visibleStaff[index], 'deactivated'),
                                onActivate: () =>
                                    _updateAdminStatus(visibleStaff[index], 'accepted'),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdminHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A11CB), Color(0xFF9C27B0), Color(0xFFBC2B8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.38),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.09),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              right: 70,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 18,
              left: -35,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(22, topPadding + 16, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Back button — closes admin panel
                  GestureDetector(
                    onTap: _toggleAdminPanel,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.30),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'STAFF ACCESS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Staff Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Monitor active and inactive staff accounts',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow({
    required int total,
    required int active,
    required int pending,
    required int deactivated,
  }) {
    return Row(
      children: [
        _buildStatCard(
          label: 'Total',
          count: total,
          colors: [const Color(0xFF6A11CB), const Color(0xFFBC2B8A)],
          icon: Icons.groups_rounded,
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          label: 'Active',
          count: active,
          colors: [const Color(0xFF11998E), const Color(0xFF38EF7D)],
          icon: Icons.verified_user_rounded,
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          label: 'Create',
          count: pending,
          colors: [const Color(0xFFF7971E), const Color(0xFFFFD200)],
          icon: Icons.pending_rounded,
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          label: 'Inactive',
          count: deactivated,
          colors: [const Color(0xFFB71C1C), const Color(0xFFEF5350)],
          icon: Icons.block_rounded,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required int count,
    required List<Color> colors,
    required IconData icon,
  }) {
    return Expanded(
      child: _AnimatedCountCard(
        label: label,
        count: count,
        colors: colors,
        icon: icon,
      ),
    );
  }

  Widget _buildDeactivatedStaffButton(List<AdminModel> deactivatedStaff) {
    return InkWell(
      onTap: deactivatedStaff.isEmpty
          ? null
          : () => _showDeactivatedStaffSheet(deactivatedStaff),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1C8FF), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restore_rounded,
                color: Color(0xFFEF5350),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deactivated Staff',
                    style: TextStyle(
                      color: Color(0xFF2D1B5E),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'View and restore inactive staff',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${deactivatedStaff.length}',
                style: const TextStyle(
                  color: Color(0xFFEF5350),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeactivatedStaffSheet(List<AdminModel> deactivatedStaff) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFDF6F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1C8FF),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(
                    Icons.restore_rounded,
                    color: Color(0xFF7C3AED),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Deactivated Staff',
                      style: TextStyle(
                        color: Color(0xFF2D1B5E),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF2D1B5E),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: deactivatedStaff.length,
                  itemBuilder: (context, index) {
                    final staff = deactivatedStaff[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED).withOpacity(0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF9C27B0),
                            child: Text(
                              staff.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${staff.firstName} ${staff.lastName}',
                                  style: const TextStyle(
                                    color: Color(0xFF2D1B5E),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (staff.email.isNotEmpty)
                                  Text(
                                    staff.email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await _updateAdminStatus(staff, 'accepted');
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: const Text('Restore'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF11998E),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6A11CB).withOpacity(0.10),
                  const Color(0xFFBC2B8A).withOpacity(0.15),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_2_outlined,
              size: 55,
              color: const Color(0xFF7C3AED).withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'No Staff Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D1B5E),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Staff members\nwill be listed here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAdminStatus(AdminModel admin, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(admin.id)
          .update({'status': newStatus});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              newStatus == 'accepted' ? 'Staff activated.' : 'Staff deactivated.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF7C3AED),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update staff status.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ─── STAFF PAGE WIDGETS ─────────────────────────────────
  // ═══════════════════════════════════════════════════════════

  Widget _buildStaffManagementButton(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _staffStream,
      builder: (context, snapshot) {
        final staffCount = snapshot.data?.docs
                .map((d) => AdminModel.fromDoc(d))
                .where((member) =>
                    member.isValidStaff &&
                    member.status == 'accepted')
                .length ??
            0;

        return GestureDetector(
          onTap: _toggleAdminPanel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF6A11CB),
                  Color(0xFFBC2B8A),
                  Color(0xFFFF6B9D)
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9C27B0).withOpacity(0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.30),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.groups_2_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Staff Management',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'View active and inactive staff accounts',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.35), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF69FF97),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$staffCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedRotation(
                      turns: _showAdminPanel ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF80AB), Color(0xFFF06292), Color(0xFFE91E8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE91E63).withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              right: 60,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Positioned(
              bottom: 15,
              left: -35,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(22, topPadding + 16, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'MANAGEMENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Staff Section',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create and manage staff accounts',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.80),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar({required int pendingCount}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFF48FB1).withOpacity(0.10),
          borderRadius: BorderRadius.circular(15),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5F96), Color(0xFFE91E8C)],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E63).withOpacity(0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFF06292),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  const SizedBox(width: 6),
                  const Text('Create'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16),
                  const SizedBox(width: 6),
                  const Text('Staff Accounts'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTab(List<StaffApplicant> pending) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: _buildCreateStaffForm(),
    );
  }

  Widget _buildCreateStaffForm() {
    return Form(
      key: _createStaffFormKey,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Staff Create Account',
              style: TextStyle(
                color: Color(0xFF3D2C2C),
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Fill up the staff information and create the account directly.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _buildCreateField(_firstNameController, 'First Name'),
            _buildCreateField(
              _middleNameController,
              'Middle Name',
              requiredField: false,
            ),
            _buildCreateField(_lastNameController, 'Last Name'),
            _buildCreateField(
              _ageController,
              'Age',
              keyboardType: TextInputType.number,
              validator: (value) {
                final age = int.tryParse(value?.trim() ?? '');
                if (age == null || age < 18 || age > 50) {
                  return 'Enter a valid age from 18 to 50.';
                }
                return null;
              },
            ),
            _buildCreateField(
              _phoneController,
              'Phone Number',
              keyboardType: TextInputType.phone,
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (!RegExp(r'^09\d{9}$').hasMatch(phone)) {
                  return 'Phone must start with 09 and contain 11 digits.';
                }
                return null;
              },
            ),
            _buildCreateField(_addressController, 'Address', maxLines: 2),
            _buildCreateField(
              _emailController,
              'Email',
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$')
                    .hasMatch(email)) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            _buildCreateField(
              _passwordController,
              'Password',
              obscureText: true,
              validator: (value) {
                final password = value?.trim() ?? '';
                if (!RegExp(r'^(?=.*[0-9])(?=.*[!@#\$%^&*]).{8,}$')
                    .hasMatch(password)) {
                  return 'Use 8+ chars with a number and special character.';
                }
                return null;
              },
            ),
            _buildCreateField(
              _confirmPasswordController,
              'Confirm Password',
              obscureText: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isCreatingStaff ? null : _createStaffAccount,
                icon: _isCreatingStaff
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  _isCreatingStaff ? 'Creating...' : 'Create Account',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E8C),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateField(
    TextEditingController controller,
    String label, {
    bool requiredField = true,
    bool obscureText = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        keyboardType: keyboardType,
        validator: validator ??
            (value) {
              if (requiredField && (value?.trim().isEmpty ?? true)) {
                return '$label is required.';
              }
              return null;
            },
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFFFF8FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFF8BBD0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFF8BBD0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE91E8C), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildAcceptedTab(List<StaffApplicant> accepted) {
    if (accepted.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No Staff Accounts',
        subtitle: 'Created staff accounts\nwill be shown here.',
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 650;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: accepted.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isCompact ? 1 : 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: isCompact ? 0 : 14,
        childAspectRatio: isCompact ? 1.05 : 0.88,
      ),
      itemBuilder: (context, index) {
        return _AnimatedListItem(
          index: index,
          child: _buildAcceptedCard(accepted[index], index),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF48FB1).withOpacity(0.12),
                  const Color(0xFFFFCDD2).withOpacity(0.22),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 52,
              color: const Color(0xFFF48FB1).withOpacity(0.50),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF5D3A3A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicantCard(StaffApplicant applicant, int index) {
    final List<List<Color>> gradients = [
      [const Color(0xFFF48FB1), const Color(0xFFE91E8C)],
      [const Color(0xFFFFB3C6), const Color(0xFFF06292)],
      [const Color(0xFFCE93D8), const Color(0xFFAB47BC)],
      [const Color(0xFF80DEEA), const Color(0xFF26C6DA)],
    ];
    final gradient = gradients[index % gradients.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: gradient[0].withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      applicant.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${applicant.firstName} ${applicant.lastName}',
                        style: const TextStyle(
                          color: Color(0xFF3D2C2C),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        applicant.role.isEmpty
                            ? 'No role specified'
                            : applicant.role,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.orange.shade200, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Waiting for approval',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async =>
                        await _updateApplicantStatus(applicant, 'rejected'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F3),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close_rounded,
                              color: Colors.red.shade400, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            'Decline',
                            style: TextStyle(
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      await _updateApplicantStatus(applicant, 'accepted');
                      _tabController.animateTo(1);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradient),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: gradient[0].withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded,
                              color: Colors.white, size: 16),
                          SizedBox(width: 5),
                          Text(
                            'Accept',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedCard(StaffApplicant applicant, int index) {
    final List<List<Color>> gradients = [
      [const Color(0xFFF48FB1), const Color(0xFFE91E8C)],
      [const Color(0xFFFFB3C6), const Color(0xFFF06292)],
      [const Color(0xFFCE93D8), const Color(0xFFAB47BC)],
      [const Color(0xFF80DEEA), const Color(0xFF26C6DA)],
    ];
    final gradient = gradients[index % gradients.length];

    return GestureDetector(
      onTap: () => _showStaffDetails(applicant, index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: gradient[0].withOpacity(0.40),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  applicant.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${applicant.firstName} ${applicant.middleName.isNotEmpty ? '${applicant.middleName} ' : ''}${applicant.lastName}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF3D2C2C),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (applicant.staffId.isNotEmpty)
              Text(
                'ID: ${applicant.staffId}',
                style: const TextStyle(color: Color(0xFF7A6D6D), fontSize: 11),
              ),
            const SizedBox(height: 5),
            if (applicant.role.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: gradient[0].withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  applicant.role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: gradient[1],
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    gradient[0].withOpacity(0.10),
                    gradient[1].withOpacity(0.15)
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.remove_red_eye_outlined,
                      size: 13, color: gradient[1]),
                  const SizedBox(width: 4),
                  Text(
                    'View Profile',
                    style: TextStyle(
                      color: gradient[1],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateApplicantStatus(
      StaffApplicant applicant, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(applicant.id)
          .update({'status': newStatus});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'accepted'
                ? 'Applicant accepted.'
                : newStatus == 'deactivated'
                    ? 'Applicant deactivated.'
                    : 'Applicant declined.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFE91E63),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update applicant status.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFC2105C),
        ),
      );
    }
  }

  String _pad(int value, [int width = 4]) =>
      value.toString().padLeft(width, '0');

  Future<String> _generateStaffId() async {
    final counterDocRef = FirebaseFirestore.instance
        .collection('counters')
        .doc('staff');
    final count = await FirebaseFirestore.instance.runTransaction<int>((
      transaction,
    ) async {
      final snapshot = await transaction.get(counterDocRef);
      final current = snapshot.exists
          ? (snapshot.data()?['count'] as int? ?? 0) + 1
          : 1;
      transaction.set(counterDocRef, {
        'count': current,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return current;
    });
    return 'STF-${_pad(count)}';
  }

  Future<void> _createStaffAccount() async {
    if (!mounted) return;
    if (!(_createStaffFormKey.currentState?.validate() ?? false)) return;
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    if (password != confirmPassword) {
      _showStaffCreateSnack('Passwords do not match.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isCreatingStaff = true);
    FirebaseApp? secondaryApp;
    UserCredential? createdCredential;
    try {
      final staffId = await _generateStaffId();
      secondaryApp = await Firebase.initializeApp(
        name: 'staffCreate${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      createdCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: password,
      );
      final uid = createdCredential.user?.uid;
      if (uid == null) throw Exception('Unable to create auth account.');

      await FirebaseFirestore.instance.collection('staff_requests').doc(uid).set({
        'email': _emailController.text.trim(),
        'role': 'staff',
        'firstName': _firstNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'status': 'accepted',
        'uid': uid,
        'userId': uid,
        'staffId': staffId,
        'username': staffId,
        'loginPassword': password,
        'mustChangePassword': false,
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await secondaryAuth.signOut();
      _clearCreateStaffForm();
      setState(() => _isCreatingStaff = false);
      if (!mounted) return;
      _tabController.animateTo(1);
      _showStaffCreateSnack('Staff account created: $staffId');
    } on FirebaseAuthException catch (e) {
      if (createdCredential?.user != null) {
        try {
          await createdCredential!.user!.delete();
        } catch (_) {}
      }
      final message = e.code == 'email-already-in-use'
          ? 'This email is already registered.'
          : e.message ?? 'Unable to create staff account.';
      _showStaffCreateSnack(message, isError: true);
    } catch (e) {
      _showStaffCreateSnack('Unable to create staff account: $e', isError: true);
    } finally {
      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isCreatingStaff = false);
    }
  }

  void _clearCreateStaffForm() {
    _firstNameController.clear();
    _middleNameController.clear();
    _lastNameController.clear();
    _ageController.clear();
    _phoneController.clear();
    _addressController.clear();
    _emailController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
  }

  void _showStaffCreateSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? const Color(0xFFC2105C) : const Color(0xFF4A7C59),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showStaffDetails(StaffApplicant applicant, int index) {
    final List<List<Color>> gradients = [
      [const Color(0xFFF48FB1), const Color(0xFFE91E8C)],
      [const Color(0xFFFFB3C6), const Color(0xFFF06292)],
      [const Color(0xFFCE93D8), const Color(0xFFAB47BC)],
      [const Color(0xFF80DEEA), const Color(0xFF26C6DA)],
    ];
    final gradient = gradients[index % gradients.length];

    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.50),
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, _, __) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: animation,
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8FA),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pink.withOpacity(0.18),
                      blurRadius: 35,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 30, 20, 26),
                          decoration:
                              BoxDecoration(gradient: LinearGradient(colors: gradient)),
                          child: Column(
                            children: [
                              Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.22),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.5),
                                    width: 2.5,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    applicant.initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                [
                                  applicant.firstName,
                                  applicant.middleName,
                                  applicant.lastName
                                ].where((s) => s.isNotEmpty).join(' '),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (applicant.role.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    applicant.role,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _buildDetailRow(
                                  icon: Icons.badge_outlined,
                                  label: 'Staff ID',
                                  value: applicant.staffId.isEmpty
                                      ? 'N/A'
                                      : applicant.staffId,
                                  gradient: gradient),
                              _buildDetailRow(
                                  icon: Icons.cake_outlined,
                                  label: 'Age',
                                  value: applicant.age.isEmpty
                                      ? 'N/A'
                                      : applicant.age,
                                  gradient: gradient),
                              _buildDetailRow(
                                  icon: Icons.phone_outlined,
                                  label: 'Phone',
                                  value: applicant.phone.isEmpty
                                      ? 'N/A'
                                      : applicant.phone,
                                  gradient: gradient),
                              _buildDetailRow(
                                  icon: Icons.mail_outline_rounded,
                                  label: 'Email',
                                  value: applicant.email.isEmpty
                                      ? 'N/A'
                                      : applicant.email,
                                  gradient: gradient),
                              _buildDetailRow(
                                  icon: Icons.location_on_outlined,
                                  label: 'Address',
                                  value: applicant.address.isEmpty
                                      ? 'N/A'
                                      : applicant.address,
                                  gradient: gradient),
                              const SizedBox(height: 8),
                              if (applicant.isAccepted)
                                GestureDetector(
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await _updateApplicantStatus(
                                        applicant, 'deactivated');
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC2105C),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFC2105C)
                                              .withOpacity(0.30),
                                          blurRadius: 12,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Deactivate Staff',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: gradient),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gradient[0].withOpacity(0.40),
                                        blurRadius: 12,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Close',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
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
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required List<Color> gradient,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFF48FB1).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradient[0].withOpacity(0.14),
                  gradient[1].withOpacity(0.20),
                ],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: gradient[1], size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF3D2C2C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ─── ANIMATED LIST ITEM ───────────────────────────────────────
// ═══════════════════════════════════════════════════════════════
class _AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;

  const _AnimatedListItem({required this.child, required this.index});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ─── ANIMATED COUNT CARD ──────────────────────────────────────
// ═══════════════════════════════════════════════════════════════
class _AnimatedCountCard extends StatefulWidget {
  final String label;
  final int count;
  final List<Color> colors;
  final IconData icon;

  const _AnimatedCountCard({
    required this.label,
    required this.count,
    required this.colors,
    required this.icon,
  });

  @override
  State<_AnimatedCountCard> createState() => _AnimatedCountCardState();
}

class _AnimatedCountCardState extends State<_AnimatedCountCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<int> _countAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _countAnim = IntTween(begin: 0, end: widget.count)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _scaleAnim = Tween<double>(begin: 0.75, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(_AnimatedCountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _countAnim = IntTween(begin: oldWidget.count, end: widget.count)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: widget.colors[0].withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _countAnim,
              builder: (_, __) => Text(
                '${_countAnim.value}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ─── ANIMATED ADMIN CARD ──────────────────────────────────────
// ═══════════════════════════════════════════════════════════════
class _AnimatedAdminCard extends StatefulWidget {
  final int index;
  final AdminModel admin;
  final bool isInactiveByLogin;
  final VoidCallback onDeactivate;
  final VoidCallback onActivate;

  const _AnimatedAdminCard({
    required this.index,
    required this.admin,
    this.isInactiveByLogin = false,
    required this.onDeactivate,
    required this.onActivate,
  });

  @override
  State<_AnimatedAdminCard> createState() => _AnimatedAdminCardState();
}

class _AnimatedAdminCardState extends State<_AnimatedAdminCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 80 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<List<Color>> gradients = [
      [const Color(0xFF6A11CB), const Color(0xFFBC2B8A)],
      [const Color(0xFF7C3AED), const Color(0xFFE91E8C)],
      [const Color(0xFF5C6BC0), const Color(0xFF7C3AED)],
      [const Color(0xFF9C27B0), const Color(0xFFFF5F96)],
    ];
    final gradient = gradients[widget.index % gradients.length];

    final isActive =
        widget.admin.status == 'accepted' && !widget.isInactiveByLogin;
    final isPending = widget.admin.status == 'pending';

    final Color statusColor = isActive
        ? const Color(0xFF11998E)
        : isPending
            ? const Color(0xFFF7971E)
            : const Color(0xFFEF5350);
    final String statusLabel =
        isActive ? 'Active' : isPending ? 'Pending' : 'Inactive';
    final IconData statusIcon = isActive
        ? Icons.verified_rounded
        : isPending
            ? Icons.pending_rounded
            : Icons.block_rounded;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Gradient top accent bar
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      topRight: Radius.circular(22),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: gradient[0].withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.admin.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.admin.firstName} ${widget.admin.lastName}',
                              style: const TextStyle(
                                color: Color(0xFF2D1B5E),
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (widget.admin.email.isNotEmpty)
                              Text(
                                widget.admin.email,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: statusColor.withOpacity(0.30),
                                    width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon,
                                      size: 11, color: statusColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Expand chevron
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: gradient[0],
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                // Expandable details section
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        Container(
                          height: 1,
                          color: gradient[0].withOpacity(0.10),
                          margin: const EdgeInsets.only(bottom: 14),
                        ),
                        if (widget.admin.staffId.isNotEmpty)
                          _buildDetailTile(
                            icon: Icons.badge_outlined,
                            label: 'Staff ID',
                            value: widget.admin.staffId,
                            color: gradient[0],
                          ),
                        if (widget.admin.phone.isNotEmpty)
                          _buildDetailTile(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: widget.admin.phone,
                            color: gradient[0],
                          ),
                        if (widget.admin.address.isNotEmpty)
                          _buildDetailTile(
                            icon: Icons.location_on_outlined,
                            label: 'Address',
                            value: widget.admin.address,
                            color: gradient[0],
                          ),
                        const SizedBox(height: 6),

                        // Action buttons
                        if (widget.admin.status == 'deactivated')
                          GestureDetector(
                            onTap: widget.onActivate,
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFF11998E),
                                  Color(0xFF38EF7D)
                                ]),
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF11998E)
                                        .withOpacity(0.30),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: Colors.white, size: 15),
                                  SizedBox(width: 5),
                                  Text(
                                    'Activate Staff',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (widget.admin.status == 'accepted')
                          GestureDetector(
                            onTap: widget.onDeactivate,
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0F3),
                                borderRadius: BorderRadius.circular(13),
                                border:
                                    Border.all(color: Colors.red.shade100),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.block_rounded,
                                      color: Colors.red.shade400, size: 15),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Deactivate Staff',
                                    style: TextStyle(
                                      color: Colors.red.shade400,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
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

  Widget _buildDetailTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF2D1B5E),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ─── MODELS ───────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════
class StaffApplicant {
  final String id;
  final String role;
  final String firstName;
  final String middleName;
  final String lastName;
  final String staffId;
  final String age;
  final String phone;
  final String email;
  final String address;
  final String status;

  StaffApplicant({
    required this.id,
    required this.role,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.staffId,
    required this.age,
    required this.phone,
    required this.email,
    required this.address,
    required this.status,
  });

  factory StaffApplicant.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return StaffApplicant(
      id: doc.id,
      role: data['role'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      middleName: data['middleName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      staffId: data['staffId'] as String? ?? '',
      age: data['age']?.toString() ?? '',
      phone: data['phone'] as String? ?? '',
      email: data['email'] as String? ?? '',
      address: data['address'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
    );
  }

  bool get isAccepted => status == 'accepted';

  String get initials {
    String i = '';
    if (firstName.isNotEmpty) i += firstName[0];
    if (lastName.isNotEmpty) i += lastName[0];
    return i.toUpperCase();
  }
}

class AdminModel {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String staffId;
  final String adminId;
  final String address;
  final String status;
  final String role;
  final DateTime? lastLoginAt;

  AdminModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.staffId,
    required this.adminId,
    required this.address,
    required this.status,
    required this.role,
    required this.lastLoginAt,
  });

  factory AdminModel.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return AdminModel(
      id: doc.id,
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      staffId: data['staffId'] as String? ?? '',
      adminId: data['adminId'] as String? ?? '',
      address: data['address'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      role: data['role'] as String? ?? '',
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isValidAdmin =>
      role.toLowerCase().trim() == 'admin' && adminId.isNotEmpty;

  bool get isValidStaff =>
      role.toLowerCase().trim() == 'staff' && staffId.isNotEmpty;

  bool get isInactiveByLogin {
    if (status != 'accepted' || lastLoginAt == null) return false;
    return DateTime.now().difference(lastLoginAt!).inDays >= 3;
  }

  String get initials {
    String i = '';
    if (firstName.isNotEmpty) i += firstName[0];
    if (lastName.isNotEmpty) i += lastName[0];
    return i.toUpperCase();
  }
}
