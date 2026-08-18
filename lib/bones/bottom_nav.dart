import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/inventory_service.dart';
import '../Staff_pages/Staff_notifcation.dart';
import '../Staff_pages/dashboard_page.dart';
import '../Staff_pages/search_page.dart';
import '../Staff_pages/profile_page.dart';
import '../Staff_pages/daily_stock_page.dart';
import '../Admin_pages/Admin/Message.dart';

class BottomNav extends StatefulWidget {
  const BottomNav({super.key});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  int _prevEntryCount = 0;
  int _salesLaunchToken = 0;
  String? _salesInitialView;
  String? _salesInitialGroup;
  bool _openPendingOnSalesLaunch = false;

  @override
  void initState() {
    super.initState();
    // listen for inventory updates so the dashboard can rebuild
    InventoryService().addListener(_onInventoryChanged);
    // initialize previous count so we can detect additions
    _prevEntryCount = InventoryService().entries.length;
  }

  @override
  void dispose() {
    InventoryService().removeListener(_onInventoryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onInventoryChanged() {
    // rebuild when service notifies us
    final entries = InventoryService().entries;
    final newCount = entries.length;
    setState(() {});

    // if a new entry was added, auto-scroll to the bottom to reveal it
    if (newCount > _prevEntryCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
          );
        }
      });
    }

    _prevEntryCount = newCount;
  }

  void _onMessagePressed() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MessagePage()));
  }

  void _onNotificationPressed() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StaffNotificationPage()));
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        // Dashboard Page
        return _buildDashboardPage();
      case 1:
        // Analytics Page
        return _buildAnalyticsPage();
      case 2:
        // Profile Page
        return _buildProfilePage();
      case 3:
        return DailyStockPage(
          initialView: _salesInitialView,
          initialGroupName: _salesInitialGroup,
          openPendingOnStart: _openPendingOnSalesLaunch,
          launchToken: _salesLaunchToken,
        );
      default:
        return _buildDashboardPage();
    }
  }

  Widget _buildDashboardPage() {
    // delegated to separate widget file to keep bottom_nav smaller
    return DashboardPage(
      scrollController: _scrollController,
      onMessage: _onMessagePressed,
      onNotification: _onNotificationPressed,
      onOpenSalesGroup:
          ({
            required String view,
            required String groupName,
            required String sourceInventoryId,
          }) {
            setState(() {
              _salesInitialView = view;
              _salesInitialGroup = groupName;
              _openPendingOnSalesLaunch = false;
              _salesLaunchToken++;
              _selectedIndex = 3;
            });
          },
    );
  }

  Widget _buildAnalyticsPage() {
    return AnalyticsPage(onMessage: _onMessagePressed);
  }

  Widget _buildProfilePage() {
    return ProfilePage(onMessage: _onMessagePressed);
  }

  @override
  Widget build(BuildContext context) {
    // make sure selected index is within bounds (especially after hot reload)
    const int lastIndex = 3; // dashboard, analytics, profile, stock
    if (_selectedIndex < 0 || _selectedIndex > lastIndex) {
      _selectedIndex = 0;
    }

    final size = MediaQuery.sizeOf(context);
    final hasTabletCanvas =
        size.shortestSide >= 600 || (size.width >= 900 && size.height >= 520);
    final isTabletLandscape = size.width > size.height && hasTabletCanvas;

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardPage(),
          _buildAnalyticsPage(),
          _buildProfilePage(),
          DailyStockPage(
            initialView: _salesInitialView,
            initialGroupName: _salesInitialGroup,
            openPendingOnStart: _openPendingOnSalesLaunch,
            launchToken: _salesLaunchToken,
          ),
        ],
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          _buildPendingOrdersBadge(isTabletLandscape),
          isTabletLandscape
              ? _buildLandscapeNav()
              : CurvedNavigationBar(
                  index: _selectedIndex,
                  height: 75,
                  items: <Widget>[
                    Icon(
                      Icons.home,
                      size: _selectedIndex == 0 ? 36 : 30,
                      color: _selectedIndex == 0
                          ? Colors.white
                          : Colors.white70,
                    ),
                    Icon(
                      Icons.search,
                      size: _selectedIndex == 1 ? 32 : 26,
                      color: _selectedIndex == 1
                          ? Colors.white
                          : Colors.white70,
                    ),
                    Icon(
                      Icons.person_outline,
                      size: _selectedIndex == 2 ? 32 : 26,
                      color: _selectedIndex == 2
                          ? Colors.white
                          : Colors.white70,
                    ),
                    Icon(
                      Icons.point_of_sale_rounded,
                      size: _selectedIndex == 3 ? 32 : 26,
                      color: _selectedIndex == 3
                          ? Colors.white
                          : Colors.white70,
                    ),
                  ],
                  color: const Color(0xFFF48FB1),
                  buttonBackgroundColor: const Color(0xFFE91E63),
                  backgroundColor: Colors.transparent,
                  animationCurve: Curves.easeInOut,
                  animationDuration: const Duration(milliseconds: 300),
                  onTap: (int idx) {
                    setState(() {
                      if (idx != 3) _openPendingOnSalesLaunch = false;
                      _selectedIndex = idx;
                    });
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildPendingOrdersBadge(bool compactNav) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pending_orders')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count <= 0) return const SizedBox.shrink();
        return Positioned(
          bottom: compactNav ? 76 : 88,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _salesInitialView = null;
                  _salesInitialGroup = null;
                  _openPendingOnSalesLaunch = true;
                  _salesLaunchToken++;
                  _selectedIndex = 3;
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF8BBD0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE91E63).withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bookmark_rounded,
                      color: Color(0xFFE91E63),
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '$count pending',
                      style: const TextStyle(
                        color: Color(0xFFC2105C),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLandscapeNav() {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: 380,
          height: 58,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF48FB1),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E63).withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _landscapeNavItem(Icons.home_rounded, 0),
              _landscapeNavItem(Icons.search_rounded, 1),
              _landscapeNavItem(Icons.person_outline_rounded, 2),
              _landscapeNavItem(Icons.point_of_sale_rounded, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _landscapeNavItem(IconData icon, int index) {
    final selected = _selectedIndex == index;
    return IconButton(
      onPressed: () => setState(() => _selectedIndex = index),
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xFFE91E63)
            : Colors.white.withOpacity(0.12),
        fixedSize: const Size(46, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(
        icon,
        size: selected ? 26 : 23,
        color: selected ? Colors.white : Colors.white.withOpacity(0.82),
      ),
    );
  }
}
