import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_username.dart';
import 'admin_login_accounts.dart';

String adminProfileIdentity({
  String? savedRole,
  String? savedUserId,
  String? adminId,
  String? authUserId,
}) {
  final role = savedRole?.trim().toLowerCase();
  final userId = savedUserId?.trim() ?? '';
  final publicId = adminId?.trim() ?? '';
  final authId = authUserId?.trim() ?? '';

  if (role == 'admin' && userId.isNotEmpty) {
    return userId == 'emergency-admin' ? publicId : userId;
  }
  if (role == 'admin' && publicId.isNotEmpty) return publicId;
  return authId.isNotEmpty ? authId : publicId;
}

Future<String> resolveAdminProfileIdentity(
  FirebaseFirestore db,
  SharedPreferences prefs, {
  String? authUserId,
}) async {
  final savedRole = prefs.getString('lastRole')?.trim().toLowerCase();
  final savedUserId = prefs.getString('lastUserId');
  final adminId = prefs.getString('adminId');
  final currentIdentity = adminProfileIdentity(
    savedRole: savedRole,
    savedUserId: savedUserId,
    adminId: adminId,
    authUserId: authUserId,
  );

  if (savedRole != 'admin' || (adminId?.trim().isNotEmpty ?? false) == false) {
    return currentIdentity;
  }

  final normalizedAdminId = normalizeAccountUsername(adminId!);
  final accountCollection = db.collection('staff_requests');
  final matches = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final field in const ['adminId', 'username']) {
    final result = await accountCollection
        .where(field, whereIn: accountUsernameAliases(adminId))
        .get(const GetOptions(source: Source.server));
    for (final doc in result.docs) {
      final data = doc.data();
      final matchesAdminId = ['adminId', 'username'].any(
        (key) =>
            normalizeAccountUsername('${data[key] ?? ''}') ==
            normalizedAdminId,
      );
      if (matchesAdminId) matches[doc.id] = doc;
    }
  }

  final preferred = preferSuperAdminCreatedAdmins(
    matches.values,
    dataOf: (doc) => doc.data(),
    username: adminId,
  );
  if (preferred.isEmpty) {
    if (normalizedAdminId == normalizeAccountUsername('ADM-001')) {
      for (final key in const [
        'lastUserId',
        'lastStaffDocId',
        'lastStaffPublicId',
      ]) {
        await prefs.remove(key);
      }
      return '';
    }
    return currentIdentity;
  }

  final account = preferred.first;
  if (account.id != savedUserId) {
    await prefs.setString('lastUserId', account.id);
    await prefs.setString('lastStaffDocId', account.id);
    await prefs.setString(
      'lastStaffPublicId',
      '${account.data()['adminId'] ?? account.data()['username'] ?? adminId}',
    );
  }
  return account.id;
}
