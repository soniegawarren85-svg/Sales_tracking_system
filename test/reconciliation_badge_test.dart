import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/inventory_batches.dart';

void main() {
  testWidgets('reconciliation button shows the number of pending requests', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firestore = FakeFirebaseFirestore();
    await firestore.doc('inventory_reconciliations/first').set({
      'status': 'pending',
    });
    await firestore.doc('inventory_reconciliations/second').set({
      'status': 'pending',
    });
    await firestore.doc('inventory_reconciliations/completed').set({
      'status': 'approved',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReconciliationRequestsButton(database: firestore)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.backgroundColor, Colors.red);
  });
}
