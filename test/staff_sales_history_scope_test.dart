import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/staff_sales_history_scope.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test('sales history includes only the signed-in staff member records', () {
    final ownSale = {'userId': 'cashier-a', 'branchId': 'same-branch'};
    final coworkerSale = {'userId': 'cashier-b', 'branchId': 'same-branch'};

    expect(saleBelongsToStaff(ownSale, 'cashier-a'), isTrue);
    expect(saleBelongsToStaff(coworkerSale, 'cashier-a'), isFalse);
  });

  test('history stays empty until a staff identity is available', () {
    expect(saleBelongsToStaff({'userId': 'cashier-a'}, ''), isFalse);
  });

  test('legacy staff identifiers are included without matching coworkers', () {
    expect(
      saleBelongsToStaff(
        {'staffId': 'STF-001'},
        'auth-1',
        staffAliases: {'STF-001'},
      ),
      isTrue,
    );
    expect(
      saleBelongsToStaff(
        {'staffPublicId': 'STF-002'},
        'auth-1',
        staffAliases: {'STF-001'},
      ),
      isFalse,
    );
  });

  test('date range includes every transaction on both boundary dates', () {
    final receipts = [
      {
        'salesId': 'before',
        'timestamp': Timestamp.fromDate(DateTime(2026, 10, 23, 23, 59)),
      },
      {
        'salesId': 'start',
        'timestamp': Timestamp.fromDate(DateTime(2026, 10, 24, 0, 1)),
      },
      {
        'salesId': 'end',
        'timestamp': Timestamp.fromDate(DateTime(2026, 10, 25, 23, 59)),
      },
      {
        'salesId': 'after',
        'timestamp': Timestamp.fromDate(DateTime(2026, 10, 26, 0, 0)),
      },
    ];

    final filtered = filterStaffReceiptDates(
      receipts,
      start: DateTime(2026, 10, 24),
      end: DateTime(2026, 10, 25),
    );

    expect(filtered.map((receipt) => receipt['salesId']), ['end', 'start']);
  });

  test('legacy date fields and epoch-second timestamps remain filterable', () {
    final receipts = [
      {'salesId': 'legacy-date', 'saleDate': '2026-10-01T09:30:00'},
      {
        'salesId': 'epoch-seconds',
        'timestamp': DateTime(2026, 10, 23, 11).millisecondsSinceEpoch ~/ 1000,
      },
    ];

    final filtered = filterStaffReceiptDates(
      receipts,
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 23),
    );

    expect(filtered.map((receipt) => receipt['salesId']), [
      'epoch-seconds',
      'legacy-date',
    ]);
  });
}
