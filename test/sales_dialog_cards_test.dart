import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/coffee_addon_option_card.dart';
import 'package:sales_tracking/widgets/held_order_card.dart';

void main() {
  testWidgets('add-on choices occupy separate rows and use add-on image', (
    tester,
  ) async {
    const addonImage = 'https://example.test/actual-addon.png';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Column(
              children: [
                CoffeeAddonOptionCard(
                  name: 'Whipped cream',
                  price: 12,
                  imageUrl: addonImage,
                  selected: false,
                  onTap: _noop,
                ),
                SizedBox(height: 8),
                CoffeeAddonOptionCard(
                  name: 'Caramel',
                  price: 8,
                  imageUrl: addonImage,
                  selected: false,
                  onTap: _noop,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final first = tester.getRect(
      find.byKey(const ValueKey('addon-option-Whipped cream')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('addon-option-Caramel')),
    );
    expect(first.width, 320);
    expect(second.width, 320);
    expect(second.top, greaterThan(first.bottom));
    final image = tester.widget<Image>(find.byType(Image).first);
    expect((image.image as NetworkImage).url, addonImage);
  });

  testWidgets('held order status distinguishes synced, pending, and offline', (
    tester,
  ) async {
    Future<void> pumpCard({required bool? hasNetwork}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeldOrderCard(
              data: const {'_pendingSync': true, 'items': []},
              hasNetwork: hasNetwork,
              onVoid: _noop,
              onRestore: _noop,
            ),
          ),
        ),
      );
    }

    await pumpCard(hasNetwork: true);
    expect(find.text('Sync pending'), findsOneWidget);
    await pumpCard(hasNetwork: false);
    expect(find.text('Saved offline'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeldOrderCard(
            data: const {'_pendingSync': false, 'items': []},
            hasNetwork: false,
            onVoid: _noop,
            onRestore: _noop,
          ),
        ),
      ),
    );
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('held order shows item and saved discount details only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeldOrderCard(
            data: {
              '_pendingSync': false,
              'createdAt': DateTime(2026, 10, 31),
              'items': [
                {
                  'name': 'Iced latte',
                  'variant': 'Large - Sugar 50% + Oat milk',
                  'quantity': 2,
                  'price': 12.5,
                },
              ],
              'discountApplied': true,
              'discountType': 'Senior Citizen',
              'discountId': 'senior-option',
            },
            hasNetwork: true,
            onVoid: _noop,
            onRestore: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Iced latte  ×2'), findsOneWidget);
    expect(find.text('Large - Sugar 50% + Oat milk'), findsOneWidget);
    expect(find.text('₱12.50 each · ₱25.00'), findsOneWidget);
    expect(
      find.text('Discount: Senior Citizen · Option ID: senior-option'),
      findsOneWidget,
    );
    expect(find.textContaining('₱'), findsOneWidget);
    expect(find.textContaining('20%'), findsNothing);
  });
}

void _noop() {}
