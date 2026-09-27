import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/admin_sales_overview.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';

void main() {
  test('year and week use complete calendar boundaries', () {
    final year = branchReportRange(DateTime(2026,9,27), 'Year');
    expect(year, (DateTime(2026), DateTime(2027)));
    final week = branchReportRange(DateTime(2026,9,27), 'Week');
    expect(week, (DateTime(2026,9,21), DateTime(2026,9,28)));
    expect(reportInRange(DateTime(2026,9,27,23,59), week.$1, week.$2), true);
  });
  testWidgets('year includes archived sold items and All exceeds ten', (tester) async {
    final year = DateTime.now().year;
    final data = BranchReportData({'completed_sales': [
      for(var i=0; i<14; i++) {'_id':'s$i','branchId':'b','timestamp':DateTime(year, i%12+1, 1), 'total':100, 'isDeleted':true,
        'items':[{'itemId':'item$i','publicId':'IT-$i','name':'Archived $i','quantity':i+1,'price':100}]},
    ], 'sales_inventory':[], 'staff_cash_drawer':[{'_id':'b','dailyOpeningCash':1200}]});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BranchReportDialog(branchId:'b', branchName:'Branch', reportData:Future.value(data)))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip,'Year'));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(BranchReportDialog));
    final items = state.visibleItems(data) as List<Map<String,dynamic>>;
    expect(items.length,14);
    expect((state.rankedItems(items) as List).length,14);
    expect(state.bars(data).$4.length,12);
    final top = find.text('Top 10 Selling');
    for(var i=0;i<30 && top.evaluate().isEmpty;i++) { await tester.drag(find.byType(ListView).first,const Offset(0,-350)); await tester.pumpAndSettle(); }
    await tester.ensureVisible(top);
    await tester.pumpAndSettle();
    await tester.tap(top);
    await tester.pumpAndSettle();
    expect((state.rankedItems(items) as List).length,10);
    expect((state.rankedItems(items) as List).first['sold'],14);
    await tester.tap(find.text('Low 10 Selling'));
    await tester.pumpAndSettle();
    expect((state.rankedItems(items) as List).length,10);
    expect((state.rankedItems(items) as List).first['sold'],1);
    expect(tester.takeException(),isNull);
  });
}
