import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'theme/design.dart';
import 'Login/Login/Login.dart';
import 'Login/Login/forgot_password.dart';
import 'Firebase.dart';
import 'services/inventory_service.dart';
import 'services/offline_login.dart';
import 'bones/bottom_nav.dart';
import 'Admin_pages/Admin/Dashboard.dart';
import 'Super_admin_pages/Dashboard.dart';
import 'services/super_admin.dart';
import 'services/session_actor.dart';
import 'services/login_validation.dart';
import 'services/password_reset_service.dart';
import 'services/account_session_control.dart';
import 'services/shorebird_update_service.dart';
import 'widgets/network_status_banner.dart';
import 'widgets/raspberry_cupcake_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  // Initialize InventoryService to start listening to Firestore
  InventoryService().initialize();
  OfflineAccountSync.start();
  FirebaseAuth.instance.authStateChanges().listen(
    (_) => OfflineAccountSync.start(),
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  bool _handlingResetReturn = false;
  Timer? _sessionTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionWatch;
  String? _watchedAccount;
  bool _checkingSession = false;
  bool _forcingLogout = false;
  bool _checkingForShorebirdUpdate = false;
  bool _showingShorebirdDialog = false;
  bool _shorebirdNotificationPending = false;
  bool _shorebirdUpdatePending = false;
  bool _shorebirdRestartPending = false;
  static const _shorebirdLastPromptKey = 'shorebird.lastPromptAt';

  @override
  void initState() {
    super.initState();
    ShorebirdUpdateService.salesProcessActive.addListener(
      _onSalesProcessStateChanged,
    );
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleAppLink,
      onError: (Object error) => debugPrint('App link error: $error'),
    );
    unawaited(_handleInitialLink());
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _watchAccountSession(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(
        const Duration(seconds: 2),
        _checkForShorebirdUpdate,
      );
    });
  }

  void _onSalesProcessStateChanged() {
    if (!ShorebirdUpdateService.salesProcessActive.value) {
      unawaited(_showPendingShorebirdDialog());
    }
  }

  Future<void> _checkForShorebirdUpdate() async {
    if (!mounted ||
        _checkingForShorebirdUpdate ||
        !ShorebirdUpdateService.updater.isAvailable) {
      return;
    }
    _checkingForShorebirdUpdate = true;
    try {
      final status = await ShorebirdUpdateService.check();
      if (!mounted) return;
      if (status == UpdateStatus.restartRequired) {
        await ShorebirdUpdateService.clearNotification();
        _shorebirdRestartPending = true;
        await _showPendingShorebirdDialog();
        return;
      }
      if (status != UpdateStatus.outdated || _showingShorebirdDialog) return;

      _shorebirdNotificationPending = true;
      final prefs = await SharedPreferences.getInstance();
      final lastPrompt = prefs.getInt(_shorebirdLastPromptKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastPrompt >= const Duration(hours: 24).inMilliseconds) {
        _shorebirdUpdatePending = true;
      }
      await _showPendingShorebirdDialog();
    } catch (error) {
      // Offline devices and Shorebird service errors should never block app use.
      debugPrint('Shorebird update check failed: $error');
    } finally {
      _checkingForShorebirdUpdate = false;
    }
  }

  Future<void> _showPendingShorebirdDialog() async {
    if (!mounted ||
        _showingShorebirdDialog ||
        ShorebirdUpdateService.salesProcessActive.value ||
        (!_shorebirdNotificationPending &&
            !_shorebirdUpdatePending &&
            !_shorebirdRestartPending)) {
      return;
    }
    _showingShorebirdDialog = true;
    try {
      if (_shorebirdNotificationPending) {
        await ShorebirdUpdateService.notifyAvailable();
        _shorebirdNotificationPending = false;
      }
      if (!_shorebirdUpdatePending && !_shorebirdRestartPending) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          ShorebirdUpdateService.salesProcessActive.value ||
          _navigatorKey.currentState == null) {
        return;
      }

      final restartPending = _shorebirdRestartPending;
      final action = await showDialog<bool>(
        context: _navigatorKey.currentState!.context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(restartPending ? 'Update ready' : 'Update Available'),
          content: Text(
            restartPending
                ? 'The update is ready. Restart the app when convenient to apply it.'
                : 'A new app update is ready to download. You can install it now or do it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(restartPending ? 'OK' : 'Update Now'),
            ),
          ],
        ),
      );

      if (restartPending) {
        _shorebirdRestartPending = false;
      } else {
        _shorebirdUpdatePending = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          _shorebirdLastPromptKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        if (action == true && mounted) await _downloadShorebirdUpdate();
      }
    } finally {
      _showingShorebirdDialog = false;
    }
  }

  Future<void> _downloadShorebirdUpdate() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !mounted) return;
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Downloading update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text('Downloading the update. Please keep this screen open.'),
            ],
          ),
        ),
      ),
    );
    try {
      await ShorebirdUpdateService.download();
      if (!mounted || !navigator.mounted) return;
      navigator.pop();
      await ShorebirdUpdateService.clearNotification();
      if (!mounted || !navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (context) => AlertDialog(
          title: const Text('Update ready'),
          content: const Text(
            'The update is downloaded and will be applied the next time you restart the app.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted || !navigator.mounted) return;
      navigator.pop();
      debugPrint('Shorebird update download failed: $error');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_shorebirdLastPromptKey);
      if (!mounted || !navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (context) => AlertDialog(
          title: const Text('Update unavailable'),
          content: const Text(
            'The update could not be downloaded. Check your internet connection and try again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    ShorebirdUpdateService.salesProcessActive.removeListener(
      _onSalesProcessStateChanged,
    );
    _sessionTimer?.cancel();
    unawaited(_sessionWatch?.cancel());
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  Future<void> _watchAccountSession() async {
    if (_checkingSession || _forcingLogout) return;
    _checkingSession = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('lastUserId');
      if (id == _watchedAccount) return;
      await _sessionWatch?.cancel();
      _watchedAccount = id;
      if (id == null ||
          id.isEmpty ||
          prefs.getString('lastRole') == 'super_admin')
        return;
      _sessionWatch = FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(id)
          .snapshots()
          .listen(
            (snapshot) async {
              if (!snapshot.exists ||
                  snapshot.metadata.hasPendingWrites ||
                  _forcingLogout ||
                  !mounted)
                return;
              final current = await SharedPreferences.getInstance();
              if (current.getString('lastUserId') != id) return;
              if (accountSessionRevoked(
                snapshot.data()!,
                current.getInt('accountSessionVersion.$id') ?? 0,
              )) {
                await _showAccountLoggedOut();
              }
            },
            onError: (Object error) =>
                debugPrint('Session status unavailable: $error'),
          );
    } finally {
      _checkingSession = false;
    }
  }

  Future<void> _showAccountLoggedOut() async {
    if (_forcingLogout) return;
    _forcingLogout = true;
    try {
      await _sessionWatch?.cancel();
      _watchedAccount = null;
      final prefs = await SharedPreferences.getInstance();
      await clearPersistedAccountSession(prefs);
      for (final key
          in prefs
              .getKeys()
              .where(
                (key) =>
                    key.startsWith('offlineLogin.') ||
                    key.startsWith('offlineAccount.'),
              )
              .toList()) {
        await prefs.remove(key);
      }
      await FirebaseAuth.instance.signOut();
      final navigator = _navigatorKey.currentState;
      if (navigator == null || !mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('Account logged out'),
            content: const Text(
              'This account has been logged out on all devices. Sign in again with your new password.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _forcingLogout = false;
    }
  }

  Future<void> _handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _handleAppLink(uri);
    } catch (error) {
      debugPrint('Initial app link error: $error');
    }
  }

  void _handleAppLink(Uri uri) {
    if (uri.scheme != 'angelzbites' || uri.host != 'login') return;
    if (_handlingResetReturn) return;
    _handlingResetReturn = true;
    unawaited(_returnToLogin(uri.queryParameters['requestId']));
  }

  Future<void> _returnToLogin(String? requestId) async {
    await FirebaseAuth.instance.signOut();
    final preferences = await SharedPreferences.getInstance();
    await clearPersistedAccountSession(preferences);
    final completed =
        requestId != null &&
        await PasswordResetSession.markCompleted(requestId);
    await WidgetsBinding.instance.endOfFrame;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('Unable to open login after password reset: no navigator.');
      _handlingResetReturn = false;
      return;
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) =>
            completed ? const ForgotPasswordScreen() : const LoginScreen(),
      ),
      (_) => false,
    );
    _handlingResetReturn = false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Sales Tracking',
      theme: AppTheme.theme,
      home: const SessionGate(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return NetworkStatusBanner(
          child: DefaultTextStyle(
            style: GoogleFonts.dmSans(color: Colors.black),
            child: child ?? const SizedBox(),
          ),
        );
      },
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final Future<Widget> _startPage = _resolveStartPage();

  Future<Widget> _resolveStartPage() async {
    final prefs = await SharedPreferences.getInstance();
    if (Uri.base.queryParameters['passwordReset'] == 'success') {
      await FirebaseAuth.instance.signOut();
      await clearPersistedAccountSession(prefs);
      final requestId = Uri.base.queryParameters['requestId'];
      final completed =
          requestId != null &&
          await PasswordResetSession.markCompleted(requestId);
      return completed ? const ForgotPasswordScreen() : const LoginScreen();
    }
    await SuperAdmin.migrateLegacySession(prefs);
    if (SuperAdmin.isSession(prefs)) return const SuperAdminDashboard();
    if (prefs.getString('lastRole') == SuperAdmin.role) {
      await clearPersistedAccountSession(prefs);
      return const LoginScreen();
    }
    final lastRole = prefs.getString('lastRole')?.trim().toLowerCase();
    final savedUserId = prefs.getString('lastUserId') ?? '';
    final user = FirebaseAuth.instance.currentUser;

    if (savedUserId == 'emergency-admin' && lastRole == 'admin') {
      return const AdminDashboard();
    }

    if (user == null) {
      if (savedUserId.isNotEmpty && lastRole == 'admin') {
        return const AdminDashboard();
      }
      if (savedUserId.isNotEmpty && lastRole == 'staff') {
        return const BottomNav();
      }
      await clearPersistedAccountSession(prefs);
      return const LoginScreen();
    }

    try {
      final profileId = savedUserId.isNotEmpty ? savedUserId : user.uid;
      final doc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(profileId)
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      final status = data?['status']?.toString().trim().toLowerCase();
      final role = data?['role']?.toString().trim().toLowerCase();

      final validStatus =
          status == 'accepted' || (status == null && role == 'admin');
      if (!doc.exists ||
          data == null ||
          !validStatus ||
          !['admin', 'staff'].contains(role) ||
          loginAccountStatusError(data) != null) {
        await FirebaseAuth.instance.signOut();
        await clearPersistedAccountSession(prefs);
        return const LoginScreen();
      }

      final publicId = (data[role == 'admin' ? 'adminId' : 'staffId'] ?? '')
          .toString();
      await clearPersistedAccountSession(prefs);
      await prefs.setString('lastRole', role!);
      await prefs.setString('lastUserId', profileId);
      await prefs.setString('lastStaffDocId', profileId);
      await prefs.setString('lastStaffPublicId', publicId);
      if (role == 'admin') await prefs.setString('adminId', publicId);
      return role == 'admin' ? const AdminDashboard() : const BottomNav();
    } catch (_) {
      if (savedUserId.isNotEmpty && lastRole == 'admin') {
        return const AdminDashboard();
      }
      if (savedUserId.isNotEmpty && lastRole == 'staff') {
        return const BottomNav();
      }
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _startPage,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return snapshot.data!;
        }
        return const Scaffold(
          body: RaspberryCupcakeLoader(
            fullScreen: true,
            message: 'Loading your workspace...',
          ),
        );
      },
    );
  }
}
