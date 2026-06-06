import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/inventory_service.dart';
import '../../services/expiry_notification_service.dart';

import 'InventoryPage.dart';
import 'CoffeeMenuPage.dart';
import 'Notification.dart';
import 'Message.dart';
import 'Budget.dart';
import 'SalesPage.dart';
import 'SettingsPage.dart';
import 'StaffPage.dart';
import 'Reports.dart';

// ─── Color Palette ────────────────────────────────────────────────────────────
const kPrimaryBrown = Color(0xFFE91E63); // Pink
const kLightBrown = Color(0xFFF48FB1); // Light Pink
const kAccentBrown = Color(0xFFF8BBD0); // Accent Pink
const kCreamWhite = Color(0xFFFFF8F3);
const kDeepBrown = Color(0xFFC2105C); // Deep Pink

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  static const String kShopLogoAsset = 'Assets/Image/ob.jpg';
  static const String kAdminAvatarUrl =
      'https://i.imgur.com/placeholder_admin.png'; // Replace with your real image

  final _navItems = const [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Home'),
    _NavItem(icon: Icons.paid_rounded, label: 'Allocation'),
    _NavItem(icon: Icons.pie_chart_rounded, label: 'Sales'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    print('✅ AdminDashboard initialized');
    print('📦 Current entries: ${InventoryService().entries.length}');
    ExpiryNotificationService().checkAndNotifyExpiringItems();
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

  int _calculateTotalStockFromProducts(List<QueryDocumentSnapshot> products) {
    int total = 0;
    for (var doc in products) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        if (data['isDeleted'] == true) continue;
        final items =
            (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final activeItems = _activeItemVariants(items);
        if (activeItems.isEmpty) continue;
        // Sum the actual starting stock quantities, not the count of items
        for (var item in activeItems) {
          final stock =
              int.tryParse(item['startingStock']?.toString() ?? '0') ?? 0;
          total += stock;
        }
      } catch (e) {
        print('Error calculating stock for product: $e');
      }
    }
    return total;
  }

  String _extractAdminName(Map<String, dynamic>? data) {
    if (data == null) return 'Admin Name';

    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final middleName = (data['middleName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';
    final fullName = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');

    return fullName.isEmpty ? 'Admin Name' : fullName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCreamWhite,
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 1:
        // Budget page displays without the admin collapsible header
        return const BudgetPage();
      case 2:
        // Sales page should display without the admin collapsible header
        return const SalesPage();
      case 3:
        return const SettingsPage();
      default:
        return _buildHomePage();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HOME PAGE  –  NestedScrollView + SliverAppBar (collapsing header)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHomePage() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxScrolled) => [
        _buildSliverAppBar(showFullHeader: true),
      ],
      body: _buildHomeBody(),
    );
  }

  Widget _buildHomeBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsCard(),
          const SizedBox(height: 20),
          _buildSectionLabel('Quick Actions'),
          const SizedBox(height: 12),
          _buildOptionsGrid(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SLIVER APP BAR  –  Collapsing header with real image + admin badge
  // ══════════════════════════════════════════════════════════════════════════
  SliverAppBar _buildSliverAppBar({required bool showFullHeader}) {
    return SliverAppBar(
      expandedHeight: showFullHeader ? 270.0 : 80.0,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: kPrimaryBrown,
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
                for (final doc in snapshot.data?.docs ??
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
                  Icons.message_rounded,
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
        const SizedBox(width: 4),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('admin_notifications')
              .where('isRead', isEqualTo: false)
              .snapshots(),
          builder: (context, snapshot) {
            final unreadCount = snapshot.hasData
                ? snapshot.data!.docs.length
                : 0;
            return _buildIconButton(Icons.notifications_none_rounded, () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationPage()),
              );
            }, badgeCount: unreadCount, iconSize: 22, padding: const EdgeInsets.all(10));
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
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
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
          errorBuilder: (_, __, ___) => Container(
            color: Colors.white,
            child: const Icon(Icons.cake_rounded, color: kLightBrown, size: 20),
          ),
        ),
      ),
    );
  }

  // ── Full expanded header content ─────────────────────────────────────────
  Widget _buildExpandedHeader() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.expand,
          children: [
            Image.asset(
              'Assets/Image/Bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: kDeepBrown),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kDeepBrown, kLightBrown, kAccentBrown],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildShopLogoBig(),
                        const SizedBox(width: 14),
                        Expanded(child: _buildShopTitle()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildAdminProfileCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Large shop logo ───────────────────────────────────────────────────────
  Widget _buildShopLogoBig() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          kShopLogoAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.white,
            child: const Icon(Icons.cake_rounded, color: kLightBrown, size: 34),
          ),
        ),
      ),
    );
  }

  // ── Shop title + subtitle ─────────────────────────────────────────────────
  Widget _buildShopTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Decorative label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '🧁  BAKERY MANAGEMENT',
            style: TextStyle(
              fontSize: 9,
              color: Colors.white,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "Angel'Z Bites",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.1,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Cupcakes",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
            height: 1.2,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── Admin profile card (glassmorphic style) ───────────────────────────────
  Widget _buildAdminProfileCard() {
    final userEmail = FirebaseAuth.instance.currentUser?.email;

    final adminDocStream = userEmail != null
        ? FirebaseFirestore.instance
              .collection('staff_requests')
              .where('email', isEqualTo: userEmail)
              .limit(1)
              .snapshots()
        : Stream<QuerySnapshot<Map<String, dynamic>>>.empty();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: adminDocStream,
      builder: (context, snapshot) {
        Map<String, dynamic>? data;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          data = snapshot.data!.docs.first.data();
        }

        final fullName = _extractAdminName(data);
        final role = data?['role']?.toString().trim().toLowerCase() ?? 'admin';
        String displayId;
        if (data == null) {
          displayId = '#0001';
        } else {
          final primaryId = role == 'admin' ? data['adminId'] : data['staffId'];
          final fallbackId = role == 'admin'
              ? data['staffId']
              : data['adminId'];
          displayId = (primaryId ?? fallbackId)?.toString() ?? '#0001';
        }

        final isNarrow = MediaQuery.of(context).size.width < 360;
        final avatarStack = Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  kAdminAvatarUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 52,
                    height: 52,
                    color: Colors.white.withOpacity(0.25),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xFF66BB6A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        );

        final profileDetails = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                runSpacing: 6,
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'ID: $displayId',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB74D).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFFB74D).withOpacity(0.6),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      '👑 Admin',
                      style: TextStyle(
                        color: Color(0xFFFFE0B2),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final editButton = GestureDetector(
          onTap: () {
            setState(() => _selectedIndex = 3);
          },
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.edit_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.2,
            ),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        avatarStack,
                        const SizedBox(width: 14),
                        profileDetails,
                      ],
                    ),
                    const SizedBox(height: 14),
                    Align(alignment: Alignment.centerRight, child: editButton),
                  ],
                )
              : Row(
                  children: [
                    avatarStack,
                    const SizedBox(width: 14),
                    profileDetails,
                    editButton,
                  ],
                ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  STATS CARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStatsCard() {
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
                final items =
                    (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];
                final activeItems = _activeItemVariants(items);
                return activeItems.isNotEmpty;
              }).toList();

              // Stock = count of categories with at least one active variant
              totalStock = activeSalesDocs.length;

              // Items = count of active variants only
              for (var doc in activeSalesDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final items =
                    (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];
                final activeItems = _activeItemVariants(items);
                totalItems += activeItems.length;
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('staff_requests')
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

                final statsWidgets = [
                  _buildStatItem(
                    Icons.point_of_sale_rounded,
                    totalItems.toString(),
                    'Items',
                  ),
                  _buildStatItem(
                    Icons.inventory_2_rounded,
                    totalStock.toString(),
                    'Stock',
                  ),
                  _buildStatItem(
                    Icons.people_alt_rounded,
                    staffCount.toString(),
                    'Staff',
                  ),
                ];

                return Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
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
                        color: kPrimaryBrown.withOpacity(0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(child: statsWidgets[0]),
                      _buildStatDivider(),
                      Expanded(child: statsWidgets[1]),
                      _buildStatDivider(),
                      Expanded(child: statsWidgets[2]),
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

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1,
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
  Widget _buildSectionLabel(String label) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: kPrimaryBrown,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: kDeepBrown,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsGrid() {
    final width = MediaQuery.of(context).size.width;
    final childAspectRatio = width < 400 ? 1.02 : 1.08;

    final items = [
      _GridActionItem(
        icon: Icons.people_alt_rounded,
        label: 'Staff',
        color: const Color(0xFF5C6BC0),
        bgColor: const Color(0xFFEDE7F6),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StaffPage())),
      ),
      _GridActionItem(
        icon: Icons.inventory_2_rounded,
        label: 'Cakes Inventory',
        color: const Color(0xFF26A69A),
        bgColor: const Color(0xFFE0F2F1),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const InventoryPage())),
      ),
      _GridActionItem(
        icon: Icons.coffee_rounded,
        label: 'Coffee',
        color: const Color(0xFF8D6E63),
        bgColor: const Color(0xFFFFF3E0),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CoffeeMenuPage())),
      ),
      _GridActionItem(
        icon: Icons.assessment_rounded,
        label: 'Reports',
        color: const Color(0xFFD81B60),
        bgColor: const Color(0xFFFFE4EF),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ReportsPage())),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, i) => _buildGridItem(items[i]),
    );
  }

  Widget _buildGridItem(_GridActionItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: item.color.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: item.color.withOpacity(0.12), width: 1.2),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: item.bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(item.icon, color: item.color, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kDeepBrown,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BOTTOM NAV BAR
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildIconButton(
    IconData icon,
    VoidCallback onTap, {
    int badgeCount = 0,
    double iconSize = 24,
    EdgeInsets? padding,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 10),
            padding: padding ?? const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -2,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              _navItems.length,
              (index) => _buildNavItem(_navItems[index], index),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, int index) {
    final selected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
              child: Icon(
                item.icon,
                key: ValueKey(selected),
                size: 24,
                color: selected ? kPrimaryBrown : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? kPrimaryBrown : Colors.grey[500],
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
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

class _GridActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _GridActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
}
