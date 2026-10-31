import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_allocation_table.dart';

void main() {
  testWidgets('beverage availability ignores stock and hides expiry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchAllocationTable(
            rows: [
              {
                'id': 'BV-001',
                'name': 'Dubai Chewy Smoothie',
                'allocationDate': DateTime(2026, 1, 1),
                'remaining': 0,
                'sizes': [
                  {'name': 'Small', 'price': 100},
                ],
                'status': 'Available',
              },
            ],
            beverages: true,
            inventory: true,
            actions: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Sold Out'), findsNothing);
    expect(find.text('Expiry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add-on inventory hides expiry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchAllocationTable(
            rows: [
              {
                'id': 'AD-001',
                'name': 'Extra Cream',
                'allocationDate': DateTime(2026, 1, 1),
                'remaining': 2,
                'price': 10,
                'costPrice': 5,
              },
            ],
            beverages: false,
            inventory: true,
            addons: true,
            actions: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.text('Expiry'), findsNothing);
    expect(find.text('Availability'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
