import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/return_batch_service.dart';
import 'package:sales_tracking/services/allocation_checklist_service.dart';
import 'package:sales_tracking/widgets/return_batch_cards.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReturnBatchService service;
  List<Map<String, dynamic>> selection() => [
    for (var i = 0; i < 2; i++)
      {
        'collection': 'completed_sales',
        'id': 'refund',
        'line': '$i',
        'quantity': 1,
        'branchId': 'b',
        'branchName': 'Dagupan',
        'itemDisplayId': 'CO-00${i + 1}',
      },
    {
      'collection': 'stock_adjustments',
      'id': 'reduce',
      'line': 'item',
      'quantity': 2,
      'branchId': 'b',
      'branchName': 'Dagupan',
      'itemDisplayId': 'BND-001',
    },
  ];
  Future<int> submit(String batch, [List<Map<String, dynamic>>? items]) =>
      service.submit(
        batchId: batch,
        items: items ?? selection(),
        actorId: 'staff',
        actorName: 'Warren User',
        actorPublicId: 'STF-001',
        scopeIds: ['b', 'staff'],
      );
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = ReturnBatchService(db);
    await db.doc('completed_sales/refund').set({
      'type': 'refund',
      'userId': 'staff',
      'branchId': 'b',
      'reason': 'Damaged packaging',
      'timestamp': Timestamp.now(),
      'items': [
        {'name': 'OG Cookies', 'variant': '', 'quantity': 1, 'price': 89},
        {'name': 'Red Velvet', 'quantity': 1, 'price': 99},
      ],
    });
    await db.doc('stock_adjustments/reduce').set({
      'type': 'bundle_stock_adjustment',
      'userId': 'staff',
      'branchId': 'b',
      'itemName': 'Bundle Cakes',
      'variant': '',
      'quantity': 2,
      'reason': 'Contaminated',
      'comment': 'Water entered the box',
      'unitPrice': 500,
    });
    await db.doc('staff_inventory/stock').set({'staffId': 'b', 'stock': 20});
  });
  test(
    'one batch preserves details and claims every source exactly once',
    () async {
      expect(await submit('batch'), 3);
      expect(await submit('batch'), 0);
      final records = (await db.collection('allocation_checklist').get()).docs;
      expect(records, hasLength(3));
      expect(records.map((d) => d.data()['batchId']).toSet(), {'batch'});
      // Fake Firestore resolves server timestamps per write. Group by batchId.
      expect(records.every((d) => d.data()['createdAt'] is Timestamp), isTrue);
      expect(
        (await db.doc('completed_sales/refund').get())
            .data()!['checklistReturnedQuantities'],
        {'0': 1, '1': 1},
      );
      expect(
        (await db.doc('staff_inventory/stock').get()).data()!['stock'],
        20,
      );
      final cookie = (await db.doc('allocation_checklist/batch_0').get())
          .data()!;
      expect(cookie['name'], 'OG Cookies');
      expect(cookie['itemDisplayId'], 'CO-001');
      expect(cookie['submittedByStaffId'], 'STF-001');
      expect(cookie['submittedByName'], 'Warren User');
      final reduced = (await db.doc('allocation_checklist/batch_2').get())
          .data()!;
      expect(reduced['name'], 'Bundle Cakes');
      expect(reduced['comment'], 'Water entered the box');
      expect(reduced['isBundle'], true);
      await AllocationChecklistService(
        db,
      ).confirmReturn('batch_0', actorId: 'admin', actorName: 'Admin');
      expect(
        (await db.doc('allocation_checklist/batch_0').get()).data()!['status'],
        'Return Completed',
      );
    },
  );
  test(
    'invalid item aborts the whole batch without claiming any source',
    () async {
      final items = selection();
      items.last['quantity'] = 99;
      await expectLater(submit('bad', items), throwsStateError);
      expect((await db.collection('allocation_checklist').get()).docs, isEmpty);
      expect(
        (await db.doc('completed_sales/refund').get())
            .data()!['checklistReturnedQuantities'],
        isNull,
      );
      expect(await submit('good'), 3);
    },
  );
  test(
    'new batch cannot re-return claimed stock or reuse a different payload',
    () async {
      await submit('batch');
      await expectLater(submit('duplicate'), throwsStateError);
      await expectLater(
        submit('batch', selection().take(1).toList()),
        throwsStateError,
      );
      final wrongBranch = selection();
      wrongBranch.first['branchId'] = 'elsewhere';
      await expectLater(submit('wrong', wrongBranch), throwsArgumentError);
      final duplicateLine = selection();
      duplicateLine.add({...duplicateLine.first});
      await expectLater(
        submit('duplicateLine', duplicateLine),
        throwsArgumentError,
      );
    },
  );
  for (final width in [360.0, 900.0]) {
    testWidgets(
      'batch card groups counts and opens searchable details at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await submit('batch');
        final docs = (await db.collection('allocation_checklist').get()).docs;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReturnBatchList(
                docs: docs,
                itemBuilder: (doc) => ReturnItemCard(data: doc.data()),
              ),
            ),
          ),
        );
        expect(find.text('Waiting Admin Confirmation'), findsOneWidget);
        expect(find.text('Categories (2)'), findsOneWidget);
        expect(find.text('Bundle (1)'), findsOneWidget);
        expect(find.text('Staff ID: STF-001'), findsOneWidget);
        await tester.pumpAndSettle();
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();
        expect(find.text('Item ID: CO-001'), findsOneWidget);
        expect(find.text('Source: Refund'), findsWidgets);
        expect(find.textContaining('Source: refund'), findsNothing);
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bundle'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bundle'));
        await tester.pumpAndSettle();
        expect(find.text('Bundle Cakes'), findsOneWidget);
        expect(find.text('OG Cookies'), findsNothing);
        expect(find.text('Source: Reduce items'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'missing');
        await tester.pumpAndSettle();
        expect(find.text('No matching items.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
