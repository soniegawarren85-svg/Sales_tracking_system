import 'branch_report_data.dart';
import 'bundle_stock_service.dart';
import 'inventory_display_ids.dart';
import '../widgets/historical_cash_drawer.dart';

bool currentAllocationAvailable(Map row, DateTime now) {
  if (row['isDeleted'] == true ||
      row['isVoided'] == true ||
      row['isAvailable'] == false ||
      row['available'] == false)
    return false;
  final expiry = cashRecordDate(row['expirationDate'] ?? row['expiryDate']);
  return expiry == null ||
      now.isBefore(DateTime(expiry.year, expiry.month, expiry.day + 1));
}

List<Map<String, dynamic>> currentReportAllocations(
  BranchReportData data,
  DateTime now,
) {
  final branches = {
    for (final b
        in data
            .rows('branches')
            .where((b) => b['isVoided'] != true && b['isDeleted'] != true))
      '${b['_id']}': b,
  };
  final result = <Map<String, dynamic>>[];
  for (final allocation in data.rows('staff_inventory')) {
    final branchId = '${allocation['branchId'] ?? allocation['staffId']}';
    if (!branches.containsKey(branchId) ||
        !currentAllocationAvailable(allocation, now))
      continue;
    final source = [
      ...data.rows('sales_inventory'),
      ...data.rows('coffee_products'),
      ...data.rows('coffee_addons'),
    ].where((s) => s['_id'] == allocation['sourceInventoryId']).firstOrNull;
    if (source != null && !currentAllocationAvailable(source, now)) continue;
    final standalone =
        allocation['isBundle'] == true ||
        allocation['isCoffee'] == true ||
        allocation['isAddon'] == true;
    final entries = standalone
        ? [allocation]
        : (allocation['items'] as List? ?? []).whereType<Map>();
    for (final item in entries) {
      if (!currentAllocationAvailable(item, now)) continue;
      final resolved = data.resolveItem(
        item,
        allocation['sourceInventoryId']?.toString(),
      );
      final variants = (source?['items'] as List? ?? []).whereType<Map>();
      if (!standalone &&
          (source?['removedItems'] as List? ?? []).whereType<Map>().any(
            (removed) => removed['id'] == item['id'],
          ))
        continue;
      final sourceItem = variants
          .where((s) => s['id'] == item['id'])
          .firstOrNull;
      if (sourceItem != null && !currentAllocationAvailable(sourceItem, now))
        continue;
      final madeToOrder =
          (allocation['isCoffee'] == true || allocation['isAddon'] == true) &&
          item['stock'] == null &&
          item['startingStock'] == null;
      final quantity = allocation['isBundle'] == true
          ? availableBundleStock(allocation, now: now).toDouble()
          : reportValue(
              item['stock'] ?? item['bundleCount'] ?? item['startingStock'],
            );
      result.add({
        'id': inventoryDisplayId(resolved),
        'name': resolved['name'],
        'branchId': branchId,
        'branch': branches[branchId]!['name'] ?? branchId,
        'type': allocation['isAddon'] == true ? 'Add-ons' : resolved['type'],
        'remaining': madeToOrder ? 'Made to order' : quantity.toInt(),
        'quantity': quantity,
        'madeToOrder': madeToOrder,
      });
    }
  }
  return result;
}

/// Each day uses its last configured opening fund, plus that day's additions.
Map<String, double> configuredReportCash(
  BranchReportData data,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  final result = <String, double>{};
  final today = DateTime(now.year, now.month, now.day);
  for (final branch in data.rows('branches')) {
    final id = '${branch['_id']}';
    final history = data
        .rows('budget_history')
        .where((r) => (r['branchId'] ?? r['staffId']) == id)
        .toList();
    final drawer =
        data
            .rows('staff_cash_drawer')
            .where((r) => r['_id'] == id)
            .firstOrNull ??
        {};
    var total = 0.0;
    for (
      var day = start;
      day.isBefore(end) && !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final next = DateTime(day.year, day.month, day.day + 1);
      final settings =
          history
              .where(
                (r) =>
                    r['type'] == 'set_daily_cash_drawer' &&
                    (cashRecordDate(
                          r['createdAt'] ?? r['timestamp'],
                        )?.isBefore(next) ??
                        false),
              )
              .toList()
            ..sort(
              (a, b) => cashRecordDate(
                a['createdAt'] ?? a['timestamp'],
              )!.compareTo(cashRecordDate(b['createdAt'] ?? b['timestamp'])!),
            );
      final reports = data
          .rows('daily_reports')
          .where(
            (r) =>
                r['branchId'] == id &&
                reportInRange(
                  r['reportDateKey'] ?? r['reportDate'] ?? r['createdAt'],
                  day,
                  next,
                ),
          )
          .toList();
      final earliestAllocation =
          history
              .map((r) => cashRecordDate(r['createdAt'] ?? r['timestamp']))
              .whereType<DateTime>()
              .toList()
            ..sort();
      final initializedByAllocation =
          settings.isEmpty &&
          reports.isEmpty &&
          earliestAllocation.isNotEmpty &&
          !earliestAllocation.first.isBefore(day) &&
          earliestAllocation.first.isBefore(next);
      total += initializedByAllocation
          ? 0
          : day == today &&
                (drawer['dailyOpeningCash'] != null ||
                    drawer['openingCash'] != null)
          ? reportValue(drawer['dailyOpeningCash'] ?? drawer['openingCash'])
          : settings.isNotEmpty
          ? reportValue(settings.last['amount'] ?? settings.last['budget'])
          : reports.isNotEmpty
          ? reportValue(
              reports.last['openingCash'] ?? reports.last['allocatedBudget'],
            )
          : day == today
          ? reportValue(drawer['dailyOpeningCash'] ?? drawer['openingCash'])
          : 0;
      total += history
          .where(
            (r) =>
                r['type'] != 'set_daily_cash_drawer' &&
                reportInRange(r['createdAt'] ?? r['timestamp'], day, next),
          )
          .fold<double>(
            0,
            (sum, r) => sum + reportValue(r['amount'] ?? r['budget']),
          );
    }
    result[id] = total;
  }
  return result;
}
