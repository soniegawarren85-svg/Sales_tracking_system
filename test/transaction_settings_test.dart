import 'package:flutter_test/flutter_test.dart';
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
      expect(settingRows(lingayen, 'discounts').first['name'], 'Senior');
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
    });

    test('tax is disabled by default and is only charged for enabled VAT', () {
      final defaults = settingsForBranch({}, 'lingayen');
      expect(defaults['taxEnabled'], isFalse);
      expect(defaults['taxClassification'], 'nonVat');
      expect(transactionTaxAmount(defaults, taxableAmount: 100), 0);

      final vat = settingsForBranch({
        'branchSettings': {
          'lingayen': {'taxEnabled': true, 'taxClassification': 'vat'},
        },
      }, 'lingayen');
      expect(
        transactionTaxAmount(vat, taxableAmount: 100),
        closeTo(10.7142857, 0.0001),
      );
      expect(
        transactionTaxAmount(vat, taxableAmount: 99),
        closeTo(10.6071429, 0.0001),
      );

      final disabledVat = settingsForBranch({
        'branchSettings': {
          'lingayen': {'taxEnabled': false, 'taxClassification': 'vat'},
        },
      }, 'lingayen');
      expect(transactionTaxAmount(disabledVat, taxableAmount: 100), 0);
    });
  });
}
