import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/cash_drawer_service.dart';
import 'package:sales_tracking/services/allocation_checklist_service.dart';

void main() {
  final today = DateTime.utc(2026, 9, 27, 1);
  test(
    'calendar reset ignores recent sales update and preserves zero opening',
    () {
      final old = {
        'drawerDate': '2026-09-26',
        'balance': 3018,
        'dailyOpeningCash': 1200,
        'updatedAt': today,
      };
      final reset = CashDrawerService.forDay(old, today);
      expect(reset['balance'], 1200);
      expect(reset['drawerDate'], '2026-09-27');
      expect(
        CashDrawerService.forDay({...reset, 'balance': 1289}, today)['balance'],
        1289,
      );
      expect(
        CashDrawerService.forDay({
          ...old,
          'dailyOpeningCash': 0,
          'openingCash': 1200,
        }, today)['balance'],
        0,
      );
    },
  );
  test('Philippine midnight resets without waiting 24 hours', () {
    final old = {
      'drawerDate': '2026-09-26',
      'balance': 3018,
      'dailyOpeningCash': 1200,
    };
    expect(
      CashDrawerService.forDay(
        old,
        DateTime.utc(2026, 9, 26, 15, 59),
      )['balance'],
      3018,
    );
    expect(
      CashDrawerService.forDay(old, DateTime.utc(2026, 9, 26, 16))['balance'],
      1200,
    );
  });
  test(
    'migration retains today credited 89 and excludes yesterday and queued sale',
    () {
      final data = {
        'drawerDate': '2026-09-26',
        'balance': 3107,
        'dailyOpeningCash': 1200,
        'appliedOfflineMutationIds': ['receipt-new', 'receipt-old'],
      };
      final receipts = [
        {
          'salesId': 'new',
          'timestamp': today,
          'total': 89,
          'paymentMode': 'Cash',
        },
        {
          'salesId': 'old',
          'timestamp': today.subtract(const Duration(days: 1)),
          'total': 1818,
          'paymentMode': 'Cash',
        },
        {
          'salesId': 'queued',
          'timestamp': today,
          'total': 99,
          'paymentMode': 'Cash',
        },
      ];
      expect(
        CashDrawerService.forDay(data, today, receipts: receipts)['balance'],
        1289,
      );
    },
  );
  test('server reset preserves today receipt and is idempotent', () async {
    final db = FakeFirebaseFirestore();
    final now = DateTime.now();
    await db.collection('staff_cash_drawer').doc('branch').set({
      'drawerDate': '2020-01-01',
      'dailyOpeningCash': 1200,
      'balance': 3107,
      'appliedOfflineMutationIds': ['receipt-r'],
    });
    await db.collection('completed_sales').doc('r').set({
      'salesId': 'r',
      'branchId': 'branch',
      'timestamp': Timestamp.fromDate(now),
      'paymentMode': 'Cash',
      'total': 89,
    });
    await CashDrawerService.ensureToday(db, 'branch');
    await CashDrawerService.ensureToday(db, 'branch');
    expect(
      (await db.collection('staff_cash_drawer').doc('branch').get())
          .data()!['balance'],
      1289,
    );
  });

  Future<FakeFirebaseFirestore> fixture({
    bool bundle = false,
    bool coffee = false,
  }) async {
    final db = FakeFirebaseFirestore();
    await db.collection('allocation_checklist').doc('delivery').set({
      'status': 'pending',
      'staffId': 'branch',
      'staffName': 'Dagupan',
      'name': 'Cookies',
      'targetDocId': 'branch_source',
      'sourceInventoryId': 'source',
      if (coffee) 'sourceCollection': 'coffee_products',
      'isCoffee': coffee,
      'isBundle': bundle,
      'bundleCount': 2,
      'bundleInstances': [
        {'id': 'b1'},
        {'id': 'b2'},
      ],
      'items': [
        {'id': 'cookie', 'name': 'Cookie', 'stock': 3, 'startingStock': 3},
      ],
    });
    await db
        .collection(coffee ? 'coffee_products' : 'sales_inventory')
        .doc('source')
        .set({
          'bundleCount': 5,
          'bundleInstances': [],
          'items': [
            {'id': 'cookie', 'stock': 7, 'startingStock': 10},
          ],
        });
    return db;
  }

  test(
    'accept adds only delivery quantity once, retaining concurrent staff stock',
    () async {
      final db = await fixture();
      await db.collection('staff_inventory').doc('branch_source').set({
        'items': [
          {'id': 'cookie', 'stock': 4, 'startingStock': 8},
        ],
      });
      final service = AllocationChecklistService(db);
      expect(
        await service.decide('delivery', accept: true, staffId: 'staff'),
        true,
      );
      expect(
        await service.decide('delivery', accept: true, staffId: 'staff'),
        false,
      );
      final data =
          (await db.collection('staff_inventory').doc('branch_source').get())
              .data()!;
      expect((data['items'] as List).single['stock'], 7);
      expect(
        (await db.collection('staff_inventory_history').get()).docs.length,
        1,
      );
    },
  );
  test(
    'accept creates new category and beverage only after decision',
    () async {
      for (final coffee in [false, true]) {
        final db = await fixture(coffee: coffee);
        expect((await db.collection('staff_inventory').get()).docs, isEmpty);
        await AllocationChecklistService(
          db,
        ).decide('delivery', accept: true, staffId: 'staff');
        expect(
          (await db.collection('staff_inventory').doc('branch_source').get())
              .exists,
          true,
        );
      }
    },
  );
  test(
    'decline requires reason, restores stock and sends only one notice',
    () async {
      final db = await fixture();
      final service = AllocationChecklistService(db);
      await expectLater(
        service.decide('delivery', accept: false, staffId: 'staff'),
        throwsArgumentError,
      );
      await service.decide(
        'delivery',
        accept: false,
        staffId: 'staff',
        reason: 'Wrong items',
      );
      await service.decide(
        'delivery',
        accept: false,
        staffId: 'staff',
        reason: 'Retry',
      );
      final source =
          (await db.collection('sales_inventory').doc('source').get()).data()!;
      expect((source['items'] as List).single['stock'], 10);
      expect((await db.collection('staff_inventory').get()).docs, isEmpty);
      final notices = (await db.collection('admin_notifications').get()).docs;
      expect(notices.length, 1);
      expect(notices.single.data()['reason'], 'Wrong items');
    },
  );
  test('decline returns bundle instances and count exactly once', () async {
    final db = await fixture(bundle: true);
    final service = AllocationChecklistService(db);
    await service.decide(
      'delivery',
      accept: false,
      staffId: 'staff',
      reason: 'Wrong delivery',
    );
    await service.decide(
      'delivery',
      accept: false,
      staffId: 'staff',
      reason: 'Retry',
    );
    final data = (await db.collection('sales_inventory').doc('source').get())
        .data()!;
    expect(data['bundleCount'], 7);
    expect((data['bundleInstances'] as List).length, 2);
  });
}
