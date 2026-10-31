import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/receipt_tax.dart';
import 'package:sales_tracking/services/transaction_settings.dart';

void main() {
  group('settingsForBranch', () {
    test('uses branch overrides for branch-specific settings', () {
      final settings = {
        'discountsEnabled': true,
        'discounts': [
          {'id': 'member', 'name': 'Member', 'percent': 5},
        ],
        'branchSettings': {
          'lingayen': {
            'discountsEnabled': false,
            'discounts': [
              {'id': 'local', 'name': 'Local', 'percent': 10},
            ],
            'payments': [
              {'id': 'gcash-lingayen', 'name': 'GCash', 'qrUrl': 'lingayen-qr'},
            ],
          },
        },
      };

      final branch = settingsForBranch(settings, 'lingayen');

      expect(branch['discountsEnabled'], isFalse);
      expect((branch['discounts'] as List).single['name'], 'Local');
      expect((branch['payments'] as List).single['qrUrl'], 'lingayen-qr');
    });

    test('does not inherit another branch payment QR or edited discounts', () {
      final settings = {
        'allowRefunds': false,
        'discounts': [
          {'id': 'member', 'name': 'Edited member', 'percent': 15},
        ],
        'payments': [
          {'id': 'gcash', 'name': 'GCash', 'qrUrl': 'legacy-qr'},
        ],
        'branchSettings': {
          'sm-dagupan': {
            'allowRefunds': false,
            'discounts': [
              {'id': 'local', 'name': 'Local', 'percent': 10},
            ],
            'payments': [
              {'id': 'gcash', 'name': 'GCash', 'qrUrl': 'dagupan-qr'},
            ],
          },
        },
      };

      final lingayen = settingsForBranch(settings, 'lingayen');
      expect(lingayen['allowRefunds'], isTrue);
      expect(
        settingRows(lingayen, 'payments').every((row) => row['qrUrl'] == null),
        isTrue,
      );
      expect(settingRows(lingayen, 'discounts'), isEmpty);
      expect(
        settingsForBranch(settings, 'sm-dagupan')['allowRefunds'],
        isFalse,
      );
      expect(
        settingRows(
          settingsForBranch(settings, 'sm-dagupan'),
          'payments',
        ).single['qrUrl'],
        'dagupan-qr',
      );
      final newBranch = settingsForBranch(settings, 'new-branch');
      expect(newBranch['discountsEnabled'], isFalse);
      expect(settingRows(newBranch, 'discounts'), isEmpty);
    });

    test('tax is disabled by default and is only charged for enabled VAT', () {
      final defaults = settingsForBranch({}, 'lingayen');
      expect(defaults['taxEnabled'], isFalse);
      expect(defaults['taxClassification'], 'nonVat');
      expect(defaults['discountsEnabled'], isFalse);
      expect(settingRows(defaults, 'discounts'), isEmpty);
      expect(transactionTaxAmount(defaults, grossAmount: 100), 0);

      final vat = settingsForBranch({
        'branchSettings': {
          'lingayen': {'taxEnabled': true, 'taxClassification': 'vat'},
        },
      }, 'lingayen');
      for (final example in [
        (total: 85.50, vatable: 76.34, vat: 9.16),
        (total: 100.0, vatable: 89.29, vat: 10.71),
        (total: 1000.0, vatable: 892.86, vat: 107.14),
      ]) {
        final breakdown = transactionTaxBreakdown(
          vat,
          grossAmount: example.total,
        );
        expect(breakdown.total, example.total);
        expect(breakdown.vatableSales, example.vatable);
        expect(breakdown.vatAmount, example.vat);
        expect(breakdown.vatableSales + breakdown.vatAmount, breakdown.total);
        expect(
          transactionTaxAmount(vat, grossAmount: example.total),
          example.vat,
        );
      }
      expect(transactionTaxBreakdown(vat, grossAmount: 79.992).total, 79.99);
      expect(
        transactionTaxBreakdown(vat, grossAmount: 79.992).vatableSales,
        71.42,
      );

      final disabledVat = settingsForBranch({
        'branchSettings': {
          'lingayen': {'taxEnabled': false, 'taxClassification': 'vat'},
        },
      }, 'lingayen');
      expect(transactionTaxAmount(disabledVat, grossAmount: 100), 0);
    });

    test('does not extract VAT for exempt and non-VAT sales', () {
      for (final settings in [
        {'taxEnabled': true, 'taxClassification': 'vatExempt'},
        {'taxEnabled': false, 'taxClassification': 'vat'},
        {'taxEnabled': true, 'taxClassification': 'nonVat'},
      ]) {
        final breakdown = transactionTaxBreakdown(settings, grossAmount: 100);
        expect(breakdown.total, 100);
        expect(breakdown.vatAmount, 0);
        expect(breakdown.vatableSales, 0);
      }
    });

    test('receipt net sales use saved breakdown and support old records', () {
      expect(
        receiptVatableSales({
          'total': 100,
          'vatableSales': 89.29,
          'tax': 10.71,
        }),
        closeTo(89.29, 0.001),
      );
      expect(
        receiptVatableSales({'total': 100, 'tax': 10.71}),
        closeTo(89.29, 0.001),
      );
      expect(
        receiptVatableSales({'total': 100, 'vat': 10.71}),
        closeTo(89.29, 0.001),
      );
      expect(
        receiptVatableSales({'total': 85.50, 'tax': 9.16}),
        closeTo(76.34, 0.001),
      );
      expect(
        receiptVatableSales({
          'total': 100,
          'vatableSales': 0,
          'taxClassification': 'nonVat',
        }),
        100,
      );
    });
  });
}
