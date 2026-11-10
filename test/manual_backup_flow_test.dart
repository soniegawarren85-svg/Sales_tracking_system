import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/database_backup.dart';
import 'package:sales_tracking/services/encrypted_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'manual export, encryption, validation, and merge restore round-trip',
    () async {
      final firestore = FakeFirebaseFirestore();
      final created = Timestamp.fromDate(DateTime.utc(2026, 11, 8, 12));
      await firestore.collection('sales_inventory').doc('product-001').set({
        'name': 'Test cookies',
        'stock': 12,
        'createdAt': created,
        'branchRef': firestore.collection('branches').doc('branch-001'),
        'variants': [
          {'name': 'Regular', 'stock': 12},
        ],
      });
      await firestore.collection('messages').doc('thread-001').set({
        'subject': 'Test conversation',
      });
      await firestore
          .collection('messages')
          .doc('thread-001')
          .collection('items')
          .doc('message-001')
          .set({'text': 'backup subcollection'});

      final clear = await DatabaseBackup.export(
        firestore: firestore,
        backupName: 'QA manual backup',
      );
      final manifest = DatabaseBackup.inspect(clear);
      expect(manifest.backupName, 'QA manual backup');
      expect(manifest.documentCount, 3);
      final encrypted = await EncryptedBackup.encrypt(
        clear,
        'Original-Super-Admin-Pass!',
      );
      expect(utf8.decode(encrypted), isNot(contains('Test cookies')));

      final decrypted = await EncryptedBackup.decrypt(
        encrypted,
        'Original-Super-Admin-Pass!',
      );
      expect(DatabaseBackup.inspect(decrypted).backupId, manifest.backupId);
      await expectLater(
        EncryptedBackup.decrypt(encrypted, 'wrong-password'),
        throwsFormatException,
      );
      final damagedEnvelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final cipherText = base64Decode(damagedEnvelope['cipherText'] as String);
      cipherText[0] ^= 1;
      damagedEnvelope['cipherText'] = base64Encode(cipherText);
      await expectLater(
        EncryptedBackup.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(damagedEnvelope))),
          'Original-Super-Admin-Pass!',
        ),
        throwsFormatException,
      );

      final restoreData = DatabaseBackup.validate(
        decrypted,
        firestore: firestore,
      );
      expect(
        restoreData.keys,
        contains('messages/thread-001/items/message-001'),
      );
      expect(restoreData['sales_inventory/product-001']!['createdAt'], created);
      expect(
        (restoreData['sales_inventory/product-001']!['branchRef']
                as DocumentReference)
            .path,
        'branches/branch-001',
      );

      await firestore.collection('sales_inventory').doc('product-001').update({
        'name': 'Changed after backup',
        'newerField': 'keep this field',
      });
      await firestore
          .collection('sales_inventory')
          .doc('created-after-backup')
          .set({'name': 'Must remain'});
      final restoredCount = await DatabaseBackup.restoreMerge(
        restoreData,
        firestore: firestore,
      );
      expect(restoredCount, 3);

      final restoredProduct = await firestore
          .collection('sales_inventory')
          .doc('product-001')
          .get();
      expect(restoredProduct.data()?['name'], 'Test cookies');
      expect(restoredProduct.data()?['newerField'], 'keep this field');
      expect(
        (await firestore
                .collection('sales_inventory')
                .doc('created-after-backup')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test(
    'branch backups contain and restore only assigned branch records',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('branches').doc('branch-001').set({
        'name': 'Lingayen',
      });
      await firestore.collection('branches').doc('branch-002').set({
        'name': 'Dagupan',
      });
      await firestore.collection('completed_sales').doc('sale-001').set({
        'branchId': 'branch-001',
        'total': 100,
      });
      await firestore.collection('completed_sales').doc('sale-002').set({
        'branchId': 'branch-002',
        'total': 200,
      });
      await firestore.collection('staff_inventory').doc('inventory-001').set({
        'staffId': 'branch-001',
        'items': ['one', 'two'],
      });
      await firestore.collection('staff_inventory').doc('inventory-002').set({
        'staffId': 'branch-002',
        'items': ['other branch'],
      });
      await firestore.collection('messages').doc('branch-message').set({
        'branchIds': ['branch-001', 'branch-002'],
        'subject': 'Branch conversation',
      });
      await firestore
          .collection('messages')
          .doc('branch-message')
          .collection('items')
          .doc('message-item')
          .set({'text': 'branch item'});
      await firestore.collection('coffee_products').doc('global-product').set({
        'name': 'Shared catalog record',
      });

      final branchBackup = await DatabaseBackup.export(
        firestore: firestore,
        branchIds: {'branch-001'},
        branchNames: {'lingayen'},
      );
      final manifest = DatabaseBackup.inspect(branchBackup);
      final docs = DatabaseBackup.validate(branchBackup, firestore: firestore);

      expect(manifest.documentCount, 5);
      expect(docs.keys, contains('branches/branch-001'));
      expect(docs.keys, contains('completed_sales/sale-001'));
      expect(docs.keys, contains('staff_inventory/inventory-001'));
      expect(docs.keys, contains('messages/branch-message/items/message-item'));
      expect(docs.keys, isNot(contains('branches/branch-002')));
      expect(docs.keys, isNot(contains('completed_sales/sale-002')));
      expect(docs.keys, isNot(contains('coffee_products/global-product')));
      expect(docs['messages/branch-message']!['branchIds'], ['branch-001']);

      final globalBackup = await DatabaseBackup.export(firestore: firestore);
      final restricted = DatabaseBackup.restrictToBranches(
        globalBackup,
        branchIds: {'branch-001'},
        branchNames: {'lingayen'},
      );
      final restrictedDocs = DatabaseBackup.validate(
        restricted,
        firestore: firestore,
      );
      expect(restrictedDocs.keys, docs.keys);
    },
  );
}
