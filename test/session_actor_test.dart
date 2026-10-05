import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/session_actor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'built-in admin resolves a profile by public ID, not document ID',
    () async {
      final db = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'emergency-admin',
        'adminId': 'ADM-0001',
      });
      await db.doc('staff_requests/profile-document').set({
        'adminId': 'ADM-0001',
        'role': ' Admin ',
        'status': ' Accepted ',
        'firstName': 'Ana',
        'lastName': 'Cruz',
      });
      final actor = await resolveSessionActor(db, admin: true);
      expect(actor.id, 'profile-document');
      expect(actor.name, 'Ana Cruz');
    },
  );

  test('built-in admin session works before profile creation', () async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'emergency-admin',
      'adminId': 'ADM-0001',
    });
    final actor = await resolveSessionActor(
      FakeFirebaseFirestore(),
      admin: true,
    );
    expect(actor.id, 'ADM-0001');
    expect(actor.name, 'Admin User');
  });

  test(
    'missing normal accounts and disabled admin profiles remain rejected',
    () async {
      final db = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'missing',
      });
      await expectLater(resolveSessionActor(db, admin: true), throwsStateError);
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'emergency-admin',
        'adminId': 'ADM-0001',
      });
      await db.doc('staff_requests/ADM-0001').set({
        'role': 'admin',
        'isVoided': true,
      });
      await expectLater(resolveSessionActor(db, admin: true), throwsStateError);
      SharedPreferences.setMockInitialValues({
        'lastRole': 'staff',
        'lastUserId': 'staff',
      });
      await expectLater(resolveSessionActor(db, admin: true), throwsStateError);
    },
  );
}
