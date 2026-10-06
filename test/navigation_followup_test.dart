import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';
import 'package:sales_tracking/widgets/branch_allocation_history.dart';
import 'package:sales_tracking/widgets/branch_analytics_bars.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';
import 'package:sales_tracking/widgets/staff_sales_item_grid.dart';

void main() {
  testWidgets(
    '24 hour chart starts at first activity and remains scrollable backwards',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 430,
              height: 280,
              child: BranchAnalyticsBars(
                values: List.generate(24, (i) => i == 10 ? 89 : 0),
                labels: List.generate(24, (i) => '$i:00'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.controller!.offset, closeTo(480, 1));
      scroll.controller!.jumpTo(0);
      await tester.pump();
      expect(scroll.controller!.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet with a narrow ticket panel still uses three item columns',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 550,
              child: StaffSalesItemGrid(
                itemCount: 4,
                itemBuilder: (_, i, compact) => Text('Item $i'),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Item 0')).dy,
        tester.getTopLeft(find.text('Item 2')).dy,
      );
      expect(
        tester.getTopLeft(find.text('Item 3')).dy,
        greaterThan(tester.getTopLeft(find.text('Item 0')).dy),
      );
    },
  );

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'checklist and returns have separate responsive controls at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = FakeFirebaseFirestore();
        for (final status in ['pending', 'Received']) {
          await db.collection('allocation_checklist').add({
            'staffId': 'b',
            'name': '$status cookies',
            'status': status,
            'createdAt': Timestamp.now(),
          });
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AllocationChecklistButton(
                scopeIds: const ['b'],
                database: db,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final checklist = find.byTooltip('Checklist'),
            returns = find.byTooltip('Returns');
        if (width < 600) {
          expect(tester.getCenter(checklist).dy, tester.getCenter(returns).dy);
          expect(find.text('Checklist'), findsNothing);
        } else {
          expect(
            tester.getCenter(returns).dy,
            greaterThan(tester.getCenter(checklist).dy),
          );
        }
        expect(
          tester
              .widgetList<Badge>(find.byType(Badge))
              .where((badge) => badge.isLabelVisible),
          hasLength(1),
        );
        await tester.tap(checklist);
        await tester.pumpAndSettle();
        expect(find.textContaining('pending cookies'), findsOneWidget);
        expect(find.textContaining('Received cookies'), findsNothing);
        expect(find.text('Return Items'), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Complete'));
        await tester.pumpAndSettle();
        expect(find.textContaining('pending cookies'), findsNothing);
        expect(find.textContaining('Received cookies'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'admin pending icon shows issues across dates with its own search',
    (tester) async {
      final db = FakeFirebaseFirestore();
      for (final status in ['pending', 'Issue Reported', 'Received']) {
        await db.collection('allocation_checklist').add({
          'staffId': 'b',
          'name': status,
          'status': status,
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 2)),
          ),
          'items': [
            {'name': '$status cookie', 'stock': 1},
          ],
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationHistoryActions(branchId: 'b', database: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      await tester.tap(find.byTooltip('Pending allocations'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filter by date'), findsNothing);
      expect(
        tester
            .widget<ListView>(find.byType(ListView))
            .childrenDelegate
            .estimatedChildCount,
        2,
      );
      await tester.tap(find.text('Issue reported'));
      await tester.pumpAndSettle();
      expect(find.text('View Items'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'not found');
      await tester.pumpAndSettle();
      expect(find.text('View Items'), findsNothing);
    },
  );

  testWidgets(
    'activity logs default to today, older logs require a selected date',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final now = DateTime.now(),
          yesterday = DateTime.now().subtract(const Duration(days: 1));
      for (final entry in [
        ('Today staff', now),
        ('Yesterday staff', yesterday),
      ]) {
        await db.collection('staff_login_sessions').add({
          'branchId': 'b',
          'staffName': entry.$1,
          'loginAt': Timestamp.fromDate(entry.$2),
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: BranchStaffActivityDialog(
            branchId: 'b',
            branchName: 'Dagupan',
            firestore: db,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Today staff'), findsOneWidget);
      expect(find.text('Yesterday staff'), findsNothing);
      expect(find.byIcon(Icons.clear), findsNothing);
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '${yesterday.month}/${yesterday.day}/${yesterday.year}',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday staff'), findsOneWidget);
      expect(find.text('Today staff'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
