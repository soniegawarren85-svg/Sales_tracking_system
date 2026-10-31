import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/widgets/admin_item_editor.dart';
import 'package:sales_tracking/widgets/inventory_batches.dart';
import 'package:sales_tracking/services/branch_report_data.dart';

void main() {
  testWidgets('catalog edits refresh metadata in existing allocations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('cookies').set({
      'name': 'Cookies',
      'items': [
        {
          'id': 'pistachio',
          'name': 'Pistachio Dubai Chewy',
          'price': 100,
          'imageUrl': 'old-image.jpg',
          'costPrice': 40,
          'stock': 320,
          'expirationDate': '2026-12-31',
        },
      ],
    });
    await db.collection('staff_inventory').doc('branch-one').set({
      'staffId': 'branch-one',
      'sourceInventoryId': 'cookies',
      'items': [
        {
          'id': 'pistachio',
          'name': 'Pistachio Dubai Chewy',
          'price': 100,
          'imageUrl': 'old-image.jpg',
          'stock': 7,
        },
      ],
      'allocationHistory': ['unchanged'],
    });
    await db.collection('staff_inventory').doc('branch-two').set({
      'staffId': 'branch-two',
      'sourceInventoryId': 'cookies',
      'items': [
        {
          'id': 'pistachio',
          'name': 'Branch Pistachio',
          'branchNameOverride': 'Branch Pistachio',
          'price': 150,
          'branchPriceOverride': 150,
          'imageUrl': 'old-image.jpg',
          'stock': 4,
        },
      ],
    });
    final entry = AdminCatalogEntry(
      id: 'pistachio',
      name: 'Pistachio Dubai Chewy',
      type: 'Categories',
      source: {'id': 'cookies', 'name': 'Cookies'},
      images: const [],
      details: const {
        'id': 'pistachio',
        'name': 'Pistachio Dubai Chewy',
        'price': 100,
        'costPrice': 40,
        'stock': 320,
        'expirationDate': '2026-12-31',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            resizeToAvoidBottomInset: false,
            body: Center(
              child: TextButton(
                onPressed: () => showAdminItemEditor(
                  context,
                  entry: entry,
                  firestore: db,
                  upload: (_) async => null,
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Pistachio Dubai Chewy XL',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '120');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pumpAndSettle();

    final saved = await db.collection('sales_inventory').doc('cookies').get();
    final catalogItem = (saved.data()!['items'] as List).single as Map;
    expect(catalogItem['price'], 120);
    expect(catalogItem['name'], 'Pistachio Dubai Chewy XL');
    final allocated =
        (await db.collection('staff_inventory').doc('branch-one').get())
            .data()!;
    final allocatedItem = (allocated['items'] as List).single as Map;
    expect(allocatedItem['price'], 120);
    expect(allocatedItem['name'], 'Pistachio Dubai Chewy XL');
    expect(allocatedItem['stock'], 7);
    expect(allocated['allocationHistory'], ['unchanged']);
    final branchInventory = BranchReportData({
      'sales_inventory': [
        {'_id': 'cookies', ...saved.data()!},
      ],
      'staff_inventory': [
        {'_id': 'branch-one', ...allocated},
      ],
    }).currentInventory('branch-one', DateTime.now()).single;
    expect(branchInventory['name'], 'Pistachio Dubai Chewy XL');
    expect(branchInventory['price'], 120);
    final overridden =
        (await db.collection('staff_inventory').doc('branch-two').get())
            .data()!;
    final overriddenItem = (overridden['items'] as List).single as Map;
    expect(overriddenItem['price'], 150);
    expect(overriddenItem['branchPriceOverride'], 150);
    expect(overriddenItem['name'], 'Branch Pistachio');
    expect(overriddenItem['stock'], 4);
    expect(find.text('Inventory changes saved successfully.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch dialog shows individual cards and searches them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final batches = [
      {
        'quantity': 10,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 20)),
        'expirationDate': '2026-12-31',
        'costPrice': 40,
        'price': 99,
      },
      {
        'quantity': 5,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 22)),
        'expirationDate': '2027-01-15',
        'costPrice': 45,
        'price': 105,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMainInventoryBatches(context, {
                'name': 'Pistachio Dubai Chewy',
                'stock': 15,
                'stockBatches': batches,
                'costPrice': 40,
                'price': 99,
              }),
              child: const Text('Show batches'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show batches'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inventory-batch-card-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inventory-batch-card-1')),
      findsOneWidget,
    );
    expect(find.text('Filter by date'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'BATCH-002');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inventory-batch-card-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('inventory-batch-card-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch dialog filters cards by the selected date range', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final batches = [
      {'quantity': 10, 'createdAt': Timestamp.fromDate(yesterday)},
      {'quantity': 5, 'createdAt': Timestamp.fromDate(today)},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMainInventoryBatches(context, {
                'name': 'Pistachio Dubai Chewy',
                'stock': 15,
                'stockBatches': batches,
              }),
              child: const Text('Show batches'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show batches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter by date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inventory-batch-card-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('inventory-batch-card-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
