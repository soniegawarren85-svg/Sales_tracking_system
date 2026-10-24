import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/verified_profile_email_change.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'new-super-admin-auth';
  @override
  String get email => 'owner@example.com';
  @override
  bool emailVerified = false;
  int sent = 0;
  bool failSend = false;
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    sent++;
    if (failSend) throw FirebaseAuthException(code: 'network-request-failed');
  }
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
}

class _Auth extends Fake implements FirebaseAuth {
  final account = _User();
  int created = 0;
  int signedIn = 0;
  int signedOut = 0;
  bool duplicate = false;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    created++;
    expect(email, 'owner@example.com');
    expect(password, 'Current@123');
    if (duplicate) throw FirebaseAuthException(code: 'email-already-in-use');
    return _Credential(account);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signedIn++;
    return _Credential(account);
  }

  @override
  Future<void> signOut() async {
    signedOut++;
  }
}

void main() {
  test(
    'first Super Admin email creates and links Auth without an old email',
    () async {
      final db = FakeFirebaseFirestore();
      final profile = db.doc('super_admin_profiles/Spr-001');
      await profile.set({'firstName': 'Owner', 'age': '29'});
      final auth = _Auth();
      final pending = await requestVerifiedProfileEmailChange(
        profile: profile,
        profileData: {},
        newEmail: 'owner@example.com',
        currentPassword: 'Current@123',
        allowInitialEmailSetup: true,
        authentication: auth,
      );
      expect(pending, isTrue);
      expect(auth.created, 1);
      expect(auth.signedIn, 0);
      expect(auth.account.sent, 1);
      expect(auth.signedOut, 1);
      final saved = (await profile.get()).data()!;
      expect(saved['authUid'], auth.account.uid);
      expect(saved['pendingAuthEmail'], 'owner@example.com');
      expect(saved['email'], isNull);
      expect(saved['firstName'], 'Owner');
      expect(saved['age'], '29');
    },
  );

  test(
    'retry after email delivery failure reuses the linked account',
    () async {
      final db = FakeFirebaseFirestore();
      final profile = db.doc('super_admin_profiles/Spr-001');
      final auth = _Auth()..account.failSend = true;
      Future<bool> save() => requestVerifiedProfileEmailChange(
        profile: profile,
        profileData: {},
        newEmail: 'owner@example.com',
        currentPassword: 'Current@123',
        allowInitialEmailSetup: true,
        authentication: auth,
      );
      await expectLater(save(), throwsStateError);
      auth.account.failSend = false;
      expect(await save(), isTrue);
      expect(auth.created, 1);
      expect(auth.signedIn, 1);
      expect((await profile.get()).data()!['email'], isNull);
      auth.account.emailVerified = true;
      expect(await save(), isFalse);
      final saved = (await profile.get()).data()!;
      expect(saved['email'], 'owner@example.com');
      expect(saved['authEmail'], 'owner@example.com');
      expect(saved.containsKey('pendingAuthEmail'), isFalse);
      expect(saved.containsKey('initialEmailVerificationPending'), isFalse);
    },
  );

  test('first setup never adopts an existing Auth account', () async {
    final db = FakeFirebaseFirestore();
    final profile = db.doc('super_admin_profiles/Spr-001');
    final auth = _Auth()..duplicate = true;
    await expectLater(
      requestVerifiedProfileEmailChange(
        profile: profile,
        profileData: {},
        newEmail: 'owner@example.com',
        currentPassword: 'Current@123',
        allowInitialEmailSetup: true,
        authentication: auth,
      ),
      throwsStateError,
    );
    expect(auth.signedIn, 0);
    expect((await profile.get()).exists, isFalse);
  });

  test(
    'existing staff email blocks initial setup before creating Auth',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/staff').set({'email': 'owner@example.com'});
      final auth = _Auth();
      await expectLater(
        requestVerifiedProfileEmailChange(
          profile: db.doc('super_admin_profiles/Spr-001'),
          profileData: {},
          newEmail: 'owner@example.com',
          currentPassword: 'Current@123',
          allowInitialEmailSetup: true,
          authentication: auth,
        ),
        throwsStateError,
      );
      expect(auth.created, 0);
    },
  );
}
