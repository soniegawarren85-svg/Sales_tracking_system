import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/report_item_history.dart';

void main() {
  testWidgets('add-on history shows sold records without stock balances', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportItemHistory(
            item: {
              'name': 'Chewy Cream',
              'type': 'Add-ons',
              'history': [
                {
                  'time': DateTime(2026, 11, 6, 10),
                  'activity': 'Opening balance',
                  'qty': 3,
                  'balance': 3,
                },
                {
                  'time': DateTime(2026, 11, 6, 11),
                  'activity': 'Sold',
                  'name': 'Chewy Cream',
                  'qty': 2,
                  'sales': 80,
                },
              ],
            },
            period: 'Today',
          ),
        ),
      ),
    );

    expect(find.text('Add-on'), findsOneWidget);
    expect(find.text('Sold'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Balance'), findsNothing);
    expect(find.text('₱80.00'), findsOneWidget);
    expect(find.text('Opening balance'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
