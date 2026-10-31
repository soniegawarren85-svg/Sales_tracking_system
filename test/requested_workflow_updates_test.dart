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
              startAreaHeight: 160,
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

  testWidgets('refresh works from a nested dashboard header', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopEdgeRefresh(
            onRefresh: () async {
              refreshes++;
            },
            child: NestedScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: Center(child: Text('Dashboard header')),
                  ),
                ),
              ],
              body: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 20,
                itemBuilder: (context, index) =>
                    SizedBox(height: 60, child: Text('Dashboard row $index')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 360));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(refreshes, 0);

    await tester.dragFrom(const Offset(200, 80), const Offset(0, 360));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create branch accepts an optional receipt address', (
    tester,
  ) async {
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
    expect(find.text('Branch address (optional)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Dagupan');
    await tester.enterText(find.byType(TextField).last, '123 Main Street');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(saved, {
      'name': 'Dagupan',
      'address': '123 Main Street',
      'openingMinutes': 0,
      'closingMinutes': 1440,
    });
  });

  testWidgets('edit branch pre-fills and can clear the optional address', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const BranchEditorDialog(
                    initial: {'name': 'Dagupan', 'address': '123 Main Street'},
                  ),
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
    expect(find.text('Edit Branch'), findsOneWidget);
    expect(find.text('123 Main Street'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?['address'], '');
    expect(saved?['name'], 'Dagupan');
    expect(tester.takeException(), isNull);
  });
}
