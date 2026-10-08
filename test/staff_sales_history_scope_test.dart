import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/staff_sales_history_scope.dart';

void main() {
  test('sales history includes only the signed-in staff member records', () {
    final ownSale = {'userId': 'cashier-a', 'branchId': 'same-branch'};
    final coworkerSale = {'userId': 'cashier-b', 'branchId': 'same-branch'};

    expect(saleBelongsToStaff(ownSale, 'cashier-a'), isTrue);
    expect(saleBelongsToStaff(coworkerSale, 'cashier-a'), isFalse);
  });

  test('history stays empty until a staff identity is available', () {
    expect(
      saleBelongsToStaff({'userId': 'cashier-a'}, ''),
      isFalse,
    );
  });
}
