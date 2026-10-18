import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/session_actor.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';

void main() {
  test(
    'branch admin can use receiving identity without approving returns',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'branch-admin',
      });
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/branch-admin').set({
        'role': 'admin',
        'status': 'accepted',
        'adminId': 'ADM-002',
        'firstName': 'Branch',
        'lastName': 'Admin',
      });
      final actor = await resolveBranchInventoryActor(db);
      expect(actor.id, 'branch-admin');
      expect(actor.publicId, 'ADM-002');
      expect(actor.name, 'Branch Admin');
      for (final branch in ['own', 'other']) {
        await db.collection('allocation_checklist').add({
          'staffId': branch,
          'kind': 'incoming',
          'status': 'pending',
        });
      }
      final records = await checklistQuery(db, ['own'], false).get();
      expect(records.docs, hasLength(1));
      expect(records.docs.single.data()['staffId'], 'own');
    },
  );
}
