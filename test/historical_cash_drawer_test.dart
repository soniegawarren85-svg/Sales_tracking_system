import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/historical_cash_drawer.dart';

void main() {
  test(
    'historical drawer uses selected date allocation, cash sales and refunds',
    () {
      expect(
        calculatedDailyCash(
          DateTime(2026, 9, 24),
          [
            {
              'createdAt': '2026-09-24T08:00:00',
              'type': 'set_daily_cash_drawer',
              'amount': 1200,
            },
            {'createdAt': '2026-09-24T12:00:00', 'amount': 100},
            {'createdAt': '2026-09-25T08:00:00', 'amount': 9999},
          ],
          [
            {
              'timestamp': '2026-09-24T10:00:00',
              'paymentMode': 'Cash',
              'total': 200,
            },
            {
              'timestamp': '2026-09-24T11:00:00',
              'paymentMode': 'GCash',
              'total': 500,
            },
            {
              'timestamp': '2026-09-24T12:00:00',
              'paymentMode': 'Cash',
              'cashDrawerDelta': -50,
              'total': -50,
            },
            {'timestamp': '2026-09-25T10:00:00', 'total': 9999},
          ],
        ),
        1450,
      );
    },
  );
  test('empty recorded day is zero', () {
    expect(calculatedDailyCash(DateTime(2026, 9, 24), [], []), 0);
  });
}
