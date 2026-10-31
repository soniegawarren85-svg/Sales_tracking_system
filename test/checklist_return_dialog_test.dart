import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/checklist_return_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('return dialog shows legacy product details newest first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'staff',
      'lastUserId': 'staff',
    });
    final db = FakeFirebaseFirestore();
    await db.doc('staff_requests/staff').set({
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Staff',
      'staffId': 'STF-001',
    });
    await db.doc('branches/branch').set({'name': 'Dagupan'});
    await db.doc('staff_inventory/allocation').set({
      'staffId': 'branch',
      'sourceInventoryId': 'inventory',
      'items': [
        {
          'id': 'CO-001',
          'publicId': 'CO-001',
          'name': 'Old product',
          'stock': 5,
        },
        {
          'id': 'CO-002',
          'publicId': 'CO-002',
          'name': 'New product',
          'stock': 5,
        },
      ],
    });
    for (final record in [
      {
        'salesId': 'old',
        'productName': 'Old product',
        'productId': 'CO-001',
        'timestamp': DateTime(2026, 10, 4),
      },
      {
        'salesId': 'new',
        'productName': 'New product',
        'productId': 'CO-002',
        'timestamp': DateTime(2026, 10, 5),
      },
    ]) {
      await db.doc('completed_sales/${record['salesId']}').set({
        'type': 'refund',
        'userId': 'staff',
        'branchId': 'branch',
        'timestamp': Timestamp.fromDate(record['timestamp'] as DateTime),
        'items': [
          {
            'name': 'Item',
            'productName': record['productName'],
            'productId': record['productId'],
            'quantity': 1,
          },
        ],
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            child: ChecklistReturnDialog(db: db, scopeIds: const ['branch']),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New product'), findsOneWidget);
    expect(find.text('Old product'), findsOneWidget);
    expect(find.text('Item ID: CO-002'), findsOneWidget);
    expect(find.text('Item ID: CO-001'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New product')).dy,
      lessThan(tester.getTopLeft(find.text('Old product')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
