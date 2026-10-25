import 'package:flutter/material.dart';
import '../../widgets/daily_sales_report.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, this.branchId, this.branchName, this.onBack});
  final String? branchId;
  final String? branchName;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => DailySalesReport(
    branchId: branchId,
    branchName: branchName,
    onBack: onBack,
  );
}
