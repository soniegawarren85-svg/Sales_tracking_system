import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';
import 'package:sales_tracking/services/branch_report_data.dart';

void main() {
  testWidgets('inventory scroll keeps search and category controls fixed', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('cat').set({
      'name': 'Cookies',
      'items': [
        for (var i = 0; i < 30; i++)
          {
            'id': 'CO-$i',
            'name': 'Cookie $i',
            'price': 99,
            'stock': 10,
            'expirationDate': '2099-12-31',
          },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: AdminCatalog(
              pinnedControls: true,
              type: 'Categories',
              firestore: db,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = tester.getTopLeft(find.byType(TextField));
    final category = tester.getTopLeft(
      find.widgetWithText(ChoiceChip, 'Cookies'),
    );
    final first = tester.getTopLeft(find.text('Cookie 0'));
    await tester.drag(
      find.byKey(const ValueKey('inventory-table-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(TextField)), search);
    expect(
      tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Cookies')),
      category,
    );
    expect(tester.getTopLeft(find.text('Cookie 0')).dy, lessThan(first.dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets('inventory fits $width without horizontal scroll', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      await db.collection('sales_inventory').doc('cat').set({
        'name': 'Cookies',
        'items': [
          {
            'id': 'COO-001',
            'name': 'Pistachio Dubai Chewy Cookie',
            'price': 99,
            'stock': 300,
            'expirationDate': '2099-12-31',
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AdminCatalog(
                  type: 'Categories',
                  firestore: db,
                  onOpen: (_) {},
                  onVoid: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pistachio Dubai Chewy Cookie'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('beverages show size totals and a separate add-ons table', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('coffee_products').doc('coffee').set({
      'name': 'Latte',
      'basePrice': 100,
      'sizes': [
        {'name': 'Small', 'priceDelta': 10},
      ],
    });
    await db.collection('coffee_addons').doc('addon').set({
      'name': 'Pearls',
      'priceDelta': 20,
      'expirationDate': '2099-12-31',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminCatalog(
              type: 'Beverages',
              firestore: db,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('₱110.00'), findsOneWidget);
    expect(find.text('Pearls'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Add-ons'));
    await tester.pumpAndSettle();
    expect(find.text('Pearls'), findsOneWidget);
    expect(find.text('Latte'), findsNothing);
    expect(find.byType(Table), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('starting fund and drawer appear only for a single day', (
    tester,
  ) async {
    final data = BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'Branch'},
      ],
      'staff_cash_drawer': [
        {'_id': 'b', 'dailyOpeningCash': 1200},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(
            branchId: 'b',
            branchName: 'Branch',
            reportData: Future.value(data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Starting fund'), findsOneWidget);
    expect(find.text('Cash drawer'), findsOneWidget);
    for (final period in ['Week', 'Month', 'Year', 'Day']) {
      final chip = find.widgetWithText(ChoiceChip, period);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.text('Starting fund'),
        period == 'Day' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Cash drawer'),
        period == 'Day' ? findsOneWidget : findsNothing,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
