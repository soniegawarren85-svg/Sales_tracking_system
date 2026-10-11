import 'dart:async';
import 'package:sales_tracking/services/bundle_metadata_service.dart';
import 'package:sales_tracking/services/checklist_status.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/widgets/admin_item_editor.dart';

void main() {
  test('save errors identify permissions and size failures', () {
    expect(
      inventorySaveError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
      contains('permissions'),
    );
    expect(
      inventorySaveError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'resource-exhausted',
        ),
      ),
      contains('too large'),
    );
  });
  testWidgets(
    'bundle editor loads current names and dates and saves added stock',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('sales_inventory').doc('cat').set({
        'name': 'Cookies',
        'items': [
          {
            'id': 'v',
            'publicId': 'CO-006',
            'name': 'Red Velvet',
            'stock': 40,
            'expirationDate': '2099-12-31',
          },
        ],
      });
      final data = <String, dynamic>{
        'id': 'b',
        'name': 'Cookies Bundle',
        'price': 500,
        'isBundle': true,
        'bundleCount': 0,
        'items': [
          {
            'sourceInventoryId': 'cat',
            'variantId': 'v',
            'name': 'Old name',
            'quantity': 2,
          },
        ],
      };
      await db.collection('sales_inventory').doc('b').set(data);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminItemEditor(
                  context,
                  entry: AdminCatalogEntry(
                    id: 'BND-001',
                    name: 'Cookies Bundle',
                    type: 'Bundle',
                    source: data,
                    details: data,
                    images: [],
                  ),
                  firestore: db,
                  upload: (_) async => null,
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Each new bundle'), findsNothing);
      expect(find.textContaining('Expires: 2099-12-31'), findsOneWidget);
      expect(find.textContaining('Red Velvet'), findsWidgets);
      final quantity = find.byWidgetPredicate(
        (widget) => widget is TextFormField && widget.controller?.text == '0',
      );
      await tester.enterText(quantity, '10');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(
        (await db.collection('sales_inventory').doc('b').get())
            .data()!['bundleCount'],
        10,
      );
      expect(
        ((await db.collection('sales_inventory').doc('cat').get())
                    .data()!['items']
                as List)
            .single['stock'],
        20,
      );
    },
  );
  testWidgets(
    'metadata save preserves concurrent stock and updates allocation cost',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final item = <String, dynamic>{
        'id': 'v',
        'publicId': 'CO-1',
        'name': 'Cookie',
        'stock': 100,
        'price': 50,
        'costPrice': 25,
        'expirationDate': '2099-12-31',
      };
      final category = <String, dynamic>{
        'id': 'cat',
        'name': 'Cookies',
        'items': [item],
      };
      await db.doc('sales_inventory/cat').set(category);
      await db.doc('staff_inventory/a').set({
        'sourceInventoryId': 'cat',
        'items': [
          {...item, 'stock': 10},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminItemEditor(
                  context,
                  entry: AdminCatalogEntry(
                    id: 'CO-1',
                    name: 'Cookie',
                    type: 'Categories',
                    source: category,
                    details: item,
                    images: [],
                  ),
                  firestore: db,
                  upload: (_) async => null,
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      // A sale arrives after the editor opened, before the admin changes cost.
      await db.doc('sales_inventory/cat').update({
        'items': [
          {...item, 'stock': 80},
        ],
      });
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == '25',
        ),
        '30',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved =
          ((await db.doc('sales_inventory/cat').get()).data()!['items'] as List)
              .single;
      expect(saved['stock'], 80);
      expect(saved['costPrice'], 30);
      final allocation =
          ((await db.doc('staff_inventory/a').get()).data()!['items'] as List)
              .single;
      expect(allocation['stock'], 10);
      expect(allocation['costPrice'], 30);
      expect(find.text('Edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('timeout and wrapped web timeout show a useful save status', () {
    for (final error in [
      TimeoutException('save'),
      StateError(
        "TypeError: Instance of 'TimeoutException': type 'TimeoutException' is not a subtype of type 'JavaScriptObject'",
      ),
    ]) {
      final message = inventorySaveError(error);
      expect(message, contains('did not confirm'));
      expect(message, isNot(contains('JavaScriptObject')));
    }
  });
  test(
    'save scopes exclude closed, deleted and unrelated allocation records',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 60; i++) {
        await db.doc('allocation_checklist/closed$i').set({
          'sourceInventoryId': 'cat',
          'status': ChecklistStatus.received,
          'costPrice': 0,
        });
        await db.doc('staff_inventory/deleted$i').set({
          'sourceInventoryId': 'cat',
          'isDeleted': true,
          'costPrice': 0,
        });
      }
      await db.doc('staff_inventory/active').set({
        'sourceInventoryId': 'cat',
        'costPrice': 0,
      });
      await db.doc('staff_inventory/current').set({
        'sourceInventoryId': 'cat',
        'costPrice': 50,
      });
      await db.doc('allocation_checklist/pending').set({
        'sourceInventoryId': 'cat',
        'status': ChecklistStatus.awaiting,
        'costPrice': 0,
      });
      final targets = await bundleMetadataTargets(
        db,
        'cat',
        needsUpdate: (data) => data['costPrice'] != 50,
      );
      expect(targets.map((r) => r.path).toSet(), {
        'staff_inventory/active',
        'allocation_checklist/pending',
      });
    },
  );
  test('only changed fields are included in inventory updates', () {
    expect(
      inventoryChangedFields(
        {'name': 'Cookie', 'price': 89.0, 'costPrice': 50, 'stock': 200},
        {'name': 'Cookie', 'price': 89, 'costPrice': 55, 'stock': 200},
      ),
      {'costPrice': 55},
    );
  });
}
