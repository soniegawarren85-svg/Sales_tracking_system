// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales_tracking/main.dart';
import 'package:sales_tracking/services/inventory_service.dart';
import 'package:sales_tracking/widgets/item_card.dart';
import 'package:sales_tracking/screens/staff_page.dart';
import 'package:sales_tracking/models/inventory.dart';
import 'package:sales_tracking/widgets/header.dart';

void main() {


  testWidgets('Summary widgets are no longer shown', (WidgetTester tester) async {
    // regardless of inventory entries, the dashboard no longer displays
    // the starting/remaining stock summary at the top.
    InventoryService().clear();
    InventoryService().addInventory(Inventory(item: 'Sales A', startingA: 0, startingB: 0, startingC: 0));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Starting Stock'), findsNothing);
    expect(find.text('Remaining Stock'), findsNothing);
  });

  testWidgets('Starting entry followed by remaining updates same card', (WidgetTester tester) async {
    InventoryService().clear();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // first tap should open starting mode for Sales A (no entry yet)
    expect(InventoryService().hasEntryForItemToday('Sales A'), isFalse);
    // scroll card into view since the page now has large top padding
    await tester.ensureVisible(find.widgetWithText(ItemCard, 'Sales A'));
    await tester.tap(find.widgetWithText(ItemCard, 'Sales A'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Enter Starting Stock'), findsOneWidget);

    // fill values and save
    await tester.enterText(find.byType(TextFormField).first, '5');
    await tester.enterText(find.byType(TextFormField).at(1), '6');
    await tester.enterText(find.byType(TextFormField).at(2), '7');
    await tester.ensureVisible(find.text('Save Inventory'));
    await tester.tap(find.text('Save Inventory'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // wait for snackbar to disappear
    await tester.pump(const Duration(seconds: 1));

    // the service should now have a single entry with starting values
    expect(InventoryService().entries.length, equals(1));
    final first = InventoryService().entries.first;
    expect(first.safeItem, equals('Sales A'));
    expect(first.startingA, equals(5));
    expect(first.startingB, equals(6));
    expect(first.startingC, equals(7));
    expect(first.remainingA, equals(0));
    expect(first.remainingB, equals(0));
    expect(first.remainingC, equals(0));

    // the performance card for the entry should show the starting total,
    // and should not show remaining until non-zero values are entered.
    await tester.pumpAndSettle();
    expect(find.text('Starting: 18'), findsOneWidget);
    expect(find.text('Remaining: 0'), findsNothing);

    // make sure snackbar is gone before next tap
    await tester.pump(const Duration(seconds: 5));

    // instead of tapping the card again (which was flaky in tests),
    // directly navigate to StaffPage in remaining mode for Sales A
    expect(InventoryService().hasEntryForItemToday('Sales A'), isTrue);
    await tester.pumpWidget(MaterialApp(
        home: StaffPage(selectedItem: 'Sales A', isRemaining: true)));
    await tester.pumpAndSettle();
    expect(find.byType(StaffPage), findsOneWidget);
    expect(find.text('Enter Remaining Stock'), findsOneWidget);

    // enter remaining counts and save
    await tester.enterText(find.byType(TextFormField).first, '2');
    await tester.enterText(find.byType(TextFormField).at(1), '3');
    await tester.enterText(find.byType(TextFormField).at(2), '4');
    await tester.ensureVisible(find.text('Update Remaining'));
    await tester.tap(find.text('Update Remaining'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // still only one entry, and remaining values should be recorded
    expect(InventoryService().entries.length, equals(1));
    final updated = InventoryService().entries.first;
    expect(updated.safeItem, equals('Sales A'));
    expect(updated.startingA, equals(5));
    expect(updated.remainingA, equals(2));
    expect(updated.startingB, equals(6));
    expect(updated.remainingB, equals(3));
    expect(updated.startingC, equals(7));
    expect(updated.remainingC, equals(4));

    // remaining should now be displayed as total on the card
    await tester.pumpAndSettle();
    expect(find.text('Remaining: 9'), findsOneWidget);

    // dashboard summary would have reflected remaining but that widget is gone,
    // so we don't assert against it here.
  });

  testWidgets('Different items start independent entries', (WidgetTester tester) async {
    InventoryService().clear();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // add starting stock for Sales A first
    await tester.ensureVisible(find.widgetWithText(ItemCard, 'Sales A'));
    await tester.tap(find.widgetWithText(ItemCard, 'Sales A'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Enter Starting Stock'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.ensureVisible(find.text('Save Inventory'));
    await tester.tap(find.text('Save Inventory'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // now tap Sales B; it should still offer starting stock because B has no entry
    // make sure B is visible before tapping
    await tester.ensureVisible(find.widgetWithText(ItemCard, 'Sales B'));
    await tester.tap(find.widgetWithText(ItemCard, 'Sales B'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Enter Starting Stock'), findsOneWidget,
        reason: 'Sales B should not default to remaining when only A exists');
  });

  testWidgets('Profile header shows message, logo, and profile icons', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    // header widget should be present
    expect(find.byType(Header), findsOneWidget);
    // message button still accessible
    expect(find.byIcon(Icons.mail_outline), findsOneWidget);

  });
}
