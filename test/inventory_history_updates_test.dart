import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_inventory_edit_dialog.dart';
import 'package:sales_tracking/widgets/inventory_batches.dart';
import 'package:sales_tracking/widgets/activity_feed.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/receipt_tax.dart';

void main() {
  testWidgets(
    'save stays visible until persistence finishes and supports retry',
    (tester) async {
      var pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => BranchInventoryEditDialog(
                    item: const {'name': 'Cookie', 'price': 99, 'stock': 130},
                    onSave: (_) {
                      calls++;
                      return pending.future;
                    },
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(calls, 1);
      pending.completeError(StateError('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      pending = Completer<void>();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(calls, 2);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BranchInventoryEditDialog), findsNothing);
    },
  );
  testWidgets(
    'unbundle operation combines equal items and retains depleted history',
    (tester) async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 7; i++) {
        await db.doc('staff_inventory/part-$i').set({
          'staffId': 'branch',
          'sourceInventoryId': 'cookies',
          'name': 'Cookies',
          'origin': 'unbundle',
          'reconciliationId': 'request',
          'assignedAt': Timestamp.now(),
          'items': [
            {
              'id': 'pistachio',
              'name': 'Pistachio',
              'stock': 0,
              'startingStock': 2,
              'assignedStartingStock': 2,
            },
          ],
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showInventoryBatches(
                  context,
                  allocationId: 'part-0',
                  scopeIds: ['branch'],
                  database: db,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(
        find.text('Pistachio - 0 remaining / 14 allocated'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Filter allocation dates'), findsOneWidget);
    },
  );
  testWidgets('batch history shows opening table and sold batch details', (
    tester,
  ) async {
    const connectivityChannel = MethodChannel(
      'dev.fluttercommunity.plus/connectivity',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      connectivityChannel,
      (call) async => ['none'],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        connectivityChannel,
        null,
      ),
    );
    final db = FakeFirebaseFirestore();
    final now = DateTime.now();
    await db.collection('sales_inventory').doc('cookies').set({
      'name': 'Cookies',
      'items': [
        {
          'id': 'cookie-1',
          'publicId': 'COO-01',
          'name': 'Chocolate cookie',
          'stock': 3,
          'startingStock': 4,
          'assignedStartingStock': 4,
          'price': 20,
          'costPrice': 10,
        },
      ],
    });
    await db.collection('staff_inventory').doc('cookie-allocation').set({
      'staffId': 'branch',
      'sourceInventoryId': 'cookies',
      'name': 'Cookies',
      'assignedAt': Timestamp.fromDate(now),
      'items': [
        {
          'id': 'cookie-1',
          'publicId': 'COO-01',
          'name': 'Chocolate cookie',
          'stock': 3,
          'startingStock': 4,
          'assignedStartingStock': 4,
          'price': 20,
          'costPrice': 10,
        },
      ],
    });
    await db.collection('completed_sales').doc('sale-1').set({
      'branchId': 'branch',
      'timestamp': Timestamp.fromDate(now),
      'items': [
        {
          'id': 'cookie-1',
          'itemId': 'cookie-1',
          'name': 'Chocolate cookie',
          'quantity': 1,
          'price': 20,
          'staffInventoryDocId': 'cookie-allocation',
        },
      ],
    });
    final reportData = BranchReportData({
      'branches': [
        {'_id': 'branch', 'name': 'SM Dagupan'},
      ],
      'sales_inventory': [
        {
          '_id': 'cookies',
          'name': 'Cookies',
          'items': [
            {
              'id': 'cookie-1',
              'publicId': 'COO-01',
              'name': 'Chocolate cookie',
              'stock': 3,
              'startingStock': 4,
              'assignedStartingStock': 4,
              'price': 20,
              'costPrice': 10,
            },
          ],
        },
      ],
      'staff_inventory': [
        {
          '_id': 'cookie-allocation',
          'staffId': 'branch',
          'sourceInventoryId': 'cookies',
          'name': 'Cookies',
          'assignedAt': Timestamp.fromDate(now),
          'items': [
            {
              'id': 'cookie-1',
              'publicId': 'COO-01',
              'name': 'Chocolate cookie',
              'stock': 3,
              'startingStock': 4,
              'assignedStartingStock': 4,
              'price': 20,
              'costPrice': 10,
            },
          ],
        },
      ],
      'completed_sales': [
        {
          '_id': 'sale-1',
          'branchId': 'branch',
          'timestamp': Timestamp.fromDate(now),
          'items': [
            {
              'id': 'cookie-1',
              'itemId': 'cookie-1',
              'name': 'Chocolate cookie',
              'quantity': 1,
              'price': 20,
              'staffInventoryDocId': 'cookie-allocation',
            },
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showInventoryBatches(
                context,
                allocationId: 'cookie-allocation',
                scopeIds: const ['branch'],
                itemId: 'cookie-1',
                database: db,
                reportData: reportData,
              ),
              child: const Text('Open batches'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open batches'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Opening / time'), findsOneWidget);
    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('1 sold'), findsNWidgets(2));
    expect(
      find.text('No inventory history for the selected dates.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('allocation history displays short allocation and sold labels', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('staff_inventory/cookies').set({
      'staffId': 'branch',
      'sourceInventoryId': 'cookies-source',
      'name': 'Cookies',
      'isBundle': false,
      'assignedAt': Timestamp.now(),
      'items': [
        {'id': 'cookie', 'name': 'Cookie', 'stock': 5},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showInventoryBatches(
                context,
                allocationId: 'cookies',
                scopeIds: ['branch'],
                database: db,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Allocation'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Sold'), findsOneWidget);
    expect(find.text('Allocation date'), findsNothing);
    expect(find.text('Sale date'), findsNothing);
  });
  testWidgets('recent activity defaults to today', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('activity_logs/old').set({
      'description': 'Yesterday edit',
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
    });
    await db.doc('activity_logs/new').set({
      'description': 'Today edit',
      'createdAt': Timestamp.now(),
    });
    await db.doc('activity_logs/admin').set({
      'description': 'Admin performance update',
      'actorRole': 'Admin',
      'createdAt': Timestamp.now(),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecentActivityPanel(database: db)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Yesterday edit'), findsNothing);
    expect(find.text('Today edit'), findsOneWidget);
    expect(find.text('Admin performance update'), findsNothing);
    expect(find.byTooltip('Filter activity dates'), findsOneWidget);
  });
  test('tax labels use receipt snapshot', () {
    expect(receiptTaxLabel({'taxClassification': 'vat', 'tax': 0}), 'VAT');
    expect(
      receiptTaxLabel({'taxClassification': 'non_vat', 'tax': 0}),
      'Non-VAT',
    );
    expect(receiptTaxLabel({}), 'Not recorded');
    expect(receiptTaxAmount({'vatAmount': 12}), 12);
  });
}
