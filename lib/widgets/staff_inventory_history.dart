import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/number_format.dart';

DateTime? _historyDate(dynamic value) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse('$value')?.toLocal();
}

int _historyQuantity(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

List<Map> _historyMapRows(dynamic value) =>
    value is Iterable ? value.whereType<Map>().toList() : const [];

List<Map<String, dynamic>> staffInventoryHistoryEntries({
  required String staffId,
  required String kind,
  required String categoryId,
  required String categoryName,
  required Set<String> itemIds,
  required Set<String> itemNames,
  required Iterable<Map<String, dynamic>> adjustments,
  required Iterable<Map<String, dynamic>> sales,
  Set<String> scopeIds = const {},
  Iterable<Map<String, dynamic>> reconciliations = const [],
  Iterable<Map<String, dynamic>> returns = const [],
}) {
  final result = <Map<String, dynamic>>[];
  final normalizedIds = itemIds
      .map((value) => value.trim())
      .where((v) => v.isNotEmpty)
      .toSet();
  final normalizedNames = itemNames
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  final staffScope = {staffId, ...scopeIds};

  bool belongsToItem(Map row) {
    final identifiers =
        [
              row['itemId'],
              row['id'],
              row['publicId'],
              row['coffeeId'],
              row['addonId'],
              row['variantId'],
              row['sourceInventoryId'],
            ]
            .map((value) => '${value ?? ''}'.trim())
            .where((value) => value.isNotEmpty);
    final rowIds = identifiers.toSet();
    final name = '${row['itemName'] ?? row['name'] ?? ''}'.trim().toLowerCase();
    if (normalizedIds.isEmpty && normalizedNames.isEmpty) return true;
    return rowIds.intersection(normalizedIds).isNotEmpty ||
        (name.isNotEmpty && normalizedNames.contains(name));
  }

  bool isRelevantAdjustment(Map<String, dynamic> row) {
    if (row['staffId'] != staffId && row['userId'] != staffId) return false;
    final type = '${row['type'] ?? ''}'.toLowerCase();
    if (kind == 'addons') {
      if (type != 'addon_void') return false;
      return belongsToItem(row);
    }
    if (kind == 'bundle') {
      if (type != 'bundle_stock_adjustment' &&
          type != 'bundle_instance_adjustment') {
        return false;
      }
      return (categoryId.isNotEmpty &&
              '${row['categoryId'] ?? ''}' == categoryId) ||
          belongsToItem(row);
    }
    if (kind == 'beverages') {
      if (type != 'coffee_void') return false;
      return (categoryId.isNotEmpty &&
              '${row['categoryId'] ?? ''}' == categoryId) ||
          belongsToItem(row);
    }
    if (type == 'coffee_void' ||
        type == 'addon_void' ||
        type == 'bundle_stock_adjustment' ||
        type == 'bundle_instance_adjustment') {
      return false;
    }
    final categoryMatches =
        categoryId.isNotEmpty && '${row['categoryId'] ?? ''}' == categoryId;
    return categoryMatches || belongsToItem(row);
  }

  for (final row in adjustments.where(isRelevantAdjustment)) {
    final date = _historyDate(row['createdAt'] ?? row['timestamp']);
    if (date == null) continue;
    final quantity = _historyQuantity(row['quantity']);
    if (quantity <= 0) continue;
    result.add({
      'activity': 'Reduce',
      'name': row['itemName'] ?? row['categoryName'] ?? categoryName,
      'itemId':
          row['itemId'] ?? row['coffeeId'] ?? row['bundleInstanceId'] ?? '',
      'quantity': quantity,
      'price': row['unitPrice'] ?? row['bundlePrice'] ?? 0,
      'reason': row['reason'] ?? 'Stock reduction',
      'comment': row['comment'] ?? '',
      'date': date,
    });
  }

  if (kind == 'bundle') {
    for (final row in reconciliations) {
      if ((!staffScope.contains('${row['staffId']}') &&
              row['submittedBy'] != staffId) ||
          !['convert', 'unbundle'].contains('${row['action']}')) {
        continue;
      }
      final date = _historyDate(row['reviewedAt'] ?? row['createdAt']);
      if (date == null) continue;
      final quantity = _historyQuantity(row['quantity']);
      if (quantity <= 0) continue;
      result.add({
        'activity': row['action'] == 'unbundle' ? 'Unbundled' : 'Converted',
        'name': row['name'] ?? categoryName,
        'itemId': row['allocationId'] ?? '',
        'quantity': quantity,
        'price': 0,
        'reason':
            '${row['status'] ?? ''} ${row['targetSnapshot'] is Map ? (row['targetSnapshot'] as Map)['name'] ?? '' : ''}',
        'comment': '',
        'date': date,
      });
    }
    for (final row in returns) {
      if ((!staffScope.contains('${row['staffId']}') &&
              row['submittedBy'] != staffId) ||
          row['kind'] != 'return' ||
          row['isBundle'] != true ||
          row['returnSourceCollection'] != 'staff_inventory') {
        continue;
      }
      final date = _historyDate(row['createdAt'] ?? row['updatedAt']);
      if (date == null) continue;
      final quantity = _historyQuantity(row['quantity']);
      if (quantity <= 0) continue;
      result.add({
        'activity': 'Returned',
        'name': row['name'] ?? categoryName,
        'itemId': row['returnSourceId'] ?? '',
        'quantity': quantity,
        'price': row['unitPrice'] ?? 0,
        'reason': row['reason'] ?? 'Return request',
        'comment': '${row['status'] ?? ''}',
        'date': date,
      });
    }
  }

  for (final sale in sales) {
    if (sale['userId'] != staffId || sale['isVoided'] == true) continue;
    final saleType = '${sale['type'] ?? 'sale'}'.toLowerCase();
    final saleStatus = '${sale['status'] ?? ''}'.toLowerCase();
    if (['void', 'voided', 'cancelled', 'canceled'].contains(saleStatus)) {
      continue;
    }
    final date = _historyDate(sale['timestamp'] ?? sale['createdAt']);
    if (date == null) continue;
    final refund = saleType == 'refund' || saleStatus == 'refund';
    for (final raw in (sale['items'] as List? ?? const []).whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final isBundle = item['isBundle'] == true;
      final isCoffee = item['isCoffee'] == true;
      if (kind == 'addons') {
        final addonRows = [
          ..._historyMapRows(item['addons']),
          ..._historyMapRows(item['addOns']),
          ..._historyMapRows(item['selectedAddons']),
        ];
        for (final rawAddon in addonRows) {
          final addon = Map<String, dynamic>.from(rawAddon);
          if (!belongsToItem(addon)) continue;
          final quantity =
              _historyQuantity(addon['quantity'] ?? addon['count'] ?? 1) *
              _historyQuantity(item['quantity'] ?? 1);
          if (quantity <= 0) continue;
          result.add({
            'activity': refund ? 'Refund' : 'Sold',
            'name': addon['name'] ?? categoryName,
            'itemId': addon['addonId'] ?? addon['itemId'] ?? addon['id'] ?? '',
            'quantity': quantity,
            'price': addon['priceDelta'] ?? addon['price'] ?? 0,
            'reason': sale['salesId'] ?? 'Sale',
            'comment': '',
            'date': date,
          });
        }
        final variantAddonName = '${item['addonName'] ?? ''}'.trim();
        if (addonRows.isEmpty && variantAddonName.isNotEmpty) {
          final addon = {
            'name': variantAddonName,
            'addonId': item['addonId'] ?? item['addonItemId'],
          };
          if (belongsToItem(addon)) {
            result.add({
              'activity': refund ? 'Refund' : 'Sold',
              'name': variantAddonName,
              'itemId': addon['addonId'] ?? '',
              'quantity': _historyQuantity(item['quantity'] ?? 1),
              'price': item['addonPriceDelta'] ?? 0,
              'reason': sale['salesId'] ?? 'Sale',
              'comment': '',
              'date': date,
            });
          }
        }
        continue;
      }
      if (kind == 'bundle' && !isBundle) continue;
      if (kind == 'beverages' && !isCoffee) continue;
      if (kind == 'categories' && (isBundle || isCoffee)) continue;
      if (!belongsToItem(item)) {
        final sourceMatches =
            categoryId.isNotEmpty &&
            [
              item['sourceInventoryId'],
              item['categoryId'],
              item['category'],
            ].any((value) => '${value ?? ''}' == categoryId);
        final nameMatches = normalizedNames.contains(
          '${item['name'] ?? ''}'.trim().toLowerCase(),
        );
        if (!sourceMatches && !nameMatches) continue;
      }
      final quantity = _historyQuantity(item['quantity'] ?? 1);
      if (quantity <= 0) continue;
      result.add({
        'activity': refund ? 'Refund' : 'Sold',
        'name': item['name'] ?? categoryName,
        'itemId': item['itemId'] ?? item['coffeeId'] ?? item['publicId'] ?? '',
        'quantity': quantity,
        'price': item['price'] ?? 0,
        'reason': sale['salesId'] ?? 'Sale',
        'comment': '',
        'date': date,
      });
    }
  }

  result.sort(
    (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
  );
  return result;
}

Future<void> showStaffInventoryHistory(
  BuildContext context, {
  required String staffId,
  required String kind,
  required String categoryId,
  required String categoryName,
  Set<String> itemIds = const {},
  Set<String> itemNames = const {},
  Set<String> scopeIds = const {},
  FirebaseFirestore? database,
}) => showDialog<void>(
  context: context,
  builder: (_) => _StaffInventoryHistoryDialog(
    db: database ?? FirebaseFirestore.instance,
    staffId: staffId,
    kind: kind,
    categoryId: categoryId,
    categoryName: categoryName,
    itemIds: itemIds,
    itemNames: itemNames,
    scopeIds: scopeIds,
  ),
);

class _StaffInventoryHistoryDialog extends StatefulWidget {
  const _StaffInventoryHistoryDialog({
    required this.db,
    required this.staffId,
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.itemIds,
    required this.itemNames,
    required this.scopeIds,
  });

  final FirebaseFirestore db;
  final String staffId;
  final String kind;
  final String categoryId;
  final String categoryName;
  final Set<String> itemIds;
  final Set<String> itemNames;
  final Set<String> scopeIds;

  @override
  State<_StaffInventoryHistoryDialog> createState() =>
      _StaffInventoryHistoryDialogState();
}

class _StaffInventoryHistoryDialogState
    extends State<_StaffInventoryHistoryDialog> {
  late final DateTimeRange dateRange = DateTimeRange(
    start: DateUtils.dateOnly(DateTime.now()),
    end: DateUtils.dateOnly(DateTime.now()),
  );
  late DateTimeRange selectedRange = dateRange;
  String search = '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> reconciliationStream =
      widget.db
          .collection('inventory_reconciliations')
          .where(
            'staffId',
            whereIn: widget.scopeIds.isEmpty
                ? [widget.staffId]
                : widget.scopeIds.take(30).toList(),
          )
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> adjustmentStream =
      widget.db
          .collection('stock_adjustments')
          .where('userId', isEqualTo: widget.staffId)
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> salesStream = widget.db
      .collection('completed_sales')
      .where('userId', isEqualTo: widget.staffId)
      .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> returnStream = widget
      .db
      .collection('allocation_checklist')
      .where(
        'staffId',
        whereIn: widget.scopeIds.isEmpty
            ? [widget.staffId]
            : widget.scopeIds.take(30).toList(),
      )
      .snapshots();

  String dayLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> selectDateRange() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: selectedRange,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(
        () => selectedRange = DateTimeRange(
          start: DateUtils.dateOnly(picked.start),
          end: DateUtils.dateOnly(picked.end),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDeep, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${widget.categoryName} History',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close history',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) =>
                        setState(() => search = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search sold, reduce, item, ID, reason, date',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primaryDark,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Filter by date range',
                        onPressed: selectDateRange,
                        icon: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceTint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${dayLabel(selectedRange.start)} – ${dayLabel(selectedRange.end)}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selectedRange.start != dateRange.start ||
                    selectedRange.end != dateRange.end)
                  TextButton(
                    onPressed: () => setState(() => selectedRange = dateRange),
                    child: const Text('Today'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: adjustmentStream,
              builder: (context, adjustmentsSnapshot) {
                if (adjustmentsSnapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load inventory history.'),
                  );
                }
                if (!adjustmentsSnapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryDark,
                    ),
                  );
                }
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: salesStream,
                  builder: (context, salesSnapshot) {
                    if (salesSnapshot.hasError) {
                      return const Center(
                        child: Text('Unable to load sales history.'),
                      );
                    }
                    if (!salesSnapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryDark,
                        ),
                      );
                    }
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: reconciliationStream,
                      builder: (context, reconciliationSnapshot) {
                        if (!reconciliationSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryDark,
                            ),
                          );
                        }
                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: returnStream,
                          builder: (context, returnSnapshot) {
                            if (!returnSnapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryDark,
                                ),
                              );
                            }
                            final entries =
                                staffInventoryHistoryEntries(
                                  staffId: widget.staffId,
                                  scopeIds: widget.scopeIds,
                                  kind: widget.kind,
                                  categoryId: widget.categoryId,
                                  categoryName: widget.categoryName,
                                  itemIds: widget.itemIds,
                                  itemNames: widget.itemNames,
                                  adjustments: adjustmentsSnapshot.data!.docs
                                      .map((doc) => doc.data()),
                                  sales: salesSnapshot.data!.docs.map(
                                    (doc) => doc.data(),
                                  ),
                                  reconciliations: reconciliationSnapshot
                                      .data!
                                      .docs
                                      .map((doc) => doc.data()),
                                  returns: returnSnapshot.data!.docs.map(
                                    (doc) => doc.data(),
                                  ),
                                ).where((entry) {
                                  final date = entry['date'] as DateTime;
                                  final day = DateUtils.dateOnly(date);
                                  if (day.isBefore(selectedRange.start) ||
                                      day.isAfter(selectedRange.end)) {
                                    return false;
                                  }
                                  if (search.isEmpty) return true;
                                  final text = [
                                    entry['activity'],
                                    entry['name'],
                                    entry['itemId'],
                                    entry['reason'],
                                    entry['comment'],
                                    entry['quantity'],
                                    entry['price'],
                                    dayLabel(date),
                                  ].join(' ').toLowerCase();
                                  return text.contains(search);
                                }).toList();
                            final totals = <String, int>{};
                            for (final entry in entries) {
                              final activity = '${entry['activity']}';
                              totals[activity] =
                                  (totals[activity] ?? 0) +
                                  _historyQuantity(entry['quantity']);
                            }
                            return Column(
                              children: [
                                if (search.isNotEmpty && totals.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      10,
                                    ),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (final entry
                                              in totals.entries.indexed) ...[
                                            if (entry.$1 > 0)
                                              const SizedBox(width: 8),
                                            _totalChip(
                                              entry.$2.key == 'Refund'
                                                  ? 'Refunded'
                                                  : entry.$2.key == 'Reduce'
                                                  ? 'Reduced'
                                                  : entry.$2.key,
                                              entry.$2.value,
                                              switch (entry.$2.key) {
                                                'Sold' => Icons.point_of_sale,
                                                'Refund' => Icons.undo_rounded,
                                                'Reduce' =>
                                                  Icons.remove_circle_outline,
                                                'Unbundled' =>
                                                  Icons.call_split_rounded,
                                                'Converted' =>
                                                  Icons.autorenew_rounded,
                                                'Returned' =>
                                                  Icons
                                                      .assignment_return_rounded,
                                                _ => Icons.history_rounded,
                                              },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: entries.isEmpty
                                      ? Center(
                                          child: Text(
                                            search.isEmpty
                                                ? 'No history found Today'
                                                : 'No matching history found.',
                                            style: const TextStyle(
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        )
                                      : ListView.separated(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            2,
                                            16,
                                            16,
                                          ),
                                          itemCount: entries.length,
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(height: 9),
                                          itemBuilder: (context, index) =>
                                              _historyCard(entries[index]),
                                        ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _totalChip(String label, int quantity, IconData icon) => Chip(
    avatar: Icon(icon, size: 17, color: AppColors.primaryDark),
    label: Text('$label: $quantity'),
    backgroundColor: AppColors.blush,
    side: BorderSide.none,
    labelStyle: const TextStyle(
      color: AppColors.primaryDeep,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _historyCard(Map<String, dynamic> entry) {
    final date = entry['date'] as DateTime;
    final activity = '${entry['activity']}';
    final color = activity == 'Sold'
        ? const Color(0xFF27834A)
        : activity == 'Refund'
        ? const Color(0xFFBA6B00)
        : AppColors.primaryDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.blush),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry['name'] ?? widget.categoryName}',
                  style: const TextStyle(
                    color: AppColors.primaryDeep,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${activity == 'Reduce'
                    ? '-'
                    : activity == 'Refund'
                    ? '−'
                    : '+'}${entry['quantity']}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '$activity • ${formatMoney(num.tryParse('${entry['price']}') ?? 0)} • ${dayLabel(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ('${entry['reason'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${activity == 'Reduce' ? 'Reason' : 'Receipt'}: ${entry['reason']}',
                style: const TextStyle(color: AppColors.text),
              ),
            ),
          if ('${entry['comment'] ?? ''}'.isNotEmpty)
            Text(
              'Note: ${entry['comment']}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}
