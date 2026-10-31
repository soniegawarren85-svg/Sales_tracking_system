import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import 'historical_cash_drawer.dart';
import '../theme/app_colors.dart';
import 'branch_analytics_bars.dart';

class ReportSalesTimeline extends StatefulWidget {
  const ReportSalesTimeline({
    super.key,
    required this.data,
    required this.start,
    required this.end,
    required this.period,
    this.branchId,
  });
  final BranchReportData data;
  final DateTime start, end;
  final String period;
  final String? branchId;
  @override
  State<ReportSalesTimeline> createState() => _ReportSalesTimelineState();
}

class _ReportSalesTimelineState extends State<ReportSalesTimeline> {
  @override
  Widget build(BuildContext context) {
    final branches = widget.data
        .rows('branches')
        .where(
          (row) =>
              row['isVoided'] != true &&
              row['isDeleted'] != true &&
              (widget.branchId == null || row['_id'] == widget.branchId),
        )
        .toList();
    final branch = widget.branchId;
    final rangedSales = widget.data
        .sales(branch, widget.start, widget.end)
        .where(
          (sale) =>
              !reportRefund(sale) &&
              sale['type'] != 'reduce' &&
              sale['status'] != 'reduced',
        )
        .toList();
    final hours = widget.data.hours(branch, widget.start);
    final points = widget.period == 'Day'
        ? hours.length
        : widget.period == 'Year'
        ? 12
        : widget.end.difference(widget.start).inDays;
    final completed = List.filled(points, 0.0);
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
      for (final sale in rangedSales) {
        final saleDate = cashRecordDate(sale['timestamp'] ?? sale['createdAt']);
        if (saleDate == null ||
            saleDate.isBefore(start) ||
            !saleDate.isBefore(end)) {
          continue;
        }
        completed[i] += reportValue(sale['total']);
      }
    }
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales Analytics',
              style: TextStyle(
                color: AppColors.primaryDeep,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.branchId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${branches.firstOrNull?['name'] ?? 'Assigned branch'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            Text(
              'Completed sales: ₱${completed.fold<double>(0, (a, b) => a + b).toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.primaryDark),
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
                    values: completed,
                    labels: labels,
                    selectedStatus: 'Completed',
                    colors: const [
                      AppColors.primaryDeep,
                      AppColors.primaryDark,
                    ],
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
