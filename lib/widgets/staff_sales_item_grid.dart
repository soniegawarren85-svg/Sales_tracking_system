import 'package:flutter/material.dart';

/// Category cards always show at least three columns, including phone layouts.
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
      final columns = bundles
          ? (constraints.maxWidth / 230).ceil().clamp(1, 8)
          : (constraints.maxWidth / 240).floor().clamp(3, 8);
      final compact =
          (constraints.maxWidth - (columns - 1) * 12) / columns < 140;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent:
              (bundles ? 290 : 230) +
              (MediaQuery.textScalerOf(context).scale(14) - 14) * 6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => itemBuilder(context, index, compact),
      );
    },
  );
}
