import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/branch_report_data.dart';
import '../services/bundle_stock_service.dart';
import '../services/number_format.dart';
import '../services/report_pdf_theme.dart';
import '../services/report_print.dart';
import '../services/save_bytes.dart';
import '../theme/app_colors.dart';
import 'historical_cash_drawer.dart';

Future<void> showInventoryReport(
  BuildContext context, {
  required String? branchId,
  FirebaseFirestore? database,
}) => showDialog<void>(
  context: context,
  builder: (_) => InventoryReportDialog(
    branchId: branchId,
    data: BranchReportData.watch(firestore: database),
  ),
);

class InventoryReportDialog extends StatefulWidget {
  const InventoryReportDialog({
    super.key,
    required this.branchId,
    required this.data,
  });

  final String? branchId;
  final Stream<BranchReportData> data;

  @override
  State<InventoryReportDialog> createState() => _InventoryReportDialogState();
}

class _InventoryReportDialogState extends State<InventoryReportDialog> {
  final _today = DateUtils.dateOnly(DateTime.now());
  DateTimeRange? _range;
  bool _busy = false;

  DateTimeRange get _selectedRange =>
      _range ?? DateTimeRange(start: _today, end: _today);

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
    );
    if (selected != null && mounted) {
      setState(() => _range = selected);
    }
  }

  DateTime? _date(dynamic value) => cashRecordDate(value);

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _mainInventory(BranchReportData data) {
    final result = <Map<String, dynamic>>[];
    for (final source in data.rows('sales_inventory')) {
      if (source['isDeleted'] == true || source['isVoided'] == true) continue;
      if (source['isBundle'] == true) {
        result.add({
          ...source,
          'name': source['name'] ?? 'Bundle',
          'type': 'Bundle',
          'quantity': availableBundleStock(source, now: _today),
          'stockTracked': true,
        });
        continue;
      }
      for (final item in (source['items'] as List? ?? []).whereType<Map>()) {
        if (item['isDeleted'] == true || item['isVoided'] == true) continue;
        result.add({
          ...item,
          'sourceInventoryId': source['_id'],
          'name': item['name'] ?? item['variant'] ?? source['name'] ?? 'Item',
          'type': 'Categories',
          'quantity': item['stock'] ?? item['startingStock'] ?? 0,
          'stockTracked': true,
        });
      }
    }
    for (final beverage in data.rows('coffee_products')) {
      if (beverage['isDeleted'] == true || beverage['isVoided'] == true) {
        continue;
      }
      result.add({
        ...beverage,
        'name': beverage['name'] ?? 'Beverage',
        'type': 'Beverages',
        'quantity': beverage['stock'],
        'stockTracked': beverage['stock'] != null,
      });
    }
    for (final addon in data.rows('coffee_addons')) {
      if (addon['isDeleted'] == true || addon['isVoided'] == true) continue;
      result.add({
        ...addon,
        'name': addon['name'] ?? 'Add-on',
        'type': 'Add-ons',
        'quantity': addon['stock'],
        'stockTracked': addon['stock'] != null,
      });
    }
    return result;
  }

  List<Map<String, dynamic>> _currentInventory(BranchReportData data) {
    if (widget.branchId == null) return _mainInventory(data);
    return data.currentInventory(widget.branchId!, DateTime.now()).map((row) {
      final quantity = row['remaining'];
      return {...row, 'quantity': quantity, 'stockTracked': quantity != null};
    }).toList();
  }

  int _expiredCount(BranchReportData data) {
    final start = DateUtils.dateOnly(_selectedRange.start);
    final end = DateUtils.dateOnly(
      _selectedRange.end,
    ).add(const Duration(days: 1));
    bool expired(Map item) {
      final value = _date(item['expirationDate'] ?? item['expiryDate']);
      if (value == null) return false;
      final date = DateUtils.dateOnly(value);
      return !date.isBefore(start) && date.isBefore(end);
    }

    if (widget.branchId == null) {
      final items = _mainInventory(data);
      return items.where(expired).length;
    }
    final seen = <String>{};
    for (final allocation
        in data
            .rows('staff_inventory')
            .where(
              (row) =>
                  (row['staffId'] == widget.branchId ||
                      row['branchId'] == widget.branchId) &&
                  row['isDeleted'] != true &&
                  row['isVoided'] != true,
            )) {
      final variants =
          allocation['isBundle'] == true ||
              allocation['isCoffee'] == true ||
              allocation['isAddon'] == true
          ? [allocation]
          : (allocation['items'] as List? ?? []).whereType<Map>();
      for (final item in variants.where(expired)) {
        seen.add(
          '${allocation['sourceInventoryId']}/${item['publicId'] ?? item['id'] ?? item['name']}',
        );
      }
    }
    return seen.length;
  }

  List<Map<String, dynamic>> _movementRows(BranchReportData data) {
    final range = _selectedRange;
    final start = DateUtils.dateOnly(range.start);
    final end = DateUtils.dateOnly(range.end).add(const Duration(days: 1));
    final branchIds = widget.branchId == null
        ? data.rows('branches').map((row) => '${row['_id']}').toList()
        : [widget.branchId!];
    final result = <Map<String, dynamic>>[];
    for (final branch in branchIds) {
      for (final item in data.items(branch, start, end)) {
        for (final event in (item['history'] as List? ?? []).whereType<Map>()) {
          final at = _date(event['time']);
          if (at == null || at.isBefore(start) || !at.isBefore(end)) continue;
          result.add({
            ...event,
            'itemName': event['name'] ?? item['name'] ?? 'Item',
            'branchName':
                data
                    .rows('branches')
                    .where((row) => row['_id'] == branch)
                    .map((row) => row['name'] ?? row['branchName'] ?? branch)
                    .firstOrNull ??
                branch,
          });
        }
      }
      for (final log in data.rows('activity_logs')) {
        final branches = (log['branchIds'] as List? ?? const [])
            .map((value) => '$value')
            .toSet();
        final details = log['details'] as Map? ?? const {};
        final logBranch = details['branchId'] ?? details['branch'];
        final at = _date(log['createdAt'] ?? log['timestamp']);
        if ((!branches.contains(branch) && '$logBranch' != branch) ||
            at == null ||
            at.isBefore(start) ||
            !at.isBefore(end)) {
          continue;
        }
        final action = '${log['action'] ?? ''}'.toLowerCase();
        if (!action.contains('return')) continue;
        result.add({
          'time': at,
          'activity': 'Returned',
          'qty': -reportValue(
            details['quantity'] ?? details['returnQuantity'] ?? 1,
          ).abs(),
          'balance': null,
          'itemName':
              details['bundleName'] ??
              details['item'] ??
              details['itemName'] ??
              'Inventory return',
          'branchName': branch,
        });
      }
    }
    result.sort(
      (a, b) => (_date(b['time']) ?? DateTime(0)).compareTo(
        _date(a['time']) ?? DateTime(0),
      ),
    );
    return result;
  }

  Map<String, double> _movementMetrics(
    BranchReportData data,
    List<Map<String, dynamic>> movements,
  ) {
    double amount(bool Function(String) matches) => movements
        .where(
          (row) => matches('${row['activity'] ?? ''}'.trim().toLowerCase()),
        )
        .fold<double>(0, (total, row) => total + reportValue(row['qty']).abs());
    final allocated = amount(
      (name) => name.contains('allocation') || name.contains('allocated'),
    );
    return {
      'Starting Stock': amount(
        (name) => name.contains('opening') || name.contains('starting'),
      ),
      'Stock Received': widget.branchId == null
          ? amount((name) => name.contains('received'))
          : allocated,
      'Stock Allocated': widget.branchId == null
          ? allocated
          : amount((name) => name.contains('allocated')),
      'Stock Returned': amount((name) => name.contains('return')),
      'Stock Adjustments': amount(
        (name) =>
            name.contains('adjust') ||
            name.contains('reduce') ||
            name.contains('unbundle'),
      ),
      'Damaged Items': amount((name) => name.contains('damaged')),
      'Expired Items': amount((name) => name.contains('expired')),
      'Remaining Stock': _currentInventory(
        data,
      ).fold<double>(0, (total, row) => total + reportValue(row['quantity'])),
    };
  }

  Map<String, double> _summary(
    BranchReportData data,
    List<Map<String, dynamic>> inventory,
  ) {
    double stockValue(Map row, String key) {
      final quantity = reportValue(row['quantity']);
      if (row['stockTracked'] != true) return 0;
      final unit = reportValue(row[key]);
      return quantity * unit;
    }

    return {
      'Total Products': inventory.length.toDouble(),
      'Total Bundles': inventory
          .where((row) => row['type'] == 'Bundle' || row['isBundle'] == true)
          .length
          .toDouble(),
      'Total Beverages': inventory
          .where((row) => row['type'] == 'Beverages' || row['isCoffee'] == true)
          .length
          .toDouble(),
      'Total Stock Quantity': inventory.fold<double>(
        0,
        (total, row) => total + reportValue(row['quantity']),
      ),
      'Total Inventory Cost': inventory.fold<double>(
        0,
        (total, row) => total + stockValue(row, 'costPrice'),
      ),
      'Total Inventory Value': inventory.fold<double>(
        0,
        (total, row) => total + stockValue(row, 'price'),
      ),
      'Low Stock Items': inventory
          .where(
            (row) =>
                '${row['status'] ?? ''}'.toLowerCase().contains('low stock') ||
                row['isLowStock'] == true,
          )
          .length
          .toDouble(),
      'Out of Stock Items': inventory
          .where(
            (row) =>
                row['stockTracked'] == true &&
                reportValue(row['quantity']) <= 0,
          )
          .length
          .toDouble(),
      'Expired Items': _expiredCount(data).toDouble(),
    };
  }

  List<List<dynamic>> _exportRows(
    Map<String, double> summary,
    Map<String, double> movements,
    List<Map<String, dynamic>> activity,
  ) => [
    ['INVENTORY REPORT'],
    ['Scope', widget.branchId ?? 'Main inventory'],
    [
      'Movement period',
      '${_dateLabel(_selectedRange.start)} to ${_dateLabel(_selectedRange.end)}',
    ],
    [],
    ['OVERALL INVENTORY'],
    ['Metric', 'Value'],
    for (final entry in summary.entries)
      [
        entry.key,
        entry.key.startsWith('Total Inventory')
            ? entry.value.toStringAsFixed(2)
            : entry.value,
      ],
    [],
    ['STOCK MOVEMENT'],
    ['Metric', 'Quantity'],
    for (final entry in movements.entries) [entry.key, entry.value],
    [],
    ['MOVEMENT DETAILS'],
    ['Date / time', 'Branch', 'Item', 'Activity', 'Quantity', 'Balance'],
    for (final row in activity)
      [
        _date(row['time'])?.toIso8601String() ?? '',
        row['branchName'] ?? '',
        row['itemName'] ?? '',
        row['activity'] ?? '',
        reportValue(row['qty']).abs(),
        row['balance'] ?? '',
      ],
  ];

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  Uint8List _excel(List<List<dynamic>> rows) {
    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    String cell(int column, int row, dynamic value) {
      final name = String.fromCharCode(65 + column);
      final reference = '$name$row';
      if (value is num) {
        return '<c r="$reference"><v>$value</v></c>';
      }
      return '<c r="$reference" t="inlineStr"><is><t>${_xml('$value')}</t></is></c>';
    }

    final sheet = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
    );
    for (var index = 0; index < rows.length; index++) {
      final rowNumber = index + 1;
      sheet.write('<row r="$rowNumber">');
      for (var column = 0; column < rows[index].length; column++) {
        sheet.write(cell(column, rowNumber, rows[index][column]));
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');
    add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '</Types>',
    );
    add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
    );
    add(
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="Inventory Report" sheetId="1" r:id="rId1"/></sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '</Relationships>',
    );
    add('xl/worksheets/sheet1.xml', sheet.toString());
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> _saveExcel(List<List<dynamic>> rows) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = _excel(rows);
      final name =
          'inventory-report-${_today.year}-${_today.month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}.xlsx';
      final path = kIsWeb
          ? name
          : await FilePicker.platform.saveFile(
              bytes: bytes,
              fileName: name,
              type: FileType.custom,
              allowedExtensions: const ['xlsx'],
            );
      if (path != null) await saveBytes(path, bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save inventory report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(
    Map<String, double> summary,
    Map<String, double> movements,
    List<Map<String, dynamic>> activity,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await printReportDocument(
        name:
            'inventory-report-${_today.toIso8601String().split('T').first}.pdf',
        build: () async {
          final pdf = pw.Document(theme: await reportPdfTheme());
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              build: (_) => [
                pw.Header(level: 0, text: 'Inventory Report'),
                pw.Text('Scope: ${widget.branchId ?? 'Main inventory'}'),
                pw.Text(
                  'Movement period: ${_dateLabel(_selectedRange.start)} to ${_dateLabel(_selectedRange.end)}',
                ),
                pw.SizedBox(height: 16),
                pw.Header(level: 1, text: 'Overall inventory'),
                pw.TableHelper.fromTextArray(
                  headers: const ['Metric', 'Value'],
                  data: summary.entries
                      .map(
                        (entry) => [
                          entry.key,
                          entry.key.startsWith('Total Inventory')
                              ? formatMoney(entry.value)
                              : entry.value.toStringAsFixed(0),
                        ],
                      )
                      .toList(),
                ),
                pw.SizedBox(height: 16),
                pw.Header(level: 1, text: 'Stock movement'),
                pw.TableHelper.fromTextArray(
                  headers: const ['Metric', 'Quantity'],
                  data: movements.entries
                      .map(
                        (entry) => [entry.key, entry.value.toStringAsFixed(0)],
                      )
                      .toList(),
                ),
                pw.SizedBox(height: 16),
                pw.Header(level: 1, text: 'Movement details'),
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'Date / time',
                    'Branch',
                    'Item',
                    'Activity',
                    'Quantity',
                  ],
                  data: activity
                      .map(
                        (row) => [
                          _date(row['time'])?.toIso8601String() ?? '',
                          '${row['branchName'] ?? ''}',
                          '${row['itemName'] ?? ''}',
                          '${row['activity'] ?? ''}',
                          reportValue(row['qty']).abs().toStringAsFixed(0),
                        ],
                      )
                      .toList(),
                ),
              ],
            ),
          );
          return pdf.save();
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to print inventory report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(14),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 920,
        maxHeight:
            MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            28,
      ),
      child: StreamBuilder<BranchReportData>(
        stream: widget.data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load inventory report: ${snapshot.error}',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final inventory = _currentInventory(data);
          final summary = _summary(data, inventory);
          final movements = _movementRows(data);
          final movementMetrics = _movementMetrics(data, movements);
          final exportRows = _exportRows(summary, movementMetrics, movements);
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 17, 12, 17),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryDeep, AppColors.primaryDark],
                  ),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0x33FFFFFF),
                      child: Icon(
                        Icons.assessment_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'INVENTORY REPORT',
                            style: TextStyle(
                              color: Color(0xFFFFDCE6),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            widget.branchId == null
                                ? 'Main inventory'
                                : data
                                      .rows('branches')
                                      .where(
                                        (row) => row['_id'] == widget.branchId,
                                      )
                                      .map(
                                        (row) =>
                                            row['name'] ??
                                            row['branchName'] ??
                                            widget.branchId,
                                      )
                                      .firstOrNull
                                      .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                          'Current inventory',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickRange,
                      icon: const Icon(Icons.date_range_rounded, size: 18),
                      label: Text(
                        '${_dateLabel(_selectedRange.start)} – ${_dateLabel(_selectedRange.end)}',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Stock totals show the selected branch’s current inventory. Movement and expiry records use the selected date range.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 700
                            ? 3
                            : constraints.maxWidth >= 420
                            ? 2
                            : 1;
                        final spacing = 10.0;
                        final width =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final entry in summary.entries)
                              SizedBox(
                                width: width,
                                child: _InventoryReportMetric(
                                  title: entry.key,
                                  value: entry.key.startsWith('Total Inventory')
                                      ? formatMoney(entry.value)
                                      : entry.value.toStringAsFixed(0),
                                  icon: _summaryIcon(entry.key),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Stock movement',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 600 ? 4 : 2;
                        final spacing = 8.0;
                        final width =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final entry in movementMetrics.entries)
                              SizedBox(
                                width: width,
                                child: _InventoryMovementMetric(
                                  title: entry.key,
                                  value: entry.value.toStringAsFixed(0),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Movement details',
                            style: TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text('${movements.length} records'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (movements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(
                          child: Text('No stock movement in this date range.'),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(
                            AppColors.blush,
                          ),
                          columns: const [
                            DataColumn(label: Text('Date / time')),
                            DataColumn(label: Text('Branch')),
                            DataColumn(label: Text('Item')),
                            DataColumn(label: Text('Activity')),
                            DataColumn(label: Text('Quantity')),
                            DataColumn(label: Text('Balance')),
                          ],
                          rows: movements
                              .map(
                                (row) => DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        _date(row['time'])
                                                ?.toLocal()
                                                .toString()
                                                .substring(0, 16) ??
                                            'Not recorded',
                                      ),
                                    ),
                                    DataCell(
                                      Text('${row['branchName'] ?? 'Main'}'),
                                    ),
                                    DataCell(
                                      Text('${row['itemName'] ?? 'Item'}'),
                                    ),
                                    DataCell(
                                      Text('${row['activity'] ?? 'Movement'}'),
                                    ),
                                    DataCell(
                                      Text(
                                        reportValue(
                                          row['qty'],
                                        ).abs().toStringAsFixed(0),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        row['balance'] == null
                                            ? '—'
                                            : reportValue(
                                                row['balance'],
                                              ).toStringAsFixed(0),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                child: Row(
                  children: [
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _print(summary, movementMetrics, movements),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Print'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF218838),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : () => _saveExcel(exportRows),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.grid_on_rounded),
                      label: const Text('Save Excel'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  IconData _summaryIcon(String title) => switch (title) {
    'Total Products' => Icons.inventory_2_outlined,
    'Total Bundles' => Icons.all_inbox_outlined,
    'Total Beverages' => Icons.local_cafe_outlined,
    'Total Stock Quantity' => Icons.numbers_rounded,
    'Total Inventory Cost' => Icons.payments_outlined,
    'Total Inventory Value' => Icons.account_balance_wallet_outlined,
    'Low Stock Items' => Icons.warning_amber_rounded,
    'Out of Stock Items' => Icons.remove_shopping_cart_outlined,
    _ => Icons.event_busy_outlined,
  };
}

class _InventoryReportMetric extends StatelessWidget {
  const _InventoryReportMetric({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: AppColors.blush),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D94163A),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.blush,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.primaryDark, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InventoryMovementMetric extends StatelessWidget {
  const _InventoryMovementMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8FA),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.blush),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.primaryDark,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}
