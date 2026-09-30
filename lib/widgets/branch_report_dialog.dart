import '../services/report_pdf_theme.dart';
import '../services/number_format.dart';
import 'branch_receipts_dialog.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/branch_report_data.dart';
import '../services/save_bytes.dart';
import '../theme/app_colors.dart';
import 'admin_recent_sales.dart';
import 'admin_sales_overview.dart';
import 'branch_analytics_bars.dart';
import 'historical_cash_drawer.dart';

Future<void> showBranchReport(
  BuildContext context, {
  String? branchId,
  String? branchName,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      BranchReportDialog(branchId: branchId, branchName: branchName),
);

class BranchReportDialog extends StatefulWidget {
  const BranchReportDialog({
    super.key,
    this.branchId,
    this.branchName,
    this.reportData,
  });
  final String? branchId;
  final String? branchName;
  final Future<BranchReportData>? reportData;
  @override
  State<BranchReportDialog> createState() => _BranchReportDialogState();
}

class _BranchReportDialogState extends State<BranchReportDialog> {
  late Future<BranchReportData> _data =
      widget.reportData ?? BranchReportData.load();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  String _period = 'Day', _search = '', _payment = 'All', _status = 'All';
  bool _printing = false;
  String _itemType = 'All', _rank = 'All';
  String _tableType = 'Categories', _comparison = 'Complete';
  bool _tableAddons = false;
  Timer? _closingTimer;
  StreamSubscription<BranchReportData>? _liveSubscription;
  int _closingMinutes = 1140;
  late String _branchName = widget.branchName ?? 'Branch';
  bool get closingReady => reportClosingAvailable(
    range.$1,
    range.$2,
    DateTime.now(),
    closingMinutes: _closingMinutes,
  );
  @override
  void initState() {
    super.initState();
    if (widget.reportData == null)
      _liveSubscription = BranchReportData.watch().listen(
        (data) {
          if (mounted)
            setState(() {
              _data = Future.value(data);
              _branchName =
                  '${data.rows('branches').where((row) => row['_id'] == widget.branchId).firstOrNull?['name'] ?? _branchName}';
            });
        },
        onError: (Object error) {
          debugPrint('Report updates: $error');
        },
      );
    _closingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    _closingTimer?.cancel();
    super.dispose();
  }

  Map<String, double> reportTotals(BranchReportData data) {
    final values = data.totals(widget.branchId!, range.$1, range.$2);
    if (_period == 'Day' && !DateUtils.isSameDay(_day, DateTime.now())) {
      values['Total cash drawer today'] = values['Closing cash drawer'] ?? 0;
    }
    return {
      for (final entry in values.entries)
        if (entry.key != 'Total cash drawer today' &&
            (_period == 'Day' ||
                ![
                  'Starting fund',
                  'Total cash drawer today',
                  'Closing cash drawer',
                ].contains(entry.key)))
          (entry.key == 'Total cash drawer today' ? 'Cash drawer' : entry.key):
              entry.value,
    };
  }

  String summaryValue(String label, double value) =>
      label == 'Total sold' || label == 'Total transactions'
      ? formatNumber(value)
      : label == 'Closing cash drawer' && !closingReady
      ? '--'
      : money(value);
  (DateTime, DateTime) get range => branchReportRange(_day, _period);
  String money(num value) => formatMoney(value);
  String get title => widget.branchId == null
      ? 'Branch sales report'
      : '$_branchName ${_period == 'Day'
            ? 'Daily'
            : _period == 'Week'
            ? 'Weekly'
            : _period == 'Month'
            ? 'Monthly'
            : 'Yearly'} Report';
  String get dates =>
      '${range.$1.month}/${range.$1.day}/${range.$1.year} - ${range.$2.subtract(const Duration(days: 1)).month}/${range.$2.subtract(const Duration(days: 1)).day}/${range.$2.year}';
  List<Map<String, dynamic>> filteredSales(BranchReportData data) =>
      data
          .sales(widget.branchId, range.$1, range.$2)
          .where(
            (row) =>
                (_payment == 'All' ||
                    '${row['paymentMode'] ?? row['paymentMethod'] ?? 'Cash'}'
                            .toLowerCase() ==
                        _payment.toLowerCase()) &&
                (_search.isEmpty ||
                    '${row['salesId']} ${row['staffName']} ${row['branchName']} ${row['items']}'
                        .toLowerCase()
                        .contains(_search)),
          )
          .toList()
        ..sort(
          (a, b) => (cashRecordDate(b['timestamp']) ?? DateTime(0)).compareTo(
            cashRecordDate(a['timestamp']) ?? DateTime(0),
          ),
        );

  Widget section(String title, Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Map<String, double> branchAmounts(BranchReportData data) {
    final totals = <String, double>{
      for (final branch in data.rows('branches')) '${branch['_id']}': 0,
    };
    for (final id in totals.keys.toList()) {
      final field = _comparison == 'Refund'
          ? 'refund'
          : _comparison == 'Reduce'
          ? 'reduce'
          : 'sold';
      totals[id] = data
          .items(id, range.$1, range.$2)
          .fold<double>(0, (sum, row) => sum + reportValue(row[field]));
    }
    return totals;
  }

  List<Map<String, dynamic>> visibleItems(BranchReportData data) => data
      .items(widget.branchId!, range.$1, range.$2)
      .where(
        (row) =>
            _search.isEmpty ||
            '${row['id']} ${row['name']}'.toLowerCase().contains(_search),
      )
      .toList();

  (List<double>, List<double>, List<double>, List<String>) bars(
    BranchReportData data,
  ) {
    final hours = data.hours(widget.branchId, range.$1);
    final count = _period == 'Day'
        ? hours.length
        : _period == 'Year'
        ? 12
        : range.$2.difference(range.$1).inDays;
    final complete = List.filled(count, 0.0),
        refunds = List.filled(count, 0.0),
        reduced = List.filled(count, 0.0);
    int bucket(DateTime at) => _period == 'Day'
        ? hours.indexOf(at.hour)
        : _period == 'Year'
        ? at.month - 1
        : DateUtils.dateOnly(at).difference(range.$1).inDays;
    for (final sale in data.sales(widget.branchId, range.$1, range.$2)) {
      final at = cashRecordDate(sale['timestamp'] ?? sale['createdAt']);
      if (at == null) continue;
      final index = bucket(at);
      if (index < 0 || index >= count) continue;
      (reportRefund(sale) ? refunds : complete)[index] += reportValue(
        sale['total'],
      ).abs();
    }
    for (final row in data.losses(widget.branchId!, range.$1, range.$2)) {
      final at = cashRecordDate(row['createdAt'] ?? row['timestamp']);
      if (at == null) continue;
      final index = bucket(at);
      if (index >= 0 && index < count) reduced[index] += data.lossAmount(row);
    }
    return (
      complete,
      refunds,
      reduced,
      List.generate(
        count,
        (i) => _period == 'Day'
            ? '${hours[i] % 12 == 0 ? 12 : hours[i] % 12}${hours[i] < 12 ? 'AM' : 'PM'}'
            : _period == 'Year'
            ? const [
                'Jan',
                'Feb',
                'Mar',
                'Apr',
                'May',
                'Jun',
                'Jul',
                'Aug',
                'Sep',
                'Oct',
                'Nov',
                'Dec',
              ][i]
            : '${range.$1.add(Duration(days: i)).month}/${range.$1.add(Duration(days: i)).day}',
      ),
    );
  }

  pw.Widget pdfAnalytics(
    (List<double>, List<double>, List<double>, List<String>) chart,
    Map<String, double> totals,
  ) {
    final maximum = [
      ...chart.$1,
      ...chart.$2,
      ...chart.$3,
    ].fold<double>(0, math.max);
    final ceiling = math.max(200.0, (maximum / 200).ceil() * 200.0);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 12),
        pw.Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final entry in [
              ('Completed', totals['Total revenue'] ?? 0, '#E53935'),
              ('Refund', totals['Refunds'] ?? 0, '#F9A825'),
              ('Reduced', totals['Reduce'] ?? 0, '#1976D2'),
            ])
              pw.Text(
                '${entry.$1}: ${money(entry.$2)}',
                style: pw.TextStyle(
                  color: PdfColor.fromHex(entry.$3),
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.Text(
              'Total loss: ${money((totals['Refunds'] ?? 0) + (totals['Reduce'] ?? 0))}',
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.SizedBox(
          height: 230,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis(
                List.generate(chart.$1.length, (i) => i.toDouble()),
                format: (value) =>
                    chart.$4[value.toInt().clamp(0, chart.$4.length - 1)],
                textStyle: const pw.TextStyle(fontSize: 6),
                marginStart: 14,
                marginEnd: 14,
              ),
              yAxis: pw.FixedAxis(
                List.generate(5, (i) => ceiling * i / 4),
                format: (value) => value.toStringAsFixed(0),
                textStyle: const pw.TextStyle(fontSize: 8),
              ),
            ),
            datasets: [
              for (final series in [
                (chart.$1, '#E53935', -4.0),
                (chart.$2, '#F9A825', 0.0),
                (chart.$3, '#1976D2', 4.0),
              ])
                pw.BarDataSet(
                  data: List.generate(
                    series.$1.length,
                    (i) => pw.PointChartValue(i.toDouble(), series.$1[i]),
                  ),
                  color: PdfColor.fromHex(series.$2),
                  width: 3,
                  offset: series.$3,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<Uint8List> buildPdf(BranchReportData data) async {
    final pdf = pw.Document(theme: await reportPdfTheme());

    final totals = widget.branchId == null
        ? <String, double>{
            'Total revenue': branchAmounts(
              data,
            ).values.fold(0, (a, b) => a + b),
          }
        : reportTotals(data);
    final items = widget.branchId == null
        ? <Map<String, dynamic>>[]
        : visibleItems(data);
    final amounts = branchAmounts(data);
    final names = {
      for (final row in data.rows('branches'))
        '${row['_id']}': '${row['name']}',
    };
    final chart = widget.branchId == null ? null : bars(data);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        header: (_) => pw.Text(
          "Angel'Z Bites | $title",
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#94163A'),
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
        ),
        build: (_) => [
          pw.Text(
            '$dates | Payment: $_payment | Search: ${_search.isEmpty ? 'All' : _search}',
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: ['Summary', 'Amount'],
            data: totals.entries
                .map((e) => [e.key, summaryValue(e.key, e.value)])
                .toList(),
          ),
          if (widget.branchId == null) ...[
            pw.SizedBox(height: 16),
            pw.Text('Branch performance'),
            if (amounts.values.any((value) => value > 0))
              pw.SizedBox(
                height: 210,
                child: pw.Chart(
                  grid: pw.PieGrid(),
                  datasets: amounts.entries
                      .where((entry) => entry.value > 0)
                      .map((entry) {
                        final color =
                            ReportPie.colors[amounts.keys.toList().indexOf(
                                  entry.key,
                                ) %
                                ReportPie.colors.length];
                        return pw.PieDataSet(
                          value: entry.value,
                          color: PdfColor(color.r, color.g, color.b),
                          legend: names[entry.key] ?? entry.key,
                          innerRadius: 0,
                        );
                      })
                      .toList(),
                ),
              ),
            pw.TableHelper.fromTextArray(
              headers: ['Branch', 'Revenue'],
              data: amounts.entries
                  .map((e) => [names[e.key] ?? e.key, money(e.value)])
                  .toList(),
            ),
            ...amounts.keys.expand((id) {
              final ranked = data.items(id, range.$1, range.$2)
                ..sort(
                  (a, b) =>
                      reportValue(b['sold']).compareTo(reportValue(a['sold'])),
                );
              return [
                pw.SizedBox(height: 12),
                pw.Text('${names[id] ?? id} - Best-selling items'),
                pw.TableHelper.fromTextArray(
                  headers: ['ID', 'Item', 'Sold'],
                  data: ranked
                      .where((r) => reportValue(r['sold']) > 0)
                      .map(
                        (r) => ['${r['id']}', '${r['name']}', '${r['sold']}'],
                      )
                      .toList(),
                ),
              ];
            }),
          ],
          if (items.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Allocated items and recorded activity'),
            pw.TableHelper.fromTextArray(
              headers: [
                'ID',
                'Item',
                'Unit price',
                'Allocated',
                'Sold',
                'Refund',
                'Reduce',
                'Status',
              ],
              data: items
                  .map(
                    (r) => [
                      '${r['id']}',
                      '${r['name']}',
                      money(reportValue(r['price'])),
                      '${r['allocated']}',
                      '${r['sold']}',
                      '${r['refund']}',
                      '${r['reduce']}',
                      '${r['status']}',
                    ],
                  )
                  .toList(),
            ),
          ],
          if (chart != null) ...[
            pw.SizedBox(height: 16),
            pw.Text('Sales analytics - Complete / Refund / Reduce'),
            pdfAnalytics(chart, totals),
            pw.SizedBox(height: 12),
            pw.Text('$rankingTitle | $_itemType | $_rank $rankWord'),
            pw.TableHelper.fromTextArray(
              headers: ['Item', rankField],
              data: rankedItems(
                items,
              ).map((row) => ['${row['name']}', '${row[rankField]}']).toList(),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> export(BranchReportData data, bool save) async {
    setState(() => _printing = true);
    try {
      final bytes = await buildPdf(data);
      if (save) {
        final filename =
            'branch-report-${_day.year}-${_day.month}-${_day.day}.pdf';
        final path = kIsWeb
            ? filename
            : await FilePicker.platform.saveFile(
                bytes: bytes,
                fileName:
                    'branch-report-${_day.year}-${_day.month}-${_day.day}.pdf',
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );
        if (path != null) await saveBytes(path, bytes);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to generate report. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    backgroundColor: AppColors.background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: AppColors.primaryDeep,
              child: Row(
                children: [
                  const Icon(Icons.assessment_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close report',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search receipts or items',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Select report date',
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && mounted)
                        setState(() {
                          _day = picked;
                          _period = 'Day';
                        });
                    },
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...['Day', 'Week', 'Month', 'Year'].map(
                      (period) => ChoiceChip(
                        label: Text(period),
                        selected: _period == period,
                        onSelected: (_) => setState(() => _period = period),
                      ),
                    ),
                    Text(
                      dates,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<BranchReportData>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _data = BranchReportData.load()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Unable to load report. Retry'),
                      ),
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final data = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: [
                      if (widget.branchId == null)
                        overall(data)
                      else
                        ...branch(data),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _printing
                                ? null
                                : () => export(data, true),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Save PDF'),
                          ),
                          FilledButton.icon(
                            onPressed: _printing
                                ? null
                                : () => export(data, false),
                            icon: const Icon(Icons.print_outlined),
                            label: Text(
                              _printing ? 'Generating...' : 'Print report',
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget overall(BranchReportData data) {
    final amounts = branchAmounts(data);
    final names = {
      for (final row in data.rows('branches'))
        '${row['_id']}': '${row['name']}',
    };
    final ranked =
        amounts.keys
            .where(
              (id) =>
                  _search.isEmpty ||
                  (names[id] ?? id).toLowerCase().contains(_search),
            )
            .toList()
          ..sort((a, b) => amounts[b]!.compareTo(amounts[a]!));
    final total = amounts.values.fold<double>(0, (a, b) => a + b);
    return section(
      '$_comparison by branch • ${formatNumber(total)} items',
      Column(
        children: [
          SizedBox(
            height: 230,
            child: Center(
              child: SizedBox.square(
                dimension: 210,
                child: CustomPaint(painter: ReportPie(amounts.values.toList())),
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            children: ['Complete', 'Refund', 'Reduce']
                .map(
                  (value) => ChoiceChip(
                    label: Text(value),
                    selected: _comparison == value,
                    onSelected: (_) => setState(() => _comparison = value),
                  ),
                )
                .toList(),
          ),
          if (total == 0) const Text('No activity recorded for this period.'),
          ...ranked.map((id) {
            final top = data.items(id, range.$1, range.$2)
              ..sort(
                (a, b) =>
                    reportValue(
                      b[_comparison == 'Refund'
                          ? 'refund'
                          : _comparison == 'Reduce'
                          ? 'reduce'
                          : 'sold'],
                    ).compareTo(
                      reportValue(
                        a[_comparison == 'Refund'
                            ? 'refund'
                            : _comparison == 'Reduce'
                            ? 'reduce'
                            : 'sold'],
                      ),
                    ),
              );
            return ExpansionTile(
              leading: CircleAvatar(
                backgroundColor:
                    ReportPie.colors[amounts.keys.toList().indexOf(id) %
                        ReportPie.colors.length],
                child: Text(
                  '${ranked.indexOf(id) + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(names[id] ?? id),
              subtitle: Text(
                '${top.fold<double>(0, (sum, row) => sum + reportValue(row[_comparison == 'Refund'
                        ? 'refund'
                        : _comparison == 'Reduce'
                        ? 'reduce'
                        : 'sold'])).toStringAsFixed(0)} ${_comparison.toLowerCase()} / ${top.fold<double>(0, (sum, row) => sum + reportValue(row['allocated'])).toStringAsFixed(0)} allocated',
              ),
              children: top
                  .where(
                    (row) =>
                        reportValue(
                          row[_comparison == 'Refund'
                              ? 'refund'
                              : _comparison == 'Reduce'
                              ? 'reduce'
                              : 'sold'],
                        ) >
                        0,
                  )
                  .map(
                    (row) => ListTile(
                      title: Text('${row['name']}'),
                      trailing: Text(
                        '${reportValue(row[_comparison == 'Refund'
                            ? 'refund'
                            : _comparison == 'Reduce'
                            ? 'reduce'
                            : 'sold']).toStringAsFixed(0)} ${_comparison.toLowerCase()}',
                      ),
                    ),
                  )
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  String get rankField => _status == 'Refund'
      ? 'refund'
      : _status == 'Reduce'
      ? 'reduce'
      : 'sold';
  String get rankingTitle => _status == 'Refund'
      ? 'Refund items'
      : _status == 'Reduce'
      ? 'Reduced items'
      : 'Best-selling items';
  String get rankWord => _status == 'Refund'
      ? 'Refunds'
      : _status == 'Reduce'
      ? 'Reductions'
      : 'Selling';
  List<Map<String, dynamic>> rankedItems(List<Map<String, dynamic>> items) {
    final ranked =
        items
            .where(
              (row) =>
                  (_itemType == 'All' || row['type'] == _itemType) &&
                  reportValue(row[rankField]) > 0,
            )
            .toList()
          ..sort(
            (a, b) => _rank == 'Low'
                ? reportValue(a[rankField]).compareTo(reportValue(b[rankField]))
                : reportValue(
                    b[rankField],
                  ).compareTo(reportValue(a[rankField])),
          );
    return _rank == 'All' ? ranked : ranked.take(10).toList();
  }

  void activityDetails(BranchReportData data, String status) {
    setState(() {
      _status = status;
      _rank = 'All';
    });
    final refunds = status == 'Refund';
    final records = refunds
        ? data
              .sales(widget.branchId, range.$1, range.$2)
              .where(reportRefund)
              .toList()
        : status == 'Reduce'
        ? data.losses(widget.branchId!, range.$1, range.$2)
        : data
              .sales(widget.branchId, range.$1, range.$2)
              .where((row) => !reportRefund(row))
              .toList();
    showDialog<void>(
      context: context,
      builder: (_) => BranchReceiptsDialog(
        sales: records,
        period: dates,
        title: 'View ${status.toLowerCase()} items',
        reductions: status == 'Reduce',
        recordsStream: widget.reportData != null
            ? null
            : BranchReportData.watch().map(
                (fresh) => status == 'Reduce'
                    ? fresh.losses(widget.branchId!, range.$1, range.$2)
                    : fresh
                          .sales(widget.branchId, range.$1, range.$2)
                          .where(
                            (row) => status == 'Refund'
                                ? reportRefund(row)
                                : !reportRefund(row),
                          )
                          .toList(),
              ),
      ),
    );
  }

  List<Widget> branch(BranchReportData data) {
    final settings =
        data
            .rows('branches')
            .where((b) => b['_id'] == widget.branchId)
            .firstOrNull ??
        {};
    _closingMinutes = (settings['closingMinutes'] as num?)?.toInt() ?? 1140;
    final openingMinutes = (settings['openingMinutes'] as num?)?.toInt() ?? 600;
    String timeLabel(int minutes) =>
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);
    final totals = reportTotals(data);
    final items = visibleItems(data);
    final chart = bars(data);
    final all = _status == 'All';
    final values = List.generate(
      chart.$1.length,
      (i) => _status == 'Refund'
          ? chart.$2[i]
          : _status == 'Reduce'
          ? chart.$3[i]
          : _status == 'Complete'
          ? chart.$1[i]
          : chart.$1[i] + chart.$2[i] + chart.$3[i],
    );
    final ranked = rankedItems(items);
    final chartColor = _status == 'Refund'
        ? const Color(0xFFF9A825)
        : _status == 'Reduce'
        ? const Color(0xFF1976D2)
        : const Color(0xFFE53935);
    return [
      section(
        'Sales summary',
        Column(
          children: [
            ...totals.entries.map(
              (entry) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text(
                      summaryValue(entry.key, entry.value),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_period == 'Day')
              Text(
                'Shop hours: ${timeLabel(openingMinutes)}–${timeLabel(_closingMinutes)}. Closing cash drawer is available from ${timeLabel(_closingMinutes)} and includes later cash orders that day. GCash is excluded.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => BranchReceiptsDialog(
                  sales: data.sales(widget.branchId, range.$1, range.$2),
                  period: dates,
                  recordsStream: widget.reportData != null
                      ? null
                      : BranchReportData.watch().map(
                          (fresh) =>
                              fresh.sales(widget.branchId, range.$1, range.$2),
                        ),
                ),
              ),
              icon: const Icon(Icons.receipt_long),
              label: const Text('View all receipts'),
            ),
          ],
        ),
      ),
      section(
        'Allocated items',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              children: ['Categories', 'Bundle', 'Beverages']
                  .map(
                    (type) => ChoiceChip(
                      label: Text(type),
                      selected: _tableType == type,
                      onSelected: (_) => setState(() {
                        _tableType = type;
                        _tableAddons = false;
                      }),
                    ),
                  )
                  .toList(),
            ),
            if (_tableType == 'Beverages')
              TextButton(
                onPressed: () => setState(() => _tableAddons = !_tableAddons),
                child: Text(_tableAddons ? 'View beverages' : 'View add-ons'),
              ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(AppColors.blush),
                columns: [
                  'ID',
                  'Item',
                  if (_tableType == 'Beverages' && !_tableAddons) ...[
                    'Small',
                    'Medium',
                    'Large',
                  ] else
                    'Unit price',
                  'Starting allocated',
                  'Remaining allocated',
                  'Sold',
                  'Refund',
                  'Reduce',
                  'Expiration date',
                  'Status',
                ].map((label) => DataColumn(label: Text(label))).toList(),
                rows: items
                    .where(
                      (row) =>
                          row['type'] ==
                          (_tableAddons ? 'Add-ons' : _tableType),
                    )
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(Text('${row['id']}')),
                          DataCell(Text('${row['name']}')),
                          if (_tableType == 'Beverages' && !_tableAddons)
                            ...['Small', 'Medium', 'Large'].map((size) {
                              final option = (row['sizes'] as List? ?? [])
                                  .whereType<Map>()
                                  .where(
                                    (s) =>
                                        '${s['name']}'.toLowerCase() ==
                                        size.toLowerCase(),
                                  )
                                  .firstOrNull;
                              return DataCell(
                                Text(
                                  option == null
                                      ? '?'
                                      : money(
                                          reportValue(row['basePrice']) +
                                              reportValue(option['priceDelta']),
                                        ),
                                ),
                              );
                            })
                          else
                            DataCell(Text(money(reportValue(row['price'])))),
                          ...[
                            'allocated',
                            'remaining',
                            'sold',
                            'refund',
                            'reduce',
                          ].map(
                            (key) => DataCell(
                              Text(
                                row[key] == null
                                    ? 'Not recorded'
                                    : formatNumber(reportValue(row[key])),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${row['expirationDate'] ?? '?'}'
                                  .split('T')
                                  .first,
                            ),
                          ),
                          DataCell(Text('${row['status']}')),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      section(
        'Sales analytics',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: all,
                  onSelected: (_) => setState(() => _status = 'All'),
                ),
                for (final entry in [
                  ('Refund', const Color(0xFFF9A825)),
                  ('Reduce', const Color(0xFF1976D2)),
                  ('Complete', const Color(0xFFE53935)),
                ])
                  ActionChip(
                    avatar: Icon(Icons.circle, color: entry.$2, size: 14),
                    label: Text(entry.$1),
                    onPressed: () => setState(() {
                      _status = entry.$1;
                      _rank = 'All';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Total Completed: ${money(totals['Total revenue']!)}',
              style: const TextStyle(
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Total Reduced: ${money(totals['Reduce']!)}',
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Total Refund: ${money(totals['Refunds']!)}',
              style: const TextStyle(
                color: Color(0xFFF9A825),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(
                      constraints.maxWidth,
                      chart.$1.length * 38.0,
                    ),
                    child: BranchAnalyticsBars(
                      values: values,
                      labels: chart.$4,
                      colors: [chartColor, chartColor],
                      refunds: all ? chart.$2 : null,
                      reduced: all ? chart.$3 : null,
                      selectedStatus: _status == 'Complete'
                          ? 'Completed'
                          : _status == 'Reduce'
                          ? 'Reduced'
                          : _status,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text(
                  'Total loss: ${money(totals['Reduce']! + totals['Refunds']!)}',
                ),
                Text(
                  'Total profit: ${money(totals['Total revenue']! - totals['Reduce']! - totals['Refunds']!)}',
                ),
              ],
            ),
            const Text(
              'Profit shown is revenue less refunds and reductions.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            if (_status != 'All')
              OutlinedButton.icon(
                onPressed: () => activityDetails(data, _status),
                icon: const Icon(Icons.receipt_long),
                label: Text('View all ${_status.toLowerCase()} items'),
              ),
            if (_period == 'Day')
              const Text(
                'Hourly activity for the full selected day.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
      section(
        rankingTitle,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: ['All', 'Categories', 'Bundle', 'Beverages']
                  .map(
                    (type) => ChoiceChip(
                      label: Text(type),
                      selected: _itemType == type,
                      onSelected: (_) => setState(() => _itemType = type),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Top', 'Low']
                  .map(
                    (rank) => ChoiceChip(
                      label: Text(rank == 'All' ? 'All' : '$rank 10 $rankWord'),
                      selected: _rank == rank,
                      onSelected: (_) => setState(() => _rank = rank),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            if (ranked.isEmpty) const Text('No matching items in this period.'),
            ...ranked.map(
              (row) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.blush,
                  child: Text('${ranked.indexOf(row) + 1}'),
                ),
                title: Text('${row['name']}'),
                trailing: Text(
                  '${reportValue(row[rankField]).toStringAsFixed(0)} ${rankField == 'sold'
                      ? 'sold'
                      : rankField == 'refund'
                      ? 'refunded'
                      : 'reduced'}',
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class ReportPie extends CustomPainter {
  ReportPie(this.values);
  final List<double> values;
  static const colors = [
    AppColors.primary,
    AppColors.primaryDeep,
    Color(0xFF527D9C),
    Color(0xFFD19A40),
    AppColors.rose,
    Color(0xFF54897C),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final rect = Offset.zero & size;
    if (total <= 0) {
      canvas.drawOval(rect, Paint()..color = AppColors.blush);
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant ReportPie oldDelegate) =>
      oldDelegate.values != values;
}
