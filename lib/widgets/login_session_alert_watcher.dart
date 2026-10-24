import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/super_admin.dart';
import 'account_activity_logs_dialog.dart';

class LoginSessionAlertWatcher extends StatefulWidget {
  const LoginSessionAlertWatcher({super.key, this.firestore});

  final FirebaseFirestore? firestore;

  @override
  State<LoginSessionAlertWatcher> createState() =>
      _LoginSessionAlertWatcherState();
}

class _LoginSessionAlertWatcherState extends State<LoginSessionAlertWatcher> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  final Set<String> _notified = {};

  @override
  void initState() {
    super.initState();
    _watchLogins();
  }

  Future<void> _watchLogins() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final role = prefs.getString('lastRole')?.trim().toLowerCase() ?? '';
    if (role != 'admin' && role != SuperAdmin.role) return;
    final userId = role == SuperAdmin.role
        ? prefs.getString('lastUserId')?.trim() ?? ''
        : (prefs.getString('lastUserId')?.trim().isNotEmpty == true
              ? prefs.getString('lastUserId')!.trim()
              : FirebaseAuth.instance.currentUser?.uid.trim() ?? '');
    final ownSessionId = prefs.getString('accountLoginSessionId');
    if (userId.isEmpty || ownSessionId == null) return;

    DateTime? ownLoginAt;
    var activityActorId = role == SuperAdmin.role ? SuperAdmin.id : userId;
    _subscription = (widget.firestore ?? FirebaseFirestore.instance)
        .collection('staff_login_sessions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snapshot) {
            for (final doc in snapshot.docs) {
              if (doc.id == ownSessionId) {
                ownLoginAt = _sessionTime(doc.data()['loginAt']);
                activityActorId =
                    doc.data()['actorId']?.toString() ?? activityActorId;
              }
            }
            final ownLogin = ownLoginAt;
            if (ownLogin == null || !mounted) return;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final loginAt = _sessionTime(data['loginAt']);
              if (doc.id == ownSessionId ||
                  loginAt == null ||
                  !loginAt.isAfter(ownLogin) ||
                  data['logoutAt'] != null ||
                  !_notified.add(doc.id)) {
                continue;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 12),
                  content: const Text(
                    'Another device has signed in to your account. Check your activity logs if this was not you.',
                  ),
                  action: SnackBarAction(
                    label: 'View logs',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          AccountActivityLogsDialog(actorId: activityActorId),
                    ),
                  ),
                ),
              );
            }
          },
          onError: (Object error) {
            debugPrint('Account login alerts: $error');
          },
        );
  }

  DateTime? _sessionTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
