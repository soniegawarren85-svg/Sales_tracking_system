import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionActor {
  const SessionActor(this.id, this.name);
  final String id;
  final String name;
}

String accountFullName(Map<String, dynamic> data) {
  final name = [data['firstName'], data['lastName']]
      .map((v) => '${v ?? ''}'.trim()).where((v) => v.isNotEmpty).join(' ');
  return name.isNotEmpty ? name : '${data['fullName'] ?? data['name'] ?? ''}'.trim();
}

/// The login screen supports both Firebase Auth and Firestore account sessions.
Future<SessionActor> resolveSessionActor(FirebaseFirestore db, {
  required bool admin,
  SharedPreferences? preferences,
}) async {
  final prefs = preferences ?? await SharedPreferences.getInstance();
  final expectedRole = admin ? 'admin' : 'staff';
  final savedRole = prefs.getString('lastRole');
  var id = savedRole == expectedRole ? prefs.getString('lastUserId') ?? '' : '';
  if (id == 'emergency-admin') id = prefs.getString('adminId') ?? '';
  User? user;
  if (id.isEmpty) {
    user = FirebaseAuth.instance.currentUser;
    id = user?.uid ?? '';
  }
  if (id.isEmpty || id.contains('/')) throw StateError('No active account session.');
  final profile = (await db.collection('staff_requests').doc(id).get()).data();
  if (profile == null || profile['isVoided'] == true ||
      '${profile['role'] ?? 'staff'}'.toLowerCase() != expectedRole ||
      (profile['status'] != null && '${profile['status']}'.isNotEmpty &&
          '${profile['status']}'.toLowerCase() != 'accepted')) {
    throw StateError('The active account is no longer available.');
  }
  final name = accountFullName(profile);
  return SessionActor(id, name.isNotEmpty ? name : user?.displayName ?? (admin ? 'Admin' : 'Staff'));
}
