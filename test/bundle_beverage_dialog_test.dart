import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/bundle_beverage_dialog.dart';
import 'package:sales_tracking/services/sale_stock.dart';

void main() {
  final bundle = <String, dynamic>{
    'name': 'Cookie and drink',
    'price': 500,
    'isBundle': true,
    'staffInventoryDocId': 'allocation',
    'bundleItems': [
      {'name': 'Cookie', 'quantity': 2},
      {
        'name': 'Smoothie (Small)',
        'sourceCollection': 'coffee_products',
        'sourceInventoryId': 'coffee',
        'coffeeSize': 'Small',
        'quantity': 1,
      },
    ],
  };
  test(
    'Only extras increase bundle price and configurations stay distinct',
    () {
      final drinks = bundleDrinkServings(bundle);
      expect(drinks.length, 1);
      final plain = customizeBundle(bundle, drinks);
      expect(plain['price'], 500);
      drinks.single['sugarLevel'] = '25%';
      drinks.single['addons'] = [
        {'id': 'cream', 'name': 'Cream', 'priceDelta': 20},
      ];
      final custom = customizeBundle(bundle, drinks);
      expect(custom['price'], 520);
      expect(custom['id'], isNot(plain['id']));
      expect(custom['staffInventoryDocId'], 'allocation');
      expect(custom['variant'], contains('Sugar 25% + Cream'));
      final stock = applySaleStock(
        {'isBundle': true, 'bundleCount': 5},
        'sale',
        [
          {...plain, 'quantity': 1},
          {...custom, 'quantity': 2},
        ],
      );
      expect(stock['bundleCount'], 2);
    },
  );
  testWidgets('Fixed size, sugar selection, add-on and cancellation', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => BundleBeverageDialog(
                    bundle: bundle,
                    addons: const [
                      {'id': 'cream', 'name': 'Cream', 'priceDelta': 20},
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Size: Small'), findsOneWidget);
    expect(find.textContaining('Medium'), findsNothing);
    expect(find.textContaining('110'), findsNothing);
    await tester.tap(find.text('25%'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cream (+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bundle to order'));
    await tester.pumpAndSettle();
    expect(result!['price'], 520);
    expect((result!['bundleBeverages'] as List).single['sugarLevel'], '25%');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
