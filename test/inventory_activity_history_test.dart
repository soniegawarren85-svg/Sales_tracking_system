import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/inventory_activity_history.dart';

void main() {
  testWidgets('inventory activity history includes branch-linked sales', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('staff_requests').doc('cashier-1').set({
      'uid': 'cashier-1',
      'role': 'staff',
      'status': 'accepted',
      'branchIds': ['branch-1'],
    });
    await db.collection('completed_sales').doc('sale-1').set({
      'userId': 'cashier-1',
      'salesId': 'S-001',
      'status': 'completed',
      'timestamp': DateTime.now(),
      'staffName': 'Branch cashier',
      'items': [
        {
          'name': 'Pistachio Dubai Chewyy',
          'quantity': 2,
          'price': 140,
          'sourceInventoryId': 'category-1',
        },
      ],
    });
    final sales = await db
        .collection('completed_sales')
        .where('userId', whereIn: ['cashier-1'])
        .get();
    expect(sales.docs, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryActivityHistoryButton(
            branchId: 'branch-1',
            type: 'Categories',
            database: db,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Inventory activity history'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sold · Pistachio Dubai Chewyy'), findsOneWidget);
    expect(find.textContaining('Qty 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
