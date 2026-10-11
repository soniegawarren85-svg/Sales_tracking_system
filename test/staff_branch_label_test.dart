import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_branch_label.dart';

void main() {
  testWidgets('shows assigned branch name from the staff profile', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('sm-dagupan').set({
      'name': 'SM Dagupan',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffBranchLabel(
            branchIds: const ['sm-dagupan'],
            staffIdentifiers: const ['staff-uid'],
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Branch: SM Dagupan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows branch assigned by staff identity', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('sm-dagupan').set({
      'name': 'SM Dagupan',
      'staffIds': ['staff-uid'],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffBranchLabel(
            branchIds: const [],
            staffIdentifiers: const ['staff-uid'],
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Branch: SM Dagupan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
