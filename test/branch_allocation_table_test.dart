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
                'remaining': 0,
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
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Sold Out'), findsNothing);
    expect(find.text('Remaining allocated'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('low-stock add-ons never display sold-out status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchAllocationTable(
            rows: [
              {
                'id': 'AD-001',
                'name': 'Extra Cream',
                'remaining': 0,
                'isLowStock': true,
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

    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Sold Out'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add-on sales report hides made-to-order stock columns', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchAllocationTable(
            rows: [
              {
                'id': 'AD-001',
                'name': 'Extra Cream',
                'type': 'Add-ons',
                'sold': 2,
                'sales': 20,
              },
            ],
            beverages: false,
            addons: true,
            actions: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.text('Remaining allocated'), findsNothing);
    expect(find.text('Starting allocated'), findsNothing);
    expect(find.text('Allocated in period'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('beverage report shows per-size rows without action column', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchAllocationTable(
            beverages: true,
            showActions: false,
            actions: (_) => const Icon(Icons.more_horiz),
            rows: [
              {
                'id': 'COF-001',
                'name': 'Iced Coffee',
                'type': 'Beverages',
                'allocationDate': null,
                'status': 'Available',
                'basePrice': 100,
                'costPrice': 60,
                'sizes': [
                  {'name': 'Small', 'priceDelta': 10, 'costPrice': 11},
                  {'name': 'Medium', 'priceDelta': 20, 'costPrice': 22},
                  {'name': 'Large', 'priceDelta': 40, 'costPrice': 44},
                ],
                'sizeSales': {
                  'Small|coffee': {'sold': 2, 'sales': 220},
                  'Medium|coffee': {'sold': 1, 'sales': 120},
                  'Large|coffee': {'sold': 1, 'sales': 140},
                },
              },
            ],
          ),
        ),
      ),
    );

    expect(find.text('Size'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('₱110.00'), findsOneWidget);
    expect(find.text('₱120.00'), findsWidgets);
    expect(find.text('₱140.00'), findsWidgets);
    expect(find.text('₱220.00'), findsOneWidget);
    expect(find.text('₱11.00'), findsOneWidget);
    expect(find.text('₱22.00'), findsOneWidget);
    expect(find.text('₱44.00'), findsOneWidget);
    expect(find.text('Iced Coffee'), findsOneWidget);
    expect(find.text('COF-001'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Actions'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('beverage report displays current low-stock status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchAllocationTable(
            beverages: true,
            showActions: false,
            actions: (_) => const SizedBox.shrink(),
            rows: [
              {
                'id': 'COF-002',
                'name': 'Matcha',
                'type': 'Beverages',
                'isLowStock': true,
                'sizes': [
                  {'name': 'Small', 'priceDelta': 50, 'costPrice': 20},
                ],
              },
            ],
          ),
        ),
      ),
    );

    expect(find.text('Low stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
