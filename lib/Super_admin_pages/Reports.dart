import 'package:flutter/material.dart';
import '../widgets/daily_sales_report.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, this.onBack});
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => DailySalesReport(onBack: onBack);
}
