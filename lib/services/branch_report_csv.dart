import 'dart:convert';
import 'dart:typed_data';
import 'branch_report_data.dart';
import '../widgets/historical_cash_drawer.dart';

String csvCell(dynamic value) {
  var text = value == null ? '' : '$value';
  if (value is String &&
      RegExp(r'^[=+@\-\t\r]').hasMatch(text) &&
      !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

/// Excel-compatible UTF-8 CSV with separate, labelled sections per branch.
Uint8List branchReportCsv(
  BranchReportData data,
  DateTime start,
  DateTime end, {
  String? branchId,
  DateTime? now,
}) => Uint8List.fromList(
  utf8.encode(
    '\uFEFF${branchReportRows(data, start, end, branchId: branchId, now: now).map((row) => row.map(csvCell).join(',')).join('\r\n')}',
  ),
);

List<List<dynamic>> branchReportRows(
  BranchReportData data,
  DateTime start,
  DateTime end, {
  String? branchId,
  DateTime? now,
}) {
  final generated = now ?? DateTime.now();
  String date(DateTime value) => value.toIso8601String().split('T').first;
  String money(dynamic value) => reportValue(value).toStringAsFixed(2);
  double sum(Iterable<Map<String, dynamic>> rows, String field) =>
      rows.fold<double>(0, (total, row) => total + reportValue(row[field]));
  double soldCost(Iterable<Map<String, dynamic>> rows) => rows.fold<double>(
    0,
    (total, row) =>
        total +
        (row['totalCost'] != null
            ? reportValue(row['totalCost'])
            : reportValue(row['costPrice']) * reportValue(row['sold'])),
  );
  final rows = <List<dynamic>>[
    ['SALES REPORT'],
    [
      'Period',
      '${date(start)} to ${date(end.subtract(const Duration(days: 1)))}',
    ],
    ['Generated', generated.toIso8601String()],
    ['Currency', 'PHP'],
    [
      'Allocation scope',
      'Current active inventory as of ${date(generated)}; sales activity uses the selected period.',
    ],
    [],
  ];
  for (final branch
      in data
          .rows('branches')
          .where((b) => branchId == null || b['_id'] == branchId)) {
    final id = '${branch['_id']}';
    final current = data.currentAllocatedItems(id, start, end, now: generated);
    final totals = data.allocationReportTotals(id, start, end, now: generated);
    final sales = data.sales(id, start, end);
    final losses = data.losses(id, start, end);
    final refundsEnabled = data.refundsEnabled(id);
    final ranked =
        data
            .items(id, start, end)
            .where((r) => reportValue(r['sold']) > 0)
            .toList()
          ..sort(
            (a, b) => reportValue(b['sold']).compareTo(reportValue(a['sold'])),
          );
    rows.addAll([
      ['BRANCH', branch['name'] ?? id, branch['branchCode'] ?? id],
      [],
      ['1. SALES SUMMARY'],
      ['Metric', 'Amount / count'],
      for (final entry in totals.entries)
        if (refundsEnabled || entry.key != 'Refunds')
          [entry.key, money(entry.value)],
      ['Cost of sold items', money(data.totals(id, start, end)['Total cost'])],
      ['Total loss', money((totals['Refunds'] ?? 0) + (totals['Reduce'] ?? 0))],
      [],
      ['2. CURRENT ALLOCATED ITEMS'],
      [
        'Total cost',
        'Cost price x sold items; unsold inventory contributes 0.',
      ],
    ]);
    for (final type in ['Categories', 'Bundle', 'Beverages', 'Add-ons']) {
      final selected = current.where((row) => row['type'] == type).toList();
      if (selected.isEmpty) continue;
      final beverage = type == 'Beverages';
      double? sizePrice(Map row, String size) {
        final option = (row['sizes'] as List? ?? [])
            .whereType<Map>()
            .where((r) => '${r['name']}'.toLowerCase() == size.toLowerCase())
            .firstOrNull;
        return option == null
            ? null
            : reportValue(row['basePrice']) +
                  reportValue(option['priceDelta'] ?? option['price']);
      }

      rows.addAll([
        [type],
        [
          'ID',
          'Allocation date',
          'Item',
          'Cost price',
          if (beverage) ...[
            'Small price',
            'Medium price',
            'Large price',
          ] else
            'Selling price',
          if (!beverage) ...[
            'Starting allocation',
            'Allocated in period',
            'Remaining allocation',
          ],
          'Sales',
          'Sold items',
          'Total profit',
          'Net profit',
          'Total cost',
          'Expiry',
        ],
        for (final row in selected)
          [
            row['id'],
            cashRecordDate(row['allocationDate']) == null
                ? ''
                : date(cashRecordDate(row['allocationDate'])!),
            row['name'],
            money(row['costPrice']),
            if (beverage) ...[
              for (final size in ['Small', 'Medium', 'Large'])
                sizePrice(row, size) == null ? '' : money(sizePrice(row, size)),
            ] else
              money(row['price']),
            if (!beverage) ...[row['starting'], row['added'], row['remaining']],
            money(row['sales']),
            row['sold'],
            money(row['profit']),
            money(row['netProfit']),
            money(
              (row['totalCost'] != null
                  ? reportValue(row['totalCost'])
                  : reportValue(row['costPrice']) * reportValue(row['sold'])),
            ),
            cashRecordDate(row['expirationDate']) == null
                ? ''
                : date(cashRecordDate(row['expirationDate'])!),
          ],
        [
          'TOTAL',
          '',
          '',
          '',
          if (beverage) ...['', '', ''] else '',
          if (!beverage) ...[
            sum(selected, 'starting'),
            sum(selected, 'added'),
            sum(selected, 'remaining'),
          ],
          money(sum(selected, 'sales')),
          sum(selected, 'sold'),
          money(sum(selected, 'profit')),
          money(sum(selected, 'netProfit')),
          money(soldCost(selected)),
          '',
        ],
        [],
      ]);
    }
    if (current.isEmpty) rows.add(['No current allocated items']);
    rows.addAll([
      [],
      ['3. SALES ANALYTICS'],
      [
        'Date / hour',
        'Transactions',
        'Sold items',
        'Sales',
        'Net sales',
        'VAT / tax',
        'Discounts',
        if (refundsEnabled) 'Refunds',
        'Reduced stock value',
        'Profit',
      ],
    ]);
    final hourly = end.difference(start).inDays == 1;
    for (
      var at = start;
      at.isBefore(end);
      at = hourly
          ? at.add(const Duration(hours: 1))
          : DateTime(at.year, at.month, at.day + 1)
    ) {
      final next = hourly
          ? at.add(const Duration(hours: 1))
          : DateTime(at.year, at.month, at.day + 1);
      final until = next.isAfter(end) ? end : next;
      final selectedSales = sales
          .where((sale) => reportInRange(sale['timestamp'], at, until))
          .toList();
      final completed = selectedSales
          .where((sale) => !reportRefund(sale))
          .toList();
      final bucket = <String, double>{
        'Total transactions': completed.length.toDouble(),
        'Total sold': completed.fold<double>(
          0,
          (total, sale) =>
              total +
              (sale['items'] as List? ?? []).whereType<Map>().fold<double>(
                0,
                (count, item) => count + reportValue(item['quantity']),
              ),
        ),
        'Total revenue': sum(completed, 'total'),
        'Total VAT / tax': completed.fold<double>(
          0,
          (total, sale) =>
              total +
              reportValue(
                sale['tax'] ??
                    sale['vatAmount'] ??
                    sale['taxAmount'] ??
                    sale['vat'],
              ),
        ),
        'Total net sales': completed.fold<double>(
          0,
          (total, sale) =>
              total +
              reportValue(sale['total']) -
              reportValue(
                sale['tax'] ??
                    sale['vatAmount'] ??
                    sale['taxAmount'] ??
                    sale['vat'],
              ),
        ),
        'Total discount': sum(completed, 'discount'),
        'Refunds': selectedSales
            .where(reportRefund)
            .fold<double>(
              0,
              (total, sale) => total + reportValue(sale['total']).abs(),
            ),
        'Reduce': losses
            .where(
              (loss) => reportInRange(
                loss['createdAt'] ?? loss['timestamp'],
                at,
                until,
              ),
            )
            .fold<double>(0, (total, loss) => total + data.lossAmount(loss)),
        'Total profit': data.profitForItems(data.items(id, at, until)),
      };
      rows.add([
        hourly
            ? '${date(at)} ${at.hour.toString().padLeft(2, '0')}:00'
            : date(at),
        bucket['Total transactions'],
        bucket['Total sold'],
        money(bucket['Total revenue']),
        money(bucket['Total net sales']),
        money(bucket['Total VAT / tax']),
        money(bucket['Total discount']),
        if (refundsEnabled) money(bucket['Refunds']),
        money(bucket['Reduce']),
        money(bucket['Total profit']),
      ]);
    }
    rows.addAll([
      [
        'TOTAL',
        totals['Total transactions'],
        totals['Total sold'],
        money(totals['Total revenue']),
        money(totals['Total net sales']),
        money(totals['Total VAT / tax']),
        money(totals['Total discount']),
        if (refundsEnabled) money(totals['Refunds']),
        money(totals['Reduce']),
        money(totals['Total profit']),
      ],
      [],
      ['4. BEST-SELLING ITEMS'],
      [
        'Rank',
        'ID',
        'Item',
        'Type',
        'Sales',
        'Sold items',
        'Cost of sold items',
        'Profit',
        'Net profit',
      ],
      for (var i = 0; i < ranked.length; i++)
        [
          i + 1,
          ranked[i]['id'],
          ranked[i]['name'],
          ranked[i]['type'],
          money(ranked[i]['sales']),
          ranked[i]['sold'],
          money(ranked[i]['totalCost']),
          money(ranked[i]['profit']),
          money(ranked[i]['netProfit']),
        ],
      if (ranked.isEmpty) ['No sales in this period'],
      [],
      ['5. RECEIPT RECORDS'],
      [
        'Receipt',
        'Date / time',
        'Staff',
        'Payment',
        'Status',
        'Subtotal',
        'Discount',
        'VAT / tax',
        'Total',
      ],
      for (final sale in sales)
        [
          sale['salesId'] ?? sale['_id'],
          cashRecordDate(sale['timestamp'])?.toIso8601String(),
          sale['staffName'] ?? sale['staffId'] ?? sale['userId'],
          sale['paymentMode'] ?? sale['paymentMethod'],
          reportRefund(sale) ? 'Refund' : 'Complete',
          money(sale['subtotal']),
          money(sale['discount']),
          money(
            sale['tax'] ??
                sale['vatAmount'] ??
                sale['taxAmount'] ??
                sale['vat'],
          ),
          money(sale['total']),
        ],
      [],
      ['6. RECEIPT ITEM DETAILS'],
      [
        'Receipt',
        'ID',
        'Item',
        'Quantity',
        'Unit price',
        'Recorded unit cost',
        'Line total',
      ],
      for (final sale in sales)
        for (final item in (sale['items'] as List? ?? []).whereType<Map>())
          [
            sale['salesId'] ?? sale['_id'],
            item['publicId'] ?? item['itemId'] ?? item['id'],
            item['name'],
            item['quantity'],
            money(item['price']),
            money(item['costPrice']),
            money(reportValue(item['quantity']) * reportValue(item['price'])),
          ],
      [],
      ['7. STOCK REDUCTIONS'],
      ['Date / time', 'Item', 'Quantity', 'Reason', 'Loss amount'],
      for (final loss in losses)
        [
          cashRecordDate(
            loss['createdAt'] ?? loss['timestamp'],
          )?.toIso8601String(),
          loss['itemName'] ?? loss['name'],
          loss['quantity'],
          loss['reason'],
          money(data.lossAmount(loss)),
        ],
      [],
      [],
    ]);
  }
  return rows;
}
