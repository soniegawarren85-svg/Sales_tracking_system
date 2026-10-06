import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/collection_storage.dart';
import 'package:sales_tracking/services/local_database_sync_service.dart';
import 'package:sales_tracking/services/cash_drawer_service.dart';

class MemoryStorage implements CollectionStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late offline queue changes only today drawer and never replays twice',
    () async {
      final db = FakeFirebaseFirestore();
      final service = LocalDatabaseSyncService.forDatabase(
        db,
        storage: MemoryStorage(),
      );
      await db.collection('staff_cash_drawer').doc('branch').set({
        'drawerDate': '2020-01-01',
        'dailyOpeningCash': 1200,
        'balance': 3018,
      });
      await service.cacheCollectionDocs('pending_cash_drawer_changes', [
        {
          '_localDocId': 'old',
          'drawerId': 'branch',
          'cashDelta': 500,
          'createdAt': DateTime.now().subtract(const Duration(days: 1)),
        },
        {
          '_localDocId': 'new',
          'drawerId': 'branch',
          'cashDelta': 89,
          'createdAt': DateTime.now(),
        },
      ]);
      await service.syncPendingCashDrawerChanges();
      await service.syncPendingCashDrawerChanges();
      final drawer =
          (await db.collection('staff_cash_drawer').doc('branch').get())
              .data()!;
      expect(drawer['balance'], 1289);
      expect(drawer['drawerDate'], CashDrawerService.dayKey(DateTime.now()));
      expect(drawer['appliedOfflineMutationIds'], containsAll(['old', 'new']));
      expect(
        await service.getCachedCollection('pending_cash_drawer_changes'),
        isEmpty,
      );
    },
  );
  test(
    'server cache merge includes only unapplied current-day pending movements',
    () async {
      final db = FakeFirebaseFirestore();
      final service = LocalDatabaseSyncService.forDatabase(
        db,
        storage: MemoryStorage(),
      );
      await service.cacheCollectionDocs('pending_cash_drawer_changes', [
        {
          '_localDocId': 'old',
          'drawerId': 'branch',
          'cashDelta': 500,
          'createdAt': DateTime.now().subtract(const Duration(days: 1)),
        },
        {
          '_localDocId': 'new',
          'drawerId': 'branch',
          'cashDelta': 89,
          'createdAt': DateTime.now(),
        },
      ]);
      final server = {
        '_localDocId': 'branch',
        'balance': 1200,
        'dailyOpeningCash': 1200,
        'drawerDate': CashDrawerService.dayKey(DateTime.now()),
      };
      expect(
        (await service.mergeCashDrawerSnapshot([server])).single['balance'],
        1289,
      );
      expect(
        (await service.mergeCashDrawerSnapshot([
          {
            ...server,
            'balance': 1289,
            'appliedOfflineMutationIds': ['new'],
          },
        ])).single['balance'],
        1289,
      );
    },
  );
  test(
    'inventory replacement refunds do not change the staff cash drawer',
    () async {
      final db = FakeFirebaseFirestore();
      final service = LocalDatabaseSyncService.forDatabase(
        db,
        storage: MemoryStorage(),
      );
      await db.collection('staff_cash_drawer').doc('branch').set({
        'balance': 500,
        'dailyOpeningCash': 500,
        'drawerDate': CashDrawerService.dayKey(DateTime.now()),
      });

      await service.recordCompletedSale({
        'salesId': 'replacement-refund',
        'userId': 'staff',
        'branchId': 'branch',
        'type': 'refund',
        'status': 'Refund',
        'refundMethod': 'inventory',
        'paymentMode': 'Inventory replacement',
        'cashDrawerDelta': 0,
        'total': -89,
        'replacementValue': 89,
        'timestamp': DateTime.now(),
      });

      final drawer =
          (await db.collection('staff_cash_drawer').doc('branch').get())
              .data()!;
      expect(drawer['balance'], 500);
      expect((await service.getCachedCollection('completed_sales')).single['total'], -89);
      expect(
        await service.getCachedCollection('pending_cash_drawer_changes'),
        isEmpty,
      );
    },
  );
}
