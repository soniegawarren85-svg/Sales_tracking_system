import 'package:flutter/material.dart';

/// Category cards use two columns on phones and denser grids on larger screens.
class StaffSalesItemGrid extends StatelessWidget {
  const StaffSalesItemGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.bundles = false,
  });

  final int itemCount;
  final bool bundles;
  final Widget Function(BuildContext context, int index, bool compact)
  itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = MediaQuery.sizeOf(context);
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : size.width;
      final tablet =
          size.shortestSide >= 600 || (size.width >= 900 && size.height >= 520);
      final columns = tablet
          ? (availableWidth / 240).floor().clamp(3, 8)
          : bundles
          ? (availableWidth / 230).ceil().clamp(1, 8)
          : availableWidth < 600
          ? 2
          : (availableWidth / 240).floor().clamp(3, 8);
      const spacing = 12.0;
      final itemWidth = (availableWidth - (columns - 1) * spacing) / columns;
      final itemHeight =
          (bundles ? 290.0 : 230.0) +
          (MediaQuery.textScalerOf(context).scale(14) - 14) * 6;
      final compact = itemWidth < 140;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: List<Widget>.generate(itemCount, (index) {
          final child = itemBuilder(context, index, compact);
          return SizedBox(width: itemWidth, height: itemHeight, child: child);
        }),
      );
    },
  );
}
