import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../services/number_format.dart';
import '../theme/app_colors.dart';

class BranchSalesSummary extends StatelessWidget {
  const BranchSalesSummary({
    super.key,
    required this.data,
    required this.branchId,
  });
  final BranchReportData data;
  final String branchId;
  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final totals = data.allocationReportTotals(
      branchId,
      today,
      today.add(const Duration(days: 1)),
    );
    final branch =
        data.rows('branches').where((r) => r['_id'] == branchId).firstOrNull ??
        {};
    final now = DateTime.now();
    final closing = (branch['closingMinutes'] as num?)?.toInt() ?? 1140;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blush),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sales summary',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDeep,
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in totals.entries.where(
            (e) => e.key != 'Total cash drawer today',
          ))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key)),
                  Text(
                    entry.key == 'Closing cash drawer' &&
                            now.hour * 60 + now.minute < closing
                        ? '--'
                        : [
                            'Total sold',
                            'Total transactions',
                          ].contains(entry.key)
                        ? formatNumber(entry.value)
                        : formatMoney(entry.value),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
