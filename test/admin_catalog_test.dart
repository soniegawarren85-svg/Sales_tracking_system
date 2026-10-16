import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

void main() {
  final today = DateTime(2026, 9, 24);
  final category = <String, dynamic>{
    'id': 'category-doc',
    'categoryId': 'CAT-001',
    'name': 'Cookies',
    'imageUrl': 'category.jpg',
    'items': [
      {
        'id': 'VAR-001',
        'name': 'Pistachio',
        'startingStock': 20,
        'stock': 7,
        'imageUrl': 'pistachio.jpg',
      },
      {'id': 'VAR-002', 'name': 'Chocolate', 'startingStock': 0},
      {
        'id': 'VAR-003',
        'name': 'Expired',
        'startingStock': 30,
        'expirationDate': '2026-09-23',
      },
      {
        'id': 'VAR-004',
        'name': 'Removed',
        'startingStock': 40,
        'isDeleted': true,
      },
    ],
  };

  test('Inventory lists individual item IDs and current stock', () {
    final entries = adminCatalogEntries([category], [], now: today);
    expect(entries.map((entry) => entry.id), ['VAR-001', 'VAR-002']);
    expect(entries.first.stock, 7);
    expect(entries.last.available, isFalse);
    // Editing a visible item must not discard expired or voided siblings.
    expect(entries.first.source['items'], hasLength(4));
    expect(entries.first.details['id'], 'VAR-001');
    // A category's cover photo must not replace this item's own picture.
    expect(entries.first.images, ['pistachio.jpg']);
    expect(entries.last.images, isEmpty);
  });

  test('Home groups active variants and includes their carousel images', () {
    final entry = adminCatalogEntries(
      [category],
      [],
      gallery: true,
      now: today,
    ).single;
    expect(entry.name, 'Cookies');
    expect(entry.id, 'CAT-001');
    expect(entry.stock, 7);
    expect(entry.images, ['category.jpg', 'pistachio.jpg']);
  });

  test('Bundle stock excludes sold and reduced instances', () {
    final entry = adminCatalogEntries(
      [
        {
          'id': 'bundle-doc',
          'bundleId': '',
          'isBundle': true,
          'bundleCount': 99,
          'bundleInstances': [
            {'status': 'available'},
            {'status': 'sold'},
            {'status': 'reduced'},
          ],
        },
      ],
      [],
      now: today,
    ).single;
    expect(entry.id, 'bundle-doc');
    expect(entry.stock, 1);
  });

  test('Beverages uses existing IDs and does not invent stock quantities', () {
    final entries = adminCatalogEntries([], [
      {'id': 'coffee-doc', 'coffeeId': 'COF-001', 'name': 'Latte'},
      {'id': 'removed-coffee', 'isDeleted': true},
      {'id': 'unavailable-coffee', 'name': 'Mocha', 'isAvailable': false},
    ], now: today);
    expect(entries.length, 2);
    expect(entries.first.id, 'COF-001');
    expect(entries.first.stock, isNull);
    expect(entries.last.available, isFalse);
  });

  testWidgets('branch dropdown, search and category stay in original order', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('cookies').set({
      'name': 'Cookies',
      'items': [
        for (var i = 0; i < 20; i++)
          {'id': 'CO-$i', 'name': 'Cookie $i', 'stock': 5, 'price': 50},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: AdminCatalog(
              firestore: db,
              type: 'Categories',
              pinnedControls: true,
              onOpen: (_) {},
              actions: const Text('Add Category'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final branch = tester.getTopLeft(
      find.byType(DropdownButtonFormField<String>),
    );
    final search = tester.getTopLeft(find.byType(TextField));
    final category = tester.getTopLeft(
      find.widgetWithText(ChoiceChip, 'Cookies'),
    );
    expect(branch.dy, lessThan(search.dy));
    expect(search.dy, lessThan(category.dy));
    await tester.drag(
      find.byKey(const ValueKey('inventory-table-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byType(DropdownButtonFormField<String>)),
      branch,
    );
    expect(tester.getTopLeft(find.byType(TextField)), search);
    expect(
      tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Cookies')),
      category,
    );
    expect(find.text('Add Category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inventory table scrolls horizontally with consistent value text',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = FakeFirebaseFirestore();
      await db.collection('sales_inventory').doc('cookies').set({
        'name': 'Cookies',
        'items': [
          {
            'id': 'CO-001',
            'name': 'Cookie',
            'stock': 5,
            'price': 55,
            'costPrice': 20,
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminCatalog(
              firestore: db,
              type: 'Categories',
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final horizontalScroll = find.byKey(
        const ValueKey('admin-catalog-horizontal-scroll'),
      );
      final scrollable = find
          .descendant(of: horizontalScroll, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));

      final costText = tester.widget<Text>(find.text('₱20.00'));
      final stockText = tester.widget<Text>(find.text('5'));
      final priceText = tester.widget<Text>(find.text('₱55.00'));
      expect(costText.style?.fontSize, 12);
      expect(stockText.style?.fontSize, 12);
      expect(priceText.style?.fontSize, 12);

      await tester.drag(horizontalScroll, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inventory can scroll from controls above branch table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('cookies').set({
      'name': 'Cookies',
      'items': [
        for (var i = 0; i < 20; i++)
          {'id': 'CO-$i', 'name': 'Cookie $i', 'stock': 5, 'price': 50},
      ],
    });
    await db.collection('branches').doc('branch-1').set({
      'name': 'Other Branch',
    });
    await db.collection('staff_inventory').doc('allocation-1').set({
      'staffId': 'branch-1',
      'branchId': 'branch-1',
      'sourceInventoryId': 'cookies',
      'items': [
        for (var i = 0; i < 20; i++)
          {
            'id': 'CO-$i',
            'name': 'Cookie $i',
            'stock': 5,
            'startingStock': 5,
            'price': 50,
            'costPrice': 20,
          },
      ],
    });

    final controller = ScrollController();
    addTearDown(controller.dispose);
    var headerCollapsed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) {
                    if (!controller.hasClients) return;
                    final position = controller.position;
                    final delta = -details.delta.dy;
                    final target = (position.pixels + delta)
                        .clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        )
                        .toDouble();
                    if (delta > 0 && !headerCollapsed) {
                      setState(() => headerCollapsed = true);
                    } else if (delta < 0 &&
                        target <= position.minScrollExtent &&
                        headerCollapsed) {
                      setState(() => headerCollapsed = false);
                    }
                    if (target != position.pixels) {
                      position.jumpTo(target);
                    }
                  },
                  child: headerCollapsed
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            const SizedBox(
                              height: 70,
                              child: Center(child: Text('Inventory')),
                            ),
                            const Text('Categories / Bundle / Beverages'),
                          ],
                        ),
                ),
                Expanded(
                  child: AdminCatalog(
                    firestore: db,
                    type: 'Categories',
                    pinnedControls: true,
                    compactHeader: headerCollapsed,
                    scrollController: controller,
                    onHeaderCollapsed: (value) {
                      if (value != headerCollapsed) {
                        setState(() => headerCollapsed = value);
                      }
                    },
                    onOpen: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Branch').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final search = find.byType(TextField);
    final searchPosition = tester.getTopLeft(search);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: searchPosition + const Offset(20, 20),
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: searchPosition + const Offset(20, 20),
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(search.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(TextField), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(TextField), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(tester.takeException(), isNull);
    }

    final table = find.byKey(const ValueKey('inventory-table-scroll'));
    for (var i = 0; i < 3; i++) {
      await tester.drag(table, const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(table, const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
