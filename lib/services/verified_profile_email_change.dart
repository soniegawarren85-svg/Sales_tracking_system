import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'account_password_service.dart';
import 'profile_email.dart';

Future<void> updateLinkedProfileAuthPassword({
  required Map<String, dynamic> profileData,
  required String expectedUid,
  required String currentPassword,
  required String newPassword,
}) async {
  final linkedUid = '${profileData['authUid'] ?? expectedUid}'.trim();
  final app = await Firebase.initializeApp(
    name: 'profilePasswordChange${DateTime.now().microsecondsSinceEpoch}',
    options: Firebase.app().options,
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  try {
    UserCredential? credential;
    FirebaseAuthException? lastAuthError;
    for (final email in <String>{
      if ('${profileData['pendingAuthEmail'] ?? ''}'.trim().isNotEmpty)
        '${profileData['pendingAuthEmail']}'.trim(),
      if ('${profileData['authEmail'] ?? ''}'.trim().isNotEmpty)
        '${profileData['authEmail']}'.trim(),
      if ('${profileData['email'] ?? ''}'.trim().isNotEmpty)
        '${profileData['email']}'.trim(),
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
    if (user == null) {
      if (lastAuthError != null) throw lastAuthError;
      throw StateError('Unable to find the linked account email.');
    }
    if (user.uid != linkedUid) {
      throw StateError(
        'The email credentials do not match the linked account.',
      );
    }
    await user.updatePassword(newPassword);
  } on FirebaseAuthException catch (error) {
    final message = switch (error.code) {
      'wrong-password' ||
      'invalid-credential' => 'The current password is incorrect.',
      'requires-recent-login' =>
        'Please sign in again, then retry changing your password.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      'too-many-requests' => 'Too many attempts. Please wait before retrying.',
      'weak-password' =>
        'The new password does not meet Firebase requirements.',
      _ => 'Unable to update the linked password (${error.code}).',
    };
    throw StateError(message);
  } finally {
    await auth.signOut();
    await app.delete();
  }
}

Future<bool> requestVerifiedProfileEmailChange({
  required DocumentReference<Map<String, dynamic>> profile,
  required Map<String, dynamic> profileData,
  required String newEmail,
  required String currentPassword,
}) async {
  final db = profile.firestore;
  if (await profileEmailTaken(
    db,
    newEmail,
    profile.id,
    ownCollection: profile.parent.id,
  )) {
    throw StateError('This email is already used by another account.');
  }

  final currentEmail = confirmedProfileEmail(profileData);
  if (currentEmail.isEmpty) {
    throw StateError('A current account email is not set.');
  }

  final app = await Firebase.initializeApp(
    name: 'profileEmailChange${DateTime.now().microsecondsSinceEpoch}',
    options: Firebase.app().options,
  );
  final auth = FirebaseAuth.instanceFor(app: app);

  try {
    UserCredential? credential;
    FirebaseAuthException? lastAuthError;
    final candidates = <String>{
      if ('${profileData['pendingAuthEmail'] ?? ''}'.trim().isNotEmpty)
        '${profileData['pendingAuthEmail']}'.trim(),
      currentEmail,
      if ('${profileData['email'] ?? ''}'.trim().isNotEmpty)
        '${profileData['email']}'.trim(),
    };

    for (final email in candidates) {
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

    if (credential == null && lastAuthError?.code == 'user-not-found') {
      try {
        credential = await auth.createUserWithEmailAndPassword(
          email: currentEmail,
          password: currentPassword,
        );
      } on FirebaseAuthException catch (error) {
        if (error.code == 'email-already-in-use') {
          throw StateError(
            'This current email is already linked to another Firebase account. Sign in again and retry.',
          );
        }
        rethrow;
      }
    }

    final user = credential?.user;
    if (user == null) {
      throw StateError('The current password is incorrect.');
    }

    final linkedUid = '${profileData['authUid'] ?? ''}'.trim();
    if (linkedUid.isNotEmpty && user.uid != linkedUid) {
      throw StateError(
        'This email is linked to a different account. Contact support before changing it.',
      );
    }
    if (linkedUid.isEmpty) {
      final otherAccount = await db
          .collection('staff_requests')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      if (otherAccount.exists &&
          !(profile.parent.id == 'staff_requests' && user.uid == profile.id)) {
        throw StateError(
          'This email is already linked to a different account.',
        );
      }
    }

    final actualCurrentEmail = user.email?.trim();
    if (actualCurrentEmail == null || actualCurrentEmail.isEmpty) {
      throw StateError('Unable to read the verified account email.');
    }

    if (normalizedProfileEmail(actualCurrentEmail) ==
        normalizedProfileEmail(newEmail)) {
      await profile.set({
        'email': actualCurrentEmail,
        'authEmail': actualCurrentEmail,
        'authUid': user.uid,
        'pendingAuthEmail': FieldValue.delete(),
        'passwordAuthMode': 'firebase',
        'passwordCredential': FieldValue.delete(),
        for (final field in legacyPasswordFields) field: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return false;
    }

    await user.verifyBeforeUpdateEmail(newEmail);
    await profile.set({
      'email': actualCurrentEmail,
      'authEmail': actualCurrentEmail,
      'authUid': user.uid,
      'pendingAuthEmail': newEmail.trim(),
      'passwordAuthMode': 'firebase',
      'passwordCredential': FieldValue.delete(),
      for (final field in legacyPasswordFields) field: FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  } on FirebaseAuthException catch (error) {
    final message = switch (error.code) {
      'wrong-password' ||
      'invalid-credential' => 'The current password is incorrect.',
      'email-already-in-use' => 'That Gmail is already linked to an account.',
      'invalid-email' => 'Enter a valid Gmail address.',
      'requires-recent-login' =>
        'Please sign in again, then retry changing your Gmail.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      'too-many-requests' => 'Too many attempts. Please wait before retrying.',
      'operation-not-allowed' =>
        'Email verification is unavailable for this account.',
      _ => 'Unable to send the verification link (${error.code}).',
    };
    throw StateError(message);
  } finally {
    await auth.signOut();
    await app.delete();
  }
}
