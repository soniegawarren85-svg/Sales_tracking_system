import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/inventory_batches.dart';

void main() {
  testWidgets(
    'reconciliation requests have searchable pending and completed tabs',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      await db.doc('inventory_reconciliations/pending').set({
        'status': 'pending',
        'action': 'unbundle',
        'branchName': 'SM Dagupan',
        'name': 'Bundle Cakes',
        'quantity': 2,
        'submittedByName': 'Branch Staff',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 17)),
        'preview': {
          'loose': [
            {
              'name': 'Pistachio Dubai Chewy',
              'quantity': 2,
              'expirationDate': '2026-12-31',
            },
          ],
        },
      });
      await db.doc('inventory_reconciliations/approved').set({
        'status': 'approved',
        'action': 'unbundle',
        'branchName': 'SM Dagupan',
        'name': 'Older Bundle',
        'quantity': 1,
        'submittedByName': 'Branch Staff',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 16)),
        'preview': {
          'loose': [
            {'name': 'Red Velvet', 'quantity': 1},
            {'name': 'Red Velvet', 'quantity': 3},
          ],
        },
      });
      await db.doc('inventory_reconciliations/older-pending').set({
        'status': 'pending',
        'action': 'convert',
        'branchName': 'Other Branch',
        'name': 'Old Bundle',
        'quantity': 1,
        'submittedByName': 'Other Staff',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 10)),
        'preview': {'loose': <Map<String, dynamic>>[]},
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) =>
                Scaffold(body: ReconciliationRequestsButton(database: db)),
          ),
        ),
      );
      await tester.tap(find.text('Reconciliation'));
      await tester.pumpAndSettle();

      expect(find.text('Reconciliation requests'), findsOneWidget);
      expect(find.text('Pending Requests'), findsOneWidget);
      expect(find.text('Completed Requests'), findsOneWidget);
      expect(find.byTooltip('Filter by date range'), findsOneWidget);
      expect(find.textContaining('SM Dagupan • Bundle Cakes'), findsOneWidget);
      expect(find.textContaining('Older Bundle'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Pistachio Dubai');
      await tester.pumpAndSettle();
      expect(find.textContaining('Bundle Cakes'), findsOneWidget);
      expect(find.textContaining('Older Bundle'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Old Bundle');
      await tester.pumpAndSettle();
      expect(find.textContaining('Other Branch'), findsOneWidget);
      await tester.tap(find.byTooltip('Filter by date range'));
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .pop(
            DateTimeRange(
              start: DateTime(2026, 10, 17),
              end: DateTime(2026, 10, 17),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.textContaining('Other Branch'), findsNothing);
      expect(find.text('No matching pending requests'), findsOneWidget);
      tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.textContaining('Bundle Cakes'), findsOneWidget);
      await tester.tap(find.text('Completed Requests'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Older Bundle'), findsOneWidget);
      expect(find.textContaining('Bundle Cakes'), findsNothing);
      await tester.tap(find.textContaining('Older Bundle'));
      await tester.pumpAndSettle();
      expect(find.text('Red Velvet'), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
      expect(find.text('Items to unbundle • 4 total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('category batches only show the item whose batches were opened', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final assignedAt = Timestamp.fromDate(DateTime(2026, 10, 16));
    await db.doc('staff_inventory/category-allocation').set({
      'staffId': 'branch',
      'isBundle': false,
      'sourceInventoryId': 'cookies',
      'name': 'Cookies',
      'assignedAt': assignedAt,
      'items': [
        {'id': 'pistachio-id', 'name': 'Pistachio Dubai Chewy', 'stock': 0},
        {'id': 'og-id', 'name': 'Og Cakes', 'stock': 0},
      ],
    });
    await db.doc('staff_inventory/unbundle-pistachio').set({
      'staffId': 'branch',
      'isBundle': false,
      'sourceInventoryId': 'cookies',
      'name': 'Cookies',
      'origin': 'unbundle',
      'assignedAt': assignedAt,
      'items': [
        {
          'id': 'pistachio-id',
          'name': 'Pistachio Dubai Chewy',
          'stock': 2,
          'startingStock': 2,
          'origin': 'unbundle',
        },
      ],
    });
    await db.doc('staff_inventory/unbundle-og').set({
      'staffId': 'branch',
      'isBundle': false,
      'sourceInventoryId': 'cookies',
      'name': 'Cookies',
      'origin': 'unbundle',
      'assignedAt': assignedAt,
      'items': [
        {
          'id': 'og-id',
          'name': 'Og Cakes',
          'stock': 2,
          'startingStock': 2,
          'origin': 'unbundle',
        },
      ],
    });
    await db.doc('staff_inventory/additional-allocation').set({
      'staffId': 'branch',
      'sourceInventoryId': 'cookies',
      'name': 'Cookies',
      'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 17)),
      'items': [
        {'id': 'pistachio-id', 'name': 'Pistachio Dubai Chewy', 'stock': 10},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showInventoryBatches(
                context,
                allocationId: 'category-allocation',
                scopeIds: const ['branch'],
                itemId: 'pistachio-id',
                database: db,
              ),
              child: const Text('View batches'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('View batches'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Cookies - Pistachio Dubai Chewy - 2026-10-16'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('Cookies - Pistachio Dubai Chewy - 2026-10-17'),
      findsOneWidget,
    );
    expect(find.textContaining('Og Cakes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('allocation batch labels are short and ordered by allocation date', () {
    final labels = allocationBatchLabels([
      {
        '_id': 'random-later-id',
        'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 15)),
      },
      {
        '_id': 'random-earlier-id',
        'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 14)),
      },
    ]);

    expect(labels['random-earlier-id'], 'Batch - 001');
    expect(labels['random-later-id'], 'Batch - 002');
  });

  test(
    'category allocation batches aggregate stock without hiding batches',
    () {
      final items = aggregateCategoryAllocationItems([
        {
          'id': 'CO-004',
          'name': 'Pistachio Dubai Chewy',
          'stock': 90,
          'startingStock': 100,
          'assignedStartingStock': 100,
          'sourceDocId': 'original-allocation',
          'assignedAt': DateTime(2026, 10, 14),
        },
        {
          'id': 'CO-004',
          'name': 'Pistachio Dubai Chewy',
          'stock': 2,
          'startingStock': 2,
          'assignedStartingStock': 2,
          'sourceDocId': 'unbundle-record',
          'origin': 'unbundle',
          'unbundledQuantity': 2,
          'assignedAt': DateTime(2026, 10, 15),
        },
        {
          'id': 'CO-004',
          'name': 'Pistachio Dubai Chewy',
          'stock': 10,
          'startingStock': 10,
          'assignedStartingStock': 10,
          'sourceDocId': 'new-allocation',
          'assignedAt': DateTime(2026, 10, 16),
        },
      ]);

      expect(items, hasLength(1));
      expect(items.single['stock'], 102);
      expect(items.single['sourceDocId'], 'original-allocation');
      expect(items.single['allocatedAt'], DateTime(2026, 10, 16));
      expect(items.single.containsKey('origin'), isFalse);
      expect(items.single.containsKey('unbundledQuantity'), isFalse);
    },
  );

  test(
    'unbundle preview groups duplicate item names and totals quantities',
    () {
      final items = aggregateUnbundlePreviewItems([
        {
          'name': 'Pistachio Dubai Chewy',
          'quantity': 2,
          'expirationDate': '2026-12-31',
        },
        {'name': 'Og Cookies', 'quantity': 2, 'expirationDate': '2026-12-31'},
        {
          'name': 'Pistachio Dubai Chewy',
          'quantity': 2,
          'expirationDate': '2026-12-31',
        },
      ]);

      expect(items, hasLength(2));
      expect(
        items.singleWhere(
          (item) => item['name'] == 'Pistachio Dubai Chewy',
        )['quantity'],
        4,
      );
      expect(
        items.singleWhere((item) => item['name'] == 'Og Cookies')['quantity'],
        2,
      );
    },
  );

  test('allocation batch labels sort equal dates consistently', () {
    final labels = allocationBatchLabels([
      {'_id': 'batch-b', 'assignedAt': DateTime(2026, 10, 14)},
      {'_id': 'batch-a', 'assignedAt': DateTime(2026, 10, 14)},
    ]);

    expect(labels['batch-a'], 'Batch - 001');
    expect(labels['batch-b'], 'Batch - 002');
  });

  test('bundle instance numbers never show internal ids', () {
    expect(
      allocationInstanceNumber({
        'id': 'BND-opaque-delivery-id',
        'number': 5,
      }, 0),
      5,
    );
    expect(allocationInstanceNumber({'id': 'legacy-id'}, 2), 3);
    expect(
      allocationInstanceLabel({'id': 'BND-opaque-delivery-id', 'number': 1}, 0),
      'BND-ITM-001',
    );
  });

  test('updated bundle choices exclude returned and older batches', () {
    final selectedDate = DateTime(2026, 10, 1);
    final record = {
      '_id': 'staff-allocation',
      'bundleCount': 2,
      'bundleInstances': [
        {
          'id': 'returned',
          'number': 1,
          'batchId': 'returned-batch',
          'assignedAt': DateTime(2026, 10, 2),
          'status': 'returned',
        },
        {
          'id': 'old-available',
          'number': 2,
          'batchId': 'old-batch',
          'assignedAt': DateTime(2026, 9, 30),
          'status': 'available',
        },
      ],
    };

    expect(
      hasAvailableAllocationBatchAfter(
        record,
        'staff-allocation',
        selectedDate,
      ),
      isFalse,
    );

    record['bundleInstances'] = [
      ...(record['bundleInstances'] as List),
      {
        'id': 'new-available',
        'number': 3,
        'batchId': 'new-batch',
        'assignedAt': DateTime(2026, 10, 2),
        'status': 'available',
      },
    ];
    expect(
      hasAvailableAllocationBatchAfter(
        record,
        'staff-allocation',
        selectedDate,
      ),
      isTrue,
    );
  });

  test('combined allocation document labels each nested batch separately', () {
    final record = {
      '_id': 'staff-bundle',
      'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 15)),
      'bundleCount': 2,
      'bundleInstances': [
        {
          'id': 'older',
          'batchId': 'delivery-old',
          'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 14)),
          'status': 'available',
        },
        {
          'id': 'newer',
          'batchId': 'delivery-new',
          'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 15)),
          'status': 'available',
        },
      ],
    };
    final labels = allocationInstanceBatchLabels([record]);

    expect(labels['delivery-old'], 'Batch - 001');
    expect(labels['delivery-new'], 'Batch - 002');
    expect(allocationInstanceBatches(record, 'staff-bundle'), hasLength(2));
  });

  test(
    'bundle batch dialog list includes only currently available instances',
    () {
      final record = {
        '_id': 'staff-bundle',
        'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 15)),
        'bundleCount': 4,
        'bundleInstances': [
          {
            'id': 'available',
            'batchId': 'available-batch',
            'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'status': 'available',
          },
          {
            'id': 'returned',
            'batchId': 'returned-batch',
            'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 14)),
            'status': 'returned',
          },
          {
            'id': 'converted',
            'batchId': 'converted-batch',
            'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 13)),
            'status': 'reconciled',
          },
          {
            'id': 'pending-return',
            'batchId': 'pending-return-batch',
            'assignedAt': Timestamp.fromDate(DateTime(2026, 10, 12)),
            'status': 'return_pending',
          },
        ],
      };

      final batches = allocationInstanceBatches(record, 'staff-bundle');

      expect(batches.map((batch) => batch['batchId']), ['available-batch']);
      expect(
        (batches.single['instances'] as List).map((instance) => instance['id']),
        ['available'],
      );
    },
  );
}
