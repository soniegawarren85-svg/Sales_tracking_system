import '../services/report_current_allocations.dart';
import 'report_sales_timeline.dart';
import 'historical_cash_drawer.dart';
import 'admin_recent_sales.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/report_print.dart';
import '../services/branch_report_data.dart';
import '../services/inventory_display_ids.dart';
import '../services/report_pdf_theme.dart';
import '../theme/app_colors.dart';
import 'inventory_records_table.dart';
import 'branch_analytics_bars.dart';

class DailySalesReport extends StatefulWidget {
  const DailySalesReport({super.key, this.data});
  final Stream<BranchReportData>? data;
  @override
  State<DailySalesReport> createState() => _DailySalesReportState();
}

class _DailySalesReportState extends State<DailySalesReport> {
  late final source = widget.data ?? BranchReportData.watch();
  DateTime day = DateUtils.dateOnly(DateTime.now());
  String period = 'Day', search = '', type = 'All';
  bool printing = false;
  (DateTime, DateTime) get range {
    switch (period) {
      case 'Week':
        final start = day.subtract(Duration(days: day.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
      case 'Month':
        return (
          DateTime(day.year, day.month),
          DateTime(day.year, day.month + 1),
        );
      case 'Year':
        return (DateTime(day.year), DateTime(day.year + 1));
      default:
        return (day, day.add(const Duration(days: 1)));
    }
  }

  String reportDateLabel(dynamic value) {
    final date = cashRecordDate(value);
    return date == null
        ? 'Not recorded'
        : '${MaterialLocalizations.of(context).formatShortDate(date)} ${TimeOfDay.fromDateTime(date).format(context)}';
  }

  String money(num n) => '₱${n.toStringAsFixed(2)}';
  Future<void> printReport(
    Map<String, String> metrics,
    List<Map<String, dynamic>> rows,
    Map<String, double> branches,
  ) async {
    setState(() => printing = true);
    try {
      await printReportDocument(
        name: 'sales-report-${day.toIso8601String().split('T').first}.pdf',
        build: () async {
          final pdf = pw.Document(theme: await reportPdfTheme());
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.landscape,
              maxPages: 1000,
              build: (_) => [
                pw.Header(
                  level: 0,
                  text:
                      'Sales Reports · $period · ${day.toIso8601String().split('T').first}',
                ),
                ...metrics.entries.map((e) => pw.Text('${e.key}: ${e.value}')),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Allocated inventory · Remaining quantities are current',
                ),
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'ID',
                    'Item',
                    'Branch',
                    'Type',
                    'Allocated',
                    'Sold',
                    'Remaining now',
                  ],
                  data: rows
                      .map(
                        (r) => [
                          '${r['id']}',
                          '${r['name']}',
                          '${r['branch']}',
                          '${r['type']}',
                          '${r['allocated']}',
                          '${r['sold']}',
                          '${r['remaining']}',
                        ],
                      )
                      .toList(),
                ),
                pw.SizedBox(height: 16),
                pw.Header(level: 1, text: 'Branch sales comparison'),
                ...branches.entries.map(
                  (e) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(width: 150, child: pw.Text(e.key)),
                        pw.Container(
                          height: 12,
                          width:
                              branches.values.fold<double>(
                                    1,
                                    (a, b) => a > b ? a : b,
                                  ) ==
                                  0
                              ? 0
                              : e.value /
                                    branches.values.fold<double>(
                                      1,
                                      (a, b) => a > b ? a : b,
                                    ) *
                                    280,
                          color: PdfColors.pink800,
                        ),
                        pw.SizedBox(width: 10),
                        pw.Text(money(e.value)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          return pdf.save();
        },
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to print: $e')));
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: AppColors.primaryDeep,
      foregroundColor: Colors.white,
      title: const Text(
        'Sales Reports',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    ),
    body: StreamBuilder<BranchReportData>(
      stream: source,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Text('Unable to load reports: ${snapshot.error}'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final start = range.$1, end = range.$2;
        final sales = data
            .sales(null, start, end)
            .where(
              (s) =>
                  !reportRefund(s) &&
                  s['isDeleted'] != true &&
                  s['type'] != 'reduce' &&
                  s['status'] != 'reduced',
            )
            .toList();
        final total = sales.fold<double>(
          0,
          (sum, s) => sum + reportValue(s['total']),
        );
        final sold = sales.fold<double>(
          0,
          (sum, s) =>
              sum +
              (s['items'] as List? ?? []).whereType<Map>().fold<double>(
                0,
                (n, i) => n + reportValue(i['quantity']),
              ),
        );
        final cashByOwner = configuredReportCash(
          data,
          start,
          end,
          DateTime.now(),
        );
        final cash = cashByOwner.values.fold<double>(
          0,
          (sum, value) => sum + value,
        );
        final branches = {
          for (final b in data.rows('branches'))
            '${b['_id']}': '${b['name'] ?? b['branchName'] ?? b['_id']}',
        };
        final chart = {
          for (final b in branches.entries)
            b.value: sales
                .where((s) => s['branchId'] == b.key)
                .fold<double>(0, (sum, s) => sum + reportValue(s['total'])),
        };
        final remaining = <String, dynamic>{};
        for (final allocation
            in data
                .rows('staff_inventory')
                .where((r) => r['isDeleted'] != true)) {
          final branch = '${allocation['branchId'] ?? allocation['staffId']}';
          final entries =
              allocation['isBundle'] == true || allocation['isCoffee'] == true
              ? [allocation]
              : (allocation['items'] as List? ?? []).whereType<Map>();
          for (final item in entries) {
            final resolved = data.resolveItem(
              item,
              '${allocation['sourceInventoryId']}',
            );
            final key = '$branch/${inventoryDisplayId(resolved)}';
            if (allocation['isCoffee'] == true &&
                item['stock'] == null &&
                item['startingStock'] == null) {
              remaining[key] = 'Made to order';
            } else {
              remaining[key] =
                  reportValue(remaining[key]) +
                  reportValue(
                    item['stock'] ??
                        item['bundleCount'] ??
                        item['startingStock'],
                  );
            }
          }
        }
        final allRows = <Map<String, dynamic>>[];
        for (final branch in branches.entries) {
          for (final row in data.items(branch.key, start, end)) {
            allRows.add({
              ...row,
              'branch': branch.value,
              'remaining': remaining['${branch.key}/${row['id']}'] ?? 0,
            });
          }
        }
        final current = currentReportAllocations(data, DateTime.now());
        final allocated = current.fold<double>(
          0,
          (sum, row) => sum + reportValue(row['quantity']),
        );
        final metrics = {
          'Total sales': money(total),
          'Total sold items': '${sold.toInt()}',
          'Total transactions': '${sales.length}',
          'Cash allocated': money(cash),
          'Items allocated': '${allocated.toInt()}',
          'Average sale': money(sold == 0 ? 0 : total / sold),
        };
        final rows = allRows
            .where(
              (r) =>
                  (type == 'All' || r['type'] == type) &&
                  '${r['id']} ${r['name']} ${r['branch']}'
                      .toLowerCase()
                      .contains(search),
            )
            .toList();
        void showDetails(String selectedDetail) {
          var dialogSearch = '';
          showDialog<void>(
            context: context,
            builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, update) => Dialog(
                insetPadding: const EdgeInsets.all(20),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 1000,
                    maxHeight: MediaQuery.sizeOf(dialogContext).height * .85,
                  ),
                  child: SingleChildScrollView(
                    child: Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedDetail,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryDeep,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close details',
                                  onPressed: () => Navigator.pop(dialogContext),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (selectedDetail == 'Items allocated') ...[
                              const Text(
                                'Current available branch inventory. Quantities show remaining units; made-to-order products are listed separately.',
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search item, ID or branch',
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onChanged: (value) => update(
                                  () =>
                                      dialogSearch = value.trim().toLowerCase(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              InventoryRecordsTable(
                                headings: const [
                                  'ID',
                                  'Item',
                                  'Branch',
                                  'Type',
                                  'Remaining',
                                ],
                                flex: const {0: 1, 1: 2, 2: 1.5, 3: 1, 4: 1},
                                rows: current
                                    .where(
                                      (r) =>
                                          '${r['id']} ${r['name']} ${r['branch']}'
                                              .toLowerCase()
                                              .contains(dialogSearch),
                                    )
                                    .map(
                                      (r) =>
                                          [
                                                'id',
                                                'name',
                                                'branch',
                                                'type',
                                                'remaining',
                                              ]
                                              .map((key) => Text('${r[key]}'))
                                              .toList(),
                                    )
                                    .toList(),
                              ),
                              if (current.isEmpty)
                                const Text('No current allocations.'),
                            ] else if (selectedDetail == 'Cash allocated') ...[
                              const Text(
                                'Opening cash and additions for each day in the selected period.',
                              ),
                              ...branches.entries.map(
                                (b) => ListTile(
                                  title: Text(b.value),
                                  trailing: Text(
                                    money(cashByOwner[b.key] ?? 0),
                                  ),
                                ),
                              ),
                            ] else if (selectedDetail == 'Total sold items')
                              InventoryRecordsTable(
                                headings: const [
                                  'ID',
                                  'Item',
                                  'Branch',
                                  'Sold',
                                ],
                                flex: const {0: 1, 1: 2, 2: 1.5, 3: 1},
                                rows: allRows
                                    .where((r) => reportValue(r['sold']) > 0)
                                    .map(
                                      (r) => [
                                        'id',
                                        'name',
                                        'branch',
                                        'sold',
                                      ].map((k) => Text('${r[k]}')).toList(),
                                    )
                                    .toList(),
                              )
                            else ...[
                              if (selectedDetail == 'Average sale')
                                Text(
                                  '${money(total)} / ${sold.toInt()} sold items = ${money(sold == 0 ? 0 : total / sold)}',
                                ),
                              InventoryRecordsTable(
                                headings: const [
                                  'Receipt',
                                  'Date',
                                  'Branch',
                                  'Payment',
                                  'Total',
                                  'Details',
                                ],
                                flex: const {
                                  0: 2,
                                  1: 1.6,
                                  2: 1.2,
                                  3: 1,
                                  4: 1,
                                  5: 1,
                                },
                                rows: sales
                                    .map(
                                      (sale) => <Widget>[
                                        Text(
                                          '${sale['salesId'] ?? sale['_id']}',
                                        ),
                                        Text(
                                          '${reportDateLabel(sale['timestamp'])}',
                                        ),
                                        Text(
                                          branches['${sale['branchId']}'] ??
                                              '${sale['branchId'] ?? 'Unassigned'}',
                                        ),
                                        Text(
                                          '${sale['paymentMode'] ?? 'Cash'}',
                                        ),
                                        Text(money(reportValue(sale['total']))),
                                        TextButton(
                                          onPressed: () => showDialog<void>(
                                            context: context,
                                            builder: (_) => ReceiptDetails(
                                              id: '${sale['_id'] ?? sale['salesId']}',
                                              sale: sale,
                                            ),
                                          ),
                                          child: const Text('View'),
                                        ),
                                      ],
                                    )
                                    .toList(),
                              ),
                              if (sales.isEmpty)
                                const Text('No sales in this period.'),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        spacing: 8,
                        children: ['Day', 'Week', 'Month', 'Year']
                            .map(
                              (p) => ChoiceChip(
                                label: Text(p),
                                selected: period == p,
                                onSelected: (_) => setState(() => period = p),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      MaterialLocalizations.of(context).formatMediumDate(day),
                    ),
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (selected != null) setState(() => day = selected);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, c) {
                      final columns = c.maxWidth < 320
                          ? 1
                          : c.maxWidth < 600
                          ? 2
                          : 3;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: metrics.entries
                            .map(
                              (e) => SizedBox(
                                width:
                                    (c.maxWidth - (columns - 1) * 12) / columns,
                                height: c.maxWidth < 600 ? 200 : 160,
                                child: Card(
                                  color: AppColors.surfaceTint,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => showDetails(e.key),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(e.key),
                                          const Spacer(),
                                          Text(
                                            e.value,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primaryDeep,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            e.key == 'Items allocated'
                                                ? 'View allocated'
                                                : 'View details',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Sales by branch',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 320,
                    child: BranchAnalyticsBars(
                      values: chart.values.toList(),
                      labels: chart.keys.toList(),
                    ),
                  ),
                  ReportSalesTimeline(
                    data: data,
                    start: start,
                    end: end,
                    period: period,
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: printing
                          ? null
                          : () => printReport(metrics, rows, chart),
                      icon: const Icon(Icons.print),
                      label: Text(printing ? 'Preparing…' : 'Print report'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
