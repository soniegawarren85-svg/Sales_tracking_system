import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/branch_inventory_void_service.dart';
import 'package:sales_tracking/services/low_stock_reports.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'staff low-stock marks are saved to branch allocations and notified',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('staff_inventory')
          .doc('coffee-allocation')
          .set({
            'staffId': 'branch-one',
            'isCoffee': true,
            'name': 'Iced Latte',
          });
      await firestore.collection('staff_inventory').doc('addon-allocation').set(
        {'staffId': 'branch-one', 'isAddon': true, 'name': 'Whipped Cream'},
      );
      await firestore.collection('branches').doc('branch-one').set({
        'name': 'Branch One',
        'staffIds': ['admin-account'],
      });
      await firestore.collection('staff_requests').doc('admin-account').set({
        'role': 'admin',
        'status': 'accepted',
      });

      await markStaffInventoryLowStock(
        firestore: firestore,
        items: [
          {
            'name': 'Iced Latte',
            'type': 'Beverages',
            'staffInventoryDocId': 'coffee-allocation',
          },
          {
            'name': 'Whipped Cream',
            'type': 'Add-ons',
            'staffInventoryDocId': 'addon-allocation',
          },
        ],
        branchIds: ['branch-one'],
        staffId: 'staff-one',
        staffName: 'Staff One',
      );

      final beverage =
          (await firestore
                  .collection('staff_inventory')
                  .doc('coffee-allocation')
                  .get())
              .data()!;
      final addon =
          (await firestore
                  .collection('staff_inventory')
                  .doc('addon-allocation')
                  .get())
              .data()!;
      expect(beverage['isLowStock'], isFalse);
      expect(addon['isLowStock'], isFalse);
      expect(beverage['staffLowStockPendingAdmin'], isTrue);
      expect(addon['staffLowStockPendingAdmin'], isTrue);

      final notifications = await firestore
          .collection('admin_notifications')
          .where('type', isEqualTo: 'staff_low_stock')
          .get();
      expect(notifications.docs, hasLength(1));
      expect(notifications.docs.single.data()['items'], hasLength(2));
    },
  );

  test(
    'staff low-stock is pending when an active branch admin exists',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('branches').doc('branch-one').set({
        'staffIds': ['admin-account'],
      });
      await firestore.collection('staff_requests').doc('admin-account').set({
        'role': 'admin',
        'status': 'accepted',
      });
      await firestore.collection('staff_inventory').doc('coffee').set({
        'staffId': 'branch-one',
        'isCoffee': true,
        'name': 'Iced Latte',
      });

      await markStaffInventoryLowStock(
        firestore: firestore,
        items: [
          {
            'name': 'Iced Latte',
            'type': 'Beverages',
            'staffInventoryDocId': 'coffee',
          },
        ],
        branchIds: ['branch-one'],
        staffId: 'staff-one',
        staffName: 'Staff One',
      );

      final allocation =
          (await firestore.collection('staff_inventory').doc('coffee').get())
              .data()!;
      expect(allocation['isLowStock'], isFalse);
      expect(allocation['staffLowStockPendingAdmin'], isTrue);
      expect((await firestore.collection('messages').get()).docs, isEmpty);
      expect(
        (await firestore.collection('admin_notifications').get()).docs,
        hasLength(1),
      );
    },
  );

  test('detects branch admins assigned by their public admin ID', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('branch-one').set({
      'staffIds': ['ADM-0001'],
    });
    await firestore.collection('staff_requests').doc('admin-auth').set({
      'uid': 'admin-auth',
      'adminId': 'ADM-0001',
      'role': 'admin',
      'status': 'accepted',
    });
    await firestore.collection('staff_inventory').doc('coffee').set({
      'staffId': 'branch-one',
      'isCoffee': true,
      'name': 'Iced Latte',
    });

    await markStaffInventoryLowStock(
      firestore: firestore,
      items: [
        {
          'name': 'Iced Latte',
          'type': 'Beverages',
          'staffInventoryDocId': 'coffee',
        },
      ],
      branchIds: ['branch-one'],
      staffId: 'staff-one',
      staffName: 'Staff One',
    );

    final allocation =
        (await firestore.collection('staff_inventory').doc('coffee').get())
            .data()!;
    expect(allocation['isLowStock'], isFalse);
    expect(allocation['staffLowStockPendingAdmin'], isTrue);
    expect((await firestore.collection('messages').get()).docs, isEmpty);
  });

  test(
    'staff low-stock reports directly to Super Admin without branch admin',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('branches').doc('branch-one').set({
        'name': 'Dagupan',
        'staffIds': ['staff-one'],
      });
      await firestore.collection('staff_inventory').doc('coffee').set({
        'staffId': 'branch-one',
        'isCoffee': true,
        'name': 'Iced Latte',
      });

      await markStaffInventoryLowStock(
        firestore: firestore,
        items: [
          {
            'name': 'Iced Latte',
            'type': 'Beverages',
            'id': 'COF-1',
            'staffInventoryDocId': 'coffee',
          },
        ],
        branchIds: ['branch-one'],
        staffId: 'staff-one',
        staffName: 'Staff One',
      );

      final allocation =
          (await firestore.collection('staff_inventory').doc('coffee').get())
              .data()!;
      expect(allocation['isLowStock'], isTrue);
      expect(allocation['staffLowStockPendingAdmin'], isFalse);
      final chat = await firestore
          .collection('messages')
          .doc('Spr-001_staff-one')
          .get();
      expect(chat.data()?['lastMessage'], contains('Iced Latte'));
      final messages = await chat.reference.collection('items').get();
      expect(messages.docs.single.data()['type'], 'staff_low_stock_report');
    },
  );

  test(
    'staff cannot submit a low-stock marker for an already marked item',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_inventory').doc('coffee').set({
        'isLowStock': true,
        'name': 'Iced Latte',
      });

      await expectLater(
        markStaffInventoryLowStock(
          firestore: firestore,
          items: [
            {'name': 'Iced Latte', 'staffInventoryDocId': 'coffee'},
          ],
          branchIds: ['branch-one'],
          staffId: 'staff-one',
          staffName: 'Staff One',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already marked low stock'),
          ),
        ),
      );
    },
  );

  test(
    'low-stock reports create a detailed Super Admin conversation',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('staff_inventory')
          .doc('coffee-allocation')
          .set({'isLowStock': false, 'staffLowStockPendingAdmin': true});

      await submitLowStockReportToSuperAdmin(
        firestore: firestore,
        adminId: 'ADM-0001',
        adminName: 'Branch Admin',
        branchId: 'branch-one',
        branchName: 'Dagupan',
        items: [
          {
            'name': 'Iced Latte',
            'type': 'Beverages',
            'id': 'COF-1',
            'allocationId': 'coffee-allocation',
          },
        ],
      );

      final chat =
          (await firestore.collection('messages').doc('ADM-0001_Spr-001').get())
              .data()!;
      expect(chat['participantIds'], ['ADM-0001', 'Spr-001']);
      expect(chat['lastMessage'], contains('Dagupan'));
      expect(chat['lastMessage'], contains('Iced Latte'));

      final messages = await firestore
          .collection('messages')
          .doc('ADM-0001_Spr-001')
          .collection('items')
          .get();
      expect(messages.docs, hasLength(1));
      expect(messages.docs.single.data()['type'], 'low_stock_report');
      expect(messages.docs.single.data()['items'], hasLength(1));
      final allocation =
          (await firestore
                  .collection('staff_inventory')
                  .doc('coffee-allocation')
                  .get())
              .data()!;
      expect(allocation['isLowStock'], isTrue);
      expect(allocation['staffLowStockPendingAdmin'], isFalse);
    },
  );

  test('an already reported item cannot be submitted again', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_inventory').doc('coffee').set({
      'isLowStock': true,
      'staffLowStockPendingAdmin': false,
    });

    await expectLater(
      submitLowStockReportToSuperAdmin(
        firestore: firestore,
        adminId: 'ADM-0001',
        adminName: 'Branch Admin',
        branchId: 'branch-one',
        branchName: 'Dagupan',
        items: [
          {'name': 'Iced Latte', 'type': 'Beverages', 'allocationId': 'coffee'},
        ],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('already reported'),
        ),
      ),
    );
    expect((await firestore.collection('messages').get()).docs, isEmpty);
  });

  test(
    'low-stock beverage allocations can be voided only when allowed',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('staff_inventory')
          .doc('coffee-allocation')
          .set({
            'staffId': 'branch-one',
            'sourceInventoryId': 'coffee-source',
            'isCoffee': true,
            'isLowStock': true,
            'isDeleted': false,
            'name': 'Iced Latte',
            'stock': 2,
          });

      final item = <String, dynamic>{
        'allocationId': 'coffee-allocation',
        'sourceInventoryId': 'coffee-source',
        'type': 'Beverages',
        'name': 'Iced Latte',
        'isLowStock': true,
      };

      await expectLater(
        voidBranchInventoryAllocation(
          firestore: firestore,
          allocationId: 'coffee-allocation',
          allocationItemId: '',
          branchId: 'branch-one',
          item: item,
        ),
        throwsStateError,
      );
      final removed = await voidBranchInventoryAllocation(
        firestore: firestore,
        allocationId: 'coffee-allocation',
        allocationItemId: '',
        branchId: 'branch-one',
        item: item,
        allowLowStock: true,
      );

      expect(removed, isTrue);
      expect(
        (await firestore
                .collection('staff_inventory')
                .doc('coffee-allocation')
                .get())
            .data()?['isDeleted'],
        isTrue,
      );
    },
  );

  test('branch current inventory exposes staff low-stock markers', () {
    final data = BranchReportData({
      'branches': [],
      'completed_sales': [],
      'stock_adjustments': [],
      'staff_inventory': [
        {
          '_id': 'coffee-allocation',
          'staffId': 'branch-one',
          'sourceInventoryId': 'coffee-source',
          'isCoffee': true,
          'isLowStock': true,
          'name': 'Iced Latte',
          'assignedAt': DateTime.now(),
        },
      ],
      'staff_inventory_history': [],
      'sales_inventory': [],
      'coffee_products': [
        {'_id': 'coffee-source', 'name': 'Iced Latte'},
      ],
      'coffee_addons': [],
      'budget_history': [],
      'staff_cash_drawer': [],
      'daily_reports': [],
      'admin_settings': [],
    });

    final rows = data.currentInventory('branch-one', DateTime.now());
    expect(rows, hasLength(1));
    expect(rows.single['isLowStock'], isTrue);
  });

  test('unreported add-on stays available and keeps its catalog price', () {
    final data = BranchReportData({
      'branches': [],
      'completed_sales': [],
      'stock_adjustments': [],
      'sales_inventory': [],
      'coffee_products': [],
      'coffee_addons': [
        {
          '_id': 'addon-source',
          'name': 'Chewy Cream',
          'priceDelta': 40,
          'isDeleted': false,
        },
      ],
      'staff_inventory': [
        {
          '_id': 'addon-allocation',
          'staffId': 'branch-one',
          'sourceInventoryId': 'addon-source',
          'isAddon': true,
          'staffLowStockPendingAdmin': true,
          'name': 'Chewy Cream',
          'assignedAt': DateTime.now(),
        },
      ],
    });

    final row = data.currentInventory('branch-one', DateTime.now()).single;
    expect(row['type'], 'Add-ons');
    expect(row['price'], 40);
    expect(row['status'], 'Available');
    expect(row['isLowStock'], isFalse);
    expect(row['staffLowStockPendingAdmin'], isTrue);
  });
}
