import 'branch_report_data.dart';
import 'bundle_stock_service.dart';
import 'inventory_display_ids.dart';
import '../widgets/historical_cash_drawer.dart';

bool currentAllocationAvailable(Map row, DateTime now) {
  if (row['isDeleted'] == true ||
      row['isVoided'] == true ||
      row['isAvailable'] == false ||
      row['available'] == false) {
    return false;
  }
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
        !currentAllocationAvailable(allocation, now)) {
      continue;
    }
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
          )) {
        continue;
      }
      final sourceItem = variants
          .where((s) => s['id'] == item['id'])
          .firstOrNull;
      if (sourceItem != null && !currentAllocationAvailable(sourceItem, now)) {
        continue;
      }
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

/// Cash is a reusable branch fund, not a daily expense. Use one configured
/// balance per branch as of the selected period's end (capped at today).
Map<String, double> configuredReportCash(
  BranchReportData data,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  final todayEnd = DateTime(now.year, now.month, now.day + 1);
  final cutoff = end.isBefore(todayEnd) ? end : todayEnd;
  final includesToday = !end.isBefore(todayEnd) && start.isBefore(todayEnd);
  final result = <String, double>{};
  for (final branch in data.rows('branches')) {
    if (branch['isDeleted'] == true || branch['isVoided'] == true) continue;
    final id = '${branch['_id']}';
    final drawer =
        data
            .rows('staff_cash_drawer')
            .where((r) => r['_id'] == id)
            .firstOrNull ??
        {};
    final history =
        data
            .rows('budget_history')
            .where(
              (r) =>
                  (r['branchId'] ?? r['staffId']) == id &&
                  (cashRecordDate(
                        r['createdAt'] ?? r['timestamp'],
                      )?.isBefore(cutoff) ??
                      false),
            )
            .toList()
          ..sort(
            (a, b) => cashRecordDate(
              a['createdAt'] ?? a['timestamp'],
            )!.compareTo(cashRecordDate(b['createdAt'] ?? b['timestamp'])!),
          );
    final configured = history
        .where((r) => r['type'] == 'set_daily_cash_drawer')
        .lastOrNull;
    final reports =
        data
            .rows('daily_reports')
            .where(
              (r) =>
                  r['branchId'] == id &&
                  (cashRecordDate(
                        r['reportDateKey'] ?? r['reportDate'] ?? r['createdAt'],
                      )?.isBefore(cutoff) ??
                      false),
            )
            .toList()
          ..sort(
            (a, b) =>
                cashRecordDate(
                  a['reportDateKey'] ?? a['reportDate'] ?? a['createdAt'],
                )!.compareTo(
                  cashRecordDate(
                    b['reportDateKey'] ?? b['reportDate'] ?? b['createdAt'],
                  )!,
                ),
          );
    result[id] =
        includesToday &&
            (drawer['dailyOpeningCash'] ?? drawer['openingCash']) != null
        ? reportValue(drawer['dailyOpeningCash'] ?? drawer['openingCash'])
        : configured != null
        ? reportValue(configured['amount'] ?? configured['budget'])
        : reports.isNotEmpty
        ? reportValue(
            reports.last['openingCash'] ?? reports.last['allocatedBudget'],
          )
        : history.isNotEmpty
        ? reportValue(history.first['amount'] ?? history.first['budget'])
        : 0;
  }
  return result;
}
