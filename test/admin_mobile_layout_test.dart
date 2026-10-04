import 'package:sales_tracking/widgets/assign_inventory_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:sales_tracking/widgets/inventory_records_table.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';
import 'package:sales_tracking/widgets/item_sales_dialog.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/services/branch_report_data.dart';

void main() {
  testWidgets(
    'phone quantity tile shows full name and preserves typing on keyboard resize',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      Future<void> show(double keyboard) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: Scaffold(
              body: SizedBox(
                width: 300,
                child: AssignInventoryTile(
                  title: 'Pistachio Dubai Chewy Cookies',
                  subtitle: 'Stock: 500 • ₱99.00',
                  icon: Icons.category,
                  controller: controller,
                  enabled: true,
                ),
              ),
            ),
          ),
        ),
      );
      await show(0);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '12');
      await show(300);
      await tester.pumpAndSettle();
      expect(controller.text, '12');
      expect(
        tester
            .widget<Text>(find.text('Pistachio Dubai Chewy Cookies'))
            .maxLines,
        isNull,
      );
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        greaterThan(
          tester.getBottomLeft(find.text('Pistachio Dubai Chewy Cookies')).dy,
        ),
      );
      await tester.enterText(find.byType(TextField), '125');
      expect(controller.text, '125');
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [360.0, 430.0]) {
    testWidgets('mobile records retain readable labels and actions at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InventoryRecordsTable(
                headings: const ['Staff ID', 'Staff', 'Reason', 'Actions'],
                rows: [
                  [
                    const Text('STF-001'),
                    const Text('Warren Example Full Name'),
                    const Text(
                      'Long detailed explanation of why the staff account was deactivated',
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('View info'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Table), findsNothing);
      expect(find.text('Staff ID'), findsOneWidget);
      expect(find.text('View info'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('phone report keeps periods in one row and opens item sales', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'Dagupan'},
      ],
      'completed_sales': [
        {
          'branchId': 'b',
          'timestamp': DateTime.now(),
          'total': 178,
          'items': [
            {'id': 'c', 'name': 'OG Cookies', 'price': 89, 'quantity': 2},
          ],
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(reportData: Future.value(data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Day')).dy,
      tester.getTopLeft(find.text('Year')).dy,
    );
    expect(find.text('₱178.00'), findsWidgets);
    await tester.ensureVisible(find.text('Tap for items'));
    await tester.tap(find.text('Tap for items'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemSalesDialog), findsOneWidget);
    expect(find.text('OG Cookies'), findsWidgets);
    await tester.enterText(
      find.descendant(
        of: find.byType(ItemSalesDialog),
        matching: find.byType(TextField),
      ),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No item sales for this period.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close item sales'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone category names have their own full-width row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = FakeFirebaseFirestore();
    for (final name in ['Cookies', 'Cakes']) {
      await db.collection('sales_inventory').doc(name).set({
        'name': name,
        'items': [
          {'id': name, 'name': 'Original $name', 'stock': 2, 'price': 89},
        ],
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminCatalog(
            firestore: db,
            type: 'Categories',
            pinnedControls: true,
            onOpen: (_) {},
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final icon in [
                  Icons.add,
                  Icons.block,
                  Icons.event_busy,
                  Icons.edit,
                ])
                  IconButton(onPressed: () {}, icon: Icon(icon)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Cookies'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Cakes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.widgetWithText(ChoiceChip, 'Cakes')).dx,
      lessThanOrEqualTo(360),
    );
  });
}
