import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'historical_cash_drawer.dart';

Map<String, double> branchDayTotals(
  DateTime day,
  List<Map<String, dynamic>> history,
  List<Map<String, dynamic>> sales,
  double configuredOpening,
) {
  double number(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;
  final end = DateTime(day.year, day.month, day.day + 1);
  final eligible =
      history
          .where(
            (row) => cashRecordDate(row['createdAt'])?.isBefore(end) == true,
          )
          .toList()
        ..sort(
          (a, b) => cashRecordDate(
            a['createdAt'],
          )!.compareTo(cashRecordDate(b['createdAt'])!),
        );
  final settings = eligible
      .where((row) => row['type'] == 'set_daily_cash_drawer')
      .toList();
  var opening = settings.isEmpty
      ? configuredOpening
      : number(settings.last['amount']);
  for (final row in eligible) {
    if (row['type'] != 'set_daily_cash_drawer' &&
        DateUtils.isSameDay(cashRecordDate(row['createdAt']), day))
      opening += number(row['amount']);
  }
  var revenue = 0.0;
  var refunds = 0.0;
  for (final row in sales) {
    if (!DateUtils.isSameDay(cashRecordDate(row['timestamp']), day) ||
        row['isDeleted'] == true ||
        row['isVoided'] == true ||
        [
          'void',
          'voided',
          'cancelled',
          'canceled',
        ].contains('${row['status']}'.toLowerCase()))
      continue;
    final total = number(row['total']);
    if (total < 0 ||
        '${row['type']}'.toLowerCase() == 'refund' ||
        '${row['salesId']}'.startsWith('R-')) {
      refunds += total.abs();
    } else {
      revenue += total;
    }
  }
  final gain = revenue - refunds;
  return {
    'Starting fund': opening,
    'Total revenue': revenue,
    'Refunds': refunds,
    'Total gain (net sales)': gain,
    'Closing cash drawer': opening + gain,
  };
}

class BranchDailySummary extends StatefulWidget {
  const BranchDailySummary({
    super.key,
    required this.branchId,
    required this.day,
    this.compact = false,
  });
  final String branchId;
  final DateTime day;
  final bool compact;
  @override
  State<BranchDailySummary> createState() => _BranchDailySummaryState();
}

class _BranchDailySummaryState extends State<BranchDailySummary> {
  late final Future<Map<String, double>> totals = load();
  Future<Map<String, double>> load() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db
          .collection('budget_history')
          .where('staffId', isEqualTo: widget.branchId)
          .get(),
      db
          .collection('completed_sales')
          .where('branchId', isEqualTo: widget.branchId)
          .get(),
      db
          .collection('daily_reports')
          .where('branchId', isEqualTo: widget.branchId)
          .get(),
    ]);
    final drawer =
        (await db.collection('staff_cash_drawer').doc(widget.branchId).get())
            .data() ??
        {};
    final reports =
        results[2].docs
            .map((doc) => doc.data())
            .where(
              (row) => DateUtils.isSameDay(
                cashRecordDate(
                  row['reportDateKey'] ?? row['reportDate'] ?? row['createdAt'],
                ),
                widget.day,
              ),
            )
            .toList()
          ..sort(
            (a, b) => (cashRecordDate(b['createdAt']) ?? DateTime(1970))
                .compareTo(cashRecordDate(a['createdAt']) ?? DateTime(1970)),
          );
    final opening = reports.isNotEmpty
        ? reports.first['openingCash'] ?? reports.first['allocatedBudget']
        : null;
    final configured =
        num.tryParse(
          '${opening ?? drawer['dailyOpeningCash'] ?? drawer['openingCash'] ?? 0}',
        )?.toDouble() ??
        0;
    final result = branchDayTotals(
      widget.day,
      results[0].docs.map((doc) => doc.data()).toList(),
      results[1].docs.map((doc) => doc.data()).toList(),
      configured,
    );
    if (opening != null) {
      result['Starting fund'] = configured;
      result['Closing cash drawer'] =
          configured + result['Total gain (net sales)']!;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, double>>(
    future: totals,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Unable to load daily summary.');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      if (widget.compact)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Closing Cash Drawer',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              'PHP ${snapshot.data!['Closing cash drawer']!.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...snapshot.data!.entries.map(
            (entry) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE4EC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key)),
                  Text(
                    'PHP ${entry.value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC2105C),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Text(
            'Closing amount = starting fund + net sales. Starting fund uses the saved daily report or allocation history; otherwise the configured drawer fund. Total gain here means net sales, not profit after costs.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
    },
  );
}
