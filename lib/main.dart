import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/design.dart';
import 'Login/Login/Login.dart';
import 'Firebase.dart';
import 'services/inventory_service.dart';
import 'bones/bottom_nav.dart';
import 'Admin_pages/Admin/Dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  // Initialize InventoryService to start listening to Firestore
  InventoryService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sales Tracking',
      theme: AppTheme.theme,
      home: const SessionGate(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return DefaultTextStyle(
          style: GoogleFonts.dmSans(
            color: Colors.black,
          ),
          child: child ?? const SizedBox(),
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
    final lastRole = prefs.getString('lastRole')?.trim().toLowerCase();

    if (lastRole == 'admin') {
      return const AdminDashboard();
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await prefs.remove('lastRole');
      return const LoginScreen();
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final status = data?['status']?.toString().trim().toLowerCase();
      final role = data?['role']?.toString().trim().toLowerCase();

      if (status != 'accepted') {
        await FirebaseAuth.instance.signOut();
        await prefs.remove('lastRole');
        return const LoginScreen();
      }

      await prefs.setString('lastRole', role == 'admin' ? 'admin' : 'staff');
      return role == 'admin' ? const AdminDashboard() : const BottomNav();
    } catch (_) {
      if (lastRole == 'staff') return const BottomNav();
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
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
