import '../widgets/screen_loading_region.dart';
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

  return branchIds.fold<int>(0, (total, branchId) {
    final stock = report.currentInventory(branchId, day);
    return total +
        stock.fold<int>(
          0,
          (subtotal, item) => subtotal + reportValue(item['remaining']).round(),
        );
  });
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
      if (!snapshot.hasData) return const ScreenLoadingIndicator();

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
}
