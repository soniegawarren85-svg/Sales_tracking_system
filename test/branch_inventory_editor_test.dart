import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/branch_inventory_editor.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_inventory_monitor.dart';

void main() {
  testWidgets('branch inventory edit action follows admin permission', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'admin-user',
    });
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-user').set({
      'role': 'admin',
      'branchIds': ['branch-one'],
    });
    await firestore.collection('admin_settings').doc('transactions').set({
      'branchSettings': {
        'branch-one': {'adminAllowInventoryEdits': false},
      },
    });
    await firestore.collection('sales_inventory').doc('catalog-item').set({
      'items': [
        {'id': 'internal-item', 'publicId': 'ITEM-1', 'name': 'Cookie'},
      ],
    });
    await firestore.collection('staff_inventory').doc('branch-one-item').set({
      'staffId': 'branch-one',
      'sourceInventoryId': 'catalog-item',
      'items': [
        {'id': 'internal-item', 'publicId': 'ITEM-1', 'stock': 4, 'price': 10},
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchInventoryMonitor(
            branchId: 'branch-one',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit branch inventory'), findsNothing);
    expect(find.byTooltip('View history'), findsOneWidget);

    await firestore.collection('admin_settings').doc('transactions').set({
      'branchSettings': {
        'branch-one': {'adminAllowInventoryEdits': true},
      },
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit branch inventory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('editing inventory updates only matching branch allocations', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('sales_inventory').doc('catalog-item').set({
      'items': [
        {'id': 'internal-item', 'publicId': 'ITEM-1', 'name': 'Original'},
      ],
    });
    await firestore.collection('staff_inventory').doc('branch-one-a').set({
      'staffId': 'branch-one',
      'sourceInventoryId': 'catalog-item',
      'items': [
        {
          'id': 'internal-item',
          'publicId': 'ITEM-1',
          'name': 'Original',
          'stock': 5,
          'price': 10,
        },
      ],
    });
    await firestore.collection('staff_inventory').doc('branch-one-b').set({
      'staffId': 'branch-one',
      'sourceInventoryId': 'catalog-item',
      'items': [
        {
          'id': 'internal-item',
          'publicId': 'ITEM-1',
          'name': 'Original',
          'stock': 2,
          'price': 10,
        },
      ],
    });
    await firestore.collection('staff_inventory').doc('branch-two').set({
      'staffId': 'branch-two',
      'sourceInventoryId': 'catalog-item',
      'items': [
        {
          'id': 'internal-item',
          'publicId': 'ITEM-1',
          'name': 'Original',
          'stock': 9,
          'price': 10,
        },
      ],
    });

    await updateBranchInventoryItem(
      firestore: firestore,
      branchId: 'branch-one',
      item: {'id': 'ITEM-1', 'sourceInventoryId': 'catalog-item'},
      name: 'Branch special',
      price: 15,
      stock: 6,
    );

    final first =
        (await firestore
                    .collection('staff_inventory')
                    .doc('branch-one-a')
                    .get())
                .data()!['items'][0]
            as Map;
    final second =
        (await firestore
                    .collection('staff_inventory')
                    .doc('branch-one-b')
                    .get())
                .data()!['items'][0]
            as Map;
    final otherBranch =
        (await firestore.collection('staff_inventory').doc('branch-two').get())
                .data()!['items'][0]
            as Map;
    final central =
        (await firestore
                .collection('sales_inventory')
                .doc('catalog-item')
                .get())
            .data()!;

    expect((first['stock'] as num) + (second['stock'] as num), 6);
    expect(first['name'], 'Branch special');
    expect(first['price'], 15);
    expect(first['branchNameOverride'], 'Branch special');
    expect(second['branchPriceOverride'], 15);
    expect(otherBranch['stock'], 9);
    expect(otherBranch['branchNameOverride'], isNull);
    expect(central['items'][0]['name'], 'Original');

    final reportData = BranchReportData({
      'sales_inventory': [
        {'_id': 'catalog-item', ...central},
      ],
      'staff_inventory': [
        {
          '_id': 'branch-one-a',
          ...(await firestore
                  .collection('staff_inventory')
                  .doc('branch-one-a')
                  .get())
              .data()!,
        },
        {
          '_id': 'branch-one-b',
          ...(await firestore
                  .collection('staff_inventory')
                  .doc('branch-one-b')
                  .get())
              .data()!,
        },
      ],
    });
    final current = reportData.currentInventory('branch-one', DateTime.now());
    expect(current.single['name'], 'Branch special');
    expect(current.single['price'], 15);
    expect(current.single['remaining'], 6);
  });
}
