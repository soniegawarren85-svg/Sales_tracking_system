import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/widgets/admin_item_editor.dart';
import 'package:sales_tracking/widgets/admin_sales_overview.dart';

void main() {
  test(
    'Current categories omit expired, voided and empty records and group names',
    () {
      final now = DateTime(2026, 9, 25);
      final products = <Map<String, dynamic>>[
        {
          'id': 'old',
          'name': 'Cookies',
          'items': [
            {'name': 'Old', 'expirationDate': '2026-09-24'},
          ],
        },
        {
          'id': 'active',
          'name': 'Cookies',
          'items': [
            {'name': 'Pistachio', 'expirationDate': '2026-09-25'},
          ],
        },
        {
          'id': 'duplicate',
          'name': ' cookies ',
          'items': [
            {'name': 'Red velvet'},
          ],
        },
        {
          'id': 'void',
          'name': 'Cakes',
          'isDeleted': true,
          'items': [
            {'name': 'Cake'},
          ],
        },
        {
          'id': 'void-item',
          'name': 'Brownies',
          'items': [
            {'name': 'Brownie', 'isDeleted': true},
          ],
        },
        {'id': 'empty', 'name': 'Testing', 'items': []},
      ];
      final categories = currentCatalogCategories(products, now: now);
      expect(categories.map((item) => item['id']), ['active']);
      final visible = adminCatalogEntries(products, [], now: now);
      expect(visible.map((entry) => entry.name), ['Pistachio', 'Red velvet']);
      expect(products, hasLength(6));
    },
  );

  test('Bundle expiry uses component snapshots or an unambiguous source', () {
    final bundle = {
      'items': [
        {'name': 'Pistachio', 'parentName': 'Cookies', 'quantity': 2},
        {'name': 'Cake', 'expirationDate': '2026-12-31'},
      ],
    };
    final source = <String, dynamic>{
      'id': 'cookies',
      'name': 'Cookies',
      'items': [
        {'name': 'Pistachio', 'expirationDate': '2026-10-31'},
      ],
    };
    final items = catalogBundleContents(bundle, [source]);
    expect(items.first['expirationDate'], '2026-10-31');
    expect(items.last['expirationDate'], '2026-12-31');
    expect((bundle['items'] as List).first['expirationDate'], isNull);
    expect(
      catalogBundleContents(bundle, [
        source,
        {...source, 'id': 'other'},
      ]).first['expirationDate'],
      isNull,
    );
  });

  test('Report week crosses years and month includes leap day', () {
    expect(branchReportRange(DateTime(2026, 1, 1), 'Week'), (
      DateTime(2025, 12, 29),
      DateTime(2026, 1, 5),
    ));
    expect(branchReportRange(DateTime(2024, 2, 20), 'Month'), (
      DateTime(2024, 2),
      DateTime(2024, 3),
    ));
    expect(branchReportRange(DateTime(2026, 9, 25, 15), 'Day'), (
      DateTime(2026, 9, 25),
      DateTime(2026, 9, 26),
    ));
  });

  test('Item matching targets the ID and refuses ambiguous legacy names', () {
    final items = <Map<String, dynamic>>[
      {'id': 'a', 'name': 'Cookie'},
      {'id': 'b', 'name': 'Cookie'},
    ];
    expect(catalogItemIndex(items, {'id': 'b', 'name': 'Cookie'}), 1);
    expect(catalogItemIndex(items, {'name': 'Cookie'}), -1);
    expect(catalogItemIndex(items, {'id': 'missing'}), -1);
  });

  testWidgets(
    'Item edit opens one dialog for the selected item without a sheet',
    (tester) async {
      final entry = AdminCatalogEntry(
        id: 'a',
        name: 'Pistachio',
        type: 'Categories',
        source: const {'id': 'category'},
        images: const [],
        details: const {
          'id': 'a',
          'name': 'Pistachio',
          'price': 99,
          'stock': 300,
          'expirationDate': '2026-12-31',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdminItemEditor(
                context,
                entry: entry,
                upload: (_) async => null,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Edit Pistachio'), findsOneWidget);
      expect(find.text('3 variants'), findsNothing);
      expect(find.text('300'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Coffee edit shows size prices without a stock field', (
    tester,
  ) async {
    final entry = AdminCatalogEntry(
      id: 'coffee',
      name: 'Latte',
      type: 'Coffee',
      source: const {'id': 'coffee'},
      images: const [],
      details: const {
        'name': 'Latte',
        'basePrice': 100,
        'sizes': [
          {'name': 'Small', 'priceDelta': 0},
          {'name': 'Medium', 'priceDelta': 20},
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAdminItemEditor(
              context,
              entry: entry,
              upload: (_) async => null,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Latte'), findsOneWidget);
    expect(find.text('Current stock'), findsNothing);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
