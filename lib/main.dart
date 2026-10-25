import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
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
