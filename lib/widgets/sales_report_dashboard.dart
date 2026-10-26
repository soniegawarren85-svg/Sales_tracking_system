import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../services/number_format.dart';
import '../services/receipt_tax.dart';
import '../theme/app_colors.dart';
import 'historical_cash_drawer.dart';

const _reportColors = [
  AppColors.primaryDark,
  Color(0xffd85775),
  Color(0xffee98aa),
  Color(0xffffb98e),
  Color(0xff9e9e9e),
];

class SalesReportMetrics extends StatelessWidget {
  const SalesReportMetrics({
    super.key,
    required this.metrics,
    required this.onDetails,
  });
  final Map<String, String> metrics;
  final ValueChanged<String> onDetails;
  @override
  Widget build(BuildContext context) {
    const icons = {
      'Total sales': Icons.shopping_cart_outlined,
      'Items allocated': Icons.inventory_2_outlined,
      'Total transactions': Icons.receipt_long_outlined,
      'Cash allocated': Icons.payments_outlined,
      'Total cost': Icons.layers_outlined,
      'Total VAT': Icons.percent,
      'Total net sales': Icons.account_balance_wallet_outlined,
      'Total net profit': Icons.bar_chart,
      'Total sold items': Icons.inventory_2_outlined,
      'Total profit': Icons.trending_up_rounded,
      'Total loss': Icons.warning_amber_rounded,
    };
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 900
                ? 4
                : box.maxWidth >= 600
                ? 2
                : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in icons.entries)
                  SizedBox(
                    width: (box.maxWidth - 12 * (columns - 1)) / columns,
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => onDetails(entry.key),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.blush,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  entry.value,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 5),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        metrics[entry.key] ?? '—',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      entry.key == 'Items allocated'
                                          ? 'View allocated'
                                          : 'View details',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            for (final entry in metrics.entries.where(
              (e) => !icons.containsKey(e.key),
            ))
              TextButton(
                onPressed: () => onDetails(entry.key),
                child: Text('${entry.key}: ${entry.value}'),
              ),
          ],
        ),
      ],
    );
  }
}

class SalesReportDashboard extends StatelessWidget {
  const SalesReportDashboard({
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
  Widget build(BuildContext context) {
    final sales = data
        .sales(branchId, start, end)
        .where(
          (s) =>
              !reportRefund(s) &&
              s['type'] != 'reduce' &&
              s['status'] != 'reduced',
        )
        .toList();
    final branches = {
      for (final b in data.rows('branches'))
        if (branchId == null || b['_id'] == branchId)
          '${b['_id']}': '${b['name'] ?? b['branchName'] ?? b['_id']}',
    };
    final byBranch = <String, double>{}, payments = <String, double>{};
    final ranked = <String, Map<String, dynamic>>{};
    for (final sale in sales) {
      final amount = reportValue(sale['total']);
      final branch = branches['${sale['branchId']}'] ?? 'Unassigned';
      byBranch[branch] = (byBranch[branch] ?? 0) + amount;
      final raw = '${sale['paymentMode'] ?? sale['paymentMethod'] ?? 'Cash'}';
      final payment = raw.toLowerCase() == 'cash'
          ? 'Cash'
          : raw.toLowerCase() == 'gcash'
          ? 'GCash'
          : raw;
      payments[payment] = (payments[payment] ?? 0) + amount;
      for (final item in (sale['items'] as List? ?? []).whereType<Map>()) {
        final variant = '${item['variant'] ?? item['coffeeSize'] ?? ''}'.trim();
        final name = variant.isNotEmpty ? variant : '${item['name'] ?? 'Item'}';
        final type = item['isBundle'] == true
            ? 'Bundle'
            : item['isCoffee'] == true
            ? 'Beverages'
            : 'Categories';
        final row = ranked.putIfAbsent(
          name,
          () => {'name': name, 'type': type, 'sold': 0.0, 'sales': 0.0},
        );
        final qty = reportValue(item['quantity']);
        row['sold'] = reportValue(row['sold']) + qty;
        row['sales'] =
            reportValue(row['sales']) + qty * reportValue(item['price']);
      }
    }
    final top = ranked.values.toList()
      ..sort(
        (a, b) => reportValue(b['sold']).compareTo(reportValue(a['sold'])),
      );
    final hours = data.hours(branchId, start);
    final count = period == 'Day'
        ? hours.length
        : period == 'Year'
        ? 12
        : end.difference(start).inDays;
    final labels = <String>[];
    final amounts = <double>[], transactions = <double>[];
    final cost = <double>[],
        vat = <double>[],
        net = <double>[],
        profit = <double>[];
    for (var i = 0; i < count; i++) {
      final from = period == 'Day'
          ? start.add(Duration(hours: hours[i]))
          : period == 'Year'
          ? DateTime(start.year, i + 1)
          : start.add(Duration(days: i));
      final until = period == 'Day'
          ? from.add(const Duration(hours: 1))
          : period == 'Year'
          ? DateTime(start.year, i + 2)
          : from.add(const Duration(days: 1));
      final rows = sales.where((s) {
        final at = cashRecordDate(s['timestamp'] ?? s['createdAt']);
        return at != null && !at.isBefore(from) && at.isBefore(until);
      }).toList();
      final revenue = rows.fold<double>(
        0,
        (sum, s) => sum + reportValue(s['total']),
      );
      final tax = rows.fold<double>(
        0,
        (sum, s) =>
            sum +
            reportValue(
              s['tax'] ?? s['vatAmount'] ?? s['taxAmount'] ?? s['vat'],
            ),
      );
      double expense = 0, gain = 0;
      for (final branch in branches.keys) {
        for (final row in data.items(branch, from, until)) {
          expense += reportValue(row['totalCost']);
          gain += reportValue(row['netProfit']);
        }
      }
      labels.add(
        period == 'Day'
            ? '${from.hour}:00'
            : period == 'Year'
            ? '${from.month}'
            : '${from.month}/${from.day}',
      );
      amounts.add(revenue);
      transactions.add(rows.length.toDouble());
      cost.add(expense);
      vat.add(tax);
      net.add(
        rows.fold<double>(0, (sum, sale) => sum + receiptVatableSales(sale)),
      );
      profit.add(gain);
    }
    Widget panel(String title, Widget body, {Widget? action}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
    Widget ranking(List<Map<String, dynamic>> items) => Column(
      children: [
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No sales in this period.'),
          ),
        for (final row in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(
                  row['type'] == 'Beverages'
                      ? Icons.local_cafe_outlined
                      : row['type'] == 'Bundle'
                      ? Icons.inventory_2_outlined
                      : Icons.bakery_dining_outlined,
                  size: 20,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${row['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatNumber(reportValue(row['sold']))),
                const SizedBox(width: 12),
                SizedBox(
                  width: 70,
                  child: LinearProgressIndicator(
                    value:
                        reportValue(row['sold']) /
                        math.max(1, reportValue(top.first['sold'])),
                    color: AppColors.primary,
                    backgroundColor: AppColors.blush,
                    minHeight: 7,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatMoney(reportValue(row['sales'])),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final overview = panel(
      'Sales Overview',
      ReportTrendChart(
        labels: labels,
        series: [amounts],
        line: transactions,
        legends: const ['Sales', 'Transactions'],
      ),
    );
    final branchPanel = panel('Sales by branch', ReportDonut(values: byBranch));
    final paymentPanel = panel('Payment Method', ReportDonut(values: payments));
    final best = panel(
      'Top Selling Items',
      ranking(top.take(5).toList()),
      action: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Top Selling Items'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(child: ranking(top)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: const Text('View all'),
      ),
    );
    final trend = panel(
      'Cost, VAT, Sales and Profit Trend',
      ReportTrendChart(
        labels: labels,
        series: [cost, vat, net, profit],
        legends: const ['Cost', 'VAT', 'Net sales', 'Net profit'],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 950) {
          return Column(
            children: [
              for (final p in [
                overview,
                if (branchId == null) branchPanel,
                paymentPanel,
                best,
                trend,
              ])
                Padding(padding: const EdgeInsets.only(bottom: 12), child: p),
            ],
          );
        }
        if (branchId != null) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: overview),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: paymentPanel),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: best),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: trend),
                ],
              ),
            ],
          );
        }
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: overview),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: branchPanel),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: paymentPanel),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: best),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: trend),
              ],
            ),
          ],
        );
      },
    );
  }
}

class ReportDonut extends StatelessWidget {
  const ReportDonut({super.key, required this.values});
  final Map<String, double> values;
  @override
  Widget build(BuildContext context) {
    final entries = values.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    return Column(
      children: [
        SizedBox(
          height: 144,
          width: 144,
          child: CustomPaint(
            painter: _DonutPainter(entries.map((e) => e.value).toList()),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMoney(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const Text('Total sales', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty) const Text('No sales in this period.'),
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 9,
                  color: _reportColors[i % _reportColors.length],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                Text(
                  '${formatMoney(entries[i].value)}  ${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(14, 14, size.width - 28, size.height - 28);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = AppColors.blush);
    final total = values.fold<double>(0, (s, v) => s + v);
    var angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        angle,
        sweep,
        false,
        paint..color = _reportColors[i % _reportColors.length],
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class ReportTrendChart extends StatelessWidget {
  const ReportTrendChart({
    super.key,
    required this.labels,
    required this.series,
    required this.legends,
    this.line,
  });
  final List<String> labels, legends;
  final List<List<double>> series;
  final List<double>? line;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < legends.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 9, color: _reportColors[i % 5]),
                const SizedBox(width: 4),
                Text(legends[i], style: const TextStyle(fontSize: 11)),
              ],
            ),
        ],
      ),
      const SizedBox(height: 12),
      Semantics(
        label:
            'Chart. ${List.generate(labels.length, (i) => '${labels[i]}: ${List.generate(series.length, (j) => '${legends[j]} ${formatMoney(series[j][i])}').join(', ')}${line == null ? '' : ', ${line![i].toInt()} transactions'}').join('; ')}',
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(labels, series, line)),
        ),
      ),
      if (line != null)
        const Text(
          'Bars: sales (₱) · Line: transactions (right scale)',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.labels, this.series, this.line);
  final List<String> labels;
  final List<List<double>> series;
  final List<double>? line;
  void text(Canvas c, String s, Offset o, {Color color = Colors.grey}) {
    final t = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: 9, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    t.paint(c, o);
  }

  @override
  void paint(Canvas c, Size size) {
    if (labels.isEmpty) return;
    final maxV =
        series
            .expand((s) => s)
            .fold<double>(1, (a, b) => math.max(a, b.abs())) *
        1.15;
    final minV = series.expand((s) => s).fold<double>(0, math.min);
    final w = size.width - 68, h = size.height - 30, step = w / labels.length;
    double y(double v) => 10 + h * (maxV - v) / (maxV - minV);
    for (var i = 0; i <= 4; i++) {
      final v = minV + (maxV - minV) * i / 4;
      c.drawLine(
        Offset(42, y(v)),
        Offset(size.width - 24, y(v)),
        Paint()..color = const Color(0xffeeeeee),
      );
      text(
        c,
        v.abs() >= 1000
            ? '${(v / 1000).toStringAsFixed(1)}k'
            : v.toStringAsFixed(0),
        Offset(0, y(v) - 5),
      );
    }
    final lineMax = line?.fold<double>(1, math.max) ?? 1;
    final path = Path();
    for (var i = 0; i < labels.length; i++) {
      for (var j = 0; j < series.length; j++) {
        final x = 42 + step * i + step * .12 + j * step * .76 / series.length;
        final yy = y(series[j][i]);
        c.drawRect(
          Rect.fromLTRB(
            x,
            math.min(yy, y(0)),
            x + step * .65 / series.length,
            math.max(yy, y(0)),
          ),
          Paint()..color = _reportColors[j % 5],
        );
      }
      if (i % math.max(1, (labels.length / 6).ceil()) == 0) {
        text(c, labels[i], Offset(42 + step * i, size.height - 14));
      }
      if (line != null) {
        final p = Offset(
          42 + step * (i + .5),
          10 + h * (1 - line![i] / lineMax),
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
        c.drawCircle(p, 2.5, Paint()..color = _reportColors[1]);
      }
    }
    if (line != null) {
      c.drawPath(
        path,
        Paint()
          ..color = _reportColors[1]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      text(c, lineMax.toInt().toString(), Offset(size.width - 20, 5));
      text(c, '0', Offset(size.width - 20, 10 + h - 5));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
