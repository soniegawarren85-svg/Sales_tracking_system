import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/widgets/inventory_header_transition.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    for (final itemCount in [1, 30]) {
      testWidgets('admin header collapses at $size with $itemCount items', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = FakeFirebaseFirestore();
        await db.collection('sales_inventory').doc('cookies').set({
          'name': 'Cookies',
          'items': [
            for (var i = 0; i < itemCount; i++)
              {'id': 'CO-$i', 'name': 'Cookie $i', 'stock': 10, 'price': 99},
          ],
        });
        var collapsed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    InventoryHeaderTransition(
                      collapsed: collapsed,
                      child: const SizedBox(
                        height: 140,
                        child: Text('Inventory'),
                      ),
                    ),
                    Expanded(
                      child: AdminCatalog(
                        firestore: db,
                        type: 'Categories',
                        pinnedControls: true,
                        compactHeader: collapsed,
                        onHeaderCollapsed: (value) {
                          if (collapsed != value) {
                            setState(() => collapsed = value);
                          }
                        },
                        onOpen: (_) {},
                        actions: TextButton(
                          onPressed: () {},
                          child: const Text('Add Category'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Cookie');
        await tester.pumpAndSettle();
        final expandedSearch = tester.getTopLeft(find.byType(TextField)).dy;
        final list = find.byKey(const ValueKey('inventory-table-scroll'));
        // Wheel input also covers tablets using a mouse or trackpad.
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getTopLeft(list) + const Offset(40, 40),
            scrollDelta: const Offset(0, 180),
          ),
        );
        await tester.pump();
        final animationStart = tester.getTopLeft(find.byType(TextField)).dy;
        expect(animationStart, closeTo(expandedSearch, 1));
        await tester.pump(const Duration(milliseconds: 90));
        final firstFrame = tester.getTopLeft(find.byType(TextField)).dy;
        expect(firstFrame, lessThan(animationStart));
        await tester.pump(const Duration(milliseconds: 90));
        final middleFrame = tester.getTopLeft(find.byType(TextField)).dy;
        expect(middleFrame, lessThan(firstFrame));
        await tester.pumpAndSettle();
        expect(collapsed, isTrue);
        expect(find.text('Inventory location'), findsNothing);
        expect(find.text('Add Category'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).key,
          const ValueKey('inventory-search'),
        );
        expect(find.text('Cookie'), findsOneWidget);
        expect(
          find.widgetWithText(ChoiceChip, 'Cookies').hitTestable(),
          findsOneWidget,
        );
        final compactSearch = tester.getTopLeft(find.byType(TextField)).dy;
        expect(compactSearch, lessThan(middleFrame));
        expect(compactSearch, lessThan(expandedSearch));
        if (itemCount > 1) {
          final controller = tester
              .widget<SingleChildScrollView>(list)
              .controller!;
          final start = controller.offset;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getTopLeft(list) + const Offset(40, 40),
              scrollDelta: const Offset(0, 240),
            ),
          );
          expect(controller.offset, start);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 65));
          final intermediate = controller.offset;
          expect(intermediate, greaterThan(start));
          expect(intermediate, lessThan(start + 240));
          await tester.pumpAndSettle();
          expect(controller.offset, closeTo(start + 240, 1));
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getTopLeft(list) + const Offset(40, 40),
              scrollDelta: const Offset(0, -120),
            ),
          );
          expect(controller.offset, closeTo(start + 240, 1));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 65));
          expect(controller.offset, lessThan(start + 240));
          expect(controller.offset, greaterThan(start + 120));
          await tester.pumpAndSettle();
          expect(controller.offset, closeTo(start + 120, 1));
        }
        await tester.drag(list, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byType(TextField)).dy, compactSearch);
        // Return to the beginning, then pull down to restore all controls.
        await tester.drag(list, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.drag(list, const Offset(0, 160));
        await tester.pumpAndSettle();
        expect(collapsed, isFalse);
        expect(find.text('Inventory location'), findsOneWidget);
        expect(find.text('Cookie'), findsOneWidget);
        // Touch input must collapse even when the items fit in the viewport.
        await tester.drag(list, const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(collapsed, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
