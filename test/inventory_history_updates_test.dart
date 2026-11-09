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
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
          connectivityChannel,
          (call) async => ['wifi'],
        );
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  test('unbundle history sums item quantities for the same source batch', () {
    final events = [
      for (var index = 0; index < 16; index++)
        {
          'time': DateTime(2026, 11, 8),
          'activity': 'Unbundle',
          'batchId': 'same-source-batch',
          'branchId': 'branch',
          'itemName': 'Pistachio Dubai Chewy',
          'qty': 4,
          'balance': 112 + 4 * (index + 1),
        },
    ];

    final grouped = aggregateInventoryHistoryEvents(events);

    expect(grouped, hasLength(1));
    expect(grouped.single['qty'], 64);
    expect(grouped.single['balance'], 176);
  });

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
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('14 unbundled · 0 sold · 0 remaining'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Filter allocation dates'), findsOneWidget);
    },
  );
  testWidgets('same source-batch unbundles render as one inventory batch', (
    tester,
  ) async {
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
    await db.doc('sales_inventory/cookies').set({
      'name': 'Cookies',
      'items': [
        {
          'id': 'pistachio',
          'publicId': 'PIS-001',
          'name': 'Pistachio Dubai Chewy',
          'stock': 0,
          'price': 100,
        },
      ],
    });
    for (var index = 0; index < 2; index++) {
      await db.doc('staff_inventory/unbundle-$index').set({
        'staffId': 'branch',
        'sourceInventoryId': 'cookies',
        'bundleActionId': 'legacy-unbundle-action',
        'name': 'Cookies',
        'origin': 'unbundle',
        'assignedAt': Timestamp.now(),
        'items': [
          {
            'id': 'pistachio',
            'publicId': 'PIS-001',
            'name': 'Pistachio Dubai Chewy',
            'stock': 4,
            'startingStock': 4,
            'assignedStartingStock': 4,
            'origin': 'unbundle',
            'price': 100,
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
                allocationId: 'unbundle-0',
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
    expect(find.text('8 unbundled · 0 sold · 8 remaining'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
  testWidgets('beverage batch history shows positive quantities and size', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final now = DateTime.now();
    final allocation = {
      'staffId': 'branch',
      'sourceInventoryId': 'coffee',
      'sourceCollection': 'coffee_products',
      'name': 'Dubai Chewy Smoothie',
      'isCoffee': true,
      'assignedAt': Timestamp.fromDate(now),
      'items': [
        {'id': 'coffee', 'name': 'Dubai Chewy Smoothie'},
      ],
    };
    await db.doc('staff_inventory/beverage').set(allocation);
    final report = BranchReportData({
      'staff_inventory': [
        {'_id': 'beverage', ...allocation},
      ],
      'coffee_products': [
        {'_id': 'coffee', 'name': 'Dubai Chewy Smoothie'},
      ],
      'completed_sales': [
        {
          'branchId': 'branch',
          'timestamp': Timestamp.fromDate(now),
          'items': [
            {
              'id': 'coffee',
              'name': 'Dubai Chewy Smoothie',
              'sourceInventoryId': 'coffee',
              'isCoffee': true,
              'coffeeSize': 'Small',
              'quantity': 2,
              'price': 100,
            },
            {
              'id': 'coffee',
              'name': 'Dubai Chewy Smoothie',
              'sourceInventoryId': 'coffee',
              'isCoffee': true,
              'coffeeSize': 'Large',
              'quantity': 1,
              'price': 140,
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
                allocationId: 'beverage',
                scopeIds: const ['branch'],
                database: db,
                reportData: report,
              ),
              child: const Text('Open beverage batches'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open beverage batches'));
    for (var index = 0; index < 30; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Balance'), findsNothing);
    expect(find.text('Opening balance'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('add-on batch history omits opening balance and balance', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final now = DateTime.now();
    final allocation = {
      'staffId': 'branch',
      'sourceInventoryId': 'chewy',
      'sourceCollection': 'coffee_addons',
      'name': 'Chewy',
      'isAddon': true,
      'assignedAt': Timestamp.fromDate(now),
    };
    await db.doc('staff_inventory/addon').set(allocation);
    final report = BranchReportData({
      'staff_inventory': [
        {'_id': 'addon', ...allocation},
      ],
      'coffee_addons': [
        {'_id': 'chewy', 'name': 'Chewy'},
      ],
      'completed_sales': [
        {
          'branchId': 'branch',
          'timestamp': Timestamp.fromDate(now),
          'items': [
            {
              'id': 'coffee',
              'name': 'Latte',
              'isCoffee': true,
              'quantity': 2,
              'price': 100,
              'addonName': 'Chewy',
              'addonId': 'chewy',
              'addonPriceDelta': 20,
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
                allocationId: 'addon',
                scopeIds: const ['branch'],
                database: db,
                reportData: report,
              ),
              child: const Text('Open add-on batches'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open add-on batches'));
    for (var index = 0; index < 30; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Balance'), findsNothing);
    expect(find.text('Size'), findsNothing);
    expect(find.text('Opening balance'), findsNothing);
    expect(find.text('2'), findsOneWidget);
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
        {
          'id': 'cookie',
          'name': 'Cookie',
          'stock': 0,
          'startingStock': 5,
          'assignedStartingStock': 5,
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

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Assigned'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Sold'), findsOneWidget);
    expect(find.textContaining('remaining'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
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
    await db.doc('activity_logs/unbundle').set({
      'action': 'bundle_unbundled',
      'description': 'Cashier unbundled bundle',
      'actorRole': 'staff',
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
    expect(find.text('Cashier unbundled bundle'), findsNothing);
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
