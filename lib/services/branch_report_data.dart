import 'refund_value.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/branch_daily_summary.dart';
import '../widgets/historical_cash_drawer.dart';
import 'inventory_display_ids.dart';
import 'analytics_hours.dart';

double reportValue(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;
bool reportClosingAvailable(
  DateTime start,
  DateTime end,
  DateTime now, {
  int closingMinutes = 1140,
}) {
  if (start.isAfter(now)) return false;
  final last = end.subtract(const Duration(days: 1));
  final day = last.isAfter(now) ? now : last;
  return !now.isBefore(
    DateTime(
      day.year,
      day.month,
      day.day,
      closingMinutes ~/ 60,
      closingMinutes % 60,
    ),
  );
}

bool reportInRange(dynamic value, DateTime start, DateTime end) {
  final date = cashRecordDate(value);
  return date != null && !date.isBefore(start) && date.isBefore(end);
}

bool validReportSale(Map row) =>
    row['isVoided'] != true &&
    ![
      'void',
      'voided',
      'cancelled',
      'canceled',
    ].contains('${row['status']}'.toLowerCase());
bool reportRefund(Map row) =>
    reportValue(row['total']) < 0 ||
    ['refund', 'refunded'].contains('${row['status']}'.toLowerCase()) ||
    '${row['type']}'.toLowerCase() == 'refund' ||
    '${row['salesId']}'.toUpperCase().startsWith('R-');

class BranchReportData {
  static Stream<BranchReportData> watch() {
    const names = [
      'branches',
      'completed_sales',
      'stock_adjustments',
      'staff_inventory',
      'staff_inventory_history',
      'sales_inventory',
      'coffee_products',
      'coffee_addons',
      'budget_history',
      'staff_cash_drawer',
      'daily_reports',
    ];
    final values = <String, List<Map<String, dynamic>>>{};
    final subscriptions = <StreamSubscription>[];
    late StreamController<BranchReportData> controller;
    controller = StreamController<BranchReportData>(
      onListen: () {
        for (final name in names) {
          subscriptions.add(
            FirebaseFirestore.instance.collection(name).snapshots().listen((
              snapshot,
            ) {
              values[name] = snapshot.docs
                  .map((doc) => <String, dynamic>{...doc.data(), '_id': doc.id})
                  .toList();
              if (values.length == names.length)
                controller.add(BranchReportData(Map.from(values)));
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  final Map<String, List<Map<String, dynamic>>> collections;
  BranchReportData(this.collections);
  List<Map<String, dynamic>> rows(String collection) =>
      collection == 'completed_sales'
      ? (collections[collection] ?? []).map(refundValueRecord).toList()
      : collections[collection] ?? [];

  List<int> hours(String? branch, DateTime day) {
    final settings = rows(
      'branches',
    ).where((row) => branch == null || row['_id'] == branch).toList();
    final openings =
        settings
            .map((row) => (row['openingMinutes'] as num?)?.toInt() ?? 600)
            .toList()
          ..sort();
    final closings =
        settings
            .map((row) => (row['closingMinutes'] as num?)?.toInt() ?? 1140)
            .toList()
          ..sort();
    return analyticsHours(
      day,
      [
        ...sales(
              branch,
              DateUtils.dateOnly(day),
              DateTime(day.year, day.month, day.day + 1),
            )
            .map((row) => cashRecordDate(row['timestamp'] ?? row['createdAt']))
            .whereType<DateTime>(),
        for (final setting in settings)
          ...losses(
                '${setting['_id']}',
                DateUtils.dateOnly(day),
                DateTime(day.year, day.month, day.day + 1),
              )
              .map(
                (row) => cashRecordDate(row['createdAt'] ?? row['timestamp']),
              )
              .whereType<DateTime>(),
      ],
      openingMinutes: openings.firstOrNull ?? 600,
      closingMinutes: closings.lastOrNull ?? 1140,
    );
  }

  static Future<BranchReportData> load() async {
    const names = [
      'branches',
      'completed_sales',
      'stock_adjustments',
      'staff_inventory',
      'staff_inventory_history',
      'sales_inventory',
      'coffee_products',
      'coffee_addons',
      'budget_history',
      'staff_cash_drawer',
      'daily_reports',
    ];
    final snapshots = await Future.wait(
      names.map((name) => FirebaseFirestore.instance.collection(name).get()),
    );
    return BranchReportData({
      for (var i = 0; i < names.length; i++)
        names[i]: snapshots[i].docs
            .map((doc) => <String, dynamic>{...doc.data(), '_id': doc.id})
            .toList(),
    });
  }

  List<Map<String, dynamic>> sales(
    String? branch,
    DateTime start,
    DateTime end,
  ) => rows('completed_sales')
      .where(
        (row) =>
            (branch == null || row['branchId'] == branch) &&
            reportInRange(row['timestamp'] ?? row['createdAt'], start, end) &&
            validReportSale(row),
      )
      .toList();

  List<Map<String, dynamic>> losses(
    String branch,
    DateTime start,
    DateTime end,
  ) {
    final inventory = rows(
      'staff_inventory',
    ).where((row) => row['staffId'] == branch).map((row) => row['_id']).toSet();
    return rows('stock_adjustments')
        .where(
          (row) =>
              (row['branchId'] == branch ||
                  (row['branchId'] == null &&
                      inventory.contains(row['categoryId']))) &&
              reportInRange(row['createdAt'] ?? row['timestamp'], start, end),
        )
        .toList();
  }

  double lossAmount(Map row) => row['lossAmount'] != null
      ? reportValue(row['lossAmount']).abs()
      : reportValue(row['quantity']) *
            reportValue(row['unitPrice'] ?? row['bundlePrice']);

  double todayCashDrawer(String branch) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final drawer =
        rows(
          'staff_cash_drawer',
        ).where((row) => row['_id'] == branch).firstOrNull ??
        {};
    final key =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (drawer['drawerDate'] == key) return reportValue(drawer['balance']);
    return reportValue(drawer['dailyOpeningCash'] ?? drawer['openingCash']) +
        sales(branch, start, start.add(const Duration(days: 1)))
            .where(
              (row) =>
                  '${row['paymentMode'] ?? row['paymentMethod'] ?? 'Cash'}'
                      .toLowerCase() ==
                  'cash',
            )
            .fold<double>(
              0,
              (sum, row) =>
                  sum +
                  (row['cashDrawerDelta'] != null
                      ? reportValue(row['cashDrawerDelta'])
                      : reportRefund(row)
                      ? -reportValue(row['total']).abs()
                      : reportValue(row['total'])),
            );
  }

  Map<String, double> totals(String branch, DateTime start, DateTime end) {
    final selected = sales(branch, start, end);
    final history = rows(
      'budget_history',
    ).where((row) => row['staffId'] == branch).toList();
    final drawer =
        rows(
          'staff_cash_drawer',
        ).where((row) => row['_id'] == branch).firstOrNull ??
        {};
    final configured = reportValue(
      drawer['dailyOpeningCash'] ?? drawer['openingCash'],
    );
    final lastDay = end.subtract(const Duration(days: 1));
    double openingFor(DateTime day) {
      if (DateUtils.isSameDay(day, DateTime.now())) return configured;
      final reports =
          rows('daily_reports')
              .where(
                (row) =>
                    row['branchId'] == branch &&
                    DateUtils.isSameDay(
                      cashRecordDate(
                        row['reportDateKey'] ??
                            row['reportDate'] ??
                            row['createdAt'],
                      ),
                      day,
                    ),
              )
              .toList()
            ..sort(
              (a, b) => (cashRecordDate(b['createdAt']) ?? DateTime(0))
                  .compareTo(cashRecordDate(a['createdAt']) ?? DateTime(0)),
            );
      final saved = reports.firstOrNull;
      return saved?['openingCash'] != null || saved?['allocatedBudget'] != null
          ? reportValue(saved?['openingCash'] ?? saved?['allocatedBudget'])
          : branchDayTotals(day, history, [], configured)['Starting fund']!;
    }

    final closingDay = lastDay.isAfter(DateTime.now())
        ? DateUtils.dateOnly(DateTime.now())
        : lastDay;
    final closingRows = selected.where(
      (row) =>
          DateUtils.isSameDay(cashRecordDate(row['timestamp']), closingDay),
    );
    final cash = closingRows
        .where(
          (row) =>
              '${row['paymentMode'] ?? row['paymentMethod'] ?? 'Cash'}'
                  .toLowerCase() ==
              'cash',
        )
        .fold<double>(
          0,
          (sum, row) =>
              sum +
              (row['cashDrawerDelta'] != null
                  ? reportValue(row['cashDrawerDelta'])
                  : reportRefund(row)
                  ? -reportValue(row['total']).abs()
                  : reportValue(row['total'])),
        );
    return {
      'Starting fund': openingFor(start),
      'Total revenue': selected
          .where((row) => !reportRefund(row))
          .fold(0, (sum, row) => sum + reportValue(row['total'])),
      'Total cash drawer today': todayCashDrawer(branch),
      'Refunds': selected
          .where(reportRefund)
          .fold(0, (sum, row) => sum + reportValue(row['total']).abs()),
      'Reduce': losses(
        branch,
        start,
        end,
      ).fold(0, (sum, row) => sum + lossAmount(row)),
      'Total discount': selected
          .where((row) => !reportRefund(row))
          .fold<double>(0, (sum, row) => sum + reportValue(row['discount'])),
      'Total sold': selected
          .where((row) => !reportRefund(row))
          .fold<double>(
            0,
            (sum, sale) =>
                sum +
                (sale['items'] as List? ?? []).whereType<Map>().fold<double>(
                  0,
                  (sum, item) => sum + reportValue(item['quantity']),
                ),
          ),
      'Total transactions': selected
          .where((row) => !reportRefund(row))
          .length
          .toDouble(),
      'Closing cash drawer': openingFor(closingDay) + cash,
    };
  }

  Map<String, dynamic> resolveItem(Map raw, [String? sourceId]) {
    final item = Map<String, dynamic>.from(raw);
    final sources = [
      ...rows('sales_inventory'),
      ...rows('coffee_products'),
      ...rows('coffee_addons'),
    ];
    final identity =
        '${item['itemId'] ?? item['id'] ?? item['variantId'] ?? ''}';
    final source = sources
        .where(
          (row) =>
              row['_id'] == (sourceId ?? item['sourceInventoryId']) ||
              row['_id'] == identity,
        )
        .firstOrNull;
    final candidates = source == null ? sources : [source];
    for (final parent in candidates) {
      if (parent['isBundle'] == true) continue;
      final variants = [
        ...(parent['items'] as List? ?? []),
        ...(parent['removedItems'] as List? ?? []),
      ].whereType<Map>();
      final match = variants
          .where(
            (v) =>
                '${v['id']}' == identity ||
                (source != null &&
                    '${v['name']}' == '${item['variant'] ?? item['name']}'),
          )
          .firstOrNull;
      if (match != null)
        return {
          ...item,
          'publicId': match['publicId'] ?? match['id'],
          'name': match['name'] ?? item['variant'] ?? item['name'],
          'price': item['price'] ?? match['price'],
          'expirationDate': item['expirationDate'] ?? match['expirationDate'],
          'type': 'Categories',
        };
    }
    if (source != null &&
        (source['isBundle'] == true || source['items'] == null)) {
      return {
        ...item,
        'publicId':
            source['publicId'] ?? source['coffeeId'] ?? source['bundleId'],
        'name': source['name'],
        'price': item['price'] ?? source['price'],
        'expirationDate': item['expirationDate'] ?? source['expirationDate'],
        'sizes': source['sizes'],
        'basePrice': source['basePrice'],
        'type': source['isBundle'] == true
            ? 'Bundle'
            : rows(
                'coffee_addons',
              ).any((addon) => addon['_id'] == source['_id'])
            ? 'Add-ons'
            : 'Beverages',
      };
    }
    return {
      ...item,
      'name': '${item['variant'] ?? ''}'.trim().isNotEmpty
          ? item['variant']
          : item['name'] ?? 'Archived item',
      'type': item['isBundle'] == true
          ? 'Bundle'
          : item['isCoffee'] == true
          ? 'Beverages'
          : item['type'] ?? 'Categories',
    };
  }

  List<Map<String, dynamic>> items(
    String branch,
    DateTime start,
    DateTime end,
  ) {
    final result = <String, Map<String, dynamic>>{};
    Map<String, dynamic> ensure(Map raw, [String? source]) {
      final item = resolveItem(raw, source);
      final code = inventoryDisplayId(item);
      final key = code == '--' ? '${source ?? ''}/${item['name']}' : code;
      return result.putIfAbsent(
        key,
        () => {
          'id': code,
          'name': item['name'],
          'allocated': 0.0,
          'allocationSnapshot': 0.0,
          'relevant': false,
          'history': <Map<String, dynamic>>[],
          'sizeSales': <String, Map<String, dynamic>>{},
          'sold': 0.0,
          'sales': 0.0,
          'refund': 0.0,
          'reduce': 0.0,
          'price': reportValue(item['price']),
          'type': item['type'] ?? 'Categories',
          'status': 'Recorded',
          'expirationDate': item['expirationDate'],
          'sizes': item['sizes'],
          'basePrice': item['basePrice'],
          'remaining': null,
        },
      );
    }

    for (final row in rows('staff_inventory_history').where(
      (row) =>
          row['staffId'] == branch &&
          reportInRange(row['createdAt'], DateTime(1970), end),
    )) {
      final savedItems = (row['items'] as List? ?? []).whereType<Map>();
      if (savedItems.isNotEmpty) {
        for (final saved in savedItems) {
          if (reportValue(saved['quantity']) <= 0) continue;
          final item = ensure(saved, saved['sourceInventoryId']?.toString());
          if (reportInRange(row['createdAt'], start, end))
            item['relevant'] = true;
          item['allocated'] =
              reportValue(item['allocated']) + reportValue(saved['quantity']);
          (item['history'] as List).add({
            'time': cashRecordDate(row['createdAt']),
            'activity': 'Allocation',
            'qty': reportValue(saved['quantity']),
          });
        }
        continue;
      }
      final quantities = row['quantities'];
      if (quantities is! Map) continue;
      for (final entry in quantities.entries) {
        if (reportValue(entry.value) <= 0) continue;
        final parts = '${entry.key}'.split('::');
        final parent = rows(
          'sales_inventory',
        ).where((row) => row['_id'] == parts.first).firstOrNull;
        final index = int.tryParse(parts.last);
        final variants = (parent?['items'] as List? ?? [])
            .whereType<Map>()
            .toList();
        final legacy = index != null && index >= 0 && index < variants.length
            ? variants[index]
            : null;
        // Numeric keys in old history represent array positions, never item IDs.
        if (index != null && legacy == null) continue;
        final item = ensure(
          legacy ??
              {
                'id': parts.last,
                'name': parts.last == 'bundle'
                    ? (parent?['name'] ?? 'Bundle')
                    : parts.last,
              },
          parts.first,
        );
        item['allocated'] =
            reportValue(item['allocated']) + reportValue(entry.value);
        if (reportInRange(row['createdAt'], start, end))
          item['relevant'] = true;
        (item['history'] as List).add({
          'time': cashRecordDate(row['createdAt']),
          'activity': 'Allocation',
          'qty': reportValue(entry.value),
        });
      }
    }
    for (final row in rows(
      'staff_inventory',
    ).where((row) => row['staffId'] == branch)) {
      final at = cashRecordDate(row['assignedAt']);
      if (at != null && !at.isBefore(end)) continue;
      final variants =
          row['isBundle'] == true ||
              row['isCoffee'] == true ||
              row['isAddon'] == true
          ? [row]
          : (row['items'] as List?)?.whereType<Map>().toList() ?? [row];
      for (final variant in variants) {
        if (row['isCoffee'] != true &&
            row['isBundle'] != true &&
            row['isAddon'] != true &&
            reportValue(variant['stock'] ?? variant['startingStock']) <= 0 &&
            reportValue(
                  variant['assignedStartingStock'] ?? variant['startingStock'],
                ) <=
                0)
          continue;
        final expired = cashRecordDate(variant['expirationDate']);
        final removed = cashRecordDate(
          variant['deletedAt'] ?? variant['removedAt'] ?? row['deletedAt'],
        );
        final deleted =
            row['isDeleted'] == true || variant['isDeleted'] == true;
        if (expired != null && DateUtils.dateOnly(expired).isBefore(start))
          continue;
        if (removed != null && removed.isBefore(start)) continue;
        if (deleted && removed == null) continue;
        final source = [...rows('sales_inventory'), ...rows('coffee_products')]
            .where((source) => source['_id'] == row['sourceInventoryId'])
            .firstOrNull;
        if (source != null) {
          final sourceRemoved = cashRecordDate(source['deletedAt']);
          if (source['isDeleted'] == true &&
              (sourceRemoved == null || sourceRemoved.isBefore(start)))
            continue;
          if (row['isBundle'] != true && row['isCoffee'] != true) {
            final archived = (source['removedItems'] as List? ?? [])
                .whereType<Map>()
                .where((v) => v['id'] == variant['id'])
                .firstOrNull;
            final removedAt = cashRecordDate(archived?['removedAt']);
            if (archived != null &&
                (removedAt == null || removedAt.isBefore(start)))
              continue;
          }
        }
        final item = ensure(variant, '${row['sourceInventoryId'] ?? ''}');
        item['relevant'] = true;
        if (row['isAddon'] == true) item['type'] = 'Add-ons';
        if (!end.isBefore(
          DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1)),
        )) {
          final stock =
              variant['stock'] ??
              variant['bundleCount'] ??
              variant['startingStock'];
          if (stock != null)
            item['remaining'] =
                reportValue(item['remaining']) + reportValue(stock);
        }
        item['status'] = deleted && removed != null && removed.isBefore(end)
            ? 'Archived'
            : expired != null && expired.isBefore(end)
            ? 'Expired'
            : 'Available';
        if (at != null) {
          item['allocationSnapshot'] =
              reportValue(item['allocationSnapshot']) +
              reportValue(
                variant['assignedStartingStock'] ??
                    variant['startingStock'] ??
                    row['assignedStartingStock'] ??
                    variant['bundleCount'] ??
                    variant['stock'],
              );
        }
      }
    }
    for (final sale in sales(branch, DateTime(1970), end)) {
      for (final raw in (sale['items'] as List? ?? []).whereType<Map>()) {
        final item = ensure(raw);
        final refund = reportRefund(sale);
        final qty = reportValue(raw['quantity']).abs();
        (item['history'] as List).add({
          'time': cashRecordDate(sale['timestamp'] ?? sale['createdAt']),
          'activity': refund
              ? (sale['refundMethod'] == 'inventory'
                    ? 'Inventory replacement'
                    : 'Cash refund')
              : 'Sold',
          'qty': refund && sale['refundMethod'] != 'inventory' ? 0.0 : -qty,
        });
        if (!reportInRange(sale['timestamp'] ?? sale['createdAt'], start, end))
          continue;
        item['relevant'] = true;
        if (!refund && item['type'] == 'Beverages') {
          final size = '${raw['coffeeSize'] ?? raw['variant'] ?? 'Regular'}';
          final price = reportValue(raw['price'] ?? raw['unitPrice']);
          final sizes = item['sizeSales'] as Map<String, Map<String, dynamic>>;
          final detail = sizes.putIfAbsent(
            '$size|$price',
            () => {'size': size, 'sold': 0.0, 'price': price, 'sales': 0.0},
          );
          detail['sold'] = reportValue(detail['sold']) + qty;
          detail['sales'] = reportValue(detail['sales']) + qty * price;
        }
        final field = refund ? 'refund' : 'sold';
        item[field] =
            reportValue(item[field]) + reportValue(raw['quantity']).abs();
        if (field == 'sold') {
          item['sales'] =
              reportValue(item['sales']) +
              reportValue(raw['quantity']).abs() *
                  reportValue(
                    raw['price'] ?? raw['unitPrice'] ?? item['price'],
                  );
        }
      }
    }
    for (final loss in losses(branch, DateTime(1970), end)) {
      if (reportValue(loss['quantity']) <= 0) continue;
      final allocation = rows(
        'staff_inventory',
      ).where((row) => row['_id'] == loss['categoryId']).firstOrNull;
      final item = ensure({
        'id': loss['itemId'] ?? loss['variantId'],
        'name': loss['itemName'] ?? loss['categoryName'],
        'price': loss['unitPrice'],
        'isBundle':
            allocation?['isBundle'] == true ||
            '${loss['type']}'.contains('bundle'),
        'isCoffee':
            allocation?['isCoffee'] == true ||
            '${loss['type']}'.contains('coffee'),
      }, loss['sourceInventoryId'] ?? allocation?['sourceInventoryId']);
      (item['history'] as List).add({
        'time': cashRecordDate(loss['createdAt'] ?? loss['timestamp']),
        'activity': 'Reduce',
        'qty': -reportValue(loss['quantity']),
      });
      if (!reportInRange(loss['createdAt'] ?? loss['timestamp'], start, end))
        continue;
      item['relevant'] = true;
      item['reduce'] =
          reportValue(item['reduce']) + reportValue(loss['quantity']);
    }
    for (final item in result.values) {
      final events = (item['history'] as List).cast<Map<String, dynamic>>()
        ..sort(
          (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime),
        );
      final missing =
          reportValue(item['allocationSnapshot']) -
          reportValue(item['allocated']);
      var balance = missing > 0 ? missing : 0.0;
      if (missing > 0)
        item['allocated'] = reportValue(item['allocationSnapshot']);
      final visible = <Map<String, dynamic>>[];
      var firstAllocation = balance == 0;
      for (final event in events) {
        if ((event['time'] as DateTime).isBefore(start)) {
          balance += reportValue(event['qty']);
          if (event['activity'] == 'Allocation') firstAllocation = false;
          continue;
        }
        if (visible.isEmpty && balance != 0) {
          visible.add({
            'time': null,
            'activity': missing > 0
                ? 'Starting allocation (saved balance)'
                : 'Opening balance',
            'qty': balance,
            'balance': balance,
          });
        }
        balance += reportValue(event['qty']);
        visible.add({
          ...event,
          'activity': event['activity'] == 'Allocation'
              ? (firstAllocation
                    ? 'Starting Allocation'
                    : 'Additional Allocation')
              : event['activity'],
          'balance': balance,
        });
        if (event['activity'] == 'Allocation') firstAllocation = false;
      }
      if (visible.isEmpty && balance != 0)
        visible.add({
          'time': null,
          'activity': 'Opening balance',
          'qty': balance,
          'balance': balance,
        });
      item['history'] = visible;
      if (reportValue(item['allocated']) == 0) {
        visible.removeWhere((event) => event['time'] == null);
        for (final event in visible) {
          event['balance'] = null;
        }
      }
    }
    return result.values.where((item) => item['relevant'] == true).toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  }
}

/// Receipt counts for the selected report scope, including refund receipts.
Map<String, int> receiptCounts(List<Map<String, dynamic>> sales) => {
  'All': sales.length,
  'Cash': sales
      .where(
        (row) =>
            '${row['paymentMode'] ?? row['paymentMethod'] ?? 'Cash'}'
                .toLowerCase() ==
            'cash',
      )
      .length,
  'GCash': sales
      .where(
        (row) =>
            '${row['paymentMode'] ?? row['paymentMethod'] ?? ''}'
                .toLowerCase() ==
            'gcash',
      )
      .length,
  'Discounted': sales
      .where((row) => !reportRefund(row) && reportValue(row['discount']) > 0)
      .length,
};
