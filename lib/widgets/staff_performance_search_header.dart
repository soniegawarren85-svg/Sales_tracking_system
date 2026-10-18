import 'package:flutter/material.dart';

class PerformanceSearchHeader extends SliverPersistentHeaderDelegate {
  const PerformanceSearchHeader({
    required this.search,
    required this.range,
    required this.onSearchChanged,
    required this.onPickRange,
  });

  final String search;
  final DateTimeRange range;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickRange;

  @override
  double get minExtent => 78;

  @override
  double get maxExtent => 78;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(
    child: Material(
      color: Colors.white,
      elevation: overlapsContent ? 3 : 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: TextField(
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search performance details',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Filter performance by date range',
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range),
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant PerformanceSearchHeader oldDelegate) =>
      search != oldDelegate.search ||
      range != oldDelegate.range ||
      onSearchChanged != oldDelegate.onSearchChanged;
}
