import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../theme/app_colors.dart';

class ReportItemHistory extends StatelessWidget {
  const ReportItemHistory({
    super.key,
    required this.item,
    required this.period,
  });
  final Map<String, dynamic> item;
  final String period;

  @override
  Widget build(BuildContext context) {
    final beverage = item['type'] == 'Beverages';
    final records = beverage
        ? (item['sizeSales'] as Map? ?? {}).values.whereType<Map>().toList()
        : (item['history'] as List? ?? []).whereType<Map>().toList();
    String money(dynamic v) => '₱${reportValue(v).toStringAsFixed(2)}';
    String qty(dynamic v) => reportValue(v).toStringAsFixed(0);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('${item['name']} — History')),
          IconButton(
            tooltip: 'Close history',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(period),
              const SizedBox(height: 12),
              if (records.isEmpty)
                const Text('No recorded activity for this period.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.blush,
                    ),
                    columns:
                        (beverage
                                ? ['Size', 'Qty sold', 'Unit price', 'Sales']
                                : ['Time', 'Activity', 'Qty', 'Balance'])
                            .map((label) => DataColumn(label: Text(label)))
                            .toList(),
                    rows: records.map((record) {
                      final time = record['time'] as DateTime?;
                      final values = beverage
                          ? [
                              '${record['size']}',
                              qty(record['sold']),
                              money(record['price']),
                              money(record['sales']),
                            ]
                          : [
                              time == null
                                  ? 'Not recorded'
                                  : '${MaterialLocalizations.of(context).formatShortDate(time)} ${TimeOfDay.fromDateTime(time).format(context)}',
                              '${record['activity']}',
                              '${reportValue(record['qty']) > 0 ? '+' : ''}${qty(record['qty'])}',
                              record['balance'] == null ? 'Not recorded' : qty(record['balance']),
                            ];
                      return DataRow(
                        cells: values
                            .map((value) => DataCell(Text(value)))
                            .toList(),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
