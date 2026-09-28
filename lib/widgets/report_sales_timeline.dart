import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../theme/app_colors.dart';
import 'branch_analytics_bars.dart';

class ReportSalesTimeline extends StatefulWidget {
  const ReportSalesTimeline({
    super.key,
    required this.data,
    required this.start,
    required this.end,
    required this.period,
  });
  final BranchReportData data;
  final DateTime start, end;
  final String period;
  @override
  State<ReportSalesTimeline> createState() => _ReportSalesTimelineState();
}

class _ReportSalesTimelineState extends State<ReportSalesTimeline> {
  String? branch;
  String status = 'All';
  @override
  Widget build(BuildContext context) {
    final branches = widget.data.rows('branches');
    if (!branches.any((b) => b['_id'] == branch)) branch = null;
    final hours = widget.data.hours(branch, widget.start);
    final points = widget.period == 'Day'
        ? hours.length
        : widget.period == 'Year'
        ? 12
        : widget.end.difference(widget.start).inDays;
    final completed = List.filled(points, 0.0),
        refunds = List.filled(points, 0.0),
        reduced = List.filled(points, 0.0);
    final labels = <String>[];
    for (var i = 0; i < points; i++) {
      final start = widget.period == 'Day'
          ? widget.start.add(Duration(hours: hours[i]))
          : widget.period == 'Year'
          ? DateTime(widget.start.year, i + 1)
          : widget.start.add(Duration(days: i));
      final end = widget.period == 'Day'
          ? start.add(const Duration(hours: 1))
          : widget.period == 'Year'
          ? DateTime(start.year, start.month + 1)
          : start.add(const Duration(days: 1));
      labels.add(
        widget.period == 'Day'
            ? '${hours[i] % 12 == 0 ? 12 : hours[i] % 12}${hours[i] < 12 ? 'AM' : 'PM'}'
            : widget.period == 'Year'
            ? const [
                'Jan',
                'Feb',
                'Mar',
                'Apr',
                'May',
                'Jun',
                'Jul',
                'Aug',
                'Sep',
                'Oct',
                'Nov',
                'Dec',
              ][i]
            : '${start.month}/${start.day}',
      );
      for (final sale in widget.data.sales(branch, start, end)) {
        if (reportRefund(sale)) {
          refunds[i] += reportValue(sale['total']).abs();
        } else if (sale['type'] != 'reduce' && sale['status'] != 'reduced') {
          completed[i] += reportValue(sale['total']);
        }
      }
      for (final b in branches.where(
        (b) => branch == null || b['_id'] == branch,
      )) {
        reduced[i] += widget.data
            .losses('${b['_id']}', start, end)
            .fold<double>(0, (sum, r) => sum + widget.data.lossAmount(r));
      }
    }
    final values = List.generate(
      points,
      (i) => status == 'Completed'
          ? completed[i]
          : status == 'Refund'
          ? refunds[i]
          : status == 'Reduced'
          ? reduced[i]
          : completed[i] + refunds[i] + reduced[i],
    );
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales, refunds & reductions',
              style: TextStyle(
                color: AppColors.primaryDeep,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              isExpanded: true,
              value: branch ?? '',
              items: [
                const DropdownMenuItem(value: '', child: Text('All branches')),
                ...branches.map(
                  (b) => DropdownMenuItem(
                    value: '${b['_id']}',
                    child: Text('${b['name']}'),
                  ),
                ),
              ],
              onChanged: (value) =>
                  setState(() => branch = value == '' ? null : value),
            ),
            Wrap(
              spacing: 8,
              children: ['All', 'Completed', 'Refund', 'Reduced']
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s),
                      selected: status == s,
                      onSelected: (_) => setState(() => status = s),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text(
                  'Sales: ₱${completed.fold<double>(0, (a, b) => a + b).toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.primaryDark),
                ),
                Text(
                  'Refunds: ₱${refunds.fold<double>(0, (a, b) => a + b).toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF9C6500)),
                ),
                Text(
                  'Reduced stock value: ₱${reduced.fold<double>(0, (a, b) => a + b).toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF1976D2)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: c.maxWidth > points * 44.0
                      ? c.maxWidth
                      : points * 44.0,
                  height: 300,
                  child: BranchAnalyticsBars(
                    values: values,
                    labels: labels,
                    selectedStatus: status,
                    refunds: status == 'All' ? refunds : null,
                    reduced: status == 'All' ? reduced : null,
                    colors: status == 'Refund'
                        ? const [Color(0xFFF9A825), Color(0xFFF9A825)]
                        : status == 'Reduced'
                        ? const [Color(0xFF1976D2), Color(0xFF1976D2)]
                        : const [AppColors.primaryDeep, AppColors.primaryDark],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
