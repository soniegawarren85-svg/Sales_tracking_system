import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../services/bundle_stock_service.dart';
import '../theme/app_colors.dart';
import 'historical_cash_drawer.dart';
import 'report_item_history.dart';
import '../services/number_format.dart';

/// Cost of sold units, excluding unsold starting and additional stock.
double branchStockCost(Map row) => row['totalCost'] != null
    ? reportValue(row['totalCost'])
    : reportValue(row['costPrice']) * reportValue(row['sold']);
double? branchSizePrice(Map row, String size) {
  final override = row['branchSizePriceOverrides'] as Map?;
  final overrideValue = override?.entries
      .where((entry) => '${entry.key}'.toLowerCase() == size.toLowerCase())
      .firstOrNull
      ?.value;
  final branchPrice = num.tryParse('${overrideValue ?? ''}');
  if (branchPrice != null) return branchPrice.toDouble();
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
    this.addons = false,
    this.allowRefunds = true,
    this.showActions = true,
  });
  final List<Map<String, dynamic>> rows;
  final bool beverages, inventory, addons, allowRefunds, showActions;
  final Widget Function(Map<String, dynamic>) actions;
  String money(dynamic v) => formatMoney(reportValue(v));
  String qty(dynamic v) => v == null ? '—' : reportValue(v).toStringAsFixed(0);
  @override
  Widget build(BuildContext context) {
    String sizeKey(String value) => switch (value.trim().toLowerCase()) {
      's' || 'small' => 'small',
      'm' || 'medium' => 'medium',
      'l' || 'large' => 'large',
      final name => name,
    };
    List<Map<String, dynamic>> expandBeverageSizes(Map<String, dynamic> row) {
      final options = (row['sizes'] as List? ?? const [])
          .whereType<Map>()
          .map((size) => Map<String, dynamic>.from(size))
          .toList();
      final salesBySize = (row['sizeSales'] as Map? ?? const {}).entries
          .where((entry) => entry.value is Map)
          .toList();
      final names = <String>[];
      for (final option in options) {
        final name = '${option['name'] ?? ''}'.trim();
        if (name.isNotEmpty &&
            !names.any((existing) => sizeKey(existing) == sizeKey(name))) {
          names.add(name);
        }
      }
      for (final entry in salesBySize) {
        final name = '${entry.key}'.split('|').first.trim();
        if (name.isNotEmpty &&
            !names.any((existing) => sizeKey(existing) == sizeKey(name))) {
          names.add(name);
        }
      }
      if (names.isEmpty) names.addAll(['Small', 'Medium', 'Large']);
      return names.asMap().entries.map((sizeEntry) {
        final index = sizeEntry.key;
        final name = sizeEntry.value;
        final matches = salesBySize.where(
          (entry) => sizeKey('${entry.key}'.split('|').first) == sizeKey(name),
        );
        final sold = matches.fold<double>(
          0,
          (total, entry) => total + reportValue((entry.value as Map)['sold']),
        );
        final sales = matches.fold<double>(
          0,
          (total, entry) => total + reportValue((entry.value as Map)['sales']),
        );
        final recordedCost = matches.fold<double>(
          0,
          (total, entry) =>
              total + reportValue((entry.value as Map)['totalCost']),
        );
        final recordedCostSold = matches.fold<double>(
          0,
          (total, entry) =>
              total + reportValue((entry.value as Map)['costRecordedSold']),
        );
        final option = options
            .where(
              (candidate) => sizeKey('${candidate['name']}') == sizeKey(name),
            )
            .firstOrNull;
        final price =
            branchSizePrice(row, name) ??
            reportValue(row['basePrice']) +
                reportValue(option?['priceDelta'] ?? option?['price']);
        final optionCost = option != null && option['costPrice'] != null
            ? reportValue(option['costPrice'])
            : reportValue(row['costPrice']);
        final fallbackCost = sold > recordedCostSold
            ? (sold - recordedCostSold) * optionCost
            : 0.0;
        final totalCost = recordedCost + fallbackCost;
        final costPrice = sold > 0 ? totalCost / sold : optionCost;
        final sizeLabel = switch (sizeKey(name)) {
          'small' => 'S',
          'medium' => 'M',
          'large' => 'L',
          _ => name,
        };
        return {
          ...row,
          '_groupContinuation': index > 0,
          '_sizeLabel': sizeLabel,
          'price': price,
          'sold': sold,
          'sales': sales,
          'costPrice': costPrice,
          'totalCost': totalCost,
          'unitProfit': price - costPrice,
          'profit': sales - totalCost,
          'netProfit': sales - totalCost,
        };
      }).toList();
    }

    final columns = <(String, String)>[
      ('id', 'ID'),
      ('allocationDate', 'Allocation date'),
      ('name', 'Item'),
      if (beverages && !addons) ('_sizeLabel', 'Size'),
      if (inventory && addons) ...[
        ('costPrice', 'Cost price'),
        ('price', 'Price'),
        ('status', 'Status'),
      ] else if (inventory) ...[
        ('costPrice', 'Cost price'),
        ('price', 'Price'),
        if (!beverages) ('expirationDate', 'Expiry'),
        if (!beverages) ('remaining', 'Stock'),
        ('status', 'Status'),
      ] else ...[
        ('price', beverages ? 'Selling price' : 'Unit price'),
        if (!beverages && !addons) ...[
          ('starting', 'Starting allocated'),
          ('added', 'Allocated in period'),
          ('remaining', 'Remaining allocated'),
        ],
        ('sales', 'Sales'),
        ('sold', 'Sold items'),
        ('costPrice', 'Cost price'),
        ('unitProfit', 'Profit per item'),
        ('profit', 'Total profit'),
        ('netProfit', 'Net profit'),
        if (allowRefunds) ('refund', 'Refund'),
        ('reduce', 'Reduce'),
        if (!beverages) ('expirationDate', 'Expiration date'),
        ('status', 'Status'),
      ],
      if (showActions) ('actions', 'Actions'),
    ];
    const totalKeys = {
      'starting',
      'remaining',
      'added',
      'profit',
      'netProfit',
      'sold',
      'sales',
      'stockCost',
    };
    bool low(Map row) =>
        row['isLowStock'] == true ||
        (!beverages &&
            reportValue(row['remaining']) > 0 &&
            inventoryLowStock(
              row['remaining'],
              type: '${row['type'] ?? 'Categories'}',
            ));
    bool near(Map row) {
      final date = cashRecordDate(row['expirationDate']);
      final today = DateUtils.dateOnly(DateTime.now());
      return date != null &&
          !DateUtils.dateOnly(date).isBefore(today) &&
          !DateUtils.dateOnly(date).isAfter(today.add(const Duration(days: 5)));
    }

    Widget value(Map<String, dynamic> row, String key) {
      if (key == 'actions') return actions(row);
      if (row['_groupContinuation'] == true &&
          ['id', 'allocationDate', 'name', 'status'].contains(key)) {
        return const SizedBox.shrink();
      }
      if (key == '_sizeLabel') return Text('${row[key] ?? '—'}');
      if (key == 'image')
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 42,
            height: 42,
            child:
                (row['imageUrl']?.toString().startsWith('data:image/') ?? false)
                ? const Icon(Icons.extension_outlined)
                : (row['imageUrl']?.toString().isNotEmpty ?? false)
                ? Image.network(
                    '${row['imageUrl']}',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.extension_outlined),
                  )
                : const Icon(Icons.extension_outlined),
          ),
        );
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
      if (key == 'status' && !inventory) {
        final status = row['isLowStock'] == true
            ? 'Low stock'
            : '${row['status'] ?? 'Not recorded'}';
        return Text(status);
      }
      if (key == 'status') {
        final stockTracked = !beverages && !addons;
        final soldOut =
            stockTracked &&
            reportValue(row['remaining']) <= 0 &&
            row['isLowStock'] != true;
        final status = soldOut
            ? 'Sold Out'
            : low(row)
            ? 'Low stock'
            : near(row)
            ? 'Near expiry'
            : 'Available';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!soldOut && low(row))
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            if (!soldOut && near(row))
              const Icon(Icons.event_busy, color: Colors.deepOrange, size: 20),
            Text(
              status,
              style: TextStyle(
                color: soldOut
                    ? Colors.red.shade700
                    : low(row) || near(row)
                    ? Colors.orange.shade800
                    : Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }
      if (key == 'remaining') {
        final soldOut = reportValue(row[key]) <= 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!soldOut && low(row))
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            Text(qty(row[key])),
          ],
        );
      }
      if (['starting', 'added', 'remaining', 'sold'].contains(key)) {
        return Text(qty(row[key]));
      }
      if ([
        'stockCost',
        'profit',
        'netProfit',
        'unitProfit',
        'sales',
        'price',
        'costPrice',
      ].contains(key)) {
        return Text(
          money(key == 'stockCost' ? branchStockCost(row) : row[key]),
        );
      }
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
                for (final expanded
                    in rows
                        .expand(
                          beverages && !addons
                              ? expandBeverageSizes
                              : (row) => [row],
                        )
                        .toList()
                        .asMap()
                        .entries)
                  DataRow(
                    color: WidgetStatePropertyAll(
                      expanded.key.isOdd
                          ? const Color(0xfffaf2f5)
                          : Colors.white,
                    ),
                    cells: columns
                        .map((c) => DataCell(value(expanded.value, c.$1)))
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
                              ? ([
                                      'stockCost',
                                      'profit',
                                      'netProfit',
                                      'sales',
                                    ].contains(key)
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
