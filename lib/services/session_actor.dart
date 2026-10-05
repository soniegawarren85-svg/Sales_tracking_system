import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionActor {
  const SessionActor(this.id, this.name, {this.publicId = ''});
  final String id;
  final String name;
  final String publicId;
}

String accountFullName(Map<String, dynamic> data) {
  final name = [
    data['firstName'],
    data['lastName'],
  ].map((v) => '${v ?? ''}'.trim()).where((v) => v.isNotEmpty).join(' ');
  return name.isNotEmpty
      ? name
      : '${data['fullName'] ?? data['name'] ?? ''}'.trim();
}

/// Account document IDs and the public ADM/STF codes are not interchangeable.
Future<DocumentSnapshot<Map<String, dynamic>>?> findAccountProfile(
  FirebaseFirestore db,
  String identity,
) async {
  if (identity.isEmpty || identity.contains('/')) return null;
  final accounts = db.collection('staff_requests');
  final direct = await accounts.doc(identity).get();
  if (direct.exists) return direct;
  for (final field in ['adminId', 'staffId', 'uid', 'userId']) {
    final matches = await accounts
        .where(field, isEqualTo: identity)
        .limit(2)
        .get();
    if (matches.docs.length == 1) return matches.docs.single;
  }
  return null;
}

/// The login screen supports both Firebase Auth and Firestore account sessions.
Future<SessionActor> resolveSessionActor(
  FirebaseFirestore db, {
  required bool admin,
  SharedPreferences? preferences,
}) async {
  final prefs = preferences ?? await SharedPreferences.getInstance();
  final expectedRole = admin ? 'admin' : 'staff';
  final savedRole = prefs.getString('lastRole')?.trim().toLowerCase();
  if (savedRole != null && savedRole != expectedRole) {
    throw StateError('This action requires an $expectedRole account.');
  }
  var id = savedRole == expectedRole ? prefs.getString('lastUserId') ?? '' : '';
  final emergency = admin && id == 'emergency-admin';
  if (emergency) id = prefs.getString('adminId') ?? '';
  User? user;
  if (id.isEmpty) {
    user = FirebaseAuth.instance.currentUser;
    id = user?.uid ?? '';
  }
  if (id.isEmpty || id.contains('/')) {
    throw StateError('No active account session.');
  }
  final account = await findAccountProfile(db, id);
  final profile = account?.data();
  // Login explicitly supports the built-in admin before a profile is created.
  if (emergency && profile == null && id == 'ADM-0001') {
    return SessionActor(id, 'Admin User', publicId: id);
  }
  if (profile == null ||
      profile['isVoided'] == true ||
      '${profile['role'] ?? (emergency ? 'admin' : 'staff')}'
              .trim()
              .toLowerCase() !=
          expectedRole ||
      (profile['status'] != null &&
          '${profile['status']}'.trim().isNotEmpty &&
          '${profile['status']}'.trim().toLowerCase() != 'accepted')) {
    throw StateError('The active account is no longer available.');
  }
  final name = accountFullName(profile);
  return SessionActor(
    account!.id,
    name.isNotEmpty
        ? name
        : user?.displayName ?? (admin ? 'Admin User' : 'Staff'),
    publicId: '${profile[admin ? 'adminId' : 'staffId'] ?? ''}',
  );
}
