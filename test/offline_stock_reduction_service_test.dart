import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/offline_stock_reduction_service.dart';

void main() {
  late FakeFirebaseFirestore database;
  late OfflineStockReductionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = FakeFirebaseFirestore();
    service = OfflineStockReductionService();
    await database.collection('staff_inventory').doc('allocation-1').set({
      'staffId': 'branch-1',
      'items': [
        {
          'id': 'cookie-1',
          'name': 'Cookie',
          'variant': 'Pistachio',
          'stock': 4,
          'startingStock': 10,
          'reducedQuantity': 0,
          'price': 99,
        },
      ],
    });
  });

  test('queued reductions sync once against the latest stock', () async {
    await service.enqueue({
      'id': 'reduction-1',
      'inventoryId': 'allocation-1',
      'itemId': 'cookie-1',
      'itemName': 'Cookie',
      'variant': 'Pistachio',
      'quantity': 2,
      'categoryName': 'Cookies',
      'reason': 'Damaged',
      'comment': '',
      'staffId': 'staff-1',
      'staffName': 'Cashier',
    });

    await service.sync(database);
    await service.sync(database);

    final inventory =
        (await database.collection('staff_inventory').doc('allocation-1').get())
            .data()!;
    final item = (inventory['items'] as List).single as Map;
    expect(item['stock'], 2);
    expect(item['reducedQuantity'], 2);
    expect(
      (await database.collection('stock_adjustments').doc('reduction-1').get())
          .exists,
      isTrue,
    );
    expect(
      (await database
              .collection('admin_notifications')
              .doc('offline_stock_reduction-1')
              .get())
          .exists,
      isTrue,
    );
    expect(await service.pending(), isEmpty);
  });

  test('stale reductions remain queued instead of overselling stock', () async {
    await service.enqueue({
      'id': 'reduction-2',
      'inventoryId': 'allocation-1',
      'itemId': 'cookie-1',
      'itemName': 'Cookie',
      'variant': 'Pistachio',
      'quantity': 5,
      'categoryName': 'Cookies',
      'reason': 'Damaged',
      'comment': '',
      'staffId': 'staff-1',
      'staffName': 'Cashier',
    });

    await service.sync(database);

    final item =
        ((await database
                            .collection('staff_inventory')
                            .doc('allocation-1')
                            .get())
                        .data()!['items']
                    as List)
                .single
            as Map;
    expect(item['stock'], 4);
    expect((await service.pending()).single['id'], 'reduction-2');
    expect(
      (await database.collection('stock_adjustments').doc('reduction-2').get())
          .exists,
      isFalse,
    );
  });

  test(
    'online reductions use matching stock across accepted allocation batches',
    () async {
      await database.collection('staff_inventory').doc('allocation-1').set({
        'staffId': 'branch-1',
        'sourceInventoryId': 'cookies-source',
        'items': [
          {
            'id': 'pistachio',
            'name': 'Pistachio Dubai Chewy',
            'variant': 'Pistachio',
            'stock': 0,
            'price': 120,
          },
        ],
      });
      await database.collection('staff_inventory').doc('allocation-2').set({
        'staffId': 'branch-1',
        'sourceInventoryId': 'cookies-source',
        'items': [
          {
            'id': 'pistachio',
            'name': 'Pistachio Dubai Chewy',
            'stock': 17,
            'price': 120,
          },
        ],
      });
      for (final id in ['reduction-a', 'reduction-b']) {
        await service.enqueue({
          'id': id,
          'inventoryId': 'allocation-1',
          'sourceInventoryId': 'cookies-source',
          'itemId': 'pistachio',
          'itemName': 'Pistachio Dubai Chewy',
          'variant': 'Pistachio',
          'quantity': 1,
          'unitPrice': 120,
          'categoryName': 'Cookies',
          'reason': 'Damaged',
          'staffId': 'staff-1',
          'staffName': 'Cashier',
        });
      }

      await service.sync(database);

      expect(await service.pending(), isEmpty);
      final oldItems =
          ((await database
                          .collection('staff_inventory')
                          .doc('allocation-1')
                          .get())
                      .data()!['items']
                  as List)
              .cast<Map>();
      final acceptedItems =
          ((await database
                          .collection('staff_inventory')
                          .doc('allocation-2')
                          .get())
                      .data()!['items']
                  as List)
              .cast<Map>();
      expect(oldItems.single['stock'], 0);
      expect(acceptedItems.single['stock'], 15);
      final firstAdjustment =
          (await database
                  .collection('stock_adjustments')
                  .doc('reduction-a')
                  .get())
              .data()!;
      expect(firstAdjustment['previousStock'], 17);
      expect(firstAdjustment['unitPrice'], 120);
      expect(
        (await database
                .collection('stock_adjustments')
                .doc('reduction-b')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test('pending reductions are reflected in the local inventory view', () {
    final adjusted = service.applyPendingToInventory(
      {
        'items': [
          {'id': 'cookie-1', 'stock': 4, 'startingStock': 10},
        ],
      },
      'allocation-1',
      [
        {'inventoryId': 'allocation-1', 'itemId': 'cookie-1', 'quantity': 2},
      ],
    );

    expect(((adjusted['items'] as List).single as Map)['stock'], 2);
  });

  test(
    'shared catalog IDs do not target the wrong allocated variant',
    () async {
      await database.collection('staff_inventory').doc('allocation-1').set({
        'staffId': 'branch-1',
        'items': [
          {
            'id': 'chocolate-variant',
            'itemId': 'shared-cookie',
            'name': 'Cookie',
            'variant': 'Chocolate',
            'stock': 0,
            'price': 99,
          },
          {
            'id': 'pistachio-variant',
            'itemId': 'shared-cookie',
            'name': 'Cookie',
            'variant': 'Pistachio',
            'stock': 18,
            'price': 100,
          },
        ],
      });
      await service.enqueue({
        'id': 'reduction-3',
        'inventoryId': 'allocation-1',
        'itemId': 'shared-cookie',
        'itemName': 'Cookie',
        'variant': 'Pistachio',
        'quantity': 2,
        'categoryName': 'Cookies',
        'reason': 'Damaged',
        'comment': '',
        'staffId': 'staff-1',
        'staffName': 'Cashier',
      });

      await service.sync(database);

      final items =
          ((await database
                          .collection('staff_inventory')
                          .doc('allocation-1')
                          .get())
                      .data()!['items']
                  as List)
              .cast<Map>();
      expect(items[0]['stock'], 0);
      expect(items[1]['stock'], 16);
    },
  );

  test(
    'shared IDs on allocation rows still match the selected variant',
    () async {
      await database.collection('staff_inventory').doc('allocation-1').set({
        'staffId': 'branch-1',
        'items': [
          {
            'id': 'shared-cookie',
            'name': 'Cookie',
            'variant': 'Chocolate',
            'stock': 0,
          },
          {
            'id': 'shared-cookie',
            'name': 'Cookie',
            'variant': 'Pistachio',
            'stock': 18,
          },
        ],
      });
      await service.enqueue({
        'id': 'reduction-4',
        'inventoryId': 'allocation-1',
        'itemId': 'shared-cookie',
        'itemName': 'Cookie',
        'variant': 'Pistachio',
        'quantity': 2,
        'categoryName': 'Cookies',
        'reason': 'Damaged',
        'comment': '',
        'staffId': 'staff-1',
        'staffName': 'Cashier',
      });

      await service.sync(database);

      final items =
          ((await database
                          .collection('staff_inventory')
                          .doc('allocation-1')
                          .get())
                      .data()!['items']
                  as List)
              .cast<Map>();
      expect(items[0]['stock'], 0);
      expect(items[1]['stock'], 16);
      expect(await service.pending(), isEmpty);
    },
  );

  test('reductions use available stock across duplicate variant rows', () {
    final result = reduceMatchingInventoryRows(
      rows: [
        {
          'id': 'shared-cookie',
          'name': 'Cookie',
          'variant': 'Chocolate',
          'stock': 0,
          'price': 99,
        },
        {
          'id': 'shared-cookie',
          'name': 'Cookie',
          'variant': 'Pistachio',
          'stock': 18,
          'price': 100,
        },
      ],
      itemId: 'shared-cookie',
      itemName: 'Cookie',
      variant: 'Pistachio',
      quantity: 2,
      beverage: false,
    );

    expect(result.previousStock, 18);
    expect(result.newStock, 16);
    expect(result.items[0]['stock'], 0);
    expect(result.items[1]['stock'], 16);
  });

  test(
    'beverage reduction matches a size field and skips empty duplicates',
    () {
      final result = reduceMatchingInventoryRows(
        rows: [
          {
            'name': 'Dubai Chewy Smoothie - Medium',
            'coffeeSize': 'Medium',
            'stock': 0,
            'price': 120,
          },
          {
            'name': 'Dubai Chewy Smoothie - Medium',
            'coffeeSize': 'Medium',
            'stock': 18,
            'price': 120,
          },
          {
            'name': 'Dubai Chewy Smoothie - Small',
            'coffeeSize': 'Small',
            'stock': 4,
            'price': 110,
          },
        ],
        itemId: '',
        itemName: 'Dubai Chewy Smoothie',
        variant: 'Medium',
        quantity: 1,
        beverage: true,
      );

      expect(result.previousStock, 18);
      expect(result.items[0]['stock'], 0);
      expect(result.items[1]['stock'], 17);
      expect(result.items[2]['stock'], 4);
      expect(result.unitPrice, 120);
    },
  );

  test('online beverage queue syncs and removes its pending notice', () async {
    await database.collection('staff_inventory').doc('allocation-1').set({
      'staffId': 'branch-1',
      'branchName': 'SM Dagupan',
      'items': [
        {
          'name': 'Dubai Chewy Smoothie - Medium',
          'coffeeSize': 'Medium',
          'stock': 0,
          'price': 120,
        },
        {
          'name': 'Dubai Chewy Smoothie - Medium',
          'coffeeSize': 'Medium',
          'stock': 18,
          'price': 120,
        },
      ],
    });
    await service.enqueue({
      'id': 'beverage-reduction',
      'type': 'coffee_void',
      'inventoryId': 'allocation-1',
      'itemName': 'Dubai Chewy Smoothie',
      'coffeeId': 'CF-001',
      'variant': 'Medium',
      'quantity': 1,
      'unitPrice': 120,
      'categoryName': 'Dubai Chewy Smoothie',
      'reason': 'Damaged',
      'staffId': 'staff-1',
      'staffName': 'Cashier',
    });

    await service.sync(database);

    expect(await service.pending(), isEmpty);
    final data =
        (await database.collection('staff_inventory').doc('allocation-1').get())
            .data()!;
    final items = (data['items'] as List).cast<Map>();
    expect(items[0]['stock'], 0);
    expect(items[1]['stock'], 17);
    final adjustment =
        (await database
                .collection('stock_adjustments')
                .doc('beverage-reduction')
                .get())
            .data()!;
    expect(adjustment['type'], 'coffee_void');
    expect(adjustment['branchId'], 'branch-1');
    expect(adjustment['coffeeSize'], 'Medium');
    expect(adjustment['unitPrice'], 120);
  });

  test(
    'pending reduction projects stock from matching accepted allocations',
    () {
      final projected = service.applyPendingToInventoryDocuments(
        [
          {
            '_localDocId': 'allocation-1',
            'staffId': 'branch-1',
            'sourceInventoryId': 'cookies-source',
            'items': [
              {'id': 'pistachio', 'name': 'Pistachio', 'stock': 0},
            ],
          },
          {
            '_localDocId': 'allocation-2',
            'staffId': 'branch-1',
            'sourceInventoryId': 'cookies-source',
            'items': [
              {'id': 'pistachio', 'name': 'Pistachio', 'stock': 17},
            ],
          },
        ],
        [
          {
            'id': 'pending',
            'inventoryId': 'allocation-1',
            'sourceInventoryId': 'cookies-source',
            'itemId': 'pistachio',
            'itemName': 'Pistachio',
            'quantity': 2,
          },
        ],
      );

      expect(((projected[0]['items'] as List).single as Map)['stock'], 0);
      expect(((projected[1]['items'] as List).single as Map)['stock'], 15);
    },
  );

  test('queued bundle reductions update inventory and history once', () async {
    await database.collection('staff_inventory').doc('bundle-allocation').set({
      'staffId': 'branch-1',
      'name': 'Cookie Box',
      'bundleId': 'BND-003-25',
      'bundleCount': 2,
      'bundleInstances': [
        {'id': 'bundle-a', 'status': 'available'},
        {'id': 'bundle-b', 'status': 'available'},
      ],
    });
    await service.enqueue({
      'id': 'bundle-reduction',
      'type': 'bundle_instance_adjustment',
      'inventoryId': 'bundle-allocation',
      'bundleId': 'BND-003-25',
      'bundleInstanceIds': ['bundle-a'],
      'bundleDisplayIds': ['BND-003-25-001'],
      'quantity': 1,
      'unitPrice': 150,
      'categoryName': 'Cookie Box',
      'reason': 'Damaged',
      'staffId': 'staff-1',
      'staffName': 'Cashier',
    });

    await service.sync(database);
    await service.sync(database);

    final inventory =
        (await database
                .collection('staff_inventory')
                .doc('bundle-allocation')
                .get())
            .data()!;
    expect(inventory['bundleCount'], 1);
    expect(
      ((inventory['bundleInstances'] as List).first as Map)['status'],
      'reduced',
    );
    expect(
      (await database
              .collection('stock_adjustments')
              .doc('bundle-reduction')
              .get())
          .data()?['type'],
      'bundle_stock_adjustment',
    );
    expect(await service.pending(), isEmpty);
  });

  test(
    'queued offline refund replacements consume allocated stock once',
    () async {
      await database.collection('staff_inventory').doc('allocation-1').set({
        'staffId': 'branch-1',
        'items': [
          {'id': 'cookie-1', 'name': 'Cookie', 'stock': 5, 'startingStock': 5},
        ],
      });
      await service.enqueue({
        'id': 'refund_replacement_R-001',
        'type': 'refund_inventory_replacement',
        'inventoryId': 'allocation-1',
        'operations': [
          {
            'docId': 'allocation-1',
            'kind': 'Categories',
            'itemId': 'cookie-1',
            'itemName': 'Cookie',
            'quantity': 1,
          },
        ],
        'userId': 'staff-1',
        'staffId': 'staff-1',
        'reason': 'Refund replacement',
      });

      await service.sync(database);
      await service.sync(database);

      final item =
          ((await database
                              .collection('staff_inventory')
                              .doc('allocation-1')
                              .get())
                          .data()!['items']
                      as List)
                  .single
              as Map;
      expect(item['stock'], 4);
      expect(
        (await database
                .collection('stock_adjustments')
                .doc('refund_replacement_R-001')
                .get())
            .data()?['type'],
        'refund_replacement',
      );
      expect(await service.pending(), isEmpty);
    },
  );
}
