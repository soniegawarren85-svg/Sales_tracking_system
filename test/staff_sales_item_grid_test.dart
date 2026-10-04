import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_sales_item_grid.dart';

void main() {
  for (final width in [280.0, 360.0, 600.0, 820.0]) {
    testWidgets('three category items share the first row at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      final third = tester.getTopLeft(find.byKey(const ValueKey(2)));
      final fourth = tester.getTopLeft(find.byKey(const ValueKey(3)));
      expect(first.dy, third.dy);
      expect(third.dx, greaterThan(first.dx));
      expect(fourth.dy, greaterThan(first.dy));
      await tester.tap(find.byKey(const ValueKey(2)));
      expect(tapped, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
