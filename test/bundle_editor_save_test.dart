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
}
