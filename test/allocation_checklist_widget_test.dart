import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';

void main() {
  for (final width in [360.0, 768.0]) {
    testWidgets('admin checklist at $width watches returns across branches', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await db.doc('allocation_checklist/return').set({
        'kind': 'return',
        'status': 'Awaiting Admin Confirmation',
        'name': 'Damaged cookie',
        'quantity': 2,
        'staffId': 'branch',
      });
      await db.doc('allocation_checklist/incoming').set({
        'status': 'Awaiting Confirmation',
        'name': 'Delivery',
        'staffId': 'branch',
      });
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const [],
              isAdmin: true,
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checklist (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Received'), findsNothing);
      expect(find.text('Returned Items'), findsOneWidget);
      expect(find.text('Incoming Items'), findsNothing);
      expect(find.textContaining('Pending Confirmation'), findsNothing);
      expect(find.text('Review returned items'), findsOneWidget);
      expect(find.text('Waiting Admin Confirmation'), findsNothing);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(
        tester.getCenter(find.text('View')).dy,
        closeTo(tester.getCenter(find.text('branch')).dy, 1),
      );
      expect(
        tester.getCenter(find.text('View')).dx,
        greaterThan(tester.getCenter(find.text('branch')).dx),
      );
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Decline'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Decline return'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('A reason is required'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      final details = find.ancestor(
        of: find.text('Returned items'),
        matching: find.byType(Dialog),
      );
      expect(
        find.descendant(of: details, matching: find.text('Accept')),
        findsNothing,
      );
      expect(
        find.descendant(of: details, matching: find.text('Decline')),
        findsNothing,
      );
      await db.doc('allocation_checklist/return').update({
        'status': 'Return Completed',
      });
      await tester.pumpAndSettle();
      expect(find.text('Returned Items'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close returned items'));
      await tester.pumpAndSettle();
      expect(find.text('Done · Return accepted'), findsOneWidget);
      await tester.tap(find.byTooltip('Close checklist'));
      await tester.pumpAndSettle();
      expect(find.text('Checklist (0)'), findsOneWidget);
    });
  }

  testWidgets(
    'branch checklist count, search, type filter and required issue reason',
    (tester) async {
      final db = FakeFirebaseFirestore();
      for (final row in [
        {
          'staffId': 'branch',
          'status': 'pending',
          'name': 'Cookies',
          'items': [
            {'name': 'Chocolate', 'stock': 3},
          ],
        },
        {
          'staffId': 'branch',
          'status': 'pending',
          'name': 'Latte',
          'isCoffee': true,
        },
        {'staffId': 'other', 'status': 'pending', 'name': 'Other branch'},
        {'staffId': 'branch', 'status': 'accepted', 'name': 'Old delivery'},
      ]) {
        await db.collection('allocation_checklist').add(row);
      }
      await tester.binding.setSurfaceSize(const Size(420, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const ['branch'],
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Checklist'), findsOneWidget);
      expect(find.text('Checklist (2)'), findsNothing);
      await tester.tap(find.text('Checklist'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chocolate'), findsOneWidget);
      expect(find.text('Other branch'), findsNothing);
      await tester.ensureVisible(find.text('Beverages'));
      await tester.tap(find.text('Beverages'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chocolate'), findsNothing);
      expect(find.textContaining('Latte'), findsWidgets);
      await tester.ensureVisible(find.text('All items'));
      await tester.tap(find.text('All items'));
      await tester.enterText(find.byType(TextField).first, 'Chocolate');
      await tester.pumpAndSettle();
      expect(find.textContaining('Latte'), findsNothing);
      await tester.ensureVisible(find.text('Confirm Received'));
      await tester.tap(find.text('Confirm Received'));
      await tester.pumpAndSettle();
      expect(find.text('Receive allocated items?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Received'), findsOneWidget);
      await tester.ensureVisible(find.text('Report Issue'));
      await tester.tap(find.text('Report Issue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('A reason is required'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
