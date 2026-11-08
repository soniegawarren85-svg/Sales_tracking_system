import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/low_stock_reports.dart';
import 'package:sales_tracking/widgets/staff_inventory_badge.dart';

void main() {
  test('active branch admin is recognized through branch membership', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('branch-1').set({
      'staffIds': ['admin-1'],
    });
    await firestore.collection('staff_requests').doc('admin-1').set({
      'role': 'admin',
      'status': 'accepted',
    });

    expect(
      await branchHasActiveAdmin(firestore: firestore, branchIds: ['branch-1']),
      isTrue,
    );
  });

  test('staff checklist badge is hidden for branches with an admin', () {
    final rows = [
      {
        '_id': 'checklist-1',
        'status': 'Awaiting Confirmation',
        'kind': 'incoming',
        'batchId': 'batch-1',
      },
    ];

    expect(staffInventoryChecklistBadgeCount(rows, branchAdminExists: true), 0);
    expect(
      staffInventoryChecklistBadgeCount(rows, branchAdminExists: false),
      1,
    );
  });

  test('staff checklist badge counts unique pending batches only', () {
    final rows = [
      {
        '_id': 'checklist-1',
        'status': 'Awaiting Confirmation',
        'kind': 'incoming',
        'batchId': 'batch-1',
      },
      {
        '_id': 'checklist-2',
        'status': 'pending',
        'kind': 'incoming',
        'batchId': 'batch-1',
      },
      {
        '_id': 'checklist-3',
        'status': 'Received',
        'kind': 'incoming',
        'batchId': 'batch-2',
      },
    ];

    expect(
      staffInventoryChecklistBadgeCount(rows, branchAdminExists: false),
      1,
    );
  });
}
