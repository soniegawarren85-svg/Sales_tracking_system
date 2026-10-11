import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/widgets/staff_performance_panel.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';
import 'package:sales_tracking/services/branch_report_data.dart';

void main() {
  testWidgets('report exports CSV and accepts a custom multi-day range', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(
            branchId: 'b',
            branchName: 'SM Dagupan',
            reportData: Future.value(
              BranchReportData({
                'branches': [
                  {'_id': 'b', 'name': 'SM Dagupan'},
                ],
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save CSV File'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Save CSV File'), findsOneWidget);
    expect(find.text('Print report'), findsOneWidget);
    expect(find.text('Save PDF'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month).first);
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    final selected = DateTimeRange(
      start: today.subtract(const Duration(days: 3)),
      end: today,
    );
    tester.state<NavigatorState>(find.byType(Navigator).last).pop(selected);
    await tester.pumpAndSettle();
    expect(find.text('SM Dagupan Date range Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inventory switches branches and searches warning status', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final now = DateTime.now();
    final expiry = now.add(const Duration(days: 4)).toIso8601String();
    final item = {
      'id': 'cookie',
      'publicId': 'CO-1',
      'name': 'Cookie',
      'stock': 150,
      'price': 50,
      'costPrice': 25,
      'expirationDate': expiry,
    };
    await db.collection('branches').doc('b').set({'name': 'SM Dagupan'});
    await db.collection('sales_inventory').doc('cat').set({
      'name': 'Cookies',
      'items': [item],
    });
    await db.collection('staff_inventory').doc('allocation').set({
      'staffId': 'b',
      'sourceInventoryId': 'cat',
      'assignedAt': Timestamp.fromDate(now),
      'items': [
        {...item, 'stock': 40, 'startingStock': 40},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminCatalog(
            firestore: db,
            pinnedControls: true,
            type: 'Categories',
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Low stock: 0'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SM Dagupan').last);
    await tester.pumpAndSettle();
    expect(find.text('Low stock: 1'), findsNothing);
    expect(find.text('Near expiry: 1'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'low stock');
    await tester.pumpAndSettle();
    expect(find.text('Cookie'), findsOneWidget);
    expect(find.text('Low stock: 1'), findsOneWidget);
    expect(find.text('Near expiry: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main branch').last);
    await tester.pumpAndSettle();
    expect(find.text('Low stock: 0'), findsOneWidget);
  });

  testWidgets('staff dropdown stays fixed while only performance scrolls', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('b').set({
      'name': 'SM Dagupan',
      'staffIds': ['one', 'two'],
    });
    for (final id in ['one', 'two']) {
      await db.collection('staff_requests').doc(id).set({
        'firstName': id,
        'lastName': 'Cashier',
        'uid': id,
        'staffId': id,
      });
    }
    for (var i = 0; i < 12; i++) {
      await db.collection('completed_sales').doc('$i').set({
        'branchId': 'b',
        'userId': 'one',
        'timestamp': Timestamp.now(),
        'total': 50,
        'items': [
          {'name': 'Cookie', 'price': 50, 'quantity': 1},
        ],
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffPerformancePanel(branchId: 'b', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<String>);
    final initialPosition = tester.getTopLeft(dropdown);
    final summary = find.byKey(const ValueKey('staff-performance-summary'));
    final summaryPosition = tester.getTopLeft(summary);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(dropdown), initialPosition);
    expect(tester.getTopLeft(summary), summaryPosition);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('two Cashier').last);
    await tester.pumpAndSettle();
    expect(
      find.text('No orders recorded for this staff in this date range.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
