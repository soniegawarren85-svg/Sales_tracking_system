import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_addons.dart';
import 'package:sales_tracking/widgets/admin_void_inventory.dart';

void main() {
  testWidgets('void requires a typed reason and saves it with the record', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('coffee_addons').doc('cream');
    await ref.set({'name': 'Cream', 'priceDelta': 20});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminAddonsTable(firestore: db)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Void add-on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void item'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a reason.'), findsOneWidget);
    expect((await ref.get()).data()!['isDeleted'], isNull);
    await tester.enterText(find.byType(TextFormField), '  Damaged packaging  ');
    await tester.tap(find.text('Void item'));
    await tester.pumpAndSettle();
    final data = (await ref.get()).data()!;
    expect(data['isDeleted'], true);
    expect(data['voidReason'], 'Damaged packaging');
    expect(data['deletedAt'], isA<Timestamp>());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('popup shows reasons, searches, switches type and restores', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('cookies').set({
      'name': 'Cookies',
      'items': [],
      'removedItems': [
        {
          'id': 'cookie',
          'name': 'Dubai Cookie',
          'voidReason': 'Broken box',
          'removedAt': Timestamp.now(),
        },
        {
          'id': 'red',
          'name': 'Red Velvet',
          'voidReason': 'Wrong entry',
          'removedAt': Timestamp.now(),
        },
      ],
    });
    await db.collection('sales_inventory').doc('bundle').set({
      'name': 'Party Bundle',
      'isBundle': true,
      'isDeleted': true,
      'voidReason': 'Cancelled order',
      'deletedAt': Timestamp.now(),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 900,
                    height: 650,
                    child: AdminVoidInventory(
                      type: 'Categories',
                      popup: true,
                      firestore: db,
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Broken box'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Dubai');
    await tester.pumpAndSettle();
    expect(find.text('Red Velvet'), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore item?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore').last);
    await tester.pumpAndSettle();
    final restored =
        (await db.collection('sales_inventory').doc('cookies').get()).data()!;
    expect((restored['items'] as List).single['name'], 'Dubai Cookie');
    expect((restored['items'] as List).single['voidReason'], isNull);
    await tester.enterText(find.byType(TextField), '');
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('ID'), findsOneWidget);
    expect(find.text('Qty'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter by date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    tester
        .state<NavigatorState>(find.byType(Navigator).last)
        .pop(
          DateTime(2020, 1, 1),
        );
    await tester.pumpAndSettle();
    expect(find.text('Wrong entry'), findsNothing);
    expect(find.text('No records match your filters.'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter by date'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).pop(DateTime.now());
    await tester.pumpAndSettle();
    expect(find.text('Wrong entry'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(AdminVoidInventory), findsNothing);
  });

  testWidgets('expired beverages include add-ons in the records table', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('coffee_addons').doc('old').set({
      'name': 'Old Cream',
      'expirationDate': '2020-01-01',
    });
    await db.collection('coffee_addons').doc('fresh').set({
      'name': 'Fresh Cream',
      'expirationDate': '2099-01-01',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminVoidInventory(
          type: 'Beverages',
          expired: true,
          popup: true,
          firestore: db,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old Cream'), findsNothing);
    await tester.tap(find.byTooltip('Filter by date'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).pop(DateTime(2020, 1, 1));
    await tester.pumpAndSettle();
    expect(find.text('Old Cream'), findsOneWidget);
    expect(find.text('Qty'), findsNothing);
    expect(find.text('Availability'), findsOneWidget);
    expect(find.text('Fresh Cream'), findsNothing);
    expect(find.byTooltip('Restore'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
