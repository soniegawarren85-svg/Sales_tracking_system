import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/activity_feed.dart';
import 'package:sales_tracking/widgets/staff_performance_panel.dart';

void main() {
  testWidgets(
    'admin performance shows assigned allocation and return activity',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('activity_logs').doc('allocation').set({
        'action': 'inventory_allocated',
        'actorId': 'Spr-001',
        'actorName': 'Super admin',
        'actorPublicId': 'Spr-001',
        'actorRole': 'super_admin',
        'branchIds': ['branch-1'],
        'description': 'Allocated items to SM Dagupan',
        'createdAt': Timestamp.now(),
      });
      await db.collection('activity_logs').doc('return').set({
        'action': 'return_approved',
        'actorId': 'admin-auth',
        'actorName': 'Branch Admin',
        'actorPublicId': 'ADM-001',
        'actorRole': 'admin',
        'branchIds': ['branch-1'],
        'description': 'Approved inventory return',
        'createdAt': Timestamp.now(),
      });
      await db.collection('activity_logs').doc('other-branch').set({
        'action': 'inventory_allocated',
        'actorId': 'Spr-001',
        'actorRole': 'super_admin',
        'branchIds': ['branch-2'],
        'description': 'Allocated items to another branch',
        'createdAt': Timestamp.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityFeed(
              actorId: 'admin-auth',
              branchId: 'branch-1',
              includeBranchActivity: true,
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allocated items to SM Dagupan'), findsOneWidget);
      expect(find.text('Approved inventory return'), findsOneWidget);
      expect(find.text('Allocated items to another branch'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('activity cards show structured item details', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('activity_logs').doc('item-created').set({
      'action': 'inventory_created',
      'actorId': 'super-admin',
      'actorName': 'Super admin',
      'actorPublicId': 'Spr-001',
      'actorRole': 'super_admin',
      'description': 'Created inventory item Chocolate Cookie',
      'details': {
        'category': 'Cookies',
        'itemId': 'CO-014',
        'costPrice': 12,
        'sellingPrice': 25,
        'stock': 40,
        'items': [
          {'name': 'Chocolate Cookie', 'quantity': 4, 'itemId': 'CO-014'},
        ],
        'fields': ['name', 'price', 'stock'],
      },
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 18, 9, 30)),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityFeed(database: db, cardRows: true, compact: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Inventory created'), findsOneWidget);
    final renderedDetails = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(renderedDetails, contains('Category: Cookies'));
    expect(renderedDetails, contains('Item Id: CO-014'));
    expect(renderedDetails, contains('Selling Price: 25'));
    expect(renderedDetails, contains('Stock: 40'));
    expect(renderedDetails, contains('Chocolate Cookie × 4'));
    expect(
      find.textContaining('Updated fields: Name, Price, Stock'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity feed pages through five activities at a time', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (var index = 0; index < 12; index++) {
      await db.collection('activity_logs').doc('activity-$index').set({
        'action': 'inventory_created',
        'actorName': 'Super admin',
        'description': 'Activity $index',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 18, index)),
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityFeed(database: db, compact: true, cardRows: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(5));
    expect(find.text('Activity 11'), findsOneWidget);
    expect(find.text('Activity 6'), findsNothing);
    expect(find.text('1 / 3 • 12 activities'), findsOneWidget);

    await tester.tap(find.byTooltip('Next activities'));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(5));
    expect(find.text('Activity 6'), findsOneWidget);
    expect(find.text('Activity 11'), findsNothing);
    expect(find.text('2 / 3 • 12 activities'), findsOneWidget);

    await tester.tap(find.byTooltip('Next activities'));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('Activity 1'), findsOneWidget);
    expect(find.text('Activity 0'), findsOneWidget);
    expect(find.text('3 / 3 • 12 activities'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('branch performance matches assigned admins by public admin ID', () {
    expect(
      performanceAccountBelongsToBranch(
        branchId: 'branch-1',
        branchAccountIds: {'ADM-001'},
        documentId: 'auth-uid',
        account: {'uid': 'auth-uid', 'adminId': 'ADM-001', 'role': 'admin'},
      ),
      isTrue,
    );
  });

  test('branch performance matches assigned staff by user ID', () {
    expect(
      performanceAccountBelongsToBranch(
        branchId: 'branch-1',
        branchAccountIds: {'staff-uid'},
        documentId: 'request-doc',
        account: {'userId': 'staff-uid', 'role': 'staff'},
      ),
      isTrue,
    );
  });

  test('does not match an account outside the selected branch', () {
    expect(
      performanceAccountBelongsToBranch(
        branchId: 'branch-1',
        branchAccountIds: {'branch-2-staff'},
        documentId: 'other-uid',
        account: {
          'uid': 'other-uid',
          'branchIds': ['branch-2'],
        },
      ),
      isFalse,
    );
  });

  test('recognizes legacy admin accounts with an admin ID but no role', () {
    expect(performanceAccountRole({'adminId': 'ADM-002'}), 'admin');
    expect(
      performanceAccountAvailable(
        branchId: 'branch-1',
        branchAccountIds: {},
        documentId: 'legacy-admin',
        account: {
          'adminId': 'ADM-002',
          'branchIds': ['branch-1'],
        },
        roleSelection: true,
        selectedRole: 'admin',
      ),
      isTrue,
    );
    expect(
      performanceAccountAvailable(
        branchId: 'branch-1',
        branchAccountIds: {},
        documentId: 'inactive-admin',
        account: {'adminId': 'ADM-003', 'status': 'deactivated'},
        roleSelection: true,
        selectedRole: 'admin',
      ),
      isFalse,
    );
  });

  testWidgets('assigned admin is selectable and search remains pinned', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('branches/branch-1').set({'name': 'SM Dagupan'});
    await db.doc('staff_requests/admin-auth').set({
      'uid': 'admin-auth',
      'adminId': 'ADM-001',
      'branchIds': ['branch-1'],
      'role': 'admin',
      'status': 'accepted',
      'firstName': 'Branch',
      'lastName': 'Admin',
    });
    await db.doc('staff_requests/legacy-admin').set({
      'uid': 'legacy-admin',
      'adminId': 'ADM-002',
      'branchIds': ['branch-1'],
      'status': 'accepted',
      'firstName': 'Legacy',
      'lastName': 'Admin',
    });
    for (var index = 0; index < 8; index++) {
      await db.doc('activity_logs/activity-$index').set({
        'actorId': 'admin-auth',
        'actorName': 'Branch Admin',
        'actorPublicId': 'ADM-001',
        'actorRole': 'admin',
        'branchIds': ['branch-1'],
        'description': 'Updated inventory $index',
        'createdAt': Timestamp.fromDate(
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, index == 0 ? 23 : index),
        ),
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffPerformancePanel(
            branchId: 'branch-1',
            roleSelection: true,
            firestore: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    expect(dropdowns, findsOneWidget);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('Legacy Admin • ADM-002'), findsOneWidget);
    await tester.tap(find.text('Legacy Admin • ADM-002').last);
    await tester.pumpAndSettle();
    expect(find.text('Legacy Admin'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Branch Admin • ADM-001').last);
    await tester.pumpAndSettle();

    expect(find.text('Branch Admin'), findsWidgets);
    expect(find.text('Updated inventory 0'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Search performance details'), findsOneWidget);
    expect(find.text('Select role'), findsOneWidget);
    expect(find.text('Select admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin branch performance does not list ADM accounts', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('branches/branch-1').set({
      'name': 'SM Dagupan',
      'staffIds': ['cashier', 'admin'],
    });
    await db.doc('staff_requests/cashier').set({
      'uid': 'cashier',
      'staffId': 'STF-010',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Dagupan',
      'lastName': 'Cashier',
      'branchIds': ['branch-1'],
    });
    await db.doc('staff_requests/admin').set({
      'uid': 'admin',
      'adminId': 'ADM-001',
      'branchIds': ['branch-1'],
      'role': 'admin',
      'status': 'accepted',
      'firstName': 'Branch',
      'lastName': 'Admin',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffPerformancePanel(branchId: 'branch-1', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dagupan Cashier • STF-010'), findsOneWidget);
    expect(find.text('Branch Admin • ADM-001'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
