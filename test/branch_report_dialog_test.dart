import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';

void main() {
  BranchReportData fixture() {
    final now = DateTime.now();
    return BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'Sm dagupan'},
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
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'GCash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'GCash'));
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
    final dynamic state = tester.state(find.byType(BranchReportDialog));
    final Uint8List bytes =
        await tester.runAsync(
          () async => await state.buildPdf(data) as Uint8List,
        ) ??
        Uint8List(0);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'daily analytics use all 24 hours and refund legend opens item details',
    (tester) async {
      final data = fixture();
      final now = DateTime.now();
      data.collections['branches']!.single['openingMinutes'] = 480;
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
