import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/admin_profile_identity.dart';

void main() {
  test('uses the logged-in admin profile instead of a stale auth user', () {
    expect(
      adminProfileIdentity(
        savedRole: 'admin',
        savedUserId: 'new-admin-uid',
        adminId: 'ADM-002',
        authUserId: 'old-admin-uid',
      ),
      'new-admin-uid',
    );
  });

  test('uses the public ID for the emergency admin session', () {
    expect(
      adminProfileIdentity(
        savedRole: 'admin',
        savedUserId: 'emergency-admin',
        adminId: 'ADM-0001',
        authUserId: 'old-admin-uid',
      ),
      'ADM-0001',
    );
  });

  test('falls back to Firebase Auth only when no admin session is saved', () {
    expect(
      adminProfileIdentity(adminId: 'ADM-001', authUserId: 'auth-admin-uid'),
      'auth-admin-uid',
    );
  });

  test(
    'migrates stale ADM-001 session to the Super Admin-created account',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'old-warren-uid',
        'adminId': 'ADM-001',
      });
      final prefs = await SharedPreferences.getInstance();
      final db = FakeFirebaseFirestore();
      await db.collection('staff_requests').doc('old-warren-uid').set({
        'role': 'admin',
        'adminId': 'ADM-0001',
        'username': 'ADM-001',
        'firstName': 'Warren',
        'lastName': 'Soniega',
      });
      await db.collection('staff_requests').doc('new-admin-uid').set({
        'role': 'admin',
        'adminId': 'ADM-002',
        'username': 'ADM-001',
        'createdByRole': 'super_admin',
        'firstName': 'Test',
        'lastName': 'Admin',
      });

      final identity = await resolveAdminProfileIdentity(db, prefs);

      expect(identity, 'new-admin-uid');
      expect(prefs.getString('lastUserId'), 'new-admin-uid');
      expect(prefs.getString('lastStaffDocId'), 'new-admin-uid');
      expect(prefs.getString('lastStaffPublicId'), 'ADM-002');
    },
  );

  test(
    'clears the legacy Warren ADM-001 session if no replacement exists',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'old-warren-uid',
        'adminId': 'ADM-001',
      });
      final prefs = await SharedPreferences.getInstance();
      final db = FakeFirebaseFirestore();
      await db.collection('staff_requests').doc('old-warren-uid').set({
        'role': 'admin',
        'adminId': 'ADM-0001',
        'username': 'ADM-001',
        'firstName': 'Warren',
        'lastName': 'Soniega',
      });

      final identity = await resolveAdminProfileIdentity(db, prefs);

      expect(identity, isEmpty);
      expect(prefs.getString('lastUserId'), isNull);
      expect(prefs.getString('lastStaffDocId'), isNull);
      expect(prefs.getString('lastStaffPublicId'), isNull);
    },
  );
}
