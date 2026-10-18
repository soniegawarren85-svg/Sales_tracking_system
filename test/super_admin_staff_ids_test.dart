import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Super_admin_pages/StaffPage.dart';

void main() {
  test('admin account details display the admin ID as its public ID', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('staff_requests').doc('admin-auth').set({
      'role': 'admin',
      'adminId': 'ADM-002',
      'username': 'ADM-002',
      'firstName': 'Test',
      'lastName': 'Admin',
      'status': 'accepted',
    });

    final document = (await db.collection('staff_requests').get()).docs.single;
    final admin = AdminModel.fromDoc(document);

    expect(admin.staffId, isEmpty);
    expect(admin.adminId, 'ADM-002');
    expect(admin.publicId, 'ADM-002');
    expect(admin.isValidAdmin, isTrue);
  });

  test('admin ID generation continues after existing account IDs', () {
    expect(
      nextStaffPublicId(
        role: 'admin',
        accounts: [
          {'role': 'admin', 'adminId': 'ADM-001'},
        ],
        counter: 0,
      ),
      'ADM-002',
    );
  });

  test('staff and admin ID sequences stay independent', () {
    final accounts = [
      {'role': 'admin', 'adminId': 'ADM-001'},
      {'role': 'staff', 'staffId': 'STF-007'},
    ];

    expect(
      nextStaffPublicId(role: 'admin', accounts: accounts, counter: 0),
      'ADM-002',
    );
    expect(
      nextStaffPublicId(role: 'staff', accounts: accounts, counter: 0),
      'STF-008',
    );
  });
}
