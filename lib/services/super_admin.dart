import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'account_password_service.dart';
import 'verified_email_sync.dart';

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
    FirebaseAuth? authentication,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (database != null) {
      final profileRef = database.collection('super_admin_profiles').doc(id);
      final profile = (await profileRef.get(
        const GetOptions(source: Source.server),
      )).data();
      final linkedUid = '${profile?['authUid'] ?? ''}'.trim();
      if (linkedUid.isNotEmpty) {
        final auth = authentication ?? FirebaseAuth.instance;
        // Email changes can leave the cached profile fields behind briefly.
        // If this device already has the linked identity, its current Auth
        // email is the authoritative additional sign-in candidate.
        final currentUser = auth.currentUser;
        final emails = <String>{
          for (final key in ['pendingAuthEmail', 'authEmail', 'email'])
            if ('${profile?[key] ?? ''}'.trim().isNotEmpty)
              '${profile![key]}'.trim(),
          if (currentUser?.uid == linkedUid &&
              (currentUser?.email ?? '').trim().isNotEmpty)
            currentUser!.email!.trim(),
        };
        for (final email in emails) {
          try {
            final credential = await auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            if (credential.user?.uid != linkedUid) {
              await auth.signOut();
              return false;
            }
            // A successful credential check must not be turned into a failed
            // login just because optional profile-email synchronization fails.
            try {
              await syncVerifiedProfileEmail(
                profile: profileRef,
                user: credential.user,
                reload: false,
              );
            } catch (_) {
              // The verified Auth session remains valid; profile sync can retry
              // on the next sign-in or account settings visit.
            }
            return true;
          } on FirebaseAuthException catch (error) {
            if (![
              'invalid-credential',
              'wrong-password',
              'user-not-found',
              'invalid-email',
            ].contains(error.code)) {
              rethrow;
            }
          }
        }
        // Once linked, old local/default passwords must never bypass Auth.
        return false;
      }
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

  /// Verifies the Super Admin password against linked Firebase Authentication
  /// without changing the active app's authentication session.
  static Future<bool> reauthenticateForBackup(
    String password, {
    FirebaseFirestore? database,
  }) async {
    final db = database ?? FirebaseFirestore.instance;
    final profileRef = db.collection('super_admin_profiles').doc(id);
    final profile = (await profileRef.get(
      const GetOptions(source: Source.server),
    )).data();
    final linkedUid = '${profile?['authUid'] ?? ''}'.trim();
    if (linkedUid.isEmpty) {
      throw StateError(
        'This Super Admin profile is not linked to Firebase Authentication. Secure backup creation requires a linked account.',
      );
    }
    final emails = <String>{
      for (final field in ['pendingAuthEmail', 'authEmail', 'email'])
        if ('${profile?[field] ?? ''}'.trim().isNotEmpty)
          '${profile![field]}'.trim(),
    };
    if (emails.isEmpty) {
      throw StateError('The linked Super Admin account has no sign-in email.');
    }

    final app = await Firebase.initializeApp(
      name:
          'superAdminBackupVerification${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      for (final email in emails) {
        try {
          final result = await auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          final user = result.user;
          if (user?.uid == linkedUid && user != null) {
            await user.reauthenticateWithCredential(
              EmailAuthProvider.credential(email: email, password: password),
            );
            return true;
          }
          throw StateError('The verified account does not match this profile.');
        } on FirebaseAuthException catch (error) {
          if (![
            'invalid-credential',
            'wrong-password',
            'user-not-found',
            'invalid-email',
          ].contains(error.code)) {
            rethrow;
          }
        }
      }
      return false;
    } finally {
      await app.delete();
    }
  }

  static Future<void> updatePassword(
    String password, {
    SharedPreferences? preferences,
    FirebaseFirestore? database,
    String? currentPassword,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (database != null) {
      if (password.length < 6) {
        throw ArgumentError('Use at least 6 characters.');
      }
      final profile =
          (await database.collection('super_admin_profiles').doc(id).get())
              .data();
      final authUid = '${profile?['authUid'] ?? ''}'.trim();
      if (authUid.isNotEmpty) {
        if (currentPassword == null || currentPassword.isEmpty) {
          throw StateError(
            'Enter your current password to update the linked account.',
          );
        }
        final app = await Firebase.initializeApp(
          name:
              'superAdminPasswordChange${DateTime.now().microsecondsSinceEpoch}',
          options: Firebase.app().options,
        );
        final auth = FirebaseAuth.instanceFor(app: app);
        try {
          UserCredential? credential;
          FirebaseAuthException? lastAuthError;
          for (final email in <String>{
            if ('${profile?['pendingAuthEmail'] ?? ''}'.trim().isNotEmpty)
              '${profile?['pendingAuthEmail']}'.trim(),
            if ('${profile?['authEmail'] ?? ''}'.trim().isNotEmpty)
              '${profile?['authEmail']}'.trim(),
            if ('${profile?['email'] ?? ''}'.trim().isNotEmpty)
              '${profile?['email']}'.trim(),
          }) {
            try {
              credential = await auth.signInWithEmailAndPassword(
                email: email,
                password: currentPassword,
              );
              break;
            } on FirebaseAuthException catch (error) {
              lastAuthError = error;
              if (![
                'invalid-credential',
                'wrong-password',
                'user-not-found',
              ].contains(error.code)) {
                rethrow;
              }
            }
          }
          final user = credential?.user;
          if (user == null || user.uid != authUid) {
            if (lastAuthError != null) throw lastAuthError;
            throw StateError(
              'Unable to verify the linked Super Admin account.',
            );
          }
          await user.updatePassword(password);
        } finally {
          await auth.signOut();
          await app.delete();
        }
      }
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
