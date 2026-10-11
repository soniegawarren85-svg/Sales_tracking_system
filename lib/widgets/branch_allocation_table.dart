import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../theme/app_colors.dart';
import 'historical_cash_drawer.dart';
import 'report_item_history.dart';

/// Stock investment for counted products; beverages are prepared on demand.
double branchStockCost(Map row) => row['type'] == 'Beverages'
    ? reportValue(
        row['totalCost'] ??
            reportValue(row['costPrice']) * reportValue(row['sold']),
      )
    : reportValue(row['costPrice']) *
          (reportValue(row['starting']) + reportValue(row['added']));
double? branchSizePrice(Map row, String size) {
  final option = (row['sizes'] as List? ?? [])
      .whereType<Map>()
      .where((s) => '${s['name']}'.toLowerCase() == size.toLowerCase())
      .firstOrNull;
  return option == null
      ? null
      : reportValue(row['basePrice']) +
            reportValue(option['priceDelta'] ?? option['price']);
}

void showBranchItemHistory(
  BuildContext context,
  BranchReportData data,
  String branch,
  Map<String, dynamic> row,
) {
  final today = DateUtils.dateOnly(DateTime.now());
  showDialog<void>(
    context: context,
    builder: (_) => ReportItemHistory(
      item: row,
      period: 'Allocation and sales history',
      initialRange: DateTimeRange(start: today, end: today),
      loadRange: (range) =>
          data
              .items(
                branch,
                range.start,
                range.end.add(const Duration(days: 1)),
              )
              .where((item) => item['id'] == row['id'])
              .firstOrNull ??
          {
            ...row,
            'history': <Map<String, dynamic>>[],
            'sizeSales': <String, dynamic>{},
          },
    ),
  );
}

class BranchAllocationTable extends StatelessWidget {
  const BranchAllocationTable({
    super.key,
    required this.rows,
    required this.beverages,
    required this.actions,
    this.inventory = false,
  });
  final List<Map<String, dynamic>> rows;
  final bool beverages, inventory;
  final Widget Function(Map<String, dynamic>) actions;
  String money(dynamic v) => '₱${reportValue(v).toStringAsFixed(2)}';
  String qty(dynamic v) => v == null ? '—' : reportValue(v).toStringAsFixed(0);
  @override
  Widget build(BuildContext context) {
    final columns = <(String, String)>[
      ('id', 'ID'),
      ('allocationDate', 'Allocation date'),
      ('name', 'Item'),
      if (inventory) ...[
        ('costPrice', 'Cost price'),
        if (!beverages) ('price', 'Price'),
        if (beverages)
          for (final size in ['Small', 'Medium', 'Large']) (size, size),
        ('expirationDate', 'Expiry'),
        if (!beverages) ('remaining', 'Stock'),
        ('status', 'Availability'),
      ] else ...[
        if (!beverages) ('starting', 'Starting allocation'),
        ('added', 'Allocated today'),
        if (!beverages) ('remaining', 'Remaining allocation'),
        ('stockCost', 'Total cost'),
        ('profit', 'Total profit'),
        ('sold', 'Total sold'),
        ('sales', 'Sales'),
        if (beverages)
          for (final size in ['Small', 'Medium', 'Large']) (size, size)
        else
          ('price', 'Price'),
      ],
      ('actions', 'Actions'),
    ];
    const totalKeys = {
      'starting',
      'added',
      'remaining',
      'stockCost',
      'profit',
      'sold',
      'sales',
    };
    bool low(Map row) =>
        !beverages &&
        row['remaining'] != null &&
        reportValue(row['remaining']) <= 50;
    bool near(Map row) {
      final date = cashRecordDate(row['expirationDate']);
      final today = DateUtils.dateOnly(DateTime.now());
      return date != null &&
          !DateUtils.dateOnly(date).isBefore(today) &&
          !DateUtils.dateOnly(date).isAfter(today.add(const Duration(days: 5)));
    }

    Widget value(Map<String, dynamic> row, String key) {
      if (key == 'actions') return actions(row);
      if (key == 'allocationDate' || key == 'expirationDate') {
        final at = cashRecordDate(row[key]);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (key == 'expirationDate' && near(row))
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.event_busy,
                  color: Colors.deepOrange,
                  size: 20,
                ),
              ),
            Text(
              at == null
                  ? 'Not recorded'
                  : MaterialLocalizations.of(context).formatShortDate(at),
            ),
          ],
        );
      }
      if (['Small', 'Medium', 'Large'].contains(key)) {
        final price = branchSizePrice(row, key);
        return Text(price == null ? '—' : money(price));
      }
      if (key == 'status')
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (low(row))
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            Text(
              low(row) ? 'Low stock' : 'Available',
              style: TextStyle(
                color: low(row)
                    ? Colors.orange.shade800
                    : Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      if (key == 'remaining')
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (low(row))
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            Text(qty(row[key])),
          ],
        );
      if (['starting', 'added', 'sold'].contains(key))
        return Text(qty(row[key]));
      if (['stockCost', 'profit', 'sales', 'price', 'costPrice'].contains(key))
        return Text(
          money(key == 'stockCost' ? branchStockCost(row) : row[key]),
        );
      return Text('${row[key] ?? ''}');
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.blush),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: const WidgetStatePropertyAll(AppColors.primary),
              headingTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              dataRowMinHeight: 58,
              dataRowMaxHeight: 76,
              columnSpacing: 26,
              horizontalMargin: 20,
              columns: columns
                  .map((c) => DataColumn(label: Text(c.$2)))
                  .toList(),
              rows: [
                for (final entry in rows.asMap().entries)
                  DataRow(
                    color: WidgetStatePropertyAll(
                      entry.key.isOdd ? const Color(0xfffaf2f5) : Colors.white,
                    ),
                    cells: columns
                        .map((c) => DataCell(value(entry.value, c.$1)))
                        .toList(),
                  ),
                if (!inventory)
                  DataRow(
                    color: const WidgetStatePropertyAll(AppColors.blush),
                    cells: columns.map((c) {
                      final key = c.$1;
                      final sum = rows.fold<double>(
                        0,
                        (s, r) =>
                            s +
                            (key == 'stockCost'
                                ? branchStockCost(r)
                                : reportValue(r[key])),
                      );
                      return DataCell(
                        Text(
                          key == 'id'
                              ? 'Total'
                              : totalKeys.contains(key)
                              ? (['stockCost', 'profit', 'sales'].contains(key)
                                    ? money(sum)
                                    : qty(sum))
                              : '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
