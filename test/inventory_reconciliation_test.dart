import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/inventory_reconciliation_service.dart';
import 'package:sales_tracking/services/allocation_checklist_service.dart';
import 'package:sales_tracking/services/bundle_metadata_service.dart';

Map<String, dynamic> cookie(int count, String expiry) => {
  'variantId': 'cookie',
  'sourceInventoryId': 'cookies',
  'parentName': 'Cookies',
  'name': 'Cookie',
  'quantity': count,
  'expirationDate': expiry,
  'costPrice': 50,
  'price': 99,
};
Map<String, dynamic> beverage() => {
  'variantId': 'Small',
  'sourceInventoryId': 'coffee',
  'sourceCollection': 'coffee_products',
  'isCoffee': true,
  'name': 'Coffee',
  'quantity': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  late InventoryReconciliationService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    service = InventoryReconciliationService(db);
    await db.doc('staff_inventory/old').set({
      'staffId': 'branch',
      'staffName': 'Branch',
      'sourceInventoryId': 'bundle',
      'name': 'Cookies bundle',
      'isBundle': true,
      'bundleCount': 2,
      'price': 350,
      'costPrice': 150,
      'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'items': [cookie(3, '2099-01-01'), beverage()],
      'bundleInstances': [
        for (var i = 0; i < 2; i++)
          {
            'id': 'old-$i',
            'status': 'available',
            'batchId': 'old-batch-001',
            'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
            'items': [
              cookie(3, i == 0 ? '2099-01-01' : '2099-02-01'),
              beverage(),
            ],
          },
      ],
    });
    await db.doc('staff_inventory/new').set({
      'staffId': 'branch',
      'sourceInventoryId': 'bundle',
      'name': 'Updated bundle',
      'isBundle': true,
      'bundleCount': 1,
      'assignedAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
      'price': 250,
      'costPrice': 100,
      'items': [cookie(2, '2099-06-01'), beverage()],
    });
  });
  Future<void> submit(
    String id, {
    String action = 'convert',
    List<String> instances = const ['old-0', 'old-1'],
  }) => service.submit(
    requestId: id,
    allocationId: 'old',
    instanceIds: instances,
    action: action,
    actorId: 'staff',
    actorName: 'Staff',
    scopeIds: ['branch'],
    targetAllocationId: action == 'convert' ? 'new' : null,
  );

  test(
    'approval conserves ingredients, expiry lots and does not stock beverages',
    () async {
      await submit('r');
      expect(
        (await db.doc('staff_inventory/old').get()).data()!['bundleCount'],
        0,
      );
      expect((await db.collection('staff_inventory').get()).docs.length, 2);
      await service.decide('r', approve: true, actorId: 'admin');
      await service.decide('r', approve: true, actorId: 'admin');
      final outputs = (await db.collection('staff_inventory').get()).docs
          .where((d) => d.data()['origin'] == 'unbundle')
          .map((d) => d.data())
          .toList();
      expect(outputs.length, 2);
      expect(
        outputs.map((d) => (d['items'] as List).single['stock']),
        everyElement(1),
      );
      expect(
        outputs
            .map((d) => (d['items'] as List).single['expirationDate'])
            .toSet(),
        {'2099-01-01', '2099-02-01'},
      );
      final converted = (await db.doc('staff_inventory/new').get()).data()!;
      expect(converted['bundleCount'], 3);
      expect(converted['price'], 250);
      final convertedInstances = (converted['bundleInstances'] as List)
          .where((instance) => instance['origin'] == 'conversion')
          .toList();
      expect(convertedInstances, hasLength(2));
      expect(
        convertedInstances.first['items'][0]['expirationDate'],
        '2099-01-01',
      );
      expect(convertedInstances.first['originBatchId'], 'old-batch-001');
      expect(
        (await db.doc('staff_inventory/reconcile_r_bundle').get()).exists,
        false,
      );
    },
  );
  test(
    'conversion accepts the same bundle version with a migrated source id',
    () async {
      await db.doc('staff_inventory/old').update({
        'bundleId': 'BND-001',
        'sourceInventoryId': 'legacy-bundle-source',
      });
      await db.doc('staff_inventory/new').update({
        'bundleId': 'BND-001',
        'sourceInventoryId': 'current-bundle-source',
      });

      await submit('migrated-source');

      final request =
          (await db.doc('inventory_reconciliations/migrated-source').get())
              .data()!;
      expect(request['status'], 'pending');
      expect((request['targetSnapshot']['items'] as List).first['quantity'], 2);
      expect(
        (await db.doc('staff_inventory/old').get()).data()!['bundleCount'],
        0,
      );
    },
  );
  test('reject releases reserved stock exactly once', () async {
    await submit('r', action: 'unbundle');
    await service.decide('r', approve: false, actorId: 'admin');
    await service.decide('r', approve: false, actorId: 'admin');
    final old = (await db.doc('staff_inventory/old').get()).data()!;
    expect(old['bundleCount'], 2);
    expect(
      (old['bundleInstances'] as List).map((i) => i['status']),
      everyElement('available'),
    );
    expect((await db.collection('staff_inventory').get()).docs.length, 2);
  });
  test('pending stock cannot be submitted twice', () async {
    await submit('r');
    await submit('r');
    await expectLater(submit('other'), throwsStateError);
  });
  test('20/20/20 becomes 2/2 and returns 18/18/20 only on approval', () async {
    Map<String, dynamic> cake(String id, int count, {bool updated = false}) => {
      'sourceInventoryId': 'cakes-category',
      'parentName': 'Cakes',
      'variantId': updated ? 'new-$id' : 'old-$id',
      'publicId': id,
      'name': id,
      'quantity': count,
      'remaining': count,
      'expirationDate': '2099-01-01',
    };
    final oldItems = [cake('A', 20), cake('B', 20), cake('C', 20)];
    await db.doc('staff_inventory/old').update({
      'bundleCount': 1,
      'items': oldItems,
      'bundleInstances': [
        {
          'id': 'old-0',
          'batchId': 'batch-001',
          'status': 'available',
          'items': oldItems,
        },
      ],
    });
    await db.doc('staff_inventory/new').update({
      'items': [cake('A', 2, updated: true), cake('B', 2, updated: true)],
    });
    await submit('cakes', instances: ['old-0']);
    expect(
      (await db.doc('inventory_reconciliations/cakes').get()).data()!['status'],
      'pending',
    );
    expect((await db.collection('staff_inventory').get()).docs, hasLength(2));
    await service.decide('cakes', approve: true, actorId: 'admin');
    await service.decide('cakes', approve: true, actorId: 'admin');
    final loose = (await db.collection('staff_inventory').get()).docs
        .map((doc) => doc.data())
        .where((doc) => doc['origin'] == 'unbundle')
        .toList();
    expect(loose, hasLength(3));
    expect(
      loose.map((doc) => doc['sourceInventoryId']),
      everyElement('cakes-category'),
    );
    expect(loose.map((doc) => doc['name']), everyElement('Cakes'));
    expect(
      {
        for (final doc in loose)
          doc['items'][0]['publicId']: doc['items'][0]['stock'],
      },
      {'A': 18, 'B': 18, 'C': 20},
    );
    final target = (await db.doc('staff_inventory/new').get()).data()!;
    final converted = (target['bundleInstances'] as List).last;
    expect(converted['originBatchId'], 'batch-001');
    expect((converted['items'] as List).map((item) => item['quantity']), [
      2,
      2,
    ]);
    expect((converted['items'] as List).map((item) => item['remaining']), [
      2,
      2,
    ]);
    expect(target['bundleCount'], 2);
  });

  test(
    'rejecting conversion preserves original contents and creates no loose stock',
    () async {
      await submit('reject-conversion');
      await service.decide(
        'reject-conversion',
        approve: false,
        actorId: 'admin',
      );
      final old = (await db.doc('staff_inventory/old').get()).data()!;
      expect(old['bundleCount'], 2);
      expect(old['bundleInstances'][0]['items'][0]['quantity'], 3);
      expect((await db.collection('staff_inventory').get()).docs, hasLength(2));
      expect(
        (await db.doc('staff_inventory/new').get()).data()!['bundleCount'],
        1,
      );
    },
  );

  test(
    'missing ingredient category leaves no reservation or request',
    () async {
      final data = (await db.doc('staff_inventory/old').get()).data()!;
      final instances = data['bundleInstances'] as List;
      instances[0]['items'][0].remove('sourceInventoryId');
      await db.doc('staff_inventory/old').update({
        'bundleInstances': instances,
      });
      await expectLater(
        submit('bad-source', action: 'unbundle', instances: ['old-0']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Ingredient source is missing'),
          ),
        ),
      );
      expect(
        (await db.doc('inventory_reconciliations/bad-source').get()).exists,
        isFalse,
      );
      expect(
        (await db.doc('staff_inventory/old').get()).data()!['bundleCount'],
        2,
      );
    },
  );
  test(
    'conversion rejects insufficient recipe quantities without mutation',
    () async {
      await db.doc('staff_inventory/new').update({
        'items': [cookie(4, '2099-06-01')],
      });
      await expectLater(submit('r'), throwsStateError);
      expect(
        (await db.doc('staff_inventory/old').get()).data()!['bundleCount'],
        2,
      );
    },
  );
  test('unbundle restores all physical quantities after approval', () async {
    await submit('r', action: 'unbundle', instances: ['old-1']);
    await service.decide('r', approve: true, actorId: 'admin');
    final loose = (await db.doc('staff_inventory/reconcile_r_item_0').get())
        .data()!;
    expect((loose['items'] as List).single['stock'], 3);
    expect((loose['items'] as List).single['origin'], 'unbundle');
    expect(
      (await db.doc('staff_inventory/reconcile_r_bundle').get()).exists,
      false,
    );
  });
  test('return reserves only the selected batch instances', () async {
    await AllocationChecklistService(db).submitReturn(
      requestId: 'ret',
      sourceCollection: 'staff_inventory',
      sourceId: 'old',
      lineKey: 'bundle',
      count: 1,
      reason: 'Return',
      actorId: 'staff',
      actorName: 'Staff',
      scopeIds: ['branch'],
      branchId: 'branch',
      branchName: 'Branch',
      instanceIds: ['old-1'],
    );
    final old = (await db.doc('staff_inventory/old').get()).data()!;
    expect(old['bundleCount'], 1);
    expect(old['bundleInstances'][0]['status'], 'available');
    expect(old['bundleInstances'][1]['status'], 'return_pending');
    expect(
      (await db.doc('allocation_checklist/ret').get()).data()!['kind'],
      'return',
    );
  });
  test('catalog recipe edits leave delivered bundles unchanged', () async {
    await db.doc('sales_inventory/bundle').set({
      'isBundle': true,
      'items': [cookie(3, '2099-01-01')],
      'bundleInstances': [
        {
          'id': 'available-id',
          'number': 1,
          'status': 'available',
          'items': [
            cookie(20, '2099-01-01'),
            {'name': 'Red Velvet', 'quantity': 1},
          ],
        },
        {
          'id': 'reserved-id',
          'number': 2,
          'status': 'reconciliation_pending',
          'items': [
            cookie(20, '2099-01-01'),
            {'name': 'Red Velvet', 'quantity': 1},
          ],
        },
      ],
    });
    await updateBundleMetadata(db, 'bundle', {
      'items': [cookie(2, '2099-06-01')],
      'price': 250,
      'costPrice': 100,
    });
    final central = (await db.doc('sales_inventory/bundle').get()).data()!;
    final centralInstances = central['bundleInstances'] as List;
    expect((centralInstances[0]['items'] as List).single['quantity'], 2);
    expect(
      (centralInstances[0]['items'] as List).any(
        (item) => item['name'] == 'Red Velvet',
      ),
      isFalse,
    );
    expect((centralInstances[1]['items'] as List).first['quantity'], 20);
    expect(
      (centralInstances[1]['items'] as List).any(
        (item) => item['name'] == 'Red Velvet',
      ),
      isTrue,
    );
    expect(
      (await db.doc('staff_inventory/old').get())
          .data()!['items'][0]['quantity'],
      3,
    );
    expect((await db.doc('staff_inventory/old').get()).data()!['price'], 350);
  });
}
