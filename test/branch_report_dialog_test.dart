import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';

void main() {
  test('made-to-order report rows omit remaining quantity', () {
    for (final type in ['Beverages', 'Add-on', 'Add-ons']) {
      expect(
        branchItemActivitySummary({
          'type': type,
          'sold': 0,
          'added': 1,
          'reduce': 0,
          'remaining': -27,
        }),
        'Sold 0 • Allocated 1 • Reduced 0',
      );
    }
    expect(
      branchItemActivitySummary({
        'type': 'Categories',
        'sold': 2,
        'added': 3,
        'reduce': 1,
        'remaining': 4,
      }),
      'Sold 2 • Allocated 3 • Reduced 1 • Remaining 4',
    );
  });

  BranchReportData fixture() {
    final now = DateTime.now();
    return BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'Sm dagupan'},
        {'_id': 'voided', 'name': 'Sm Urdaneta', 'isVoided': true},
      ],
      'staff_cash_drawer': [
        {'_id': 'b', 'dailyOpeningCash': 1200},
      ],
      'completed_sales': [
        {
          '_id': 'cash',
          'salesId': 'S-1',
          'branchId': 'b',
          'timestamp': now,
          'paymentMode': 'Cash',
          'total': 100,
          'items': [
            {'itemId': 'v', 'name': 'Cookie', 'price': 50, 'quantity': 2},
          ],
        },
        {
          '_id': 'gcash',
          'salesId': 'S-2',
          'branchId': 'b',
          'timestamp': now,
          'paymentMode': 'GCash',
          'total': 150,
          'items': [
            {'itemId': 'v', 'name': 'Cookie', 'price': 50, 'quantity': 3},
          ],
        },
      ],
    });
  }

  testWidgets('branch dialog fits narrow screens and filters receipt payment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = fixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(
            branchId: 'b',
            branchName: 'Sm dagupan',
            reportData: Future.value(data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final viewAll = find.text('View all receipts');
    await tester.ensureVisible(viewAll);
    await tester.pumpAndSettle();
    await tester.tap(viewAll);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'GCash');
    await tester.pumpAndSettle();
    expect(find.text('S-2'), findsOneWidget);
    expect(find.text('S-1'), findsNothing);
    final dynamic state = tester.state(find.byType(BranchReportDialog));
    final Uint8List bytes =
        await tester.runAsync(
          () async => await state.buildPdf(data) as Uint8List,
        ) ??
        Uint8List(0);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily beverage report groups item metadata and size costs', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final sizes = [
      {'name': 'Small', 'priceDelta': 0, 'costPrice': 10},
      {'name': 'Medium', 'priceDelta': 20, 'costPrice': 20},
      {'name': 'Large', 'priceDelta': 40, 'costPrice': 30},
    ];
    final data = BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'SM Dagupan'},
      ],
      'coffee_products': [
        {
          '_id': 'coffee-source',
          'coffeeId': 'COF-001',
          'publicId': 'COF-001',
          'name': 'Latte',
          'basePrice': 100,
          'sizes': sizes,
        },
      ],
      'staff_inventory': [
        {
          '_id': 'coffee-allocation',
          'staffId': 'b',
          'sourceInventoryId': 'coffee-source',
          'publicId': 'COF-001',
          'name': 'Latte',
          'isCoffee': true,
          'sizes': sizes,
          'assignedAt': today,
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(
            branchId: 'b',
            branchName: 'SM Dagupan',
            reportData: Future.value(data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Allocated items'),
      300,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Beverages'));
    await tester.pumpAndSettle();

    expect(find.text('Latte'), findsOneWidget);
    expect(find.text('COF-001'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('₱10.00'), findsOneWidget);
    expect(find.text('₱20.00'), findsOneWidget);
    expect(find.text('₱30.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-branch report renders pie and generates printable PDF', (
    tester,
  ) async {
    final data = fixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(reportData: Future.value(data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Branch sales report'), findsOneWidget);
    expect(find.text('Sm dagupan'), findsOneWidget);
    expect(find.text('Sm Urdaneta'), findsNothing);
    final dynamic state = tester.state(find.byType(BranchReportDialog));
    final Uint8List bytes =
        await tester.runAsync(
          () async => await state.buildPdf(data) as Uint8List,
        ) ??
        Uint8List(0);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily sales summary shows reduced count and total loss', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'SM Dagupan'},
      ],
      'stock_adjustments': [
        {
          '_id': 'reduce-1',
          'branchId': 'b',
          'createdAt': DateTime.now(),
          'quantity': 1,
          'lossAmount': 100,
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(
            branchId: 'b',
            branchName: 'SM Dagupan',
            reportData: Future.value(data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sales summary'));
    await tester.pumpAndSettle();

    expect(find.text('Reduced items'), findsOneWidget);
    expect(find.text('Total loss'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'daily analytics use all 24 hours and refund legend opens item details',
    (tester) async {
      final data = fixture();
      final now = DateTime.now();
      data.collections['branches']!.firstWhere(
        (branch) => branch['_id'] == 'b',
      )['openingMinutes'] = 480;
      for (final sale in data.collections['completed_sales']!) {
        sale['timestamp'] = DateTime(now.year, now.month, now.day, 12);
      }
      data.collections['completed_sales']!.add({
        '_id': 'refund',
        'salesId': 'R-1',
        'branchId': 'b',
        'type': 'refund',
        'timestamp': DateTime(now.year, now.month, now.day, 12),
        'total': -50,
        'items': [
          {'itemId': 'v', 'name': 'Cookie', 'quantity': 1, 'price': 50},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BranchReportDialog(
              branchId: 'b',
              branchName: 'Sm dagupan',
              reportData: Future.value(data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(BranchReportDialog));
      final chart = state.bars(data);
      expect(chart.$4.first, '12AM');
      expect(chart.$4.last, '11PM');
      expect(chart.$4.length, 24);
      final legend = find.widgetWithText(ActionChip, 'Refund');
      for (
        var attempt = 0;
        attempt < 12 && legend.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(legend);
      await tester.pumpAndSettle();
      await tester.tap(legend);
      await tester.pumpAndSettle();
      expect(find.text('View refund items'), findsNothing);
      await tester.ensureVisible(find.text('View all refund items'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View all refund items'));
      await tester.pumpAndSettle();
      expect(find.text('View refund items'), findsOneWidget);
      expect(find.text('R-1'), findsOneWidget);
      await tester.tap(find.byTooltip('Close receipts'));
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 12 && find.text('Top 10 Refunds').evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(find.text('Top 10 Refunds'), findsOneWidget);
      expect(find.text('Low 10 Refunds'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
