import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log.dart';
import 'account_presence.dart';
import 'login_ip.dart';

class AccountLoginSession {
  static const _sessionPreference = 'accountLoginSessionId';

  static Future<void> start({
    required String userId,
    required String actorId,
    required String publicId,
    required String name,
    required String role,
    FirebaseFirestore? database,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final db = database ?? FirebaseFirestore.instance;
    final ref = db.collection('staff_login_sessions').doc();
    final ipFuture = loginIp()
        .timeout(const Duration(seconds: 3), onTimeout: () => null)
        .catchError((Object _) => null);
    final deviceId =
        prefs.getString('accountDeviceId') ??
        db.collection('staff_login_sessions').doc().id;
    await prefs.setString('accountDeviceId', deviceId);
    await ref.set({
      'userId': userId,
      'actorId': actorId,
      'deviceId': deviceId,
      'staffId': publicId,
      'staffName': name,
      'type': role,
      'role': role,
      'loginAt': FieldValue.serverTimestamp(),
      'logoutAt': null,
    });
    await prefs.setString(_sessionPreference, ref.id);
    unawaited(
      ipFuture
          .then((ip) async {
            if (ip != null) {
              await ref.set({'ipAddress': ip}, SetOptions(merge: true));
            }
          })
          .catchError((Object error) {
            // IP lookup is best effort and must not block account sign-in.
          }),
    );
    await ActivityLog.record(
      'account_login',
      '$role account signed in.',
      database: db,
      eventId: 'account_login_${ref.id}',
      details: {'sessionId': ref.id, 'deviceId': deviceId},
    );
  }

  static Future<void> close({FirebaseFirestore? database}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_sessionPreference);
    final db = database ?? FirebaseFirestore.instance;
    final role = prefs.getString('lastRole') ?? '';
    final userId = prefs.getString('lastUserId') ?? '';
    await prefs.remove(_sessionPreference);
    if (role.isNotEmpty && userId.isNotEmpty) {
      await AccountPresenceService.stop(
        role: role,
        userId: userId,
        database: db,
      );
    }
    if (sessionId == null || sessionId.isEmpty) return;
    final ref = db.collection('staff_login_sessions').doc(sessionId);
    try {
      await Future.wait([
        ref.set({
          'logoutAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
        ActivityLog.record(
          'account_logout',
          '${role.isEmpty ? 'Account' : role} account signed out.',
          database: db,
          eventId: 'account_logout_$sessionId',
          details: {'sessionId': sessionId},
        ),
      ]).timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('Logout record queued or deferred: $error');
    }
  }
}
