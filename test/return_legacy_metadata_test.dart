import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/return_metadata_service.dart';
import 'package:sales_tracking/widgets/return_batch_cards.dart';

void main() {
  testWidgets(
    'legacy details recover short IDs, staff, expiry and bundle filters',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/staff').set({
        'firstName': 'Yacult',
        'lastName': 'Pngovue',
        'staffId': 'STF-001',
        'email': 'cc@gmail.com',
      });
      await db.doc('sales_inventory/cookies').set({
        'items': [
          {
            'id': 'VAR-1788168384770000-716957',
            'publicId': 'CO-006',
            'name': 'Red Velvet',
            'expirationDate': '2026-12-31',
          },
          {
            'id': 'pistachio',
            'publicId': 'CO-004',
            'name': 'Pistachio Dubai Chewy',
            'expirationDate': '2026-12-31',
          },
        ],
      });
      await db.doc('sales_inventory/bundle').set({
        'isBundle': true,
        'bundleId': 'BND-001',
        'name': 'Bundle Cakes',
        'expirationDate': '2026-12-30',
        'items': [
          {'id': 'old-pistachio-copy', 'name': 'Pistachio Dubai Chewy'},
        ],
      });
      await db.doc('stock_adjustments/reduce').set({
        'userId': 'staff',
        'itemId': 'VAR-1788168384770000-716957',
        'itemName': 'Red Velvet',
        'expirationDate': '2026-10-01',
      });
      final resolver = ReturnMetadataService(db);
      final red = await resolver.resolve({
        'name': 'Red Velvet',
        'itemDisplayId': 'VAR-1788168384770000-716957',
        'returnSourceCollection': 'stock_adjustments',
        'returnSourceId': 'reduce',
        'sourceStaffName': 'cc@gmail.com',
      });
      expect(red['itemDisplayId'], 'CO-006');
      expect(red['sourceStaffName'], 'Yacult Pngovue');
      expect(red['sourceStaffId'], 'STF-001');
      expect(red['expirationDate'], '2026-10-01');
      expect(
        await resolver.itemCode({
          'name': 'Pistachio Dubai Chewy',
          'itemDisplayId': '--',
        }),
        'CO-004',
      );
      final records = [
        {
          'name': 'Red Velvet',
          'itemDisplayId': 'VAR-1788168384770000-716957',
          'returnSourceCollection': 'stock_adjustments',
          'returnSourceId': 'reduce',
        },
        {'name': 'Bundle Cakes', 'itemDisplayId': 'BND-001', 'isBundle': false},
      ];
      for (var i = 0; i < records.length; i++) {
        await db.doc('allocation_checklist/r$i').set({
          ...records[i],
          'kind': 'return',
          'submittedBy': 'staff',
          'staffId': 'branch',
          'submittedByName': 'cc@gmail.com',
          'createdAt': Timestamp.fromDate(DateTime(2026, 10, 4, 17, 42)),
        });
      }
      final docs = (await db.collection('allocation_checklist').get()).docs;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReturnBatchList(
              docs: docs,
              itemBuilder: (doc) => ReturnItemCard(
                key: ValueKey(doc.id),
                data: doc.data(),
                db: db,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Categories (1)'), findsOneWidget);
      expect(find.text('Bundle (1)'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Item ID: CO-006'), findsOneWidget);
      expect(find.text('Staff: cc@gmail.com'), findsNothing);
      expect(find.text('Staff ID: Not recorded'), findsNothing);
      expect(find.text('Expiry: 2026-10-01'), findsOneWidget);
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(find.text('Bundle Cakes'), findsNothing);
      expect(find.text('Red Velvet'), findsOneWidget);
      await tester.tap(find.text('Bundle'));
      await tester.pumpAndSettle();
      expect(find.text('Bundle Cakes'), findsOneWidget);
      expect(find.text('Red Velvet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'legacy item resolves master ID, never the refund document ID',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('sales_inventory/cookies').set({
        'items': [
          {'name': 'Pistachio Dubai Chewy', 'publicId': 'CO-004'},
        ],
      });
      final metadata = ReturnMetadataService(db);
      expect(
        await metadata.itemCode({
          'name': 'Pistachio Dubai Chewy',
          'itemDisplayId': '--',
          'id': 'refund-document',
          'collection': 'completed_sales',
        }),
        'CO-004',
      );
      await db.doc('staff_requests/uid').set({
        'firstName': 'Maria',
        'lastName': 'Santos',
        'email': 'staff@example.com',
        'staffId': 'STF-2',
      });
      expect(await metadata.profile('uid'), {
        'name': 'Maria Santos',
        'staffId': 'STF-002',
      });
      expect(await metadata.profile('staff@example.com'), {
        'name': 'Maria Santos',
        'staffId': 'STF-002',
      });
    },
  );

  testWidgets(
    'same-minute legacy returns group, retain all details and resolve staff',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/uid').set({
        'firstName': 'Maria',
        'lastName': 'Santos',
        'staffId': 'STF-002',
      });
      for (var i = 0; i < 4; i++) {
        await db.doc('allocation_checklist/r$i').set({
          'kind': 'return',
          'staffId': 'branch',
          'branchId': 'branch',
          'branchName': 'Dagupan',
          'submittedBy': i == 3 ? 'other' : 'uid',
          'submittedByName': 'staff@example.com',
          'createdAt': Timestamp.fromDate(
            DateTime(2026, 10, 4, 17, i == 2 ? 43 : 42, i),
          ),
          'name': 'Item $i',
          'status': 'Awaiting Admin Confirmation',
        });
      }
      final docs = (await db.collection('allocation_checklist').get()).docs;
      final groups = groupReturnBatches(docs);
      expect(groups.length, 3);
      expect(groups.values.first.length, 2);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReturnBatchList(
              docs: docs.take(2).toList(),
              itemBuilder: (doc) => Text(doc.data()['name']),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Staff: Maria Santos'), findsOneWidget);
      expect(find.text('Staff ID: STF-002'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.text('Categories (2)'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
