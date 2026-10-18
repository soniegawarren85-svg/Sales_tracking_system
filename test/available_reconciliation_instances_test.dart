import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/inventory_reconciliation_service.dart';

void main() {
  test('only available bundle instances can be presented for requests', () {
    final available = availableReconciliationInstances({
      'bundleCount': 1,
      'bundleInstances': [
        {'id': 'available', 'status': 'available'},
        {'id': 'reduced', 'status': 'reduced'},
        {'id': 'sold', 'status': 'sold'},
        {'id': 'refunded', 'status': 'refunded'},
        {'id': 'reserved', 'status': 'reconciliation_pending'},
      ],
    }, 'allocation');

    expect(available.map((instance) => instance['id']), ['available']);
  });
}
