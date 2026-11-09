import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Super_admin_pages/StaffPage.dart';

void main() {
  testWidgets(
    'staff search rebuilds keep receiving staff_requests live updates',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('staff-initial').set({
        'role': 'staff',
        'staffId': 'STF-001',
        'status': 'accepted',
        'firstName': 'Mila',
        'lastName': 'Initial',
      });

      await tester.pumpWidget(
        MaterialApp(home: StaffPage(firestore: firestore)),
      );
      await tester.pumpAndSettle();

      final searchField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Search name, ID, role, email or status',
      );
      await tester.ensureVisible(searchField);
      await tester.enterText(searchField, 'Mila');
      await tester.pumpAndSettle();

      await firestore.collection('staff_requests').doc('staff-updated').set({
        'role': 'staff',
        'staffId': 'STF-002',
        'status': 'accepted',
        'firstName': 'Mila',
        'lastName': 'Updated',
      });
      await tester.pumpAndSettle();

      expect(find.text('Mila Updated'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
