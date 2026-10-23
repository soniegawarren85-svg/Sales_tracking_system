import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_inventory_edit_dialog.dart';
import 'package:sales_tracking/widgets/inventory_batches.dart';
import 'package:sales_tracking/widgets/activity_feed.dart';
import 'package:sales_tracking/services/receipt_tax.dart';

void main() {
  testWidgets('save stays visible until persistence finishes and supports retry', (tester) async {
    var pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => BranchInventoryEditDialog(item: const {'name': 'Cookie', 'price': 99, 'stock': 130}, onSave: (_) {calls++; return pending.future;})), child: const Text('Edit'))))));
    await tester.tap(find.text('Edit')); await tester.pumpAndSettle();
    await tester.tap(find.text('Save')); await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(calls, 1);
    pending.completeError(StateError('Try again')); await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    pending = Completer<void>();
    await tester.tap(find.text('Save')); await tester.pump();
    expect(calls, 2);
    pending.complete(); await tester.pumpAndSettle();
    expect(find.byType(BranchInventoryEditDialog), findsNothing);
  });
  testWidgets('unbundle operation combines equal items and retains depleted history', (tester) async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 7; i++) {
      await db.doc('staff_inventory/part-$i').set({'staffId': 'branch', 'sourceInventoryId': 'cookies', 'name': 'Cookies', 'origin': 'unbundle', 'reconciliationId': 'request', 'assignedAt': Timestamp.now(), 'items': [{'id': 'pistachio', 'name': 'Pistachio', 'stock': 0, 'startingStock': 2, 'assignedStartingStock': 2}]});
    }
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showInventoryBatches(context, allocationId: 'part-0', scopeIds: ['branch'], database: db), child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile)); await tester.pumpAndSettle();
    expect(find.text('Pistachio - 0 remaining / 14 allocated'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Filter allocation dates'), findsOneWidget);
  });
  testWidgets(
    'allocation history displays short allocation and sold labels',
    (tester) async {
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
    },
  );
  testWidgets('recent activity defaults to today', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('activity_logs/old').set({'description': 'Yesterday edit', 'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)))});
    await db.doc('activity_logs/new').set({'description': 'Today edit', 'createdAt': Timestamp.now()});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecentActivityPanel(database: db))));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday edit'), findsNothing);
    expect(find.text('Today edit'), findsOneWidget);
    expect(find.byTooltip('Filter activity dates'), findsOneWidget);
  });
  test('tax labels use receipt snapshot', () {
    expect(receiptTaxLabel({'taxClassification': 'vat', 'tax': 0}), 'VAT');
    expect(receiptTaxLabel({'taxClassification': 'non_vat', 'tax': 0}), 'Non-VAT');
    expect(receiptTaxLabel({}), 'Not recorded');
    expect(receiptTaxAmount({'vatAmount': 12}), 12);
  });
}
