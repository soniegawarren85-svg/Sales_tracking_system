import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/password_reset_account_lookup.dart';
import 'package:sales_tracking/services/super_admin.dart';

void main() {
  group('lookupPasswordResetAccount', () {
    test('finds staff and admin accounts by their sign-in email', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('staff').set({
        'email': 'staff@gmail.com',
        'role': 'staff',
        'status': 'accepted',
      });
      await firestore.collection('staff_requests').doc('admin').set({
        'email': 'admin@gmail.com',
        'role': 'admin',
      });

      final staff = await lookupPasswordResetAccount(
        firestore: firestore,
        email: 'STAFF@gmail.com',
      );
      final admin = await lookupPasswordResetAccount(
        firestore: firestore,
        email: 'admin@gmail.com',
      );

      expect(staff.status, PasswordResetAccountStatus.ready);
      expect(staff.authEmail, 'staff@gmail.com');
      expect(admin.status, PasswordResetAccountStatus.ready);
    });

    test(
      'rejects an edited contact email when auth email is different',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('staff_requests').doc('staff').set({
          'email': 'new-address@gmail.com',
          'authEmail': 'old-address@gmail.com',
          'role': 'staff',
          'status': 'accepted',
        });

        final result = await lookupPasswordResetAccount(
          firestore: firestore,
          email: 'new-address@gmail.com',
        );

        expect(result.status, PasswordResetAccountStatus.contactEmailOnly);
      },
    );

    test('uses the immediately updated Firebase Auth email', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('staff').set({
        'email': 'new-address@gmail.com',
        'authEmail': 'new-address@gmail.com',
        'role': 'staff',
        'status': 'accepted',
      });

      final result = await lookupPasswordResetAccount(
        firestore: firestore,
        email: 'new-address@gmail.com',
      );

      expect(result.status, PasswordResetAccountStatus.ready);
      expect(result.authEmail, 'new-address@gmail.com');
      expect(result.emailChangePending, isFalse);
    });

    test('rejects the new email until the change is verified', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('staff').set({
        'email': 'new-address@gmail.com',
        'authEmail': 'old-address@gmail.com',
        'pendingAuthEmail': 'new-address@gmail.com',
        'role': 'staff',
        'status': 'accepted',
      });

      final result = await lookupPasswordResetAccount(
        firestore: firestore,
        email: 'new-address@gmail.com',
      );

      expect(result.status, PasswordResetAccountStatus.ready);
      expect(result.authEmail, 'new-address@gmail.com');
      expect(result.emailChangePending, isTrue);
    });

    test(
      'keeps the old sign-in email usable while a new email awaits verification',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('staff_requests').doc('staff').set({
          'email': 'old-address@gmail.com',
          'authEmail': 'old-address@gmail.com',
          'pendingAuthEmail': 'new-address@gmail.com',
          'role': 'staff',
          'status': 'accepted',
        });

        final result = await lookupPasswordResetAccount(
          firestore: firestore,
          email: 'old-address@gmail.com',
        );

        expect(result.status, PasswordResetAccountStatus.ready);
        expect(result.authEmail, 'old-address@gmail.com');
      },
    );

    test('rejects pending accounts', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('pending').set({
        'email': 'pending@gmail.com',
        'role': 'staff',
        'status': 'pending',
      });

      final result = await lookupPasswordResetAccount(
        firestore: firestore,
        email: 'pending@gmail.com',
      );

      expect(result.status, PasswordResetAccountStatus.unavailable);
    });

    test(
      'does not send Firebase reset links for the local Super Admin',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore
            .collection('super_admin_profiles')
            .doc(SuperAdmin.id)
            .set({'email': 'superadmin@gmail.com'});

        final result = await lookupPasswordResetAccount(
          firestore: firestore,
          email: 'superadmin@gmail.com',
        );

        expect(result.status, PasswordResetAccountStatus.superAdmin);
      },
    );

    test('rejects emails that do not belong to an account', () async {
      final result = await lookupPasswordResetAccount(
        firestore: FakeFirebaseFirestore(),
        email: 'unknown@gmail.com',
      );

      expect(result.status, PasswordResetAccountStatus.notFound);
    });
  });
}
