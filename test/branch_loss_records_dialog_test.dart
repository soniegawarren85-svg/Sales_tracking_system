import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_loss_records_dialog.dart';

void main() {
  final july = <String, dynamic>{
    'timestamp': DateTime(2026, 7, 15, 13),
    'staffName': 'Ana Cruz',
    'staffPublicId': 'STF-0001',
    'reason': 'Damaged',
    'items': [
      {'name': 'Cookies', 'quantity': 2},
      {'name': 'Cake bundle', 'isBundle': true, 'quantity': 1},
    ],
  };
  final september = <String, dynamic>{
    'timestamp': DateTime(2026, 9, 24, 11),
    'staffName': 'Ben Reyes',
    'staffPublicId': 'STF-0002',
    'items': [
      {'name': 'Latte', 'isCoffee': true, 'quantity': 1},
    ],
  };
  final records = [july, september];

  test('Month includes July and September of the selected year', () {
    final period = lossRecordPeriod(DateTime(2026, 9, 24), 'Month');
    final result = filterLossRecords([
      ...records,
      {...july, 'timestamp': DateTime(2027)},
    ], period: period);
    expect(result.length, 2);
    expect(result.first['staffName'], 'Ben Reyes');
  });

  test('Week crosses year boundaries and excludes the next Monday', () {
    final period = lossRecordPeriod(DateTime(2026, 1, 1), 'Week');
    expect(period.start, DateTime(2025, 12, 29));
    expect(period.end, DateTime(2026, 1, 5));
    expect(
      filterLossRecords([
        {...july, 'timestamp': DateTime(2025, 12, 31)},
        {...july, 'timestamp': DateTime(2026, 1, 5)},
      ], period: period).length,
      1,
    );
  });

  test('Exact date, staff ID search, and category filters compose', () {
    final period = lossRecordPeriod(DateTime(2026, 9, 24), 'Month');
    final result = filterLossRecords(
      records,
      period: period,
      date: DateTime(2026, 7, 15),
      query: 'stf-0001',
      category: 'Bundle',
    );
    expect(result.length, 1);
    expect((result.single['items'] as List).single['name'], 'Cake bundle');
    expect((july['items'] as List).length, 2);
    expect(
      filterLossRecords(records, period: period, category: 'Coffee').length,
      1,
    );
    expect(
      filterLossRecords(
        records,
        period: lossRecordPeriod(DateTime(2026, 9, 24), 'Day'),
      ).length,
      1,
    );
  });

  testWidgets('Gallery groups months and search narrows the visible records', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchLossRecordsDialog(
            status: 'Reduced',
            anchor: DateTime(2026, 9, 24),
            range: 'Month',
            records: records,
            staffRecords: Future.value(records),
            cardBuilder: (record) => Text(record['staffName'].toString()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ana');
    await tester.pumpAndSettle();
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
