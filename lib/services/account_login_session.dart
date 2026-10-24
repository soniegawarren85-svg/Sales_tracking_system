import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log.dart';

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
    if (sessionId == null || sessionId.isEmpty) return;
    final db = database ?? FirebaseFirestore.instance;
    final ref = db.collection('staff_login_sessions').doc(sessionId);
    final snapshot = await ref.get();
    final session = snapshot.data();
    if (snapshot.exists) {
      await ref.set({
        'logoutAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await prefs.remove(_sessionPreference);
    await ActivityLog.record(
      'account_logout',
      '${session?['type'] ?? 'Account'} account signed out.',
      database: db,
      eventId: 'account_logout_$sessionId',
      details: {'sessionId': sessionId},
    );
  }
}
