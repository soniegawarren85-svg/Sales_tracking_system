import '../../Login/Login/Login.dart';
import '../../widgets/admin_sales_overview.dart';
import '../../widgets/admin_recent_sales.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/inventory_service.dart';
import '../../services/expiry_notification_service.dart';
import '../../services/branch_session.dart';

import 'InventoryPage.dart';
import 'Message.dart';
import 'Budget.dart';
import 'SettingsPage.dart';
import 'StaffPage.dart';
import 'Reports.dart';

// ─── Color Palette (Professional / Refined) ───────────────────────────────
// A deeper, more premium magenta-plum palette instead of flat pink.
const kPrimaryBrown = Color(0xFFE91E63); // Deep magenta (primary)
const kLightBrown = Color(0xFFF48FB1); // Muted rose (secondary)
const kAccentBrown = Color(0xFFF8BBD0); // Soft blush accent
const kCreamWhite = Color(0xFFFFF8F5); // Cool off-white background
const kDeepBrown = Color(0xFFC2105C); // Deep plum for text/icons
const kSurfaceDark = Color(0xFFC2105C); // Near-black plum for dark surfaces

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  static const String kShopLogoAsset = 'Assets/Image/ob.jpg';
  final _navItems = const [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.paid_rounded, label: 'Allocation'),
    _NavItem(icon: Icons.inventory_2_rounded, label: 'Inventory'),
    _NavItem(icon: Icons.people_rounded, label: 'Staff'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Reports'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  // ── Entrance animation controller for the home page content ──────────────
  late final AnimationController _entranceController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    print('✅ AdminDashboard initialized');
    print('📦 Current entries: ${InventoryService().entries.length}');
    ExpiryNotificationService().checkAndNotifyExpiringItems();
    BranchSession.instance.load();
    BranchSession.instance.addListener(_onBranchChanged);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeIn = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    _entranceController.forward();
  }

  void _onBranchChanged() {
    if (mounted) {
      setState(() => _selectedIndex = 0);
      _entranceController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    BranchSession.instance.removeListener(_onBranchChanged);
    _entranceController.dispose();
    super.dispose();
  }

  bool _isExpired(String? expirationDateString) {
    if (expirationDateString == null || expirationDateString.trim().isEmpty) {
      return false;
    }

    final expirationDate = DateTime.tryParse(expirationDateString);
    if (expirationDate == null) {
      return false;
    }

    final now = DateTime.now();
    return expirationDate.isBefore(now) || expirationDate.isAtSameMomentAs(now);
  }

  List<Map<String, dynamic>> _activeItemVariants(
    List<Map<String, dynamic>> items,
  ) {
    return items.where((item) {
      if (item['isDeleted'] == true) return false;
      return !_isExpired(item['expirationDate']?.toString());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCreamWhite,
      body: SafeArea(
        child: Row(
          children: [
            if (MediaQuery.sizeOf(context).width >= 600) _buildSidebar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 600
          ? null
          : _buildBottomNavigationBar(),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 1:
        // Budget page displays without the admin collapsible header
        return const BudgetPage();
      case 2:
        // Inventory is part of the main admin navigation.
        return const InventoryPage(embedded: true);
      case 3:
        return const StaffPage();
      case 4:
        return const ReportsPage();
      case 5:
        return const SettingsPage();
      default:
        return _buildHomePage();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HOME PAGE  –  NestedScrollView + SliverAppBar (collapsing header)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHomePage() {
    return RefreshIndicator(
      notificationPredicate: (_) => true,
      onRefresh: () async {
        try {
          await Future.wait(
            [
              'completed_sales',
              'sales_inventory',
              'coffee_products',
              'staff_requests',
            ].map(
              (name) => FirebaseFirestore.instance
                  .collection(name)
                  .get(const GetOptions(source: Source.server)),
            ),
          ).timeout(const Duration(seconds: 15));
          if (mounted) setState(() {});
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Unable to refresh. Please check your connection.',
                ),
              ),
            );
        }
      },
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxScrolled) => [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: _buildSliverAppBar(showFullHeader: true),
          ),
        ],
        body: _buildHomeBody(),
      ),
    );
  }

  Widget _buildHomeBody() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: FadeTransition(
            opacity: _fadeIn,
            child: SlideTransition(
              position: _slideUp,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  const AdminSalesOverview(todayOnly: true),
                  const SizedBox(height: 20),
                  AdminRecentSales(
                    key: ValueKey(BranchSession.instance.branchId),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SLIVER APP BAR  –  Collapsing header with real image + admin badge
  // ══════════════════════════════════════════════════════════════════════════
  SliverAppBar _buildSliverAppBar({required bool showFullHeader}) {
    return SliverAppBar(
      expandedHeight: showFullHeader
          ? (MediaQuery.sizeOf(context).width < 600 ? 252.0 : 232.0)
          : 80.0,
      pinned: true,
      clipBehavior: Clip.antiAlias,
      stretch: true,
      elevation: 0,
      backgroundColor: kPrimaryBrown,
      title: Row(
        children: [
          _buildShopLogoMini(),
          const SizedBox(width: 10),
          const Text(
            "Angel'z Bites",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
      automaticallyImplyLeading: false,

      // ── Collapsed bar: show the sticky shop name in the toolbar
      centerTitle: false,

      actions: [
        FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, prefsSnapshot) {
            final prefs = prefsSnapshot.data;
            final adminMessageId =
                prefs?.getString('adminId') ??
                FirebaseAuth.instance.currentUser?.uid ??
                'ADM-0001';
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .where('participantIds', arrayContains: adminMessageId)
                  .snapshots(),
              builder: (context, snapshot) {
                var unreadCount = 0;
                for (final doc
                    in snapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                  final unreadBy = doc.data()['unreadBy'];
                  if (unreadBy is Map) {
                    final value = unreadBy[adminMessageId];
                    unreadCount += value is num
                        ? value.toInt()
                        : int.tryParse(value?.toString() ?? '') ?? 0;
                  }
                }
                return _buildIconButton(
                  Icons.mail_outline_rounded,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MessagePage()),
                    );
                  },
                  badgeCount: unreadCount,
                  iconSize: 22,
                  padding: const EdgeInsets.all(10),
                );
              },
            );
          },
        ),
        const SizedBox(width: 8),
      ],

      // ── Expanded / full header ────────────────────────────────────────
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        stretchModes: const [StretchMode.zoomBackground],
        background: _buildExpandedHeader(),
      ),

      // ── Smooth curved bottom shape ────────────────────────────────────
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
    );
  }

  // ── Mini shop logo (visible when collapsed) ───────────────────────────────
  Widget _buildShopLogoMini() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          kShopLogoAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: Colors.white,
            child: const Icon(Icons.cake_rounded, color: kLightBrown, size: 20),
          ),
        ),
      ),
    );
  }

  // ── Full expanded header content ─────────────────────────────────────────
  Widget _buildExpandedHeader() => ClipRRect(
    borderRadius: const BorderRadius.all(Radius.circular(28)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('Assets/Image/Final_bg.jpg', fit: BoxFit.cover),
        // Deeper, more refined gradient (adds a near-black plum layer for contrast)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [Color(0xC2C2105C), Color(0x99E91E63), Color(0x40F48FB1)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 74, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 10),
                    child: child,
                  ),
                ),
                child: const Text(
                  'Good day, Admin!',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage your products, sales, and inventory all in one place.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 17,
                      color: kDeepBrown,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatFullDate(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 12,
                          color: kDeepBrown,
                          fontWeight: FontWeight.w600,
                        ),
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
  );

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logging out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['lastRole', 'lastUserId', 'adminId']) {
      await prefs.remove(key);
    }
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SIDEBAR  –  refined dark-plum surface with hover + selection animation
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSidebar() => Container(
    width: 192,
    decoration: const BoxDecoration(
      color: kSurfaceDark,
      boxShadow: [
        BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(3, 0)),
      ],
    ),
    child: Column(
      children: [
        const SizedBox(height: 24),
        _buildShopLogoMini(),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Angelz Bites Cupcakes',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF8BBD0),
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Expanded(
          child: ListView(
            children: List.generate(
              _navItems.length,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                child: _SidebarTile(
                  item: _navItems[index],
                  selected: _selectedIndex == index,
                  onTap: () => setState(() => _selectedIndex = index),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text(
                  'Admin',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _logout,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  overlayColor: kPrimaryBrown.withOpacity(0.3),
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Logout'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  STATS CARD  –  animated count-up numbers
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStatsCard() {
    final activeBranchId = BranchSession.instance.branchId;
    return LayoutBuilder(
      builder: (context, constraints) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('sales_inventory')
              .snapshots(),
          builder: (context, salesSnapshot) {
            int totalStock = 0;
            int totalItems = 0;
            if (salesSnapshot.hasData) {
              final activeSalesDocs = salesSnapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['isDeleted'] == true) return false;
                if (data['isBundle'] == true) {
                  return true;
                }
                final items =
                    (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];
                final activeItems = _activeItemVariants(items);
                return activeItems.isNotEmpty;
              }).toList();

              for (var doc in activeSalesDocs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['isBundle'] == true) {
                  totalStock += 1;
                  continue;
                }
                final items =
                    (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];
                final activeItems = _activeItemVariants(items);
                totalItems += activeItems.length;
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: activeBranchId == null
                  ? FirebaseFirestore.instance
                        .collection('staff_requests')
                        .snapshots()
                  : FirebaseFirestore.instance
                        .collection('staff_requests')
                        .where('branchIds', arrayContains: activeBranchId)
                        .snapshots(),
              builder: (context, staffSnapshot) {
                final staffCount = staffSnapshot.hasData
                    ? staffSnapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final role = (data['role'] as String?)
                            ?.trim()
                            .toLowerCase();
                        return data['status'] == 'accepted' && role != 'admin';
                      }).length
                    : 0;

                return Container(
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.of(context).size.width >= 600
                        ? 12
                        : 18,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kPrimaryBrown, kLightBrown],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryBrown.withOpacity(0.32),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          Icons.point_of_sale_rounded,
                          totalItems,
                          'Items',
                        ),
                      ),
                      _buildStatDivider(),
                      Expanded(
                        child: _buildStatItem(
                          Icons.inventory_2_rounded,
                          totalStock,
                          'Bundles',
                        ),
                      ),
                      _buildStatDivider(),
                      Expanded(
                        child:
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('coffee_products')
                                  .snapshots(),
                              builder: (context, coffee) => _buildStatItem(
                                Icons.coffee_rounded,
                                coffee.hasData
                                    ? coffee.data!.docs
                                          .where(
                                            (doc) =>
                                                doc.data()['isDeleted'] != true,
                                          )
                                          .length
                                    : null,
                                'Coffee',
                              ),
                            ),
                      ),
                      _buildStatDivider(),
                      Expanded(
                        child: _buildStatItem(
                          Icons.people_alt_rounded,
                          staffCount,
                          'Staff',
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Animated count-up stat item. Pass `null` for value while data is loading
  /// to show an "—" placeholder instead of animating from zero.
  Widget _buildStatItem(IconData icon, int? value, String label) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(height: 8),
        value == null
            ? const Text(
                '—',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              )
            : TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: value),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, animatedValue, _) => Text(
                  '$animatedValue',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 48,
      width: 1,
      color: Colors.white.withOpacity(0.25),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  QUICK ACTIONS GRID
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildIconButton(
    IconData icon,
    VoidCallback onTap, {
    int badgeCount = 0,
    double iconSize = 19,
    EdgeInsets? padding,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Center(
        child: Badge(
          isLabelVisible: badgeCount > 0,
          label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
          child: IconButton.filled(
            tooltip: 'Messages',
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kDeepBrown,
              fixedSize: const Size(36, 36),
              minimumSize: const Size(36, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
      ],
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              _navItems.length,
              (index) => _buildNavItem(_navItems[index], index),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildNavItem(_NavItem item, int index) {
    final selected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width >= 600 ? 12 : 18,
          vertical: MediaQuery.of(context).size.width >= 600 ? 5 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? kPrimaryBrown.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                item.icon,
                key: ValueKey(selected),
                size: MediaQuery.of(context).size.width >= 600 ? 21 : 24,
                color: selected ? kPrimaryBrown : Colors.grey[400],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.width >= 600 ? 2 : 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width >= 600 ? 10 : 11,
                color: selected ? kPrimaryBrown : Colors.grey[500],
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sidebar tile with hover + selection animation ─────────────────────────
class _SidebarTile extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? kPrimaryBrown
        : (_hovering ? Colors.white.withOpacity(0.08) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              AnimatedScale(
                scale: widget.selected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  widget.item.icon,
                  size: 21,
                  color: widget.selected
                      ? Colors.white
                      : const Color(0xFFF8BBD0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.selected ? Colors.white : Colors.white70,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Data Models ──────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
