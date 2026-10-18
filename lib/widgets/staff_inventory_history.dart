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

List<Map<String, dynamic>> staffInventoryHistoryEntries({
  required String staffId,
  required String kind,
  required String categoryId,
  required String categoryName,
  required Set<String> itemIds,
  required Set<String> itemNames,
  required Iterable<Map<String, dynamic>> adjustments,
  required Iterable<Map<String, dynamic>> sales,
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

  bool belongsToItem(Map row) {
    final identifiers =
        [
              row['itemId'],
              row['id'],
              row['publicId'],
              row['coffeeId'],
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
  });

  final FirebaseFirestore db;
  final String staffId;
  final String kind;
  final String categoryId;
  final String categoryName;
  final Set<String> itemIds;
  final Set<String> itemNames;

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
              stream: widget.db.collection('stock_adjustments').snapshots(),
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
                  stream: widget.db.collection('completed_sales').snapshots(),
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
                    final entries =
                        staffInventoryHistoryEntries(
                          staffId: widget.staffId,
                          kind: widget.kind,
                          categoryId: widget.categoryId,
                          categoryName: widget.categoryName,
                          itemIds: widget.itemIds,
                          itemNames: widget.itemNames,
                          adjustments: adjustmentsSnapshot.data!.docs.map(
                            (doc) => doc.data(),
                          ),
                          sales: salesSnapshot.data!.docs.map(
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
                    final soldTotal = entries
                        .where((entry) => entry['activity'] == 'Sold')
                        .fold<int>(
                          0,
                          (total, entry) =>
                              total + _historyQuantity(entry['quantity']),
                        );
                    final refundTotal = entries
                        .where((entry) => entry['activity'] == 'Refund')
                        .fold<int>(
                          0,
                          (total, entry) =>
                              total + _historyQuantity(entry['quantity']),
                        );
                    final reducedTotal = entries
                        .where((entry) => entry['activity'] == 'Reduce')
                        .fold<int>(
                          0,
                          (total, entry) =>
                              total + _historyQuantity(entry['quantity']),
                        );
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _totalChip(
                                'Sold',
                                soldTotal,
                                Icons.point_of_sale,
                              ),
                              _totalChip(
                                'Reduced',
                                reducedTotal,
                                Icons.remove_circle_outline,
                              ),
                              _totalChip(
                                'Refunded',
                                refundTotal,
                                Icons.undo_rounded,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: entries.isEmpty
                              ? Center(
                                  child: Text(
                                    search.isEmpty
                                        ? 'No sold or reduced items in this date range.'
                                        : 'No matching sold or reduced items.',
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
