import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('debug checklist', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('allocation_checklist/received-yesterday').set({
      'kind': 'incoming',
      'staffId': 'branch',
      'status': 'Received',
      'name': 'Yesterday allocation',
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      'assignedAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      'confirmedAt': Timestamp.fromDate(DateTime.now()),
    });
    final snapshot = await db.collection('allocation_checklist').where('staffId', isEqualTo: 'branch').get();
    final d = snapshot.docs.first.data();
    print('RAW QUERY DOCS: ${snapshot.docs.length}');
    print('status label: ${ChecklistStatus.label(d)}');
    print('received? ${ChecklistStatus.label(d) == ChecklistStatus.received}');
    print('incomingOpen? ${ChecklistStatus.incomingOpen(d)}');
    print('isReturnRecord? ${ChecklistStatus.isReturnRecord(d)}');
    final selectedDay = DateUtils.dateOnly(DateTime.now());
    final selectedEnd = DateUtils.dateOnly(DateTime.now());
    final at = (d['confirmedAt'] as Timestamp).toDate();
    final rangeEnd = (selectedEnd).add(const Duration(days: 1));
    print('selectedDay=$selectedDay selectedEnd=$selectedEnd localDate=$at rangeEnd=$rangeEnd');
    print('isBefore(start)? ${at.toLocal().isBefore(selectedDay)}');
    print('isBefore(end)? ${at.toLocal().isBefore(rangeEnd)}');
    print('shouldFilterDate? ${ChecklistStatus.label(d) == ChecklistStatus.received}');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AllocationChecklistButton(scopeIds: const ['branch'], database: db))));
    await tester.pumpAndSettle();
    print('BEFORE TAP: Checklist=${find.text('Checklist').evaluate().length} Returns=${find.text('Returns').evaluate().length}');
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    print('AFTER TAP: tabs: ${find.text('Incoming Items').evaluate().length} / ${find.text('Complete Items').evaluate().length}');
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      print('TEXT: ${widget.data}');
    }
  });
}
