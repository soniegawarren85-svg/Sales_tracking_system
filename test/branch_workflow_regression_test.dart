import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/account_password_service.dart';
import 'package:sales_tracking/services/super_admin.dart';
import 'package:sales_tracking/services/report_current_allocations.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/sale_stock.dart';
import 'package:sales_tracking/widgets/branch_inventory_edit_dialog.dart';
import 'package:sales_tracking/widgets/branch_allocation_history.dart';
import 'package:sales_tracking/widgets/activity_feed.dart';
import 'package:sales_tracking/widgets/inventory_batches.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('super admin changed password is authoritative on another device', () async {
    final db = FakeFirebaseFirestore();
    expect(await SuperAdmin.verifyPassword('Super@123', database: db), isTrue);
    await SuperAdmin.updatePassword('Changed@123', database: db);
    SharedPreferences.setMockInitialValues({});
    expect(await SuperAdmin.verifyPassword('Super@123', database: db), isFalse);
    expect(await SuperAdmin.verifyPassword('Changed@123', database: db), isTrue);
  });

  test('admin password change removes all old password fallbacks', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.doc('staff_requests/admin');
    await ref.set({'role': 'admin', 'password': 'Old@123', 'temporaryPassword': 'Temporary@123'});
    await expectLater(changeFirestoreAccountPassword(account: ref,
      currentPassword: 'wrong', newPassword: 'Changed@123'), throwsStateError);
    await changeFirestoreAccountPassword(account: ref,
      currentPassword: 'Old@123', newPassword: 'Changed@123');
    final saved = (await ref.get()).data()!;
    expect(saved.containsKey('password'), isFalse);
    expect(saved.containsKey('temporaryPassword'), isFalse);
    expect(await matchesAccountPassword(saved, 'Old@123'), isFalse);
    expect(await matchesAccountPassword(saved, 'Temporary@123'), isFalse);
    expect(await matchesAccountPassword(saved, 'Changed@123'), isTrue);
  });

  test('cash drawer counts reusable fund once across day week month year', () {
    final now = DateTime(2026, 10, 18);
    final data = BranchReportData({
      'branches': [{'_id': 'b'}],
      'staff_cash_drawer': [{'_id': 'b', 'dailyOpeningCash': 2000}],
      'budget_history': [
        for (var day = 1; day <= 17; day++)
          {'staffId': 'b', 'type': 'set_daily_cash_drawer', 'amount': 1500, 'createdAt': DateTime(2026, 10, day)},
        {'staffId': 'b', 'type': 'set_daily_cash_drawer', 'amount': 2000, 'createdAt': now},
      ],
    });
    for (final start in [now, DateTime(2026, 10, 12), DateTime(2026, 10), DateTime(2026)]) {
      expect(configuredReportCash(data, start, DateTime(2027), now)['b'], 2000);
    }
    expect(configuredReportCash(data, DateTime(2026, 10), DateTime(2026, 10, 18), now)['b'], 1500);
  });

  test('category sale spanning batches deducts each allocation exactly once', () {
    final item = <String, dynamic>{'itemId': 'p', 'stock': 130,
      'categoryInventorySources': [
        {'staffInventoryDocId': 'a', 'stock': 100, 'assignedAt': '2026-10-17'},
        {'staffInventoryDocId': 'b', 'stock': 30, 'assignedAt': '2026-10-18'},
      ]};
    final lines = categorySaleLines(item, 110);
    expect(lines.map((r) => r['quantity']), [100, 10]);
    final expanded = expandSaleStockLines([{'itemId': 'p', 'quantity': 110, 'stockAllocations': lines}]);
    expect(expanded.map((r) => r['staffInventoryDocId']), ['a', 'b']);
    final updated = applySaleStock({'items': [{'id': 'p', 'stock': 30}]}, 'sale', [expanded.last]);
    expect((updated['items'] as List).single['stock'], 20);
    expect(applySaleStock(updated, 'sale', [expanded.last]), updated);
    expect(() => categorySaleLines(item, 131), throwsStateError);
  });

  for (final width in [390.0, 900.0]) {
    testWidgets('inventory editor saves and reopens safely at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      BranchInventoryEdit? saved;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        TextButton(onPressed: () async { saved = await showDialog<BranchInventoryEdit>(context: context,
          builder: (_) => const BranchInventoryEditDialog(item: {'name': 'Pistachio', 'price': 99, 'remaining': 130.0})); }, child: const Text('Edit'))))));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Edit')); await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).last, '140');
        await tester.tap(find.text('Save')); await tester.pumpAndSettle();
        expect(saved?.stock, 140); expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('history displays seeded records immediately and expands inline', (tester) async {
    final db = FakeFirebaseFirestore();
    final record = <String,dynamic>{'_id': 'x', 'staffId': 'b', 'status': 'Received',
      'createdAt': Timestamp.now(), 'confirmedByName': 'Mia', 'confirmedByRole': 'Cashier',
      'confirmedByPublicId': 'STF-010', 'items': [{'name': 'Cookie', 'stock': 130}]};
    await db.doc('allocation_checklist/x').set(record);
    await tester.pumpWidget(MaterialApp(home: AllocationHistoryDialog(branchId: 'b', database: db, initialRecords: [record])));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Received by: Mia'), findsOneWidget);
    await tester.pumpAndSettle(); await tester.tap(find.byTooltip('Expand items')); await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Cookie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('performance attributes receipts and returns to selected cashier', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('activity_logs/super').set({'actorId': 'Spr-001', 'branchIds': ['b'], 'description': 'Allocated by super', 'createdAt': Timestamp.now()});
    await db.doc('allocation_checklist/received').set({'staffId': 'b', 'status': 'Received',
      'confirmedBy': 'staff', 'confirmedByName': 'Mia', 'confirmedByPublicId': 'STF-010',
      'confirmedAt': Timestamp.now(), 'allocatedByName': 'Super admin', 'name': 'Cookies'});
    await db.doc('allocation_checklist/returned').set({'staffId': 'b', 'kind': 'return',
      'submittedBy': 'staff', 'submittedByName': 'Mia', 'createdAt': Timestamp.now()});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActivityFeed(actorId: 'staff', branchId: 'b', includeReceipts: true, database: db))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Received allocation from Super admin'), findsOneWidget);
    expect(find.text('Submitted items for return to Super Admin'), findsOneWidget);
    expect(find.text('Allocated by super'), findsNothing);
  });

  testWidgets('completed reconciliations use review day not submission day', (tester) async {
    final db = FakeFirebaseFirestore(); final now = DateTime.now();
    for (final entry in [('today', now), ('old', now.subtract(const Duration(days: 2)))]) {
      await db.doc('inventory_reconciliations/${entry.$1}').set({'branchName': entry.$1,
        'status': 'approved', 'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
        'reviewedAt': Timestamp.fromDate(entry.$2)});
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReconciliationRequestsButton(database: db))));
    await tester.tap(find.text('Reconciliation')); await tester.pumpAndSettle();
    await tester.tap(find.text('Completed Requests')); await tester.pumpAndSettle();
    expect(find.text('today'), findsOneWidget); expect(find.text('old'), findsNothing);
  });
}
