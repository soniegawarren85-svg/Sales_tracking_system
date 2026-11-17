import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/low_stock_reminder_dialog.dart';

void main() {
  testWidgets('low-stock table has one selector and shows item details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockReminderDialog(
                context: context,
                title: 'Low stock',
                description: 'Select items.',
                items: [
                  {
                    'id': 'CF-004',
                    'name': 'Biscoff Frappe',
                    'type': 'Beverages',
                    'categoryName': 'Beverages',
                    'stock': 0,
                    'allocatedAt': DateTime(2026, 11, 11),
                  },
                ],
                onRequest: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text('ID'), findsOneWidget);
    expect(find.text('Allocated date'), findsOneWidget);
    expect(find.text('CF-004'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  testWidgets('already requested items cannot be selected again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockReminderDialog(
                context: context,
                title: 'Low stock',
                description: 'Select items.',
                items: [
                  {
                    'id': 'CF-004',
                    'name': 'Biscoff Frappe',
                    'type': 'Beverages',
                    'lowStockReportStatus': 'reported',
                  },
                ],
                onRequest: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Already requested'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Checkbox && widget.onChanged == null,
      ),
      findsNWidgets(2),
    );
    await tester.tap(find.text('Biscoff Frappe'));
    await tester.pumpAndSettle();
    expect(find.text('Request (0)'), findsOneWidget);
  });

  testWidgets('select all selects every available visible item', (
    tester,
  ) async {
    List<Map<String, dynamic>>? requestedItems;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockReminderDialog(
                context: context,
                title: 'Low stock',
                description: 'Select items.',
                items: [
                  {
                    'id': 'CF-004',
                    'name': 'Biscoff Frappe',
                    'type': 'Beverages',
                  },
                  {
                    'id': 'CO-020',
                    'name': 'Chocolate Cake',
                    'type': 'Categories',
                  },
                  {
                    'id': 'CF-005',
                    'name': 'Vanilla Frappe',
                    'type': 'Beverages',
                    'lowStockReportStatus': 'reported',
                  },
                ],
                onRequest: (items) async => requestedItems = items,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible items'));
    await tester.pumpAndSettle();

    expect(find.text('Request (2)'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    await tester.tap(find.text('Request (2)'));
    await tester.pumpAndSettle();

    expect(requestedItems, hasLength(2));
    expect(requestedItems!.map((item) => item['id']), ['CF-004', 'CO-020']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('physical low-stock requests include the optional request qty', (
    tester,
  ) async {
    List<Map<String, dynamic>>? requestedItems;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLowStockReminderDialog(
                context: context,
                title: 'Low stock',
                description: 'Select items.',
                items: [
                  {
                    'id': 'CA-008',
                    'name': 'Pistachio Cake',
                    'type': 'Categories',
                    'remaining': 4,
                  },
                  {
                    'id': 'CF-004',
                    'name': 'Biscoff Frappe',
                    'type': 'Beverages',
                  },
                ],
                onRequest: (items) async => requestedItems = items,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible items'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        const ValueKey(
          'low-stock-request-quantity-|CA-008|Pistachio Cake|Categories',
        ),
      ),
      '20',
    );
    await tester.tap(find.text('Request (2)'));
    await tester.pumpAndSettle();

    expect(requestedItems, hasLength(2));
    expect(requestedItems!.first['requestedQuantity'], 20);
    expect(requestedItems!.last.containsKey('requestedQuantity'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
