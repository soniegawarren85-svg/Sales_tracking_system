import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../widgets/admin_sales_overview.dart';
import '../theme/app_colors.dart';

int currentAllocatedQuantity(BranchReportData report, DateTime day) {
  final branchIds = report
      .rows('branches')
      .where(
        (branch) => branch['isVoided'] != true && branch['isDeleted'] != true,
      )
      .map((branch) => '${branch['_id'] ?? ''}')
      .where((id) => id.isNotEmpty)
      .toSet();

  final start = DateUtils.dateOnly(day);
  final end = start.add(const Duration(days: 1));
  return branchIds.fold<int>(
    0,
    (total, branchId) =>
        total +
        report
            .items(branchId, start, end)
            .fold<int>(
              0,
              (sum, item) => sum + reportValue(item['added']).round(),
            ),
  );
}

class SuperAdminTotals extends StatelessWidget {
  const SuperAdminTotals({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<BranchReportData>(
    stream: BranchReportData.watch(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Unable to load overall totals.');
      }
      if (!snapshot.hasData) return _totalsSkeleton(context);

      final report = snapshot.data!;
      final today = DateUtils.dateOnly(DateTime.now());
      final branchIds = report
          .rows('branches')
          .where(
            (branch) =>
                branch['isVoided'] != true && branch['isDeleted'] != true,
          )
          .map((branch) => '${branch['_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet();
      final receipts = completedReceipts(
        salesForDay(
          report.rows('completed_sales'),
          today,
        ).where((sale) => branchIds.contains(sale['branchId'])),
      );
      final values = <(String, String, IconData)>[
        (
          'Total allocated',
          '${currentAllocatedQuantity(report, today)}',
          Icons.inventory_2_outlined,
        ),
        ('Total transactions', '${receipts.length}', Icons.receipt_long),
        ('Total branches', '${branchIds.length}', Icons.storefront_outlined),
      ];

      if (MediaQuery.sizeOf(context).width < 600) {
        return AdminSalesOverview(todayOnly: true, additionalTotals: values);
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 600 ? 1 : values.length;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: values
                .map(
                  (value) => SizedBox(
                    width:
                        (constraints.maxWidth - (columns - 1) * 12) / columns,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.blush),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(value.$3, color: AppColors.primary),
                          const SizedBox(height: 10),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value.$2,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                          Text(value.$1),
                          const Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      );
    },
  );

  Widget _totalsSkeleton(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 600 ? 1 : 3;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          3,
          (_) => SizedBox(
            width: width,
            child: Container(
              height: 128,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.blush),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBar(24, 24),
                  const SizedBox(height: 12),
                  _skeletonBar(90, 24),
                  const SizedBox(height: 8),
                  _skeletonBar(120, 12),
                  const Spacer(),
                  _skeletonBar(45, 10),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _skeletonBar(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF3E4E9),
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}
