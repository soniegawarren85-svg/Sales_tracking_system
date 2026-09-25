import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

DateTime? cashRecordDate(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
    ? value
    : DateTime.tryParse('$value');

double calculatedDailyCash(
  DateTime day,
  Iterable<Map<String, dynamic>> allocations,
  Iterable<Map<String, dynamic>> sales,
) {
  double number(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;
  bool sameDay(dynamic value) =>
      DateUtils.isSameDay(cashRecordDate(value), day);
  final history =
      allocations.where((record) => sameDay(record['createdAt'])).toList()
        ..sort(
          (a, b) => cashRecordDate(
            a['createdAt'],
          )!.compareTo(cashRecordDate(b['createdAt'])!),
        );
  var cash = 0.0;
  for (final record in history) {
    if (record['type'] == 'set_daily_cash_drawer') {
      cash = number(record['amount']);
    } else {
      cash += number(record['amount']);
    }
  }
  for (final sale in sales) {
    if (!sameDay(sale['timestamp']) ||
        sale['isDeleted'] == true ||
        sale['isVoided'] == true ||
        [
          'void',
          'voided',
          'cancelled',
          'canceled',
        ].contains('${sale['status']}'.toLowerCase()))
      continue;
    if ('${sale['paymentMode'] ?? sale['paymentMethod'] ?? 'Cash'}'
            .toLowerCase() !=
        'cash')
      continue;
    cash += number(sale['cashDrawerDelta'] ?? sale['total']);
  }
  return cash;
}

class HistoricalCashDrawer extends StatelessWidget {
  const HistoricalCashDrawer({
    super.key,
    required this.branchId,
    required this.day,
  });
  final String branchId;
  final DateTime day;
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('budget_history')
        .where('staffId', isEqualTo: branchId)
        .snapshots(),
    builder: (context, history) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('completed_sales')
              .where('branchId', isEqualTo: branchId)
              .snapshots(),
          builder: (context, sales) {
            final error = history.hasError || sales.hasError;
            final ready = history.hasData && sales.hasData;
            final value = ready
                ? calculatedDailyCash(
                    day,
                    history.data!.docs.map((doc) => doc.data()),
                    sales.data!.docs.map((doc) => doc.data()),
                  )
                : null;
            return Tooltip(
              message:
                  'Calculated from recorded allocations and cash transactions for this date; excludes GCash. This is not a submitted cash count.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Calculated Cash Drawer',
                    style: TextStyle(color: Colors.white70),
                  ),
                  Text(
                    error
                        ? 'Unable to load'
                        : value == null
                        ? 'Loading…'
                        : '₱${value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
  );
}
