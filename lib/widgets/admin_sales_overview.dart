import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_recent_sales.dart';

/// Receipt totals are counted once; refund records are excluded from gross sales.
List<Map<String, dynamic>> completedReceipts(
  Iterable<Map<String, dynamic>> sales,
) => sales
    .where(
      (sale) =>
          saleStatus(sale) != 'Refund' &&
          sale['isVoided'] != true &&
          sale['isDeleted'] != true &&
          ![
            'void',
            'voided',
            'cancelled',
            'canceled',
          ].contains('${sale['status']}'.toLowerCase()),
    )
    .toList();

List<Map<String, dynamic>> salesForDay(
  Iterable<Map<String, dynamic>> sales,
  DateTime day,
) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  return sales.where((sale) {
    final timestamp = sale['timestamp'];
    if (timestamp is! Timestamp) return false;
    final date = timestamp.toDate();
    return !date.isBefore(start) && date.isBefore(end);
  }).toList();
}

class AdminSalesOverview extends StatefulWidget {
  const AdminSalesOverview({
    super.key,
    this.branches = false,
    this.todayOnly = false,
    this.selectedDate,
  });
  final bool branches;
  final bool todayOnly;
  final DateTime? selectedDate;

  @override
  State<AdminSalesOverview> createState() => _AdminSalesOverviewState();
}

class _AdminSalesOverviewState extends State<AdminSalesOverview> {
  bool get branches => widget.branches;
  Timer? _midnight;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sales;

  @override
  void initState() {
    super.initState();
    _watchSales();
  }

  void _watchSales() {
    _midnight?.cancel();
    final now = DateTime.now();
    _day = DateUtils.dateOnly(widget.selectedDate ?? now);
    final end = DateTime(_day.year, _day.month, _day.day + 1);
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'completed_sales',
    );
    if (widget.todayOnly || widget.selectedDate != null) {
      query = query
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_day))
          .where('timestamp', isLessThan: Timestamp.fromDate(end));
      if (widget.selectedDate == null)
        _midnight = Timer(end.difference(now), () {
          if (mounted) setState(_watchSales);
        });
    }
    _sales = query.snapshots();
  }

  @override
  void didUpdateWidget(covariant AdminSalesOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todayOnly != widget.todayOnly ||
        oldWidget.selectedDate != widget.selectedDate)
      _watchSales();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!branches) return _totals(null);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('branches').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Text('Unable to load branch totals.');
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return _totals(
          snapshot.data!.docs
              .where((doc) => doc.data()['isVoided'] != true)
              .map((doc) => doc.id)
              .toSet(),
        );
      },
    );
  }

  Widget _totals(
    Set<String>? branchIds,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _sales,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Unable to load sales totals.');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final records = snapshot.data!.docs.map((doc) => doc.data());
      final sales =
          completedReceipts(
                (widget.todayOnly || widget.selectedDate != null)
                    ? salesForDay(records, _day)
                    : records,
              )
              .where(
                (sale) =>
                    branchIds == null || branchIds.contains(sale['branchId']),
              )
              .toList();
      final amount = sales.fold<double>(
        0,
        (sum, sale) => sum + saleNumber(sale['total']),
      );
      final sold = sales.fold<double>(
        0,
        (sum, sale) =>
            sum +
            saleItems(sale).fold<double>(
              0,
              (sum, item) => sum + saleNumber(item['quantity']),
            ),
      );
      final values = <(String, String, IconData)>[
        (
          'Total sales',
          '₱${amount.toStringAsFixed(2)}',
          Icons.payments_outlined,
        ),
        ('Total sold', sold.toStringAsFixed(0), Icons.shopping_bag_outlined),
        if (branches) ...[
          ('Total receipts', '${sales.length}', Icons.receipt_long_outlined),
          (
            'Average receipt',
            '₱${(sales.isEmpty ? 0 : amount / sales.length).toStringAsFixed(2)}',
            Icons.insights_outlined,
          ),
        ],
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 650 ? 2 : values.length;
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
                        border: Border.all(color: const Color(0xFFF8BBD0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(value.$3, color: const Color(0xFFE91E63)),
                          const SizedBox(height: 10),
                          FittedBox(
                            child: Text(
                              value.$2,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFAD1457),
                              ),
                            ),
                          ),
                          Text(value.$1),
                          Text(
                            widget.selectedDate != null
                                ? MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(_day)
                                : widget.todayOnly
                                ? 'Today'
                                : 'All time',
                            style: const TextStyle(
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

class AdminBranchRanking extends StatefulWidget {
  const AdminBranchRanking({super.key});
  @override
  State<AdminBranchRanking> createState() => _AdminBranchRankingState();
}

class _AdminBranchRankingState extends State<AdminBranchRanking> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  String _period = 'Day';
  DateTime get _start => branchReportRange(_day, _period).$1;
  DateTime get _end => branchReportRange(_day, _period).$2;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Branch sales report'),
      backgroundColor: const Color(0xFFFCE4EC),
      foregroundColor: const Color(0xFF880E4F),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 8,
          children: ['Day', 'Week', 'Month']
              .map(
                (period) => ChoiceChip(
                  label: Text(period),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Text(
          '${MaterialLocalizations.of(context).formatMediumDate(_start)} - ${MaterialLocalizations.of(context).formatMediumDate(_end.subtract(const Duration(days: 1)))}',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.calendar_month),
            label: Text(
              MaterialLocalizations.of(context).formatMediumDate(_day),
            ),
            onPressed: () async {
              final day = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (day != null && mounted) setState(() => _day = day);
            },
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('branches').snapshots(),
          builder: (context, branches) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('completed_sales')
                    .where(
                      'timestamp',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(_start),
                    )
                    .where('timestamp', isLessThan: Timestamp.fromDate(_end))
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError || branches.hasError)
                    return const Text('Unable to load branch report.');
                  if (!snapshot.hasData || !branches.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final names = {
                    for (final doc in branches.data!.docs)
                      doc.id: '${doc.data()['name'] ?? 'Branch'}',
                  };
                  final totals = <String, double>{};
                  final items = <String, Map<String, double>>{};
                  for (final sale in completedReceipts(
                    snapshot.data!.docs.map((doc) => doc.data()),
                  )) {
                    final id = '${sale['branchId'] ?? ''}';
                    if (id.isEmpty) continue;
                    totals[id] = (totals[id] ?? 0) + saleNumber(sale['total']);
                    final sold = items.putIfAbsent(id, () => {});
                    for (final item in saleItems(sale)) {
                      final name =
                          '${item['name'] ?? 'Item'}${item['variant'] == null ? '' : ' (${item['variant']})'}';
                      sold[name] =
                          (sold[name] ?? 0) + saleNumber(item['quantity']);
                    }
                  }
                  final ranked = totals.keys.toList()
                    ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
                  if (ranked.isEmpty)
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No branch sales for this period.'),
                    );
                  final max = totals[ranked.first]!;
                  return Column(
                    children: ranked.map((id) {
                      final topItems = items[id]!.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                      return Card(
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${ranked.indexOf(id) + 1}. ${names[id] ?? id}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: max <= 0
                                    ? 0
                                    : (totals[id]! / max).clamp(0, 1),
                                minHeight: 18,
                                borderRadius: BorderRadius.circular(9),
                                color: const Color(0xFFE91E63),
                                backgroundColor: const Color(0xFFFCE4EC),
                              ),
                              const SizedBox(height: 8),
                              Text('₱${totals[id]!.toStringAsFixed(2)}'),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('Best-selling items'),
                                initiallyExpanded: true,
                                children: topItems
                                    .map(
                                      (item) => ListTile(
                                        title: Text(item.key),
                                        trailing: Text(
                                          '${item.value.toStringAsFixed(0)} sold',
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
        ),
      ],
    ),
  );
}

(DateTime, DateTime) branchReportRange(DateTime anchor, String period) {
  final day = DateTime(anchor.year, anchor.month, anchor.day);
  if (period == 'Month')
    return (DateTime(day.year, day.month), DateTime(day.year, day.month + 1));
  if (period == 'Week') {
    final start = DateTime(
      day.year,
      day.month,
      day.day - (day.weekday - DateTime.monday),
    );
    return (start, DateTime(start.year, start.month, start.day + 7));
  }
  return (day, DateTime(day.year, day.month, day.day + 1));
}
