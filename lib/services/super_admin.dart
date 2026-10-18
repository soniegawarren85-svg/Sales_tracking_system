import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'account_password_service.dart';

/// Dedicated super-admin identity and session, separate from ordinary admins.
class SuperAdmin {
  static const id = 'Spr-001';
  static const sessionId = 'super-admin';
  static const name = 'Super admin';
  static const role = 'super_admin';
  static const _passwordKey = 'superAdmin.passwordHash';

  static bool matchesId(String value) =>
      value.trim().toLowerCase() == id.toLowerCase();

  static bool matchesLogin(String username, String password) =>
      matchesId(username) && password == 'Super@123';

  static String _passwordHash(String password) =>
      sha256.convert(utf8.encode('$id:$password')).toString();

  static Future<bool> verifyPassword(
    String password, {
    SharedPreferences? preferences,
    FirebaseFirestore? database,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (database != null) {
      final ref = database.collection('super_admin_credentials').doc(id);
      final data = (await ref.get(
        const GetOptions(source: Source.server),
      )).data();
      if (data?['passwordCredential'] != null) {
        return matchesAccountPassword(data!, password);
      }
      final legacy =
          data?['legacyPasswordHash'] ?? prefs.getString(_passwordKey);
      if (legacy != null) {
        if (data == null) await ref.set({'legacyPasswordHash': legacy});
        return legacy == _passwordHash(password);
      }
      return password == 'Super@123';
    }
    final storedHash = prefs.getString(_passwordKey);
    return storedHash == null
        ? password == 'Super@123'
        : storedHash == _passwordHash(password);
  }

  static Future<void> updatePassword(
    String password, {
    SharedPreferences? preferences,
    FirebaseFirestore? database,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (database != null) {
      if (password.length < 6)
        throw ArgumentError('Use at least 6 characters.');
      await database.collection('super_admin_credentials').doc(id).set({
        'passwordCredential': await createPasswordCredential(password),
        'credentialsChangedAt': FieldValue.serverTimestamp(),
      });
    }
    await prefs.setString(_passwordKey, _passwordHash(password));
  }

  static bool isSession(SharedPreferences prefs) =>
      prefs.getString('lastRole') == role &&
      prefs.getString('lastUserId') == sessionId &&
      prefs.getString('superAdminId') == id;

  static Future<void> migrateLegacySession(SharedPreferences prefs) async {
    if (prefs.getString('lastRole') == 'admin' &&
        prefs.getString('lastUserId') == sessionId &&
        prefs.getString('adminId') == id) {
      await startSession(prefs);
    }
  }

  static Future<void> startSession(SharedPreferences prefs) async {
    for (final key in ['lastStaffDocId', 'lastStaffPublicId', 'adminId']) {
      await prefs.remove(key);
    }
    await prefs.setString('superAdminId', id);
    await prefs.setString('lastUserId', sessionId);
    await prefs.setString('lastRole', role);
  }
}
