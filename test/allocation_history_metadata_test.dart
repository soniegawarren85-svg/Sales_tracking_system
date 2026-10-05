import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/allocation_history_metadata.dart';
import 'package:sales_tracking/widgets/branch_allocation_history.dart';

void main() {
  test(
    'allocator profile first and last names replace placeholder or generic names',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/admin-profile').set({
        'adminId': 'ADM-0001',
        'firstName': 'Ana',
        'lastName': 'Cruz',
      });
      final metadata = AllocationHistoryMetadata(db);
      for (final saved in ['Not recorded', 'Admin User', 'Old display name']) {
        final record = await metadata.resolve({
          'allocatedBy': 'ADM-0001',
          'allocatedByName': saved,
        });
        expect(record['allocatedByName'], 'Ana Cruz');
      }
    },
  );

  test(
    'history resolves allocator from its original delivery only within the same branch',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/admin').set({
        'adminId': 'ADM-0001',
        'firstName': 'Ana',
        'lastName': 'Cruz',
      });
      await db.doc('branches/branch').set({'branchCode': 'BR-001'});
      await db.doc('allocation_checklist/delivery').set({
        'staffId': 'branch',
        'branchName': 'Sm dagupan',
        'allocatedBy': 'admin',
      });
      final metadata = AllocationHistoryMetadata(db);
      final record = await metadata.resolve({
        'allocationId': 'delivery',
        'staffId': 'branch',
        'allocatedByName': 'Not recorded',
      });
      expect(record['allocatedByName'], 'Ana Cruz');
      expect(record['allocatedByAdminId'], 'ADM-0001');
      expect(record['branchCode'], 'BR-001');
      final unrelated = await metadata.resolve({
        'allocationId': 'delivery',
        'staffId': 'other-branch',
      });
      expect(unrelated['allocatedByName'], isNull);
      final unknown = await metadata.resolve({'staffId': 'branch'});
      expect(unknown['allocatedByName'], isNull);
    },
  );

  test('history finds a unique admin ID from a saved allocator name', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('staff_requests/admin-profile').set({
      'role': 'admin',
      'adminId': 'ADM-0002',
      'firstName': 'Ana',
      'lastName': 'Cruz',
    });
    final record = await AllocationHistoryMetadata(
      db,
    ).resolve({'allocatedByName': 'Ana Cruz'});
    expect(record['allocatedByName'], 'Ana Cruz');
    expect(record['allocatedByAdminId'], 'ADM-0002');
  });

  test('group uses allocator name from all delivery records', () {
    final group = groupAllocations([
      {'_id': 'a', 'deliveryId': 'delivery'},
      {'_id': 'b', 'deliveryId': 'delivery', 'allocatedByName': 'Ana Cruz'},
    ]).single;
    expect(group['allocatedByName'], 'Ana Cruz');
  });

  test('group preserves allocator admin ID', () {
    final group = groupAllocations([
      {'_id': 'a', 'deliveryId': 'delivery', 'allocatedByAdminId': 'ADM-0001'},
    ]).single;
    expect(group['allocatedByAdminId'], 'ADM-0001');
  });
}
