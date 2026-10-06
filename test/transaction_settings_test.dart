import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/transaction_settings.dart';

void main() {
  group('settingsForBranch', () {
    test('uses branch overrides and keeps global fallback values', () {
      final settings = {
        'discountsEnabled': true,
        'discounts': [
          {'id': 'senior', 'name': 'Senior', 'percent': 20},
        ],
        'branchSettings': {
          'lingayen': {
            'discountsEnabled': false,
            'payments': [
              {'id': 'gcash-lingayen', 'name': 'GCash', 'qrUrl': 'lingayen-qr'},
            ],
          },
        },
      };

      final branch = settingsForBranch(settings, 'lingayen');

      expect(branch['discountsEnabled'], isFalse);
      expect(branch['discounts'], settings['discounts']);
      expect((branch['payments'] as List).single['qrUrl'], 'lingayen-qr');
    });

    test('keeps existing global settings when branch has no override', () {
      final settings = {
        'allowRefunds': false,
        'payments': [
          {'id': 'gcash', 'name': 'GCash', 'qrUrl': 'legacy-qr'},
        ],
        'branchSettings': {
          'lingayen': {'allowRefunds': true},
        },
      };

      expect(settingsForBranch(settings, 'sm-dagupan')['allowRefunds'], false);
      expect(
        (settingsForBranch(settings, 'sm-dagupan')['payments'] as List)
            .single['qrUrl'],
        'legacy-qr',
      );
    });
  });
}
