import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_email.dart';

/// Only the linked, authenticated user can confirm a pending address.
Future<bool> syncVerifiedProfileEmail({
  required DocumentReference<Map<String, dynamic>> profile,
  required User? user,
  bool reload = true,
}) async {
  if (user == null) return false;
  if (reload) await user.reload().timeout(const Duration(seconds: 10));
  // Firebase User instances are snapshots; read the refreshed instance.
  final refreshed = reload ? FirebaseAuth.instance.currentUser : user;
  if (refreshed == null || refreshed.uid != user.uid) return false;
  return profile.firestore.runTransaction((transaction) async {
    final data = (await transaction.get(profile)).data();
    if (data == null) return false;
    final expectedUid = '${data['authUid'] ?? profile.id}'.trim();
    final pending = normalizedProfileEmail(data['pendingAuthEmail']);
    final email = normalizedProfileEmail(refreshed.email);
    if (expectedUid != refreshed.uid || pending.isEmpty ||
        pending != email || !refreshed.emailVerified) return false;
    transaction.update(profile, {
      'email': email,
      'authEmail': email,
      'pendingAuthEmail': FieldValue.delete(),
      'initialEmailVerificationPending': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  });
}
