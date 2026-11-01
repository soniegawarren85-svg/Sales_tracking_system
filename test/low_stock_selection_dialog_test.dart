import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/low_stock_selection_dialog.dart';

void main() {
  testWidgets('low-stock picker searches, selects all, and submits details', (
    tester,
  ) async {
    List<Map<String, dynamic>>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockSelectionDialog(
                context: context,
                title: 'Mark low stock',
                description: 'Select items.',
                items: [
                  {'name': 'Iced Latte', 'type': 'Beverages', 'id': 'COF-1'},
                  {'name': 'Whipped Cream', 'type': 'Add-ons', 'id': 'ADD-1'},
                ],
                submitLabel: 'Mark selected',
                searchHint: 'Search beverages',
                onSubmit: (items) async => submitted = items,
              ),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('Iced Latte'), findsOneWidget);
    expect(find.text('Whipped Cream'), findsOneWidget);

    await tester.tap(find.text('Iced Latte'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Mark selected (2)'));
    await tester.pumpAndSettle();

    expect(submitted, hasLength(2));
    expect(find.text('Mark low stock'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already marked items are not selected with Select all', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockSelectionDialog(
                context: context,
                title: 'Mark low stock',
                description: 'Select items.',
                items: [
                  {
                    'name': 'Iced Latte',
                    'type': 'Beverages',
                    'id': 'COF-1',
                    'isLowStock': true,
                  },
                  {'name': 'Whipped Cream', 'type': 'Add-ons', 'id': 'ADD-1'},
                ],
                submitLabel: 'Mark selected',
                searchHint: 'Search beverages',
                onSubmit: (_) async {},
              ),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iced Latte'));
    await tester.pumpAndSettle();
    expect(
      find.text('Iced Latte is already marked low stock.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
  });

  testWidgets('staff-pending items stay selectable until reported by Admin', (
    tester,
  ) async {
    List<Map<String, dynamic>>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockSelectionDialog(
                context: context,
                title: 'Report low-stock items',
                description: 'Select pending items.',
                items: [
                  {
                    'name': 'Chewy Cream',
                    'type': 'Add-ons',
                    'isLowStock': true,
                    'alreadyReported': false,
                    'staffLowStockPendingAdmin': true,
                  },
                ],
                submitLabel: 'Send report',
                searchHint: 'Search add-ons',
                onSubmit: (items) async => submitted = items,
              ),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chewy Cream'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Send report (1)'));
    await tester.pumpAndSettle();

    expect(submitted, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reported items show an Already reported validation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockSelectionDialog(
                context: context,
                title: 'Report low-stock items',
                description: 'Select pending items.',
                items: [
                  {
                    'name': 'Chewy Cream',
                    'type': 'Add-ons',
                    'isLowStock': true,
                    'alreadyReported': true,
                  },
                ],
                submitLabel: 'Send report',
                searchHint: 'Search add-ons',
                onSubmit: (_) async {},
              ),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chewy Cream'));
    await tester.pumpAndSettle();

    expect(find.text('Already reported'), findsOneWidget);
    expect(find.text('Chewy Cream is already reported.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
