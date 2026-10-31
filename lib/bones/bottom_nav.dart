import '../widgets/staff_inventory_badge.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/branch_staff_activity_dialog.dart';
import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../services/inventory_service.dart';
import '../services/staff_onboarding_service.dart';
import '../services/held_order_store.dart';
import '../services/staff_login_session.dart';
import '../services/session_actor.dart';
import '../services/shorebird_update_service.dart';
import '../widgets/logout_progress.dart';
import '../Login/Login/Login.dart';
import '../Staff_pages/dashboard_page.dart';
import '../Staff_pages/AllCateg.dart';
import '../Staff_pages/profile_page.dart';
import '../Staff_pages/daily_stock_page.dart';
import '../Admin_pages/Admin/Message.dart';
import '../widgets/staff_onboarding_card.dart';

class BottomNav extends StatefulWidget {
  const BottomNav({super.key});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _guideTourKey = GlobalKey();
  final GlobalKey _dashboardTourKey = GlobalKey();
  final GlobalKey _dashboardNavTourKey = GlobalKey();
  final GlobalKey _dashboardCategoriesTourKey = GlobalKey();
  final GlobalKey _allocatedInventoryTourKey = GlobalKey();
  final GlobalKey _productsTourKey = GlobalKey();
  final GlobalKey _performanceTourKey = GlobalKey();
  final GlobalKey _inventoryChecklistTourKey = GlobalKey();
  final GlobalKey _inventoryReturnsTourKey = GlobalKey();
  final GlobalKey _inventoryTableTourKey = GlobalKey();
  final GlobalKey _cashDrawerTourKey = GlobalKey();
  final GlobalKey _salesProcessTourKey = GlobalKey();
  final GlobalKey _salesTourKey = GlobalKey();
  final GlobalKey _profileEditTourKey = GlobalKey();
  final GlobalKey _profileInfoTourKey = GlobalKey();
  final GlobalKey _profileNavTourKey = GlobalKey();
  int _prevEntryCount = 0;
  int _salesLaunchToken = 0;
  String? _salesInitialView;
  String? _salesInitialGroup;
  bool _openPendingOnSalesLaunch = false;
  String? _sessionUserId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _loginSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;
  bool _branchAssignmentLogoutStarted = false;
  TutorialCoachMark? _tutorialCoachMark;
  final ValueNotifier<_TutorialCardState> _tutorialCardState = ValueNotifier(
    const _TutorialCardState(),
  );
  String? _staffDocumentId;
  bool _onboardingCheckStarted = false;
  bool _tutorialIsReplay = false;
  bool _tutorialStarting = false;
  bool _tabletSidebarExpanded = false;
  bool _tabletSidebarLabelsVisible = false;

  Future<void> _watchLogins() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final savedStaffId = prefs.getString('lastStaffDocId')?.trim() ?? '';
    final savedUserId = prefs.getString('lastUserId')?.trim() ?? '';
    final uid = authUid.isNotEmpty
        ? authUid
        : savedStaffId.isNotEmpty
        ? savedStaffId
        : savedUserId;
    if (uid.isNotEmpty && mounted) {
      setState(() => _sessionUserId = uid);
      _profileSubscription = FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .snapshots()
          .listen(
            (snapshot) {
              final profile = snapshot.data();
              final branchIds = (profile?['branchIds'] as List? ?? [])
                  .map((id) => '$id'.trim())
                  .where((id) => id.isNotEmpty);
              if (profile?['requiresBranchAssignment'] == true &&
                  branchIds.isEmpty) {
                unawaited(_logoutAfterBranchUnassigned());
              }
            },
            onError: (Object error) {
              debugPrint('Branch assignment monitor: $error');
            },
          );
    }
    final ownId = prefs.getString('staffLoginSessionId');
    if (uid.isEmpty || ownId == null) return;
    final seen = <String>{};
    DateTime? ownLogin;
    _loginSubscription = FirebaseFirestore.instance
        .collection('staff_login_sessions')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snapshot) {
            for (final doc in snapshot.docs) {
              if (doc.id == ownId) {
                ownLogin = sessionTime(doc.data()['loginAt']);
              }
            }
            if (ownLogin == null || !mounted) return;
            for (final doc in snapshot.docs) {
              final login = sessionTime(doc.data()['loginAt']);
              if (doc.id == ownId ||
                  login == null ||
                  login.isBefore(ownLogin!) ||
                  doc.data()['logoutAt'] != null ||
                  !seen.add(doc.id)) {
                continue;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 12),
                  content: const Text(
                    'Another device has signed in to your staff account. Check your activity logs if this was not you.',
                  ),
                  action: SnackBarAction(
                    label: 'View logs',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => BranchStaffActivityDialog(
                        branchId: '',
                        branchName: '',
                        userId: uid,
                      ),
                    ),
                  ),
                ),
              );
            }
          },
          onError: (Object error) {
            debugPrint('Login alerts: $error');
          },
        );
  }

  @override
  void initState() {
    super.initState();
    _watchLogins();
    // listen for inventory updates so the dashboard can rebuild
    InventoryService().addListener(_onInventoryChanged);
    // initialize previous count so we can detect additions
    _prevEntryCount = InventoryService().entries.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkFirstLoginOnboarding());
    });
  }

  @override
  void dispose() {
    ShorebirdUpdateService.salesProcessActive.value = false;
    _loginSubscription?.cancel();
    _profileSubscription?.cancel();
    _tutorialCoachMark?.finish();
    _tutorialCardState.dispose();
    InventoryService().removeListener(_onInventoryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    _selectedIndex = index;
    ShorebirdUpdateService.salesProcessActive.value = index == 3;
  }

  Future<void> _logoutAfterBranchUnassigned() async {
    if (_branchAssignmentLogoutStarted || !mounted) return;
    _branchAssignmentLogoutStarted = true;
    final navigator = Navigator.of(context);
    try {
      await runWithLogoutProgress(context, () async {
        try {
          await StaffLoginSession.close();
        } catch (error) {
          debugPrint('Unable to close staff session after branch void: $error');
        }
        final preferences = await SharedPreferences.getInstance();
        await clearPersistedAccountSession(preferences);
        await FirebaseAuth.instance.signOut();
      });
    } catch (error) {
      debugPrint('Unable to complete forced staff logout: $error');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Your branch assignment was removed. Please sign in again after an administrator assigns you to a branch.',
        ),
      ),
    );
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
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

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        // Dashboard Page
        return _buildDashboardPage();
      case 1:
        return _buildAllItemsPage();
      case 2:
        // Profile Page
        return _buildProfilePage();
      case 3:
        return DailyStockPage(
          tabletSideNavigation: MediaQuery.sizeOf(context).width >= 600,
          initialView: _salesInitialView,
          initialGroupName: _salesInitialGroup,
          openPendingOnStart: _openPendingOnSalesLaunch,
          launchToken: _salesLaunchToken,
          salesTourKey: _salesProcessTourKey,
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
      tabletLayout: MediaQuery.sizeOf(context).width >= 600,
      onReplayTutorial: () => _startStaffTutorial(isReplay: true),
      guideTourKey: _guideTourKey,
      dashboardTourKey: _dashboardTourKey,
      dashboardFiltersTourKey: _dashboardCategoriesTourKey,
      allocatedItemsTourKey: _allocatedInventoryTourKey,
      performanceTourKey: _performanceTourKey,
      cashDrawerTourKey: _cashDrawerTourKey,
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
              _selectPage(3);
            });
          },
      onOpenAllItems: () => setState(() {
        _salesInitialView = null;
        _salesInitialGroup = null;
        _openPendingOnSalesLaunch = false;
        _salesLaunchToken++;
        _selectPage(3);
      }),
    );
  }

  Widget _buildAllItemsPage() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.sizeOf(context).width >= 600 ? 0 : 64,
      ),
      child: AllCategPage(
        embedded: true,
        tabletLayout: MediaQuery.sizeOf(context).width >= 600,
        inventoryChecklistTourKey: _inventoryChecklistTourKey,
        inventoryReturnsTourKey: _inventoryReturnsTourKey,
        inventoryTourKey: _inventoryTableTourKey,
      ),
    );
  }

  Widget _buildProfilePage() {
    return ProfilePage(
      onMessage: _onMessagePressed,
      showLogoutButton: MediaQuery.sizeOf(context).width < 600,
      tourTargetKey: _profileInfoTourKey,
      editProfileTourKey: _profileEditTourKey,
    );
  }

  Future<void> _logoutFromSidebar() async {
    final navigator = Navigator.of(context);
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !mounted) return;
    try {
      await runWithLogoutProgress(context, () async {
        await StaffLoginSession.close();
        final preferences = await SharedPreferences.getInstance();
        await clearPersistedAccountSession(preferences);
        await FirebaseAuth.instance.signOut();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
      );
      return;
    }
    if (mounted) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _checkFirstLoginOnboarding() async {
    if (_onboardingCheckStarted) return;
    _onboardingCheckStarted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      final savedStaffId = prefs.getString('lastStaffDocId')?.trim() ?? '';
      final staffDocumentId = authUid.isNotEmpty
          ? authUid
          : savedStaffId.isNotEmpty
          ? savedStaffId
          : prefs.getString('lastUserId')?.trim() ?? '';
      if (staffDocumentId.isEmpty) {
        throw StateError(
          'The signed-in staff account could not be identified.',
        );
      }
      _staffDocumentId = staffDocumentId;
      final shouldShow = await StaffOnboardingService.shouldShowTutorial(
        database: FirebaseFirestore.instance,
        staffDocumentId: staffDocumentId,
      );
      if (mounted && shouldShow) {
        await _startStaffTutorial();
      }
    } catch (error, stackTrace) {
      _onboardingCheckStarted = false;
      debugPrint(
        'Unable to check staff onboarding status: $error\n$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Unable to check your tutorial status. Please check your connection.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => unawaited(_checkFirstLoginOnboarding()),
          ),
        ),
      );
    }
  }

  Future<void> _startStaffTutorial({bool isReplay = false}) async {
    if (_tutorialStarting || _tutorialCoachMark?.isShowing == true) return;
    _tutorialStarting = true;
    _tutorialIsReplay = isReplay;
    _tutorialCardState.value = const _TutorialCardState();
    try {
      if ((_staffDocumentId ?? '').isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
        final savedStaffId = prefs.getString('lastStaffDocId')?.trim() ?? '';
        _staffDocumentId = authUid.isNotEmpty
            ? authUid
            : savedStaffId.isNotEmpty
            ? savedStaffId
            : prefs.getString('lastUserId')?.trim();
      }
      if ((_staffDocumentId ?? '').isEmpty) {
        throw StateError(
          'The signed-in staff account could not be identified.',
        );
      }

      await _navigateToTutorialStep(0);
      if (!mounted) return;
      final tutorial = TutorialCoachMark(
        targets: _buildTutorialTargets(),
        colorShadow: Colors.black,
        opacityShadow: 0.78,
        paddingFocus: 12,
        focusAnimationDuration: const Duration(milliseconds: 450),
        unFocusAnimationDuration: const Duration(milliseconds: 300),
        pulseAnimationDuration: const Duration(milliseconds: 650),
        pulseEnable: true,
        hideSkip: true,
        showSkipInLastTarget: false,
        onFinish: () {
          if (!mounted) return;
          _tutorialCoachMark = null;
          _tutorialStarting = false;
          _tutorialIsReplay = false;
          _tutorialCardState.value = const _TutorialCardState();
        },
      );
      _tutorialCoachMark = tutorial;
      tutorial.show(context: context);
    } catch (error, stackTrace) {
      _tutorialStarting = false;
      debugPrint('Unable to start staff tutorial: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the staff guide. Please try again.'),
        ),
      );
    }
  }

  List<_StaffTourStep> _tutorialSteps() => [
    _StaffTourStep(
      key: _dashboardTourKey,
      pageIndex: 0,
      title: 'Dashboard',
      description:
          'This is your Staff dashboard, with your account overview and daily work at a glance.',
      contentAlign: ContentAlign.top,
    ),
    _StaffTourStep(
      key: _dashboardCategoriesTourKey,
      pageIndex: 0,
      title: 'Dashboard Categories',
      description:
          'Use these buttons to browse your dashboard categories, bundles, and beverages.',
      contentAlign: ContentAlign.bottom,
    ),
    _StaffTourStep(
      key: _allocatedInventoryTourKey,
      pageIndex: 0,
      title: 'Admin Allocations',
      description:
          'Items allocated by your Admin appear here. Review the items assigned to your staff account.',
      contentAlign: ContentAlign.top,
    ),
    _StaffTourStep(
      key: _cashDrawerTourKey,
      pageIndex: 0,
      title: 'Cash Drawer',
      description:
          'Check the cash allocated to your staff account and monitor your drawer balance here.',
      contentAlign: ContentAlign.bottom,
    ),
    _StaffTourStep(
      key: _performanceTourKey,
      pageIndex: 0,
      title: 'Performance',
      description:
          'Review your performance summary and sales activity cards here.',
      contentAlign: ContentAlign.bottom,
    ),
    _StaffTourStep(
      key: _inventoryChecklistTourKey,
      pageIndex: 1,
      title: 'Allocation Checklist',
      description:
          'Open Checklist to review items allocated to your staff inventory and confirm receipt.',
      contentAlign: ContentAlign.bottom,
    ),
    _StaffTourStep(
      key: _inventoryReturnsTourKey,
      pageIndex: 1,
      title: 'Inventory Returns',
      description: 'Use Returns to review and manage inventory return records.',
      contentAlign: ContentAlign.bottom,
    ),
    _StaffTourStep(
      key: _inventoryTableTourKey,
      pageIndex: 1,
      title: 'Staff Inventory',
      description:
          'Browse the inventory table to see the products available to your staff account.',
      contentAlign: ContentAlign.top,
    ),
    _StaffTourStep(
      key: _profileEditTourKey,
      pageIndex: 2,
      title: 'Edit Your Profile',
      description:
          'Use the edit button to update your personal profile information.',
      contentAlign: ContentAlign.bottom,
    ),
    _StaffTourStep(
      key: _profileInfoTourKey,
      pageIndex: 2,
      title: 'Personal Information',
      description:
          'Review the personal details saved on your Staff profile in this section.',
      contentAlign: ContentAlign.top,
    ),
    _StaffTourStep(
      key: _salesProcessTourKey,
      pageIndex: 3,
      title: 'Sales Process',
      description:
          'Choose the appropriate order type and browse the available items for a customer order.',
      contentAlign: ContentAlign.bottom,
    ),
  ];

  List<TargetFocus> _buildTutorialTargets() {
    final steps = _tutorialSteps();
    return [
      for (var index = 0; index < steps.length; index++)
        TargetFocus(
          identify: 'staff-tour-$index',
          keyTarget: steps[index].key,
          shape: ShapeLightFocus.RRect,
          radius: 14,
          enableTargetTab: false,
          enableOverlayTab: false,
          contents: [
            TargetContent(
              align: steps[index].contentAlign,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              builder: (context, controller) => ValueListenableBuilder(
                valueListenable: _tutorialCardState,
                builder: (context, cardState, _) => StaffOnboardingCard(
                  title: steps[index].title,
                  description: steps[index].description,
                  step: index + 1,
                  totalSteps: steps.length,
                  arrowPointsUp:
                      steps[index].contentAlign == ContentAlign.bottom,
                  isLastStep: index == steps.length - 1,
                  isSaving: cardState.isSaving,
                  isConfirmingSkip: cardState.isConfirmingSkip,
                  errorMessage: cardState.errorMessage,
                  retryLabel: cardState.retryLabel,
                  onRetry: cardState.retryAction,
                  onBack: index == 0
                      ? null
                      : () => unawaited(
                          _moveTutorial(controller, index - 1, goBack: true),
                        ),
                  onCancelSkip: () => _updateTutorialCard(
                    isConfirmingSkip: false,
                    clearError: true,
                  ),
                  onNext: () => unawaited(_moveTutorial(controller, index + 1)),
                  onSkip: () => _updateTutorialCard(
                    isConfirmingSkip: true,
                    clearError: true,
                  ),
                  onFinish: () => unawaited(_finishStaffTutorial()),
                ),
              ),
            ),
          ],
        ),
    ];
  }

  Future<void> _moveTutorial(
    TutorialCoachMarkController controller,
    int targetIndex, {
    bool goBack = false,
  }) async {
    if (targetIndex < 0 || targetIndex >= _tutorialSteps().length) return;
    _updateTutorialCard(isSaving: true, clearError: true);
    try {
      await _navigateToTutorialStep(targetIndex);
      if (!mounted) return;
      _updateTutorialCard(isSaving: false);
      if (goBack) {
        controller.previous();
      } else {
        controller.next();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Unable to navigate during staff tutorial: $error\n$stackTrace',
      );
      if (!mounted) return;
      _updateTutorialCard(
        isSaving: false,
        errorMessage: 'This section is still loading. Please try Next again.',
        retryLabel: 'Retry',
        retryAction: () =>
            unawaited(_moveTutorial(controller, targetIndex, goBack: goBack)),
      );
    }
  }

  Future<void> _navigateToTutorialStep(int stepIndex) async {
    final steps = _tutorialSteps();
    final step = steps[stepIndex];
    if (identical(step.key, _cashDrawerTourKey) &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (_selectedIndex != step.pageIndex) {
      setState(() {
        _selectPage(step.pageIndex);
        if (step.pageIndex != 3) _openPendingOnSalesLaunch = false;
      });
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    BuildContext? targetContext = step.key.currentContext;
    for (var attempt = 0; targetContext == null && attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      targetContext = step.key.currentContext;
    }
    if (targetContext == null || !targetContext.mounted) {
      throw StateError('The requested staff tutorial target is not available.');
    }
    final renderObject = targetContext.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final targetTop = renderObject.localToGlobal(Offset.zero).dy;
      final targetBottom = targetTop + renderObject.size.height;
      if (!mounted) return;
      final mediaQuery = MediaQuery.of(context);
      final safeTop = mediaQuery.padding.top + 12;
      final safeBottom =
          mediaQuery.size.height - mediaQuery.padding.bottom - 12;
      final tooltipSpace = math.min(280.0, (safeBottom - safeTop) * 0.38);
      final isTooltipBelow = step.contentAlign == ContentAlign.bottom;
      final tooltipNeedsRoom = isTooltipBelow
          ? safeBottom - targetBottom < tooltipSpace
          : targetTop - safeTop < tooltipSpace;
      if (targetTop < safeTop ||
          targetBottom > safeBottom ||
          tooltipNeedsRoom) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: isTooltipBelow ? 0.22 : 0.68,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    }
  }

  Future<void> _finishStaffTutorial() async {
    if (_tutorialCardState.value.isSaving) return;
    _updateTutorialCard(isSaving: true, clearError: true);
    try {
      final staffDocumentId = _staffDocumentId;
      if (staffDocumentId == null || staffDocumentId.isEmpty) {
        throw StateError(
          'The signed-in staff account could not be identified.',
        );
      }
      await StaffOnboardingService.completeTutorial(
        database: FirebaseFirestore.instance,
        staffDocumentId: staffDocumentId,
        isReplay: _tutorialIsReplay,
      );
      if (!mounted) return;
      _tutorialCoachMark?.finish();
    } catch (error, stackTrace) {
      debugPrint(
        'Unable to save staff tutorial completion: $error\n$stackTrace',
      );
      if (!mounted) return;
      _updateTutorialCard(
        isSaving: false,
        errorMessage:
            'Could not save your progress. Check your connection and retry; the tutorial will stay open.',
        retryLabel: 'Retry save',
        retryAction: () => unawaited(_finishStaffTutorial()),
      );
    }
  }

  void _updateTutorialCard({
    bool? isSaving,
    bool? isConfirmingSkip,
    String? errorMessage,
    String? retryLabel,
    VoidCallback? retryAction,
    bool clearError = false,
  }) {
    _tutorialCardState.value = _tutorialCardState.value.copyWith(
      isSaving: isSaving,
      isConfirmingSkip: isConfirmingSkip,
      errorMessage: errorMessage,
      retryLabel: retryLabel,
      retryAction: retryAction,
      clearError: clearError,
    );
  }

  @override
  Widget build(BuildContext context) {
    // make sure selected index is within bounds (especially after hot reload)
    const int lastIndex = 3; // dashboard, analytics, profile, stock
    if (_selectedIndex < 0 || _selectedIndex > lastIndex) {
      _selectPage(0);
    }

    final size = MediaQuery.sizeOf(context);
    final isTabletLayout = size.width >= 600;
    final hasTabletCanvas =
        size.shortestSide >= 600 || (size.width >= 900 && size.height >= 520);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      extendBody: !isTabletLayout && (_selectedIndex != 3 || hasTabletCanvas),
      body: Row(
        children: [
          if (isTabletLayout) _buildTabletSidebar(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildDashboardPage(),
                _buildAllItemsPage(),
                _buildProfilePage(),
                DailyStockPage(
                  tabletSideNavigation: isTabletLayout,
                  initialView: _salesInitialView,
                  initialGroupName: _salesInitialGroup,
                  openPendingOnStart: _openPendingOnSalesLaunch,
                  launchToken: _salesLaunchToken,
                  salesTourKey: _salesProcessTourKey,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isTabletLayout
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedIndex != 2 &&
                    (_selectedIndex != 3 || hasTabletCanvas))
                  _buildPendingOrdersBadge(),
                Stack(
                  children: [
                    CurvedNavigationBar(
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
                        StaffInventoryBadge(
                          userId: _sessionUserId,
                          child: Icon(
                            Icons.inventory_2_rounded,
                            size: _selectedIndex == 1 ? 32 : 26,
                            color: _selectedIndex == 1
                                ? Colors.white
                                : Colors.white70,
                          ),
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
                      color: AppColors.primaryDark,
                      buttonBackgroundColor: AppColors.primary,
                      backgroundColor: Colors.transparent,
                      animationCurve: Curves.easeInOut,
                      animationDuration: const Duration(milliseconds: 300),
                      onTap: (int idx) {
                        setState(() {
                          if (idx != 3) _openPendingOnSalesLaunch = false;
                          _selectPage(idx);
                        });
                      },
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox.expand(key: _dashboardNavTourKey),
                            ),
                            Expanded(
                              child: SizedBox.expand(key: _productsTourKey),
                            ),
                            Expanded(
                              child: SizedBox.expand(key: _profileNavTourKey),
                            ),
                            Expanded(
                              child: SizedBox.expand(key: _salesTourKey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  void _toggleTabletSidebar() {
    if (_tabletSidebarExpanded) {
      setState(() => _tabletSidebarLabelsVisible = false);
      Future<void>.delayed(const Duration(milliseconds: 170), () {
        if (mounted) setState(() => _tabletSidebarExpanded = false);
      });
      return;
    }
    setState(() => _tabletSidebarExpanded = true);
    Future<void>.delayed(const Duration(milliseconds: 130), () {
      if (mounted && _tabletSidebarExpanded && _selectedIndex != 3) {
        setState(() => _tabletSidebarLabelsVisible = true);
      }
    });
  }

  Widget _buildTabletSidebar() {
    const destinations = [
      (Icons.home_rounded, 'Dashboard'),
      (Icons.inventory_2_rounded, 'Inventory'),
      (Icons.person_outline_rounded, 'Profile'),
      (Icons.point_of_sale_rounded, 'Sales Process'),
    ];
    final salesProcessSelected = _selectedIndex == 3;
    final expanded = _tabletSidebarExpanded && !salesProcessSelected;
    final showLabels = expanded && _tabletSidebarLabelsVisible;
    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutQuart,
        width: expanded ? 176 : 64,
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withOpacity(0.14),
              blurRadius: 12,
              offset: const Offset(3, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (!salesProcessSelected)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton.filledTonal(
                    tooltip: expanded
                        ? 'Collapse navigation'
                        : 'Expand navigation',
                    onPressed: _toggleTabletSidebar,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.14),
                      foregroundColor: Colors.white,
                      fixedSize: const Size(30, 30),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(
                      expanded
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                    ),
                  ),
                ),
              ),
            SizedBox(height: salesProcessSelected ? 8 : 2),
            Container(
              width: expanded ? 44 : 36,
              height: expanded ? 44 : 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'Assets/Image/ob.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Colors.white,
                    child: Icon(
                      Icons.cake_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: showLabels
                  ? Padding(
                      key: const ValueKey('staff-sidebar-brand'),
                      padding: const EdgeInsets.only(top: 7),
                      child: Column(
                        children: [
                          const Text(
                            "Angel'Z Bites Cupcakes",
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'STAFF',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.68),
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('staff-sidebar-brand-hidden'),
                    ),
            ),
            SizedBox(height: showLabels ? 14 : 10),
            for (var index = 0; index < destinations.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: _buildTabletNavItem(
                  icon: destinations[index].$1,
                  label: destinations[index].$2,
                  index: index,
                  key: switch (index) {
                    0 => _dashboardNavTourKey,
                    1 => _productsTourKey,
                    2 => _profileNavTourKey,
                    _ => _salesTourKey,
                  },
                  expanded: showLabels,
                ),
              ),
            const Spacer(),
            _buildTabletHeldOrdersButton(expanded: showLabels),
            const SizedBox(height: 8),
            if (showLabels)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _logoutFromSidebar,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Log out'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Log out',
                onPressed: _logoutFromSidebar,
                icon: const Icon(Icons.logout_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  fixedSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletNavItem({
    required IconData icon,
    required String label,
    required int index,
    required Key key,
    required bool expanded,
  }) {
    final selected = _selectedIndex == index;
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          if (index != 3) _openPendingOnSalesLaunch = false;
          if (index == 3) {
            _tabletSidebarExpanded = false;
            _tabletSidebarLabelsVisible = false;
          }
          _selectPage(index);
        }),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 0,
            vertical: 12,
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              if (index == 1)
                StaffInventoryBadge(
                  userId: _sessionUserId,
                  child: Icon(
                    icon,
                    size: 21,
                    color: Colors.white.withOpacity(selected ? 1 : 0.8),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 21,
                  color: Colors.white.withOpacity(selected ? 1 : 0.8),
                ),
              if (expanded) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(selected ? 1 : 0.82),
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingOrdersBadge() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? _sessionUserId;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<HeldOrder>>(
      stream: HeldOrderStore.instance.watch(uid),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 3,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.bookmark_rounded),
            label: Text(
              '$count held order${count == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => setState(() {
              _salesInitialView = null;
              _salesInitialGroup = null;
              _openPendingOnSalesLaunch = true;
              _salesLaunchToken++;
              _selectPage(3);
            }),
          ),
        );
      },
    );
  }

  Widget _buildTabletHeldOrdersButton({required bool expanded}) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? _sessionUserId;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<HeldOrder>>(
      stream: HeldOrderStore.instance.watch(uid),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: expanded ? double.infinity : 42,
            height: 42,
            child: Tooltip(
              message: '$count held order${count == 1 ? '' : 's'}',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                onPressed: () => setState(() {
                  _salesInitialView = null;
                  _salesInitialGroup = null;
                  _openPendingOnSalesLaunch = true;
                  _salesLaunchToken++;
                  _tabletSidebarExpanded = false;
                  _tabletSidebarLabelsVisible = false;
                  _selectPage(3);
                }),
                child: expanded
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bookmark_rounded, size: 17),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '$count held',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Center(
                            child: Icon(Icons.bookmark_rounded, size: 18),
                          ),
                          Positioned(
                            right: -3,
                            top: -5,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Text(
                                  count > 99 ? '99+' : '$count',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
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
}

class _StaffTourStep {
  const _StaffTourStep({
    required this.key,
    required this.pageIndex,
    required this.title,
    required this.description,
    required this.contentAlign,
  });

  final GlobalKey key;
  final int pageIndex;
  final String title;
  final String description;
  final ContentAlign contentAlign;
}

class _TutorialCardState {
  const _TutorialCardState({
    this.isSaving = false,
    this.isConfirmingSkip = false,
    this.errorMessage,
    this.retryLabel,
    this.retryAction,
  });

  final bool isSaving;
  final bool isConfirmingSkip;
  final String? errorMessage;
  final String? retryLabel;
  final VoidCallback? retryAction;

  _TutorialCardState copyWith({
    bool? isSaving,
    bool? isConfirmingSkip,
    String? errorMessage,
    String? retryLabel,
    VoidCallback? retryAction,
    bool clearError = false,
  }) {
    return _TutorialCardState(
      isSaving: isSaving ?? this.isSaving,
      isConfirmingSkip: isConfirmingSkip ?? this.isConfirmingSkip,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      retryLabel: clearError ? null : retryLabel ?? this.retryLabel,
      retryAction: clearError ? null : retryAction ?? this.retryAction,
    );
  }
}
