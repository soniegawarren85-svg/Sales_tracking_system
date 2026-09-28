import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  test('branch hours follow edits and keep sales outside opening hours', () {
    final day = DateTime(2026, 9, 28);
    final data = BranchReportData({
      'branches': [{'_id': 'b', 'openingMinutes': 480, 'closingMinutes': 1140}],
      'completed_sales': [{'branchId': 'b', 'timestamp': DateTime(2026, 9, 28, 21), 'total': 350}],
    });
    expect(data.hours('b', day), containsAll([8, 19, 21]));
    data.collections['branches']!.single['openingMinutes'] = 420;
    expect(data.hours('b', day).first, 7);
  });

  testWidgets('week month and year keep revenue and hide closing cash drawer', (tester) async {
    final now = DateTime.now();
    final data = BranchReportData({
      'branches': [{'_id': 'b', 'name': 'Dagupan', 'openingMinutes': 480}],
      'completed_sales': [
        {'branchId': 'b', 'timestamp': now, 'total': 350, 'status': 'completed'},
        {'branchId': 'b', 'timestamp': now, 'total': -50, 'status': 'Refund'},
        {'branchId': 'other', 'timestamp': now, 'total': 900},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: BranchReportDialog(branchId: 'b', branchName: 'Dagupan', reportData: Future.value(data))));
    await tester.pumpAndSettle();
    for (final period in ['Week', 'Month', 'Year']) {
      await tester.tap(find.widgetWithText(ChoiceChip, period));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(BranchReportDialog));
      final Map<String, double> totals = state.reportTotals(data);
      expect(totals['Total revenue'], 350);
      expect(totals['Refunds'], 50);
      expect(totals.containsKey('Closing cash drawer'), isFalse);
      expect(find.text('Closing cash drawer'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('latest logs retain one row per device with shared IP and show logout', (tester) async {
    final db = FakeFirebaseFirestore();
    final records = db.collection('staff_login_sessions');
    for (final entry in [('old', 'tablet', 8), ('new', 'tablet', 9), ('second', 'phone', 10)]) {
      await records.doc(entry.$1).set({
        'branchId': 'b', 'userId': 'u', 'staffId': 'STF-001', 'staffName': entry.$1,
        'deviceId': entry.$2, 'ipAddress': '1.2.3.4',
        'loginAt': DateTime(2026, 9, 28, entry.$3).toIso8601String(),
        if (entry.$1 == 'new') 'logoutAt': DateTime(2026, 9, 28, 11).toIso8601String(),
      });
    }
    await tester.pumpWidget(MaterialApp(home: BranchStaffActivityDialog(branchId: 'b', branchName: 'Dagupan', firestore: db)));
    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('2h 0m'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
