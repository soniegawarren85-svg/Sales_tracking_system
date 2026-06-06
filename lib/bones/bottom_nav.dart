import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
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
        return const DailyStockPage();
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

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardPage(),
          _buildAnalyticsPage(),
          _buildProfilePage(),
          const DailyStockPage(),
        ],
      ),
      // floating home button remains; we'll keep using CurvedNavigationBar for animated curved-style bar
      // we no longer use a separate floating home button; home is an item in the curved bar
      // floatingActionButtonLocation and FloatingActionButton removed
      bottomNavigationBar: CurvedNavigationBar(
        index: _selectedIndex,
        height: 75, // max allowed by package
        items: <Widget>[
          // home icon as first item
          Icon(
            Icons.home,
            size: _selectedIndex == 0 ? 36 : 30,
            color: _selectedIndex == 0 ? Colors.white : Colors.white70,
          ),
          Icon(
            Icons.search,
            size: _selectedIndex == 1 ? 32 : 26,
            color: _selectedIndex == 1 ? Colors.white : Colors.white70,
          ),
          Icon(
            Icons.person_outline,
            size: _selectedIndex == 2 ? 32 : 26,
            color: _selectedIndex == 2 ? Colors.white : Colors.white70,
          ),
          Icon(
            Icons.account_balance_wallet_rounded,
            size: _selectedIndex == 3 ? 32 : 26,
            color: _selectedIndex == 3 ? Colors.white : Colors.white70,
          ),
        ],
        color: const Color(0xFFF48FB1),
        buttonBackgroundColor: const Color(0xFFE91E63),
        backgroundColor: Colors.transparent,
        animationCurve: Curves.easeInOut,
        animationDuration: const Duration(milliseconds: 300),
        onTap: (int idx) {
          setState(() {
            _selectedIndex = idx;
          });
        },
      ),
    );
  }
}
