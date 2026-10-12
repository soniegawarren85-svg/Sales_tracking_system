import 'package:flutter/material.dart';
import '../services/number_format.dart';
import '../services/branch_report_data.dart';
import '../theme/app_colors.dart';

class ReportItemHistory extends StatefulWidget {
  const ReportItemHistory({
    super.key,
    required this.item,
    required this.period,
    this.loadRange,
    this.initialRange,
  });
  final Map<String, dynamic> item;
  final String period;
  final Map<String, dynamic> Function(DateTimeRange range)? loadRange;
  final DateTimeRange? initialRange;

  @override
  State<ReportItemHistory> createState() => _ReportItemHistoryState();
}

class _ReportItemHistoryState extends State<ReportItemHistory> {
  late DateTimeRange? _range = widget.initialRange;
  Map<String, dynamic> get item => _range != null && widget.loadRange != null
      ? widget.loadRange!(_range!)
      : widget.item;
  String get period => widget.period;

  @override
  Widget build(BuildContext context) {
    final beverage = item['type'] == 'Beverages';
    final records = beverage
        ? (item['sizeSales'] as Map? ?? {}).values.whereType<Map>().toList()
        : (item['history'] as List? ?? []).whereType<Map>().where((record) {
            final date = record['time'] as DateTime?;
            return _range == null ||
                (date != null &&
                    !date.isBefore(_range!.start) &&
                    date.isBefore(_range!.end.add(const Duration(days: 1))));
          }).toList();
    String money(dynamic v) => formatMoney(reportValue(v));
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
              if (!beverage || widget.loadRange != null)
                Wrap(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        _range == null
                            ? 'Filter history by date range'
                            : '${MaterialLocalizations.of(context).formatShortDate(_range!.start)} – ${MaterialLocalizations.of(context).formatShortDate(_range!.end)}',
                      ),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDateRange: _range == null
                              ? null
                              : DateTimeRange(
                                  start: _range!.start,
                                  end: _range!.end.isAfter(DateTime.now())
                                      ? DateUtils.dateOnly(DateTime.now())
                                      : _range!.end,
                                ),
                        );
                        if (picked != null && mounted)
                          setState(() => _range = picked);
                      },
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (records.isEmpty)
                const Text('No recorded activity for this period.')
              else
                LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        horizontalMargin: 20,
                        columnSpacing: 28,
                        headingRowColor: const WidgetStatePropertyAll(
                          AppColors.blush,
                        ),
                        columns:
                            (beverage
                                    ? [
                                        'Size',
                                        'Qty sold',
                                        'Unit price',
                                        'Sales',
                                      ]
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
                                  '${reportValue(record['qty']) > 0 && !'${record['activity']}'.toLowerCase().contains('balance') ? '+' : ''}${qty(record['qty'])}',
                                  record['balance'] == null
                                      ? 'Not recorded'
                                      : qty(record['balance']),
                                ];
                          return DataRow(
                            cells: values
                                .map((value) => DataCell(Text(value)))
                                .toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
