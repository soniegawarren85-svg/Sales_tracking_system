import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';

void main() {
  testWidgets(
    'branch checklist count, search, type filter and required decline reason',
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
      expect(find.text('Checklist (2)'), findsOneWidget);
      await tester.tap(find.text('Checklist (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Chocolate'), findsOneWidget);
      expect(find.text('Other branch'), findsNothing);
      await tester.tap(find.text('Beverages'));
      await tester.pumpAndSettle();
      expect(find.text('Chocolate'), findsNothing);
      expect(find.text('Latte'), findsOneWidget);
      await tester.tap(find.text('All items'));
      await tester.enterText(find.byType(TextField).first, 'Chocolate');
      await tester.pumpAndSettle();
      expect(find.text('Latte'), findsNothing);
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline and return'));
      await tester.pumpAndSettle();
      expect(find.text('A reason is required'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
