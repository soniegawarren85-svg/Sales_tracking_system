import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_inventory_void_service.dart';

void main() {
  test(
    'removes only the selected sold-out variant and retains audit data',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_inventory').doc('allocation-1').set({
        'items': [
          {'id': 'sold-out', 'name': 'Cookie', 'stock': 0},
          {'id': 'available', 'name': 'Cookie', 'stock': 3},
        ],
      });

      final removed = await voidBranchInventoryAllocation(
        firestore: firestore,
        allocationId: 'allocation-1',
        allocationItemId: 'sold-out',
      );

      final allocation =
          (await firestore
                  .collection('staff_inventory')
                  .doc('allocation-1')
                  .get())
              .data()!;
      expect(removed, isTrue);
      expect(allocation['items'], [
        {'id': 'available', 'name': 'Cookie', 'stock': 3},
      ]);
      expect((allocation['removedItems'] as List).single['id'], 'sold-out');
      expect(allocation['isDeleted'], isFalse);
    },
  );

  test(
    'treats a previously removed allocation item as already voided',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_inventory').doc('allocation-1').set({
        'items': [
          {'id': 'available', 'name': 'Cookie', 'stock': 3},
        ],
      });

      expect(
        await voidBranchInventoryAllocation(
          firestore: firestore,
          allocationId: 'allocation-1',
          allocationItemId: 'already-removed',
        ),
        isFalse,
      );
      expect(
        (await firestore
                .collection('staff_inventory')
                .doc('allocation-1')
                .get())
            .data()!['items'],
        [
          {'id': 'available', 'name': 'Cookie', 'stock': 3},
        ],
      );
    },
  );

  test('treats a missing allocation as already removed', () async {
    final firestore = FakeFirebaseFirestore();

    expect(
      await voidBranchInventoryAllocation(
        firestore: firestore,
        allocationId: 'missing',
        allocationItemId: 'sold-out',
      ),
      isFalse,
    );
  });

  test('refuses to void an item that is no longer sold out', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_inventory').doc('allocation-1').set({
      'items': [
        {'id': 'item-1', 'name': 'Cookie', 'stock': 2},
      ],
    });

    expect(
      () => voidBranchInventoryAllocation(
        firestore: firestore,
        allocationId: 'allocation-1',
        allocationItemId: 'item-1',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
