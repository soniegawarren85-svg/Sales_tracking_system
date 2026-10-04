import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_category_manager.dart';
import 'package:sales_tracking/widgets/top_edge_refresh.dart';
import 'package:sales_tracking/widgets/branch_editor_dialog.dart';

void main() {
  testWidgets('category rename persists and archived categories stay hidden', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('sales_inventory/current').set({
      'name': 'Cookies',
      'items': [
        {'id': 'c', 'name': 'OG', 'stock': 3},
      ],
    });
    await db.doc('sales_inventory/old').set({
      'name': 'Expired',
      'items': [
        {'expirationDate': '2020-01-01'},
      ],
    });
    await db.doc('sales_inventory/void').set({
      'name': 'Voided',
      'isVoided': true,
      'items': [
        {'name': 'X'},
      ],
    });
    await db.doc('staff_inventory/linked').set({
      'name': 'Cookies',
      'sourceInventoryId': 'current',
      'items': [
        {'id': 'c', 'stock': 2},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCategoryManager(context, database: db),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Expired'), findsNothing);
    expect(find.text('Voided'), findsNothing);
    await tester.tap(find.byTooltip('Rename category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Fresh Cookies');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await db.doc('sales_inventory/current').get()).data()!['name'],
      'Fresh Cookies',
    );
    final linked = (await db.doc('staff_inventory/linked').get()).data()!;
    expect(linked['name'], 'Fresh Cookies');
    expect((linked['items'] as List).single['stock'], 2);
    expect(find.text('Fresh Cookies'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh requires a top gesture and a scroll position at the top',
    (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopEdgeRefresh(
              onRefresh: () async {
                refreshes++;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: List.generate(
                  30,
                  (i) => SizedBox(height: 60, child: Text('Row $i')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.dragFrom(const Offset(200, 400), const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(refreshes, 0);
      await tester.dragFrom(const Offset(200, 60), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      await tester.dragFrom(const Offset(200, 400), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(200, 60), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    },
  );

  testWidgets('create branch asks only for its name', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const BranchEditorDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Opening time'), findsNothing);
    expect(find.text('Closing time'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Dagupan');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(saved, {
      'name': 'Dagupan',
      'openingMinutes': 0,
      'closingMinutes': 1440,
    });
  });
}
