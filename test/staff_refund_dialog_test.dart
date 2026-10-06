import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_refund_dialog.dart';

void main() {
  test(
    'legacy refund receipt recovers payment details without changing drawer values',
    () {
      final data = refundReceiptDisplayData(
        {
          'type': 'refund',
          'originalSalesId': 'sale',
          'paymentMode': 'Cash',
          'refundMethod': 'cash',
          'total': -90,
          'paidAmount': 0,
        },
        [
          {
            'salesId': 'sale',
            'paymentMode': 'GCash',
            'paidAmount': 100,
            'change': 10,
            'discount': 10,
            'discountType': 'Promo',
          },
        ],
      );
      expect(data['originalPaymentMode'], 'GCash');
      expect(data['originalPaidAmount'], 100);
      expect(data['originalDiscount'], 10);
      expect(data['paymentMode'], 'Cash');
      expect(data['total'], -90);
      expect(data['paidAmount'], 0);
    },
  );
  test('beverage labels show a repeated size only once', () {
    expect(
      staffRefundItemLabel({
        'name': 'Dubai Chewy Smoothie',
        'variant': 'Small',
        'coffeeSize': 'Small',
      }),
      'Dubai Chewy Smoothie / Small',
    );
    expect(
      staffRefundItemLabel({
        'name': 'Dubai Chewy Smoothie / Small',
        'coffeeSize': 'small',
      }),
      'Dubai Chewy Smoothie / Small',
    );
  });
  test('refund choices only include currently allocated active items', () {
    final activeKeys = activeStaffRefundItemKeys([
      {
        'sourceInventoryId': 'cookies',
        'items': [
          {'id': 'active', 'stock': 4, 'expirationDate': '2026-12-31'},
          {'id': 'expired', 'stock': 4, 'expirationDate': '2026-10-04'},
          {'id': 'voided', 'stock': 4, 'isVoided': true},
          {'id': 'deleted', 'stock': 4, 'isDeleted': true},
          {'id': 'empty', 'stock': 0},
        ],
      },
      {
        'sourceInventoryId': 'coffee',
        'isCoffee': true,
        'coffeeId': 'coffee-id',
        'sizes': [
          {'name': 'Small'},
          {'name': 'Large', 'isVoided': true},
        ],
      },
      {'sourceInventoryId': 'bundle', 'isBundle': true, 'bundleCount': 1},
    ], now: DateTime(2026, 10, 5));

    expect(
      activeKeys,
      contains(
        staffRefundItemKey({
          'sourceInventoryId': 'cookies',
          'itemId': 'active',
        }),
      ),
    );
    final bundleChoices = activeStaffRefundChoices([
      {
        'sourceInventoryId': 'bundle',
        'name': 'Snack box',
        'isBundle': true,
        'bundleCount': 1,
        'items': [
          {'name': 'Cookies', 'quantity': 2},
        ],
      },
    ], now: DateTime(2026, 10, 5));
    expect(
      bundleChoices[staffRefundItemKey({
        'sourceInventoryId': 'bundle',
        'isBundle': true,
      })]?['name'],
      'Snack box',
    );
    final choices = activeStaffRefundChoices([
      {
        'sourceInventoryId': 'cookies',
        'name': 'Cookies',
        'items': [
          {'id': 'active', 'name': 'Pistachio', 'stock': 4},
        ],
      },
    ], now: DateTime(2026, 10, 5));
    expect(
      choices[staffRefundItemKey({
        'sourceInventoryId': 'cookies',
        'itemId': 'active',
      })]?['variant'],
      'Pistachio',
    );
    expect(
      activeKeys,
      contains(
        staffRefundItemKey({
          'sourceInventoryId': 'coffee',
          'coffeeSize': 'Small',
          'isCoffee': true,
        }),
      ),
    );
    expect(
      activeKeys,
      isNot(
        contains(
          staffRefundItemKey({
            'sourceInventoryId': 'cookies',
            'itemId': 'expired',
          }),
        ),
      ),
    );
    expect(
      activeKeys,
      isNot(
        contains(
          staffRefundItemKey({
            'sourceInventoryId': 'cookies',
            'itemId': 'voided',
          }),
        ),
      ),
    );
    expect(
      activeKeys,
      contains(
        staffRefundItemKey({
          'sourceInventoryId': 'coffee',
          'coffeeSize': 'Small',
          'isCoffee': true,
        }),
      ),
    );
    expect(
      activeKeys,
      contains(
        staffRefundItemKey({'sourceInventoryId': 'bundle', 'isBundle': true}),
      ),
    );
    expect(
      activeStaffRefundItemKeys([
        {
          'sourceInventoryId': 'expired-coffee-sizes',
          'isCoffee': true,
          'coffeeId': 'coffee-2',
          'sizes': [
            {'name': 'Regular', 'expirationDate': '2026-10-04'},
          ],
        },
      ], now: DateTime(2026, 10, 5)),
      isEmpty,
    );
  });

  test('receipt details show purchase and current refund eligibility', () {
    final sale = <String, dynamic>{
      'salesId': 'S-100',
      'timestamp': DateTime(2026, 10, 5, 13),
      'subtotal': 100,
      'total': 90,
      'paidAmount': 100,
      'change': 10,
      'discount': 10,
      'discountType': 'PWD',
      'paymentMode': 'Cash',
      'items': [
        {
          'name': 'Cookies',
          'variant': 'Oat',
          'sourceInventoryId': 'cookies',
          'itemId': 'oat',
          'quantity': 2,
          'price': 50,
        },
        {
          'name': 'Cookies',
          'variant': 'Expired item',
          'sourceInventoryId': 'cookies',
          'itemId': 'expired',
          'quantity': 1,
          'price': 50,
        },
      ],
    };
    final details = staffRefundReceiptDetails(
      sale,
      [
        {'index': 0, 'available': 1},
      ],
      {
        staffRefundItemKey({'sourceInventoryId': 'cookies', 'itemId': 'oat'}),
      },
      now: DateTime(2026, 10, 5, 14),
    );

    expect(details, hasLength(2));
    expect(details.first['status'], 'Refundable');
    expect(details.first['refundableQuantity'], 1);
    expect(details.first['unit'], 45);
    expect(details.last['status'], 'No longer currently allocated');
    expect(sale['timestamp'], DateTime(2026, 10, 5, 13));
    expect(sale['paidAmount'], 100);
    expect(sale['change'], 10);
    expect(sale['discountType'], 'PWD');
    expect(sale['paymentMode'], 'Cash');
  });

  test('refund receipt must be less than five hours old', () {
    final now = DateTime(2026, 10, 5, 14);
    expect(
      staffRefundWindowOpen({'timestamp': DateTime(2026, 10, 5, 13)}, now: now),
      isTrue,
    );
    expect(
      staffRefundWindowOpen({'timestamp': DateTime(2026, 10, 5, 8)}, now: now),
      isFalse,
    );
    expect(staffRefundWindowOpen({}, now: now), isFalse);
    final oldSale = {'timestamp': DateTime(2026, 10, 3, 22)};
    expect(
      staffRefundAllowedByWindow(oldSale, byReceiptId: false, now: now),
      isFalse,
    );
    expect(
      staffRefundAllowedByWindow(oldSale, byReceiptId: true, now: now),
      isTrue,
    );
  });

  test('refund confirmation amount follows quantity across sale prices', () {
    expect(
      staffRefundAmount([
        {'available': 1, 'unit': 49.5},
        {'available': 2, 'unit': 60.0},
      ], 2),
      109.5,
    );
  });

  test('refund confirmation amount follows quantity across sale prices', () {
    expect(
      staffRefundAmount([
        {'available': 1, 'unit': 49.5},
        {'available': 2, 'unit': 60.0},
      ], 2),
      109.5,
    );
  });
}
