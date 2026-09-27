import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class InventoryRecordsTable extends StatelessWidget {
  const InventoryRecordsTable({
    super.key,
    required this.headings,
    required this.rows,
    this.flex = const {},
  });
  final List<String> headings;
  final List<List<Widget>> rows;
  final Map<int, double> flex;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (final entry in flex.entries)
          entry.key: FlexColumnWidth(entry.value),
      },
      border: const TableBorder(
        horizontalInside: BorderSide(color: AppColors.border),
      ),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.primaryDark),
          children: headings
              .map(
                (label) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 16,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        for (var i = 0; i < rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i.isEven ? Colors.white : AppColors.surfaceTint,
            ),
            children: rows[i]
                .map(
                  (cell) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                      ),
                      child: cell,
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    ),
  );
}
