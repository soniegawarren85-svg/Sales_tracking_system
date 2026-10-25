import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_sales_item_grid.dart';

void main() {
  for (final width in [280.0, 360.0, 600.0, 820.0]) {
    testWidgets('category grid is responsive at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffSalesItemGrid(
              itemCount: 4,
              itemBuilder: (context, index, compact) => InkWell(
                key: ValueKey(index),
                onTap: () => tapped = index,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 6 : 14),
                  child: Column(
                    children: [
                      SizedBox(
                        height: compact ? 64 : 88,
                        width: double.infinity,
                      ),
                      Text(
                        'Pistachio Dubai Chewy $index',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: compact ? 12 : 14),
                      ),
                      const Text('₱99'),
                      const Text('55 left'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getTopLeft(find.byKey(const ValueKey(0)));
      final second = tester.getTopLeft(find.byKey(const ValueKey(1)));
      final third = tester.getTopLeft(find.byKey(const ValueKey(2)));
      final fourth = tester.getTopLeft(find.byKey(const ValueKey(3)));
      if (width < 600) {
        expect(first.dy, second.dy);
        expect(second.dx, greaterThan(first.dx));
        expect(third.dy, greaterThan(first.dy));
      } else {
        expect(first.dy, third.dy);
        expect(third.dx, greaterThan(first.dx));
        expect(fourth.dy, greaterThan(first.dy));
      }
      await tester.tap(find.byKey(const ValueKey(2)));
      expect(tapped, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('grid remains scrollable when inventory changes', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var items = List<int>.generate(12, (index) => index);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: StaffSalesItemGrid(
                    itemCount: items.length,
                    itemBuilder: (context, index, compact) => Container(
                      key: ValueKey('product-${items[index]}'),
                      alignment: Alignment.center,
                      color: Colors.pink.shade100,
                      child: Text('Product ${items[index]}'),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 300)),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => setState(() => items = items.skip(1).toList()),
              child: const Icon(Icons.refresh),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Product 0'), findsNothing);
    expect(find.text('Product 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
