import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/staff_allocation_scope.dart';
import 'package:sales_tracking/services/local_database_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'delayed profile resolves legacy branch membership, items and cash',
    () async {
      final db = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await db.collection('branches').doc('branch-a').set({
        'staffIds': ['STF-0001'],
      });
      await db.collection('staff_inventory').doc('cookies').set({
        'staffId': 'branch-a',
        'name': 'Cookies',
      });
      await db.collection('staff_inventory').doc('direct').set({
        'staffId': 'user-a',
        'name': 'Beverages',
      });
      await db.collection('staff_inventory').doc('legacy').set({
        'staffId': 'STF-0001',
        'name': 'Bundle',
      });
      await db.collection('staff_inventory').doc('other').set({
        'staffId': 'other-branch',
        'name': 'Private item',
      });
      await db.collection('staff_cash_drawer').doc('branch-a').set({
        'balance': 1497,
      });
      final scopes = <StaffAllocationScope>[];
      final resolved = Completer<StaffAllocationScope>();
      final first = Completer<void>();
      final subscription =
          watchStaffAllocationScope(
            'user-a',
            firestore: db,
            preferences: prefs,
            readCachedProfiles: () async => [],
          ).listen((scope) {
            scopes.add(scope);
            if (!first.isCompleted) first.complete();
            if (scope.targets.contains('branch-a') && !resolved.isCompleted)
              resolved.complete(scope);
          });
      addTearDown(subscription.cancel);
      await first.future;
      // Membership information arrives after the initial empty SDK snapshot.
      await db.collection('staff_requests').doc('user-a').set({
        'staffId': 'STF-001',
      });
      final scope = await resolved.future.timeout(const Duration(seconds: 3));
      expect(scopes.first.targets, contains('user-a'));
      final items = await db
          .collection('staff_inventory')
          .where('staffId', whereIn: scope.targets)
          .get();
      expect(
        items.docs.map((doc) => doc.id),
        unorderedEquals(['cookies', 'direct', 'legacy']),
      );
      final drawer = await db
          .collection('staff_cash_drawer')
          .where(FieldPath.documentId, whereIn: scope.targets)
          .get();
      expect(drawer.docs.single.data()['balance'], 1497);
    },
  );

  test(
    'assigning a branch after opening the screen updates its scope',
    () async {
      final db = FakeFirebaseFirestore();
      await db.collection('staff_requests').doc('user-a').set({
        'staffId': 'STF-002',
      });
      final updated = Completer<StaffAllocationScope>();
      final subscription =
          watchStaffAllocationScope(
            'user-a',
            firestore: db,
            readCachedProfiles: () async => [],
          ).listen((scope) {
            if (scope.targets.contains('new-branch') && !updated.isCompleted)
              updated.complete(scope);
          });
      addTearDown(subscription.cancel);
      await db.collection('branches').doc('new-branch').set({
        'staffIds': ['user-a'],
      });
      expect(
        (await updated.future.timeout(const Duration(seconds: 3))).targets,
        contains('new-branch'),
      );
    },
  );

  test(
    'another staff account cannot inherit legacy cached branch IDs',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastUserId': 'other-user',
        'lastStaffBranchIds': ['other-branch'],
      });
      final first = await watchStaffAllocationScope(
        'user-a',
        firestore: FakeFirebaseFirestore(),
        readCachedProfiles: () async => [],
      ).first;
      expect(first.targets, ['user-a']);
    },
  );

  test(
    'empty early staff query cannot erase branch allocations from disk',
    () async {
      final service = LocalDatabaseSyncService.forDatabase(
        FakeFirebaseFirestore(),
      );
      await service.cacheCollectionDocs('staff_inventory', [
        {'_localDocId': 'cookie', 'staffId': 'branch-a', 'name': 'Cookies'},
        {'_localDocId': 'own', 'staffId': 'user-a', 'name': 'Beverages'},
      ]);
      await service.cacheStaffInventorySnapshot(['user-a'], []);
      expect(
        (await service.getCachedCollection(
          'staff_inventory',
        )).map((r) => r['_localDocId']),
        ['cookie'],
      );
      await service.cacheStaffInventorySnapshot(
        ['branch-a'],
        [],
        authoritative: false,
      );
      expect(
        (await service.getCachedCollection('staff_inventory')).single['name'],
        'Cookies',
      );
      // A confirmed deletion for this branch must still be reflected.
      await service.cacheStaffInventorySnapshot(['branch-a'], []);
      expect(await service.getCachedCollection('staff_inventory'), isEmpty);
    },
  );

  test(
    'server balance replaces cached zero while retaining offline sales once',
    () async {
      final service = LocalDatabaseSyncService.forDatabase(
        FakeFirebaseFirestore(),
      );
      await service.cacheCollectionDocs('staff_cash_drawer', [
        {'_localDocId': 'branch-a', 'balance': 0},
      ]);
      await service.cacheCollectionDocs('pending_cash_drawer_changes', [
        {
          '_localDocId': 'receipt-1',
          'drawerId': 'branch-a',
          'receiptId': '1',
          'cashDelta': 100,
        },
      ]);
      final pending = await service.mergeCashDrawerSnapshot([
        {'_localDocId': 'branch-a', 'balance': 1497},
      ]);
      expect(pending.single['balance'], 1597);
      final synced = await service.mergeCashDrawerSnapshot([
        {
          '_localDocId': 'branch-a',
          'balance': 1597,
          'appliedOfflineMutationIds': ['receipt-1'],
        },
      ]);
      expect(synced.single['balance'], 1597);
      expect(
        (await service.mergeCashDrawerSnapshot([])).single['balance'],
        1597,
      );
    },
  );
}
