import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';

void main() {
  testWidgets('empty session history does not fabricate previous logins', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StaffSessionTable(sessions: [])),
      ),
    );
    expect(
      find.text('No recorded login sessions for this branch.'),
      findsOneWidget,
    );
  });
}
