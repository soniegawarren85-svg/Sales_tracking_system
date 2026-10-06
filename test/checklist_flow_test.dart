import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/allocation_checklist_service.dart';
import 'package:sales_tracking/services/checklist_status.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AllocationChecklistService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = AllocationChecklistService(db);
    await db.doc('allocation_checklist/delivery').set({
      'kind': 'incoming',
      'status': ChecklistStatus.awaiting,
      'staffId': 'branch',
      'staffName': 'Branch A',
      'targetDocId': 'stock',
      'sourceInventoryId': 'central',
      'allocatedBy': 'admin',
      'allocatedByName': 'Admin',
      'createdAt': Timestamp.now(),
      'items': [
        {'id': 'cookie', 'name': 'Cookie', 'stock': 5},
      ],
    });
  });

  Future<bool> submit({
    String id = 'return',
    int count = 2,
    String collection = 'staff_inventory',
    String source = 'stock',
    String line = 'cookie',
    String branch = 'branch',
  }) => service.submitReturn(
    requestId: id,
    sourceCollection: collection,
    sourceId: source,
    lineKey: line,
    count: count,
    reason: 'Damaged Item',
    actorId: 'staff',
    actorName: 'Staff A',
    scopeIds: ['staff', 'branch'],
    branchId: branch,
    branchName: 'Branch A',
  );
  Future<void> receive() async {
    await service.decide(
      'delivery',
      accept: true,
      staffId: 'staff',
      actorName: 'Staff A',
      scopeIds: ['branch'],
    );
  }

  test(
    'delivery, issue, staff receipt, return, discrepancy, admin receipt synchronize and audit',
    () async {
      final observed = <String>[];
      final sub = db
          .doc('allocation_checklist/delivery')
          .snapshots()
          .listen((d) => observed.add('${d.data()?['status']}'));
      await service.report(
        'delivery',
        admin: false,
        actorId: 'staff',
        actorName: 'Staff A',
        reason: 'Check packing',
        scopeIds: ['branch'],
      );
      expect((await db.doc('staff_inventory/stock').get()).exists, false);
      await receive();
      final incoming = (await db.doc('allocation_checklist/delivery').get())
          .data()!;
      expect(incoming['status'], ChecklistStatus.received);
      expect(incoming['confirmedBy'], 'staff');
      expect(incoming['confirmedAt'], isA<Timestamp>());
      expect((incoming['reports'] as Map).length, 1);
      expect(
        await service.decide('delivery', accept: true, staffId: 'staff'),
        false,
      );
      expect(await submit(), true);
      expect(await submit(), false);
      final stock = (await db.doc('staff_inventory/stock').get()).data()!;
      expect((stock['items'] as List).single['stock'], 3);
      final returns = (await db.doc('allocation_checklist/return').get())
          .data()!;
      expect(returns['submittedBy'], 'staff');
      expect(returns['createdAt'], isA<Timestamp>());
      expect(ChecklistStatus.pending(returns, admin: true), true);
      expect(ChecklistStatus.pending(returns, admin: false), false);
      await service.report(
        'return',
        admin: true,
        actorId: 'admin',
        actorName: 'Admin',
        reason: 'One missing',
        scopeIds: [],
      );
      expect(
        (await db.doc('allocation_checklist/return').get()).data()!['status'],
        ChecklistStatus.discrepancy,
      );
      expect(
        await service.confirmReturn(
          'return',
          actorId: 'admin',
          actorName: 'Admin',
        ),
        true,
      );
      expect(
        await service.confirmReturn(
          'return',
          actorId: 'admin',
          actorName: 'Admin',
        ),
        false,
      );
      final completed = (await db.doc('allocation_checklist/return').get())
          .data()!;
      expect(completed['status'], ChecklistStatus.completed);
      expect(completed['confirmedBy'], 'admin');
      expect(completed['confirmedAt'], isA<Timestamp>());
      expect(ChecklistStatus.pending(completed, admin: true), false);
      await Future<void>.delayed(Duration.zero);
      expect(observed, contains(ChecklistStatus.received));
      await sub.cancel();
    },
  );
  test(
    'received timestamp records staff acceptance, not allocation date',
    () async {
      final allocationDate = DateTime(2020, 1, 2, 9);
      await db.doc('allocation_checklist/delivery').update({
        'createdAt': Timestamp.fromDate(allocationDate),
      });
      final acceptedAfter = DateTime.now();

      await service.decide(
        'delivery',
        accept: true,
        staffId: 'staff',
        actorName: 'Staff A',
        scopeIds: ['branch'],
      );

      final received = (await db.doc('allocation_checklist/delivery').get())
          .data()!;
      final receivedAt = (received['confirmedAt'] as Timestamp).toDate();
      expect(received['createdAt'], Timestamp.fromDate(allocationDate));
      expect(receivedAt.isBefore(acceptedAfter), isFalse);
      expect(
        receivedAt.isAfter(DateTime.now().add(const Duration(seconds: 1))),
        isFalse,
      );
      expect(received['decidedAt'], isA<Timestamp>());
    },
  );

  test(
    'reject over-return, wrong scope and repeated reports after completion',
    () async {
      await expectLater(
        service.decide(
          'delivery',
          accept: true,
          staffId: 'other',
          scopeIds: ['other'],
        ),
        throwsStateError,
      );
      await receive();
      await expectLater(submit(count: 6), throwsStateError);
      await expectLater(submit(branch: 'other'), throwsArgumentError);
      expect((await db.doc('allocation_checklist/return').get()).exists, false);
      expect(
        await service.report(
          'delivery',
          admin: false,
          actorId: 'staff',
          actorName: 'Staff',
          reason: 'Late',
          scopeIds: ['branch'],
        ),
        false,
      );
    },
  );

  test(
    'refund and reduction returns claim recorded quantities without double stock deduction',
    () async {
      await receive();
      for (final collection in ['completed_sales', 'stock_adjustments']) {
        final refund = collection == 'completed_sales';
        await db.collection(collection).doc('record').set({
          'userId': 'staff',
          'branchId': 'branch',
          'type': refund ? 'refund' : 'reduction',
          'itemName': 'Cookie',
          'quantity': 3,
          'reason': 'Crushed packaging',
          'staffName': 'Original Staff',
          'salesId': 'REF-001',
          'items': [
            {'name': 'Cookie', 'quantity': 3},
          ],
        });
        expect(
          await submit(
            id: collection,
            collection: collection,
            source: 'record',
            line: refund ? '0' : 'item',
          ),
          true,
        );
        final returned =
            (await db.doc('allocation_checklist/$collection').get()).data()!;
        expect(returned['originalReason'], 'Crushed packaging');
        expect(returned['sourceStaffName'], 'Original Staff');
        expect(returned['sourceReceiptId'], 'REF-001');
        expect(returned['sourceItem']['quantity'], 3);
        await expectLater(
          submit(
            id: '${collection}2',
            collection: collection,
            source: 'record',
            line: refund ? '0' : 'item',
          ),
          throwsStateError,
        );
      }
      expect(
        ((await db.doc('staff_inventory/stock').get()).data()!['items'] as List)
            .single['stock'],
        5,
      );
    },
  );

  test(
    'bundle returns reserve instances once and cannot return sold bundles',
    () async {
      await db.doc('staff_inventory/stock').set({
        'staffId': 'branch',
        'name': 'Bundle',
        'isBundle': true,
        'bundleCount': 2,
        'bundleInstances': [
          {'id': 'a', 'status': 'available'},
          {'id': 'b', 'status': 'sold'},
        ],
      });
      await expectLater(submit(count: 2), throwsStateError);
      await submit(count: 1);
      final data = (await db.doc('staff_inventory/stock').get()).data()!;
      expect(
        (data['bundleInstances'] as List).first['status'],
        'return_pending',
      );
      expect((data['bundleInstances'] as List).last['status'], 'sold');
      await expectLater(submit(id: 'again', count: 1), throwsStateError);
    },
  );

  test('legacy delivery statuses still map to the same workflow', () {
    expect(
      ChecklistStatus.label({'status': 'pending'}),
      ChecklistStatus.awaiting,
    );
    expect(
      ChecklistStatus.label({'status': 'accepted'}),
      ChecklistStatus.received,
    );
    expect(ChecklistStatus.incomingOpen({'status': 'declined'}), false);
    expect(
      ChecklistStatus.incomingOpen({'status': ChecklistStatus.issue}),
      true,
    );
  });
}
