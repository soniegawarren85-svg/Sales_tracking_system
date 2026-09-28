import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_metadata_service.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';
import 'package:sales_tracking/widgets/admin_recent_sales.dart';

void main() {
  test('Bundle price sync preserves stock and accepted history', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('b').set({
      'isBundle': true,
      'price': 500,
    });
    for (final collection in ['staff_inventory', 'allocation_checklist']) {
      await db.collection(collection).doc('a').set({
        'sourceInventoryId': 'b',
        'isBundle': true,
        'price': 500,
        'stock': 7,
        'status': 'pending',
      });
    }
    await db.collection('allocation_checklist').doc('old').set({
      'sourceInventoryId': 'b',
      'isBundle': true,
      'price': 500,
      'status': 'accepted',
    });
    await updateBundleMetadata(db, 'b', {'price': 650});
    expect(
      (await db.collection('sales_inventory').doc('b').get()).data()!['price'],
      650,
    );
    final assigned = (await db.collection('staff_inventory').doc('a').get())
        .data()!;
    expect(assigned['price'], 650);
    expect(assigned['stock'], 7);
    expect(
      (await db.collection('allocation_checklist').doc('a').get())
          .data()!['price'],
      650,
    );
    expect(
      (await db.collection('allocation_checklist').doc('old').get())
          .data()!['price'],
      500,
    );
  });
  testWidgets('Latest sessions include logout and update live', (tester) async {
    final db = FakeFirebaseFirestore();
    final sessions = db.collection('staff_login_sessions');
    await sessions.doc('old').set({
      'branchId': 'b',
      'userId': 'u',
      'staffId': 'ST-001',
      'staffName': 'Earlier',
      'loginAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'logoutAt': Timestamp.fromDate(DateTime(2026, 1, 1, 8)),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BranchStaffActivityDialog(
          branchId: 'b',
          branchName: 'Branch',
          firestore: db,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    await sessions.doc('new').set({
      'branchId': 'b',
      'userId': 'u',
      'staffId': 'ST-001',
      'staffName': 'Latest',
      'loginAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
    });
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Earlier'), findsNothing);
    await tester.tap(find.byTooltip('Session history'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Sixth receipt appears on next page of five', (tester) async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 6; i++) {
      await db.collection('completed_sales').doc('r$i').set({
        'salesId': 'Receipt $i',
        'timestamp': Timestamp.fromDate(
          DateTime.now().subtract(Duration(seconds: i)),
        ),
        'items': [],
        'total': 10,
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AdminRecentSales(firestore: db)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt 0'), findsOneWidget);
    expect(find.text('Receipt 4'), findsOneWidget);
    expect(find.text('Receipt 5'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Next receipts'));
    await tester.tap(find.byTooltip('Next receipts'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt 5'), findsOneWidget);
    expect(find.text('Receipt 0'), findsNothing);
    await tester.tap(find.byTooltip('Previous receipts'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
