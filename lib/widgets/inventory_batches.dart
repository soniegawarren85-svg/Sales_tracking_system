import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../services/allocation_checklist_service.dart';
import '../services/bundle_stock_service.dart';
import '../services/inventory_reconciliation_service.dart';
import '../services/session_actor.dart';
import '../services/number_format.dart';
import '../services/sale_stock.dart';
import '../services/local_database_sync_service.dart';

Future<void> showMainInventoryBatches(
  BuildContext context,
  Map<String, dynamic> item,
) => showDialog<void>(
  context: context,
  builder: (_) => _MainInventoryBatchesDialog(item: item),
);

class _MainInventoryBatchesDialog extends StatefulWidget {
  const _MainInventoryBatchesDialog({required this.item});

  final Map<String, dynamic> item;

  @override
  State<_MainInventoryBatchesDialog> createState() =>
      _MainInventoryBatchesDialogState();
}

class _MainInventoryBatchesDialogState
    extends State<_MainInventoryBatchesDialog> {
  final _searchController = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _date(dynamic value) => value is Timestamp
      ? value.toDate().toLocal()
      : value is DateTime
      ? value.toLocal()
      : DateTime.tryParse('$value')?.toLocal();

  String _dateLabel(dynamic value) {
    final date = _date(value);
    if (date == null) return 'Date not recorded';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDateRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 5),
      initialDateRange: _dateRange ?? DateTimeRange(start: today, end: today),
    );
    if (range != null && mounted) setState(() => _dateRange = range);
  }

  @override
  Widget build(BuildContext context) {
    final storedBatches = (widget.item['stockBatches'] as List? ?? [])
        .whereType<Map>()
        .map((batch) => Map<String, dynamic>.from(batch))
        .toList();
    final legacyStock =
        (num.tryParse(
                  '${widget.item['stock'] ?? widget.item['startingStock'] ?? 0}',
                ) ??
                0)
            .toInt();
    final batches = storedBatches.isEmpty && legacyStock > 0
        ? [
            {
              'quantity': legacyStock,
              'createdAt': widget.item['createdAt'],
              'expirationDate': widget.item['expirationDate'] ?? '',
            },
          ]
        : storedBatches;
    final query = _searchController.text.trim().toLowerCase();
    final filteredBatches = [
      for (var index = 0; index < batches.length; index++)
        if (_matches(batches[index], index, query)) (index, batches[index]),
    ];
    final screen = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: AppColors.surfaceTint,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: screen.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.rose.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'INVENTORY BATCHES',
                          style: TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          '${widget.item['name'] ?? 'Item'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search batches',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(
                        _dateRange == null
                            ? 'Filter by date'
                            : '${_dateLabel(_dateRange!.start)} – ${_dateLabel(_dateRange!.end)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_dateRange != null)
                    IconButton(
                      tooltip: 'Clear date filter',
                      onPressed: () => setState(() => _dateRange = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filteredBatches.isEmpty
                    ? Center(
                        child: Text(
                          batches.isEmpty
                              ? 'No stock batches have been recorded yet.'
                              : 'No batches match these filters.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.primaryDark),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: filteredBatches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final (batchIndex, batch) = filteredBatches[index];
                          return _InventoryBatchCard(
                            index: batchIndex,
                            batch: batch,
                            item: widget.item,
                            dateLabel: _dateLabel,
                          );
                        },
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matches(Map<String, dynamic> batch, int index, String query) {
    final batchDate = _date(batch['createdAt'] ?? widget.item['createdAt']);
    if (_dateRange != null) {
      if (batchDate == null ||
          batchDate.isBefore(DateUtils.dateOnly(_dateRange!.start)) ||
          !batchDate.isBefore(
            DateUtils.dateOnly(_dateRange!.end).add(const Duration(days: 1)),
          )) {
        return false;
      }
    }
    if (query.isEmpty) return true;
    final searchText = [
      'BATCH-${(index + 1).toString().padLeft(3, '0')}',
      batch['batchId'],
      batch['quantity'],
      _dateLabel(batch['createdAt'] ?? widget.item['createdAt']),
      batch['expirationDate'],
      batch['costPrice'] ?? widget.item['costPrice'],
      batch['price'] ?? widget.item['price'] ?? widget.item['basePrice'],
    ].join(' ').toLowerCase();
    return searchText.contains(query);
  }
}

class _InventoryBatchCard extends StatelessWidget {
  const _InventoryBatchCard({
    required this.index,
    required this.batch,
    required this.item,
    required this.dateLabel,
  });

  final int index;
  final Map<String, dynamic> batch;
  final Map<String, dynamic> item;
  final String Function(dynamic) dateLabel;

  @override
  Widget build(BuildContext context) {
    final remaining = num.tryParse(
      '${batch['remaining'] ?? batch['quantity'] ?? 0}',
    );
    final available = remaining == null || remaining > 0;
    final batchName =
        '${batch['batchId'] ?? 'BATCH-${(index + 1).toString().padLeft(3, '0')}'}';
    final createdDate = batch['createdAt'] ?? item['createdAt'];
    final expiry = '${batch['expirationDate'] ?? 'No expiry'}';

    return Container(
      key: ValueKey('inventory-batch-card-$index'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.rose.withValues(alpha: 0.45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D94163A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.rose.withValues(alpha: 0.22),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  batchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.rose.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${batch['quantity'] ?? 0} units',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MainBatchInfoChip(
                icon: Icons.event_available_rounded,
                label: 'Added ${dateLabel(createdDate)}',
              ),
              _MainBatchInfoChip(
                icon: Icons.event_busy_rounded,
                label: expiry == 'No expiry' || expiry.isEmpty
                    ? 'No expiry'
                    : 'Expires $expiry',
              ),
              _MainBatchInfoChip(
                icon: Icons.payments_outlined,
                label:
                    'Cost ${_batchMoney(batch['costPrice'] ?? item['costPrice'])}',
              ),
              _MainBatchInfoChip(
                icon: Icons.sell_outlined,
                label:
                    'Price ${_batchMoney(batch['price'] ?? item['price'] ?? item['basePrice'])}',
              ),
              _MainBatchInfoChip(
                icon: available ? Icons.check_circle : Icons.remove_circle,
                label: available ? 'Available' : 'Out of stock',
                color: available ? const Color(0xFF2E7D32) : Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MainBatchInfoChip extends StatelessWidget {
  const _MainBatchInfoChip({
    required this.icon,
    required this.label,
    this.color = AppColors.primaryDark,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16, color: color),
    label: Text(label, style: TextStyle(color: color, fontSize: 11)),
    visualDensity: VisualDensity.compact,
    backgroundColor: color.withValues(alpha: 0.08),
    side: BorderSide.none,
    padding: const EdgeInsets.symmetric(horizontal: 4),
  );
}

String _batchMoney(dynamic value) {
  final amount = num.tryParse('$value');
  return amount == null ? '—' : '₱${amount.toStringAsFixed(2)}';
}

Map<String, String> allocationBatchLabels(
  Iterable<Map<String, dynamic>> records,
) {
  DateTime assignedDate(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value') ?? DateTime(1970);

  final sorted = records.toList()
    ..sort((a, b) {
      final byDate = assignedDate(
        a['assignedAt'],
      ).compareTo(assignedDate(b['assignedAt']));
      return byDate != 0 ? byDate : '${a['_id']}'.compareTo('${b['_id']}');
    });
  return {
    for (var index = 0; index < sorted.length; index++)
      '${sorted[index]['_id']}':
          'Batch - ${(index + 1).toString().padLeft(3, '0')}',
  };
}

List<Map<String, dynamic>> aggregateCategoryAllocationItems(
  Iterable<Map<String, dynamic>> items,
) {
  int quantity(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  DateTime? date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value');

  final aggregated = <String, Map<String, dynamic>>{};
  for (final item in items) {
    final id =
        [
              item['publicId'],
              item['itemPublicId'],
              item['id'],
              item['itemId'],
              item['variantId'],
              item['sourceItemId'],
            ]
            .map((value) => '${value ?? ''}'.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final name = '${item['name'] ?? ''}'.trim().toLowerCase();
    final variant = '${item['variant'] ?? ''}'.trim().toLowerCase();
    final key = id.isNotEmpty
        ? '${id.toLowerCase()}|$variant'
        : '$name|$variant';
    final current = aggregated[key];
    final stock = quantity(item['stock'] ?? item['startingStock']);
    if (current == null) {
      final copy = Map<String, dynamic>.from(item)..['stock'] = stock;
      aggregated[key] = copy;
      continue;
    }

    current['stock'] = quantity(current['stock']) + stock;
    current['startingStock'] =
        quantity(current['startingStock']) + quantity(item['startingStock']);
    current['assignedStartingStock'] =
        quantity(current['assignedStartingStock']) +
        quantity(item['assignedStartingStock']);
    final existingDate = date(current['allocatedAt'] ?? current['assignedAt']);
    final incomingDate = date(item['allocatedAt'] ?? item['assignedAt']);
    if (incomingDate != null &&
        (existingDate == null || incomingDate.isAfter(existingDate))) {
      current['allocatedAt'] = incomingDate;
    }
    if (current['origin'] == 'unbundle' && item['origin'] != 'unbundle') {
      for (final key in ['sourceDocId', 'price', 'imageUrl']) {
        if (item[key] != null) current[key] = item[key];
      }
    }
  }
  return aggregated.values
      .map(
        (item) => Map<String, dynamic>.from(item)
          ..remove('origin')
          ..remove('unbundledQuantity'),
      )
      .toList();
}

bool allocationItemMatchesSale(
  Map<String, dynamic> item,
  Map<String, dynamic> sale,
) {
  String normalized(dynamic value) => '${value ?? ''}'.trim().toLowerCase();

  final itemIds = [
    item['id'],
    item['itemId'],
    item['variantId'],
    item['publicId'],
    item['itemPublicId'],
    item['sourceItemId'],
  ].map(normalized).where((id) => id.isNotEmpty).toSet();
  final saleIds = [
    sale['id'],
    sale['itemId'],
    sale['variantId'],
    sale['publicId'],
    sale['itemPublicId'],
    sale['sourceItemId'],
  ].map(normalized).where((id) => id.isNotEmpty).toSet();
  final itemVariant = normalized(
    item['variant'] ?? item['coffeeSize'] ?? item['size'],
  );
  final saleVariant = normalized(
    sale['variant'] ?? sale['coffeeSize'] ?? sale['size'],
  );
  if (itemIds.intersection(saleIds).isNotEmpty) {
    return itemVariant.isEmpty ||
        saleVariant.isEmpty ||
        itemVariant == saleVariant;
  }

  final itemName = normalized(item['name']);
  final saleName = normalized(sale['name']);
  return itemName.isNotEmpty &&
      (itemName == saleName ||
          (itemVariant.isNotEmpty &&
              saleVariant.isNotEmpty &&
              itemVariant == saleVariant)) &&
      (itemVariant.isEmpty ||
          saleVariant.isEmpty ||
          itemVariant == saleVariant);
}

int allocationItemSoldQuantity(
  Map<String, dynamic> item,
  Iterable<Map<String, dynamic>> sales,
) => sales
    .where((sale) => allocationItemMatchesSale(item, sale))
    .fold<int>(
      0,
      (total, sale) => total + (int.tryParse('${sale['quantity'] ?? 0}') ?? 0),
    );

String beverageAllocationSize(
  Map<String, dynamic> item, {
  String productName = '',
}) {
  final explicitSize =
      '${item['coffeeSize'] ?? item['variant'] ?? item['size'] ?? ''}'.trim();
  final name = explicitSize.isEmpty
      ? '${item['name'] ?? ''}'.trim()
      : explicitSize;
  final normalizedName = name.toLowerCase();
  final normalizedProduct = productName.trim().toLowerCase();
  if (normalizedProduct.isNotEmpty) {
    if (normalizedName == normalizedProduct) return '';
    final prefix = '$normalizedProduct - ';
    if (normalizedName.startsWith(prefix)) {
      return name.substring(prefix.length).trim();
    }
    final parenthesizedPrefix = '$normalizedProduct (';
    if (normalizedName.startsWith(parenthesizedPrefix) && name.endsWith(')')) {
      return name.substring(parenthesizedPrefix.length, name.length - 1).trim();
    }
  }
  return name;
}

List<Map<String, dynamic>> uniqueBeverageAllocationItems(
  Iterable<Map<String, dynamic>> items, {
  String productName = '',
}) {
  String normalizedSize(Map<String, dynamic> item) =>
      beverageAllocationSize(item, productName: productName).toLowerCase();

  final bySize = <String, Map<String, dynamic>>{};
  for (final item in items) {
    final size = normalizedSize(item);
    if (size.isNotEmpty) bySize.putIfAbsent(size, () => item);
  }
  return bySize.values.toList();
}

num? allocationCurrentCatalogPrice(
  Map<String, dynamic> item,
  Iterable<Map<String, dynamic>> catalogItems,
) {
  String normalized(dynamic value) => '${value ?? ''}'.trim().toLowerCase();

  final itemIds = [
    item['id'],
    item['itemId'],
    item['variantId'],
    item['publicId'],
    item['itemPublicId'],
    item['sourceItemId'],
  ].map(normalized).where((id) => id.isNotEmpty).toSet();
  final itemName = normalized(item['name']);
  final itemVariant = normalized(
    item['variant'] ?? item['coffeeSize'] ?? item['size'],
  );
  final candidates = <Map<String, dynamic>>[];
  for (final candidate in catalogItems) {
    final candidateIds = [
      candidate['id'],
      candidate['itemId'],
      candidate['variantId'],
      candidate['publicId'],
      candidate['itemPublicId'],
      candidate['sourceItemId'],
    ].map(normalized).where((id) => id.isNotEmpty).toSet();
    final candidateName = normalized(candidate['name']);
    final candidateVariant = normalized(
      candidate['variant'] ?? candidate['coffeeSize'] ?? candidate['size'],
    );
    final nameMatches =
        itemName.isEmpty || candidateName.isEmpty || itemName == candidateName;
    final variantMatches =
        itemVariant.isEmpty ||
        candidateVariant.isEmpty ||
        itemVariant == candidateVariant;
    final idsMatch = itemIds.intersection(candidateIds).isNotEmpty;
    if ((!idsMatch && (itemName.isEmpty || candidateName != itemName)) ||
        !nameMatches ||
        !variantMatches) {
      continue;
    }
    candidates.add(candidate);
  }
  if (candidates.isEmpty) return null;
  if (itemVariant.isNotEmpty) {
    final exactVariant = candidates.where(
      (candidate) =>
          normalized(
            candidate['variant'] ??
                candidate['coffeeSize'] ??
                candidate['size'],
          ) ==
          itemVariant,
    );
    if (exactVariant.length == 1) {
      return num.tryParse('${exactVariant.single['price'] ?? ''}');
    }
    if (exactVariant.isNotEmpty) return null;
  }
  if (candidates.length != 1) return null;
  return num.tryParse('${candidates.single['price'] ?? ''}');
}

num? allocationSaleUnitPrice(Map<String, dynamic> sale) {
  for (final key in ['unitPrice', 'price', 'salePrice']) {
    final value = num.tryParse('${sale[key] ?? ''}');
    if (value != null) return value;
  }
  final quantity = int.tryParse('${sale['quantity'] ?? 0}') ?? 0;
  if (quantity <= 0) return null;
  for (final key in ['lineTotal', 'subtotal', 'total', 'amount']) {
    final value = num.tryParse('${sale[key] ?? ''}');
    if (value != null) return value / quantity;
  }
  return null;
}

bool allocationSaleInDateRange(
  Map<String, dynamic> sale,
  DateTime start,
  DateTime end,
) {
  final raw = sale['soldAt'] ?? sale['timestamp'] ?? sale['createdAt'];
  final soldAt = switch (raw) {
    Timestamp value => value.toDate().toLocal(),
    DateTime value => value.toLocal(),
    String value => DateTime.tryParse(value)?.toLocal(),
    _ => null,
  };
  if (soldAt == null) return false;
  final day = DateUtils.dateOnly(soldAt);
  return !day.isBefore(DateUtils.dateOnly(start)) &&
      !day.isAfter(DateUtils.dateOnly(end));
}

List<Map<String, dynamic>> allocationInstanceBatches(
  Map<String, dynamic> record,
  String allocationId, {
  bool availableOnly = true,
}) {
  final instances = availableOnly
      ? availableReconciliationInstances(record, allocationId)
      : reconciliationInstances(record, allocationId);
  final groups = <String, Map<String, dynamic>>{};
  for (final instance in instances) {
    final batchId = '${instance['batchId'] ?? ''}'.trim();
    final assignedAt = instance['assignedAt'] ?? record['assignedAt'];
    final key = batchId.isNotEmpty ? batchId : allocationId;
    final group = groups.putIfAbsent(
      key,
      () => {
        'batchId': key,
        'assignedAt': assignedAt,
        'allocationId': allocationId,
        'record': record,
        'instances': <Map<String, dynamic>>[],
      },
    );
    (group['instances'] as List<Map<String, dynamic>>).add(instance);
  }
  final result = groups.values.toList()
    ..sort((a, b) {
      final left = a['assignedAt'] is Timestamp
          ? (a['assignedAt'] as Timestamp).toDate()
          : DateTime.tryParse('${a['assignedAt'] ?? ''}') ?? DateTime(1970);
      final right = b['assignedAt'] is Timestamp
          ? (b['assignedAt'] as Timestamp).toDate()
          : DateTime.tryParse('${b['assignedAt'] ?? ''}') ?? DateTime(1970);
      final byDate = left.compareTo(right);
      return byDate != 0
          ? byDate
          : '${a['batchId']}'.compareTo('${b['batchId']}');
    });
  return result;
}

Map<String, String> allocationInstanceBatchLabels(
  List<Map<String, dynamic>> records,
) {
  final groups =
      [
        for (final record in records)
          ...allocationInstanceBatches(
            record,
            '${record['_id']}',
            availableOnly: false,
          ),
      ]..sort((a, b) {
        final left = a['assignedAt'] is Timestamp
            ? (a['assignedAt'] as Timestamp).toDate()
            : DateTime.tryParse('${a['assignedAt'] ?? ''}') ?? DateTime(1970);
        final right = b['assignedAt'] is Timestamp
            ? (b['assignedAt'] as Timestamp).toDate()
            : DateTime.tryParse('${b['assignedAt'] ?? ''}') ?? DateTime(1970);
        final byDate = left.compareTo(right);
        return byDate != 0
            ? byDate
            : '${a['batchId']}'.compareTo('${b['batchId']}');
      });
  return {
    for (var i = 0; i < groups.length; i++)
      '${groups[i]['batchId']}':
          'Batch - ${(i + 1).toString().padLeft(3, '0')}',
  };
}

int allocationInstanceNumber(Map<String, dynamic> instance, int index) =>
    int.tryParse('${instance['number'] ?? ''}') ?? index + 1;

String allocationInstanceLabel(Map<String, dynamic> instance, int index) =>
    'BND-ITM-${allocationInstanceNumber(instance, index).toString().padLeft(3, '0')}';

String allocationBundleId(
  Map<String, dynamic> record,
  Map<String, dynamic> instance,
  int index,
) => bundleInstanceDisplayId(record, instance, index);

List<Map<String, dynamic>> aggregateUnbundlePreviewItems(dynamic value) {
  final totals = <String, Map<String, dynamic>>{};
  for (final item in bundleRows(value)) {
    final name = '${item['name'] ?? 'Item'}'.trim();
    final key = name.toLowerCase();
    final quantity = bundleQuantity(item['quantity']);
    final expiry = '${item['expirationDate'] ?? '--'}';
    final total = totals.putIfAbsent(
      key,
      () => {'name': name, 'quantity': 0, 'expirations': <String>{}},
    );
    total['quantity'] = bundleQuantity(total['quantity']) + quantity;
    if (expiry.isNotEmpty && expiry != '--') {
      (total['expirations'] as Set<String>).add(expiry);
    }
  }
  return totals.values.map((item) {
    final expirations = item['expirations'] as Set<String>;
    return {
      'name': item['name'],
      'quantity': item['quantity'],
      'expirationDate': expirations.isEmpty
          ? '--'
          : expirations.length == 1
          ? expirations.first
          : 'Multiple expiry dates',
    };
  }).toList();
}

List<Map<String, dynamic>> allocationBatchItemsForRecord(
  Map<String, dynamic> record, {
  String? itemId,
}) {
  final requestedId = itemId?.trim() ?? '';
  if (record['isAddon'] == true) {
    if (requestedId.isEmpty) return [Map<String, dynamic>.from(record)];
    final identifiers = [
      record['id'],
      record['itemId'],
      record['variantId'],
      record['publicId'],
      record['addonId'],
    ].map((value) => '${value ?? ''}'.trim());
    return identifiers.contains(requestedId)
        ? [Map<String, dynamic>.from(record)]
        : const [];
  }
  final items = bundleRows(record['items']);
  final batchItems = items.isEmpty ? bundleRows(record['sizes']) : items;
  return batchItems.where((item) {
    if (requestedId.isEmpty) return true;
    return [
      item['id'],
      item['itemId'],
      item['variantId'],
      item['publicId'],
      item['itemPublicId'],
    ].any((value) => '${value ?? ''}'.trim() == requestedId);
  }).toList();
}

bool hasAvailableAllocationBatchAfter(
  Map<String, dynamic> record,
  String allocationId,
  DateTime date,
) => allocationInstanceBatches(record, allocationId).any((batch) {
  final assignedAt = batch['assignedAt'];
  final batchDate = assignedAt is Timestamp
      ? assignedAt.toDate()
      : assignedAt is DateTime
      ? assignedAt
      : DateTime.tryParse('$assignedAt') ?? DateTime(1970);
  return batchDate.isAfter(date);
});

Future<void> showInventoryBatches(
  BuildContext context, {
  required String allocationId,
  required List<String> scopeIds,
  String? itemId,
  bool readOnly = false,
  FirebaseFirestore? database,
}) => showDialog<void>(
  context: context,
  builder: (_) => _BatchDialog(
    allocationId: allocationId,
    scopeIds: scopeIds,
    itemId: itemId,
    readOnly: readOnly,
    db: database ?? FirebaseFirestore.instance,
  ),
);

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({
    required this.allocationId,
    required this.scopeIds,
    required this.db,
    this.itemId,
    this.readOnly = false,
  });
  final String allocationId;
  final List<String> scopeIds;
  final String? itemId;
  final bool readOnly;
  final FirebaseFirestore db;
  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  String search = '';
  DateTimeRange? currentRange;
  DateTimeRange? historyRange;
  bool historyView = false;
  final salesByAllocation = <String, List<Map<String, dynamic>>>{};
  List<Map<String, dynamic>>? records;
  String? error;
  bool busy = false;
  String action = 'return';
  String? selectedAllocation, target;
  final selected = <String>{};
  late final requestId = widget.db
      .collection('inventory_reconciliations')
      .doc()
      .id;

  DateTimeRange? get range => historyView ? historyRange : currentRange;

  set range(DateTimeRange? value) {
    if (historyView) {
      historyRange = value;
    } else {
      currentRange = value;
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final online = !(await Connectivity().checkConnectivity()).contains(
        ConnectivityResult.none,
      );
      final readOptions = online
          ? const GetOptions(source: Source.server)
          : const GetOptions(source: Source.cache);
      Map<String, dynamic>? original;
      try {
        original =
            (await widget.db
                    .collection('staff_inventory')
                    .doc(widget.allocationId)
                    .get(readOptions))
                .data();
      } catch (_) {
        final cached = await LocalDatabaseSyncService().getCachedCollection(
          'staff_inventory',
        );
        original = cached
            .where((row) => row['_localDocId'] == widget.allocationId)
            .firstOrNull;
      }
      if (original == null || !widget.scopeIds.contains(original['staffId'])) {
        throw StateError('This allocation is no longer available.');
      }
      List<Map<String, dynamic>> inventoryRows;
      List<Map<String, dynamic>> salesRows;
      try {
        final snapshots = await Future.wait([
          widget.db
              .collection('staff_inventory')
              .where('staffId', isEqualTo: original['staffId'])
              .get(readOptions),
          widget.db
              .collection('completed_sales')
              .where('branchId', isEqualTo: original['staffId'])
              .get(readOptions),
        ]);
        inventoryRows = snapshots[0].docs
            .map((doc) => {...doc.data(), '_localDocId': doc.id})
            .toList();
        salesRows = snapshots[1].docs.map((doc) => doc.data()).toList();
      } catch (_) {
        final local = LocalDatabaseSyncService();
        inventoryRows = await local.getCachedCollection('staff_inventory');
        salesRows = await local.getCachedCollection('completed_sales');
      }
      var rows = inventoryRows
          .where(
            (row) =>
                row['staffId'] == original!['staffId'] &&
                row['isDeleted'] != true &&
                (row['isBundle'] == true) == (original['isBundle'] == true) &&
                (original['isBundle'] == true
                    ? bundleInventoryGroupKey(row) ==
                          bundleInventoryGroupKey(original)
                    : row['sourceInventoryId'] ==
                          original['sourceInventoryId']),
          )
          .map(
            (row) => <String, dynamic>{
              ...row,
              '_id': row['_localDocId'] ?? row['id'],
            },
          )
          .toList();
      final currentCatalogBySource = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final sourceId = '${row['sourceInventoryId'] ?? ''}'.trim();
        if (sourceId.isEmpty) continue;
        final collection =
            '${row['sourceCollection'] ?? (row['isCoffee'] == true
                        ? 'coffee_products'
                        : row['isAddon'] == true
                        ? 'coffee_addons'
                        : 'sales_inventory')}'
                .trim();
        final key = '$collection/$sourceId';
        if (currentCatalogBySource.containsKey(key)) continue;
        try {
          final source = await widget.db
              .collection(collection)
              .doc(sourceId)
              .get(readOptions);
          final sourceData = source.data();
          final sourceItems =
              (sourceData?['items'] as List?) ??
              (sourceData?['sizes'] as List?) ??
              const [];
          currentCatalogBySource[key] = sourceItems.whereType<Map>().map((
            item,
          ) {
            final size = Map<String, dynamic>.from(item);
            if (collection == 'coffee_products') {
              final basePrice =
                  num.tryParse(
                    '${sourceData?['basePrice'] ?? sourceData?['price'] ?? ''}',
                  ) ??
                  0;
              final sizePrice =
                  num.tryParse(
                    '${size['sellingPrice'] ?? size['finalPrice'] ?? ''}',
                  ) ??
                  (basePrice +
                      (num.tryParse(
                            '${size['priceDelta'] ?? size['price'] ?? 0}',
                          ) ??
                          0));
              return {
                ...size,
                'variant': size['name'],
                'coffeeSize': size['name'],
                'price': sizePrice,
              };
            }
            return size;
          }).toList();
        } catch (error) {
          debugPrint('Unable to load current inventory prices: $error');
          currentCatalogBySource[key] = const [];
        }
      }
      rows = rows.map((row) {
        final sourceId = '${row['sourceInventoryId'] ?? ''}'.trim();
        final collection =
            '${row['sourceCollection'] ?? (row['isCoffee'] == true
                        ? 'coffee_products'
                        : row['isAddon'] == true
                        ? 'coffee_addons'
                        : 'sales_inventory')}'
                .trim();
        return {
          ...row,
          '_currentCatalogItems':
              currentCatalogBySource['$collection/$sourceId'] ??
              const <Map<String, dynamic>>[],
        };
      }).toList();
      for (final sale in salesRows) {
        if (sale['branchId'] != original['staffId'] &&
            sale['staffId'] != original['staffId']) {
          continue;
        }
        if (sale['isVoided'] == true || sale['isDeleted'] == true) continue;
        for (final line in expandSaleStockLines(bundleRows(sale['items']))) {
          final allocationId = '${line['staffInventoryDocId'] ?? ''}';
          final lineIds = [
            line['id'],
            line['itemId'],
            line['variantId'],
            line['publicId'],
            line['addonId'],
          ].map((value) => '${value ?? ''}').toSet();
          final addonName = '${line['addonName'] ?? ''}'.trim().toLowerCase();
          final matchesRequestedAddon = rows.any((row) {
            if (row['isAddon'] != true ||
                addonName != '${row['name'] ?? ''}'.trim().toLowerCase()) {
              return false;
            }
            if (widget.itemId == null) return true;
            return [
              row['id'],
              row['itemId'],
              row['variantId'],
              row['publicId'],
              row['addonId'],
            ].any((value) => '${value ?? ''}' == widget.itemId);
          });
          if (widget.itemId != null &&
              !lineIds.contains(widget.itemId) &&
              !matchesRequestedAddon) {
            continue;
          }
          final saleLine = {
            ...line,
            'soldAt': sale['timestamp'] ?? sale['createdAt'],
          };
          if (rows.any((row) => '${row['_id']}' == allocationId)) {
            salesByAllocation.putIfAbsent(allocationId, () => []).add(saleLine);
          }
          if (addonName.isNotEmpty) {
            for (final addon in rows.where((row) {
              if (addonName != '${row['name'] ?? ''}'.trim().toLowerCase()) {
                return false;
              }
              if (widget.itemId == null) return true;
              return [
                row['id'],
                row['itemId'],
                row['variantId'],
                row['publicId'],
                row['addonId'],
              ].any((value) => '${value ?? ''}' == widget.itemId);
            })) {
              salesByAllocation
                  .putIfAbsent('${addon['_id']}', () => [])
                  .add(saleLine);
            }
          }
        }
      }
      rows.sort(
        (a, b) => date(b['assignedAt']).compareTo(date(a['assignedAt'])),
      );
      final grouped = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final reconciliation = '${row['reconciliationId'] ?? ''}';
        final key = row['origin'] == 'unbundle' && reconciliation.isNotEmpty
            ? '$reconciliation|${row['sourceInventoryId']}'
            : '${row['_id']}';
        final previous = grouped[key];
        if (previous == null) {
          grouped[key] = Map<String, dynamic>.from(row);
          grouped[key]!['_sales'] = <Map<String, dynamic>>[
            ...?salesByAllocation['${row['_id']}'],
          ];
        } else {
          final sales = bundleRows(previous['_sales'])
            ..addAll(bundleRows(salesByAllocation['${row['_id']}']));
          previous['_sales'] = sales;
          previous['items'] = aggregateCategoryAllocationItems([
            ...bundleRows(previous['items']),
            ...bundleRows(row['items']),
          ]);
        }
      }
      if (mounted) setState(() => records = grouped.values.toList());
    } catch (e) {
      debugPrint('Unable to load allocation batches: $e');
      if (mounted) setState(() => error = e is StateError ? e.message : '$e');
    }
  }

  DateTime date(dynamic value) => value is Timestamp
      ? value.toDate()
      : DateTime.tryParse('$value') ?? DateTime(1970);
  String dateLabel(dynamic value) => value == null || '$value'.isEmpty
      ? '--'
      : date(value).toIso8601String().split('T').first;
  String timeLabel(dynamic value) {
    if (value == null) return '--';
    final valueDate = date(value).toLocal();
    final hour = valueDate.hour % 12 == 0 ? 12 : valueDate.hour % 12;
    final minute = valueDate.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${valueDate.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> submit() async {
    if (selectedAllocation == null || selected.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        throw StateError('Connect to the internet before submitting a return.');
      }
      final actor = await resolveBranchInventoryActor(widget.db);
      final record = records!.firstWhere((r) => r['_id'] == selectedAllocation);
      if (action == 'return') {
        await AllocationChecklistService(widget.db).submitReturn(
          requestId: requestId,
          sourceCollection: 'staff_inventory',
          sourceId: selectedAllocation!,
          lineKey: 'bundle',
          count: selected.length,
          reason: 'Return allocated bundle batch',
          actorId: actor.id,
          actorName: actor.name,
          scopeIds: widget.scopeIds,
          branchId: '${record['staffId']}',
          branchName: '${record['branchName'] ?? record['staffName'] ?? ''}',
          instanceIds: selected.toList(),
        );
      } else {
        await InventoryReconciliationService(widget.db).submit(
          requestId: requestId,
          allocationId: selectedAllocation!,
          instanceIds: selected.toList(),
          action: action,
          actorId: actor.id,
          actorName: actor.name,
          scopeIds: widget.scopeIds,
          targetAllocationId: target,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toggleBatchSelection(
    String allocationId,
    List<Map<String, dynamic>> instances,
    bool checked,
  ) {
    if (selectedAllocation != allocationId) {
      selected.clear();
      target = null;
    }
    selectedAllocation = allocationId;
    for (final instance in instances) {
      final id = '${instance['id']}';
      if (checked) {
        selected.add(id);
      } else {
        selected.remove(id);
      }
    }
    if (selected.isEmpty) selectedAllocation = null;
  }

  @override
  Widget build(BuildContext context) {
    final bundle = records?.firstOrNull?['isBundle'] == true;
    final batchLabels = allocationBatchLabels(records ?? const []);
    final instanceBatchLabels = allocationInstanceBatchLabels(
      records ?? const [],
    );
    final batchItemsByAllocation = {
      for (final record in records ?? const [])
        '${record['_id']}': allocationBatchItemsForRecord(
          record,
          itemId: widget.itemId,
        ),
    };
    final batchesByAllocation = {
      for (final record in records ?? const [])
        '${record['_id']}':
            allocationInstanceBatches(
              record,
              '${record['_id']}',
              availableOnly: false,
            ).where((batch) {
              final instances = bundleRows(batch['instances']);
              final statuses = instances
                  .map((instance) => instance['status'] ?? 'available')
                  .toSet();
              return historyView
                  ? statuses.any(
                      (status) => ![
                        'available',
                        'reconciliation_pending',
                        'return_pending',
                      ].contains(status),
                    )
                  : statuses.any(
                      (status) => [
                        'available',
                        'reconciliation_pending',
                        'return_pending',
                      ].contains(status),
                    );
            }).toList(),
    };
    bool inSelectedDates(DateTime? value) {
      if (value == null) return false;
      if (range == null) {
        final today = DateUtils.dateOnly(DateTime.now());
        return !DateUtils.dateOnly(value).isBefore(today) &&
            !DateUtils.dateOnly(value).isAfter(today);
      }
      final start = DateUtils.dateOnly(range!.start);
      final end = DateUtils.dateOnly(range!.end);
      final day = DateUtils.dateOnly(value);
      return !day.isBefore(start) && !day.isAfter(end);
    }

    bool hasCurrentStock(Map<String, dynamic> record) {
      if (record['isCoffee'] == true || record['isAddon'] == true) {
        return true;
      }
      if (record['isBundle'] == true) {
        return (batchesByAllocation['${record['_id']}'] ?? []).any(
          (batch) => bundleRows(batch['instances']).any(
            (instance) => [
              'available',
              'reconciliation_pending',
              'return_pending',
            ].contains(instance['status'] ?? 'available'),
          ),
        );
      }
      return (batchItemsByAllocation['${record['_id']}'] ?? []).any(
        (item) =>
            (int.tryParse(
                  '${item['stock'] ?? item['remaining'] ?? item['startingStock'] ?? 0}',
                ) ??
                0) >
            0,
      );
    }

    bool hasHistory(
      Map<String, dynamic> record,
      List<Map<String, dynamic>> sales,
      bool hasSoldBundle,
    ) {
      if (sales.isNotEmpty || hasSoldBundle) return true;
      if (record['isCoffee'] == true || record['isAddon'] == true) {
        return false;
      }
      return allocationBatchItemsForRecord(record, itemId: widget.itemId).any((
        item,
      ) {
        final remaining =
            int.tryParse('${item['stock'] ?? item['remaining'] ?? 0}') ?? 0;
        final allocated =
            int.tryParse(
              '${item['assignedStartingStock'] ?? item['startingStock'] ?? remaining}',
            ) ??
            0;
        return remaining == 0 && allocated > 0;
      });
    }

    final visibleRecords = (records ?? <Map<String, dynamic>>[])
        .where((record) {
          final sales = bundleRows(record['_sales']);
          final items = allocationBatchItemsForRecord(
            record,
            itemId: widget.itemId,
          );
          final hasSales = sales.isNotEmpty;
          final batches = batchesByAllocation['${record['_id']}'] ?? [];
          final hasSoldBundle = batches.any(
            (batch) => bundleRows(
              batch['instances'],
            ).any((instance) => instance['status'] == 'sold'),
          );
          final currentlyAvailable = hasCurrentStock(record);
          final hasHistoricalActivity = hasHistory(
            record,
            sales,
            hasSoldBundle,
          );
          if (historyView && !hasHistoricalActivity) {
            return false;
          }
          if (!historyView && !currentlyAvailable) return false;
          final dateMatches = historyView
              ? sales.any((sale) => inSelectedDates(date(sale['soldAt']))) ||
                    hasSoldBundle &&
                        batches.any(
                          (batch) => inSelectedDates(
                            date(
                              batch['soldAt'] ??
                                  bundleRows(batch['instances'])
                                      .map(
                                        (instance) =>
                                            instance['soldAt'] ??
                                            batch['assignedAt'],
                                      )
                                      .firstOrNull,
                            ),
                          ),
                        ) ||
                    inSelectedDates(date(record['assignedAt']))
              : record['isBundle'] == true
              ? batches.any(
                  (batch) => inSelectedDates(date(batch['assignedAt'])),
                )
              : inSelectedDates(date(record['assignedAt']));
          if (!dateMatches) return false;
          if (search.isEmpty) return true;
          final corpus = [
            '$record',
            if (record['origin'] == 'unbundle') 'unbundle',
            if (record['origin'] != 'unbundle') 'allocated',
            if (hasSales) 'sold',
            for (final sale in sales) '$sale',
            for (final item in items) '$item',
          ].join(' ').toLowerCase();
          if (search == 'sold') return hasSales || hasSoldBundle;
          if (search == 'allocated') return record['origin'] != 'unbundle';
          return corpus.contains(search);
        })
        .where(
          (record) =>
              !bundle ||
              (batchesByAllocation['${record['_id']}'] ?? []).isNotEmpty,
        )
        .where(
          (record) =>
              bundle ||
              (batchItemsByAllocation['${record['_id']}'] ?? []).isNotEmpty,
        )
        .toList();
    final dateChips = <DateTime>{};
    for (final record in records ?? const <Map<String, dynamic>>[]) {
      if (!historyView) {
        if (hasCurrentStock(record)) {
          if (record['isBundle'] == true) {
            for (final batch in batchesByAllocation['${record['_id']}'] ?? []) {
              final assigned = date(batch['assignedAt']);
              if (assigned.year > 1970) {
                dateChips.add(DateUtils.dateOnly(assigned));
              }
            }
          } else {
            final assigned = date(record['assignedAt']);
            if (assigned.year > 1970) {
              dateChips.add(DateUtils.dateOnly(assigned));
            }
          }
        }
        continue;
      }
      final sales = bundleRows(record['_sales']);
      for (final sale in sales) {
        final soldAt = date(sale['soldAt']);
        if (soldAt.year > 1970) dateChips.add(DateUtils.dateOnly(soldAt));
      }
      final batches = batchesByAllocation['${record['_id']}'] ?? [];
      for (final batch in batches) {
        for (final instance in bundleRows(batch['instances'])) {
          final status = instance['status'] ?? 'available';
          if (![
            'available',
            'reconciliation_pending',
            'return_pending',
          ].contains(status)) {
            final soldAt = date(instance['soldAt'] ?? batch['assignedAt']);
            if (soldAt.year > 1970) dateChips.add(DateUtils.dateOnly(soldAt));
          }
        }
      }
      final exhausted =
          allocationBatchItemsForRecord(record, itemId: widget.itemId).any((
            item,
          ) {
            final remaining =
                int.tryParse('${item['stock'] ?? item['remaining'] ?? 0}') ?? 0;
            final allocated =
                int.tryParse(
                  '${item['assignedStartingStock'] ?? item['startingStock'] ?? remaining}',
                ) ??
                0;
            return remaining == 0 && allocated > 0;
          });
      if (exhausted) {
        final assigned = date(record['assignedAt']);
        if (assigned.year > 1970) dateChips.add(DateUtils.dateOnly(assigned));
      }
    }
    final sortedDateChips = dateChips.toList()
      ..sort((left, right) => right.compareTo(left));
    final source = records
        ?.where((r) => r['_id'] == selectedAllocation)
        .firstOrNull;
    final selectedBatchDate = source == null
        ? null
        : reconciliationInstances(source, '$selectedAllocation')
                  .where((instance) => selected.contains('${instance['id']}'))
                  .map((instance) => date(instance['assignedAt']))
                  .firstOrNull ??
              date(source['assignedAt']);
    final targets = (records ?? [])
        .where(
          (r) =>
              r['_id'] != selectedAllocation &&
              selectedBatchDate != null &&
              hasAvailableAllocationBatchAfter(
                r,
                '${r['_id']}',
                selectedBatchDate,
              ),
        )
        .toList();
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDeep, AppColors.primaryDark],
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Allocated batches',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width < 600
              ? double.maxFinite
              : 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search allocated, sold, item, or batch',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Filter allocation dates',
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final today = DateUtils.dateOnly(DateTime.now());
                        final result = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange:
                              range ?? DateTimeRange(start: today, end: today),
                        );
                        if (result != null && mounted)
                          setState(() => range = result);
                      },
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => search = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Current batches'),
                      icon: Icon(Icons.inventory_2_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('History'),
                      icon: Icon(Icons.history_rounded),
                    ),
                  ],
                  selected: {historyView},
                  onSelectionChanged: (selection) =>
                      setState(() => historyView = selection.first),
                ),
                if (records != null && sortedDateChips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final value in sortedDateChips) ...[
                          ChoiceChip(
                            label: Text(dateLabel(value)),
                            selected:
                                range != null &&
                                DateUtils.dateOnly(range!.start) == value &&
                                DateUtils.dateOnly(range!.end) == value,
                            onSelected: (_) => setState(() {
                              range = DateTimeRange(start: value, end: value);
                            }),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ],
                if (range != null)
                  Wrap(
                    children: [
                      InputChip(
                        label: Text(
                          '${dateLabel(range!.start)} to ${dateLabel(range!.end)}',
                        ),
                        onDeleted: () => setState(() => range = null),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (records == null && error == null) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Center(child: Text('Loading allocated batches...')),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (bundle && !widget.readOnly) ...[
                  DropdownButtonFormField<String>(
                    initialValue: action,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: const [
                      DropdownMenuItem(value: 'return', child: Text('Return')),
                      DropdownMenuItem(
                        value: 'convert',
                        child: Text('Convert to Updated Bundle'),
                      ),
                      DropdownMenuItem(
                        value: 'unbundle',
                        child: Text('Unbundle to Individual Items'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            action = v!;
                            target = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  if (action == 'convert') ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('$selectedAllocation-$action'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Updated allocated version',
                      ),
                      items: targets
                          .map(
                            (r) => DropdownMenuItem(
                              value: '${r['_id']}',
                              child: Text(
                                '${r['name']} - ${dateLabel(r['assignedAt'])} - ${formatMoney(num.tryParse('${r['price']}') ?? 0)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => target = v),
                    ),
                    if (targets.isEmpty)
                      const Text(
                        'A newer version must be allocated to this branch first.',
                      ),
                  ],
                ],
                if (records != null &&
                    bundle &&
                    visibleRecords.isEmpty &&
                    error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      historyView
                          ? 'No bundle history for the selected dates.'
                          : 'No available bundles to request.',
                    ),
                  ),
                if (records != null &&
                    !bundle &&
                    visibleRecords.isEmpty &&
                    error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      historyView
                          ? 'No sold batches for the selected dates.'
                          : 'No allocated batches for today. Choose a date to view earlier allocations.',
                    ),
                  ),
                if (bundle)
                  for (final record in visibleRecords)
                    for (final batch
                        in (batchesByAllocation['${record['_id']}'] ?? [])
                            .where((batch) {
                              if (!historyView) {
                                return inSelectedDates(
                                  date(batch['assignedAt']),
                                );
                              }
                              final batchInstances = bundleRows(
                                batch['instances'],
                              );
                              return inSelectedDates(
                                    date(batch['assignedAt']),
                                  ) ||
                                  batchInstances.any(
                                    (instance) =>
                                        ![
                                          'available',
                                          'reconciliation_pending',
                                          'return_pending',
                                        ].contains(
                                          instance['status'] ?? 'available',
                                        ) &&
                                        inSelectedDates(
                                          date(
                                            instance['soldAt'] ??
                                                batch['assignedAt'],
                                          ),
                                        ),
                                  ) ||
                                  bundleRows(record['_sales']).any(
                                    (sale) =>
                                        inSelectedDates(date(sale['soldAt'])),
                                  );
                            }))
                      Builder(
                        builder: (context) {
                          final allBatchInstances = bundleRows(
                            batch['instances'],
                          );
                          final batchSoldCount = allBatchInstances
                              .where((instance) => instance['status'] == 'sold')
                              .length;
                          final batchRemainingCount = allBatchInstances
                              .where(
                                (instance) => [
                                  'available',
                                  'reconciliation_pending',
                                  'return_pending',
                                ].contains(instance['status'] ?? 'available'),
                              )
                              .length;
                          final instances = allBatchInstances.where((instance) {
                            final status = instance['status'] ?? 'available';
                            return historyView
                                ? ![
                                    'available',
                                    'reconciliation_pending',
                                    'return_pending',
                                  ].contains(status)
                                : [
                                    'available',
                                    'reconciliation_pending',
                                    'return_pending',
                                  ].contains(status);
                          }).toList();
                          final availableIds = availableReconciliationInstances(
                            record,
                            '${record['_id']}',
                          ).map((i) => '${i['id']}').toSet();
                          final selectable = instances
                              .where((i) => availableIds.contains('${i['id']}'))
                              .toList();
                          final selectedCount = instances
                              .where(
                                (instance) =>
                                    selected.contains('${instance['id']}'),
                              )
                              .length;
                          final allSelected =
                              selectable.isNotEmpty &&
                              selectedCount == selectable.length;
                          final someSelected =
                              selectedCount > 0 && !allSelected;
                          return Card(
                            color: const Color(0xFFFFFBFC),
                            elevation: 0,
                            margin: const EdgeInsets.symmetric(vertical: 7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: selectedCount > 0
                                    ? AppColors.primary
                                    : AppColors.blush,
                                width: selectedCount > 0 ? 1.5 : 1,
                              ),
                            ),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 5,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                12,
                                0,
                                12,
                                12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              collapsedShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              leading: CircleAvatar(
                                radius: 19,
                                backgroundColor: AppColors.blush,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  size: 19,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${record['name'] ?? 'Bundle'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                                  if (!widget.readOnly)
                                    Checkbox(
                                      tristate: true,
                                      value: allSelected
                                          ? true
                                          : someSelected
                                          ? null
                                          : false,
                                      onChanged: busy || selectable.isEmpty
                                          ? null
                                          : (checked) => setState(
                                              () => toggleBatchSelection(
                                                '${record['_id']}',
                                                selectable,
                                                checked == true,
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _BatchInfoChip(
                                      label:
                                          'Batch ${instanceBatchLabels['${batch['batchId']}']?.replaceFirst('Batch - ', '') ?? '001'}',
                                      icon: Icons.layers_outlined,
                                    ),
                                    _BatchInfoChip(
                                      label:
                                          '${allBatchInstances.length} allocated',
                                      icon: Icons.inventory_2_outlined,
                                    ),
                                    _BatchInfoChip(
                                      label: '$batchSoldCount sold',
                                      icon: Icons.point_of_sale_outlined,
                                    ),
                                    _BatchInfoChip(
                                      label: '$batchRemainingCount remaining',
                                      icon: Icons.inventory_2_outlined,
                                    ),
                                    if (dateLabel(batch['assignedAt']) != '--')
                                      _BatchInfoChip(
                                        label: dateLabel(batch['assignedAt']),
                                        icon: Icons.calendar_today_outlined,
                                      ),
                                    if (!widget.readOnly)
                                      _BatchInfoChip(
                                        label: '$selectedCount selected',
                                        icon:
                                            Icons.check_circle_outline_rounded,
                                      ),
                                  ],
                                ),
                              ),
                              children: [
                                for (
                                  var index = 0;
                                  index < instances.length;
                                  index++
                                )
                                  Builder(
                                    builder: (context) {
                                      final instance = instances[index];
                                      final originalIndex = allBatchInstances
                                          .indexOf(instance);
                                      final instanceId = allocationBundleId(
                                        record,
                                        instance,
                                        originalIndex,
                                      );
                                      final expiration = dateLabel(
                                        instance['expirationDate'],
                                      );
                                      final bundleItems = bundleRows(
                                        instance['items'],
                                      );
                                      final instancePrice =
                                          num.tryParse(
                                            '${instance['price'] ?? ''}',
                                          ) ??
                                          0;
                                      final recordPrice =
                                          num.tryParse(
                                            '${record['price'] ?? record['bundlePrice'] ?? ''}',
                                          ) ??
                                          0;
                                      final bundlePrice = instancePrice > 0
                                          ? instancePrice
                                          : recordPrice;
                                      final isAvailable =
                                          instance['status'] == null ||
                                          instance['status'] == 'available';
                                      return Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFBFC),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  'Bundle ${allocationInstanceNumber(instance, originalIndex)} · ID $instanceId',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color:
                                                        AppColors.primaryDeep,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Copy bundle ID',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () async {
                                                    await Clipboard.setData(
                                                      ClipboardData(
                                                        text: instanceId,
                                                      ),
                                                    );
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Bundle ID copied',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.copy_rounded,
                                                    size: 17,
                                                  ),
                                                ),
                                                _BatchInfoChip(
                                                  label: '1 allocated',
                                                  icon: Icons
                                                      .inventory_2_outlined,
                                                ),
                                                _BatchInfoChip(
                                                  label:
                                                      '${instance['status'] == 'sold' ? 1 : 0} sold',
                                                  icon: Icons
                                                      .point_of_sale_outlined,
                                                ),
                                                _BatchInfoChip(
                                                  label:
                                                      '${isAvailable ? 1 : 0} remaining',
                                                  icon: Icons
                                                      .inventory_2_outlined,
                                                ),
                                                Text(
                                                  formatMoney(bundlePrice),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF2E7D32),
                                                  ),
                                                ),
                                                _BatchInfoChip(
                                                  label:
                                                      '${instance['status'] ?? 'Available'}',
                                                  icon: Icons.circle,
                                                ),
                                                if (expiration != '--')
                                                  _BatchInfoChip(
                                                    label:
                                                        'Expires $expiration',
                                                    icon: Icons.event_outlined,
                                                  ),
                                              ],
                                            ),
                                            if (bundleItems.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              for (final item in bundleItems)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 3,
                                                      ),
                                                  child: Text(
                                                    '${item['name'] ?? 'Item'}  ×${item['quantity'] ?? 0}',
                                                    style: const TextStyle(
                                                      color: AppColors.text,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          );
                        },
                      )
                else
                  for (final record in visibleRecords)
                    Builder(
                      builder: (context) {
                        final items =
                            batchItemsByAllocation['${record['_id']}'] ??
                            const <Map<String, dynamic>>[];
                        final isCoffee = record['isCoffee'] == true;
                        final isAddon = record['isAddon'] == true;
                        int soldQuantityFor(Map<String, dynamic> item) {
                          return allocationItemSoldQuantity(
                            item,
                            bundleRows(record['_sales']),
                          );
                        }

                        final filteredItems = items.where((item) {
                          final itemName = '${item['name'] ?? ''}'.trim();
                          if (itemName.isEmpty ||
                              itemName.toLowerCase() == 'null')
                            return false;
                          if (isCoffee || isAddon) return true;
                          final remaining =
                              int.tryParse(
                                '${item['stock'] ?? item['remaining'] ?? item['startingStock'] ?? 0}',
                              ) ??
                              0;
                          return historyView ? remaining == 0 : remaining > 0;
                        }).toList();
                        final displayItems = isCoffee
                            ? uniqueBeverageAllocationItems(
                                filteredItems,
                                productName: '${record['name'] ?? ''}'.trim(),
                              )
                            : (filteredItems..sort((left, right) {
                                final leftValue =
                                    int.tryParse(
                                      '${left['stock'] ?? left['remaining'] ?? 0}',
                                    ) ??
                                    0;
                                final rightValue =
                                    int.tryParse(
                                      '${right['stock'] ?? right['remaining'] ?? 0}',
                                    ) ??
                                    0;
                                return rightValue.compareTo(leftValue);
                              }));
                        num itemPrice(Map<String, dynamic> item) {
                          if (!historyView || isCoffee) {
                            final currentPrice = allocationCurrentCatalogPrice(
                              item,
                              bundleRows(record['_currentCatalogItems']),
                            );
                            if (currentPrice != null) return currentPrice;
                          }
                          final saved = num.tryParse('${item['price'] ?? ''}');
                          if (isCoffee) {
                            final basePrice =
                                num.tryParse('${record['basePrice'] ?? ''}') ??
                                0;
                            final delta =
                                num.tryParse(
                                  '${item['priceDelta'] ?? item['sizePriceDelta'] ?? ''}',
                                ) ??
                                (saved != null && saved < basePrice
                                    ? saved
                                    : 0);
                            if (basePrice > 0) return basePrice + delta;
                          }
                          if (saved != null) return saved;
                          if (isCoffee) {
                            return (num.tryParse(
                                      '${record['basePrice'] ?? 0}',
                                    ) ??
                                    0) +
                                (num.tryParse(
                                      '${item['priceDelta'] ?? item['sizePriceDelta'] ?? 0}',
                                    ) ??
                                    0);
                          }
                          return num.tryParse(
                                '${item['priceDelta'] ?? record['price'] ?? 0}',
                              ) ??
                              0;
                        }

                        final itemNames = displayItems
                            .map((item) => '${item['name'] ?? 'Item'}'.trim())
                            .where((name) => name.isNotEmpty)
                            .toSet()
                            .join(', ');
                        final categoryName = '${record['name'] ?? 'Inventory'}'
                            .trim();
                        final title = [
                          categoryName,
                          if (itemNames.isNotEmpty) itemNames,
                          dateLabel(record['assignedAt']),
                        ].join(' - ');
                        final saleLines = bundleRows(record['_sales']).where((
                          sale,
                        ) {
                          final quantity =
                              int.tryParse('${sale['quantity'] ?? 0}') ?? 0;
                          final today = DateUtils.dateOnly(DateTime.now());
                          final matchesSaleDate = historyView
                              ? inSelectedDates(date(sale['soldAt']))
                              : allocationSaleInDateRange(sale, today, today);
                          return quantity > 0 && matchesSaleDate;
                        }).toList();
                        final totalSold = saleLines.fold<int>(
                          0,
                          (total, sale) =>
                              total +
                              (int.tryParse('${sale['quantity'] ?? 0}') ?? 0),
                        );
                        final totalSaleValue = saleLines.fold<num>(
                          0,
                          (total, sale) =>
                              total +
                              (allocationSaleUnitPrice(sale) ?? 0) *
                                  (int.tryParse('${sale['quantity'] ?? 0}') ??
                                      0),
                        );
                        return Card(
                          color: Colors.white,
                          elevation: 0,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: ExpansionTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            collapsedShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              12,
                              0,
                              12,
                              12,
                            ),
                            leading: const CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.blush,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                size: 19,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            title: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${record['origin'] == 'unbundle' || items.any((item) => item['origin'] == 'unbundle') ? 'Unbundled' : 'Assigned'} · Batch ${batchLabels['${record['_id']}']?.replaceFirst('Batch - ', '') ?? '001'} · ${dateLabel(record['assignedAt'])}',
                            ),
                            children: [
                              for (final item in displayItems)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_outlined,
                                        color: AppColors.primaryDark,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isCoffee
                                                  ? '${record['name'] ?? 'Beverage'} - ${beverageAllocationSize(item, productName: '${record['name'] ?? ''}')}'
                                                  : '${item['name'] ?? 'Item'}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.text,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            if (isCoffee)
                                              Text(
                                                'Price ${formatMoney(itemPrice(item))}',
                                                style: const TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12,
                                                ),
                                              )
                                            else if (isAddon)
                                              Text(
                                                'Price ${formatMoney(num.tryParse('${item['price'] ?? item['priceDelta'] ?? 0}') ?? 0)}',
                                                style: const TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12,
                                                ),
                                              )
                                            else
                                              Text(
                                                '${item['assignedStartingStock'] ?? item['startingStock'] ?? item['stock'] ?? 0} allocated · ${soldQuantityFor(item)} sold · ${item['stock'] ?? item['remaining'] ?? item['startingStock'] ?? 0} remaining',
                                                style: const TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (historyView &&
                                          !isCoffee &&
                                          !isAddon &&
                                          (int.tryParse(
                                                    '${item['stock'] ?? item['remaining'] ?? 0}',
                                                  ) ??
                                                  0) ==
                                              0)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Chip(
                                            label: Text('Sold'),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      Text(
                                        formatMoney(itemPrice(item)),
                                        style: const TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (saleLines.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Sales total: $totalSold sold · ${formatMoney(totalSaleValue)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                              for (final sale in saleLines)
                                for (
                                  var soldUnit = 0;
                                  soldUnit <
                                      (int.tryParse(
                                            '${sale['quantity'] ?? 0}',
                                          ) ??
                                          0);
                                  soldUnit++
                                )
                                  ListTile(
                                    title: Text(
                                      [
                                        if (isCoffee)
                                          '${record['name'] ?? 'Beverage'} - ${sale['coffeeSize'] ?? sale['variant'] ?? sale['size'] ?? 'Size'}'
                                        else
                                          '${sale['name'] ?? record['name'] ?? 'Item'}'
                                              '${'${sale['variant'] ?? ''}'.trim().isEmpty ? '' : ' (${sale['variant']})'}',
                                        'Sold-1',
                                        if (allocationSaleUnitPrice(sale)
                                            case final unitPrice?)
                                          formatMoney(unitPrice),
                                      ].join(' · '),
                                    ),
                                    subtitle: Text(
                                      '${dateLabel(sale['soldAt'])} · ${timeLabel(sale['soldAt'])}',
                                    ),
                                  ),
                            ],
                          ),
                        );
                      },
                    ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (bundle && !widget.readOnly)
            FilledButton(
              onPressed:
                  busy ||
                      selected.isEmpty ||
                      (action == 'convert' && target == null)
                  ? null
                  : submit,
              child: Text(busy ? 'Submitting...' : 'Submit request'),
            ),
        ],
      ),
    );
  }
}

class _BatchInfoChip extends StatelessWidget {
  const _BatchInfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.primaryDark),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.primaryDark,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ReconciliationRequestsButton extends StatelessWidget {
  const ReconciliationRequestsButton({super.key, this.database});
  final FirebaseFirestore? database;
  @override
  Widget build(BuildContext context) {
    void open() => showDialog<void>(
      context: context,
      builder: (_) =>
          _RequestsDialog(db: database ?? FirebaseFirestore.instance),
    );
    final db = database ?? FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('inventory_reconciliations')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final icon = Badge.count(
          count: snapshot.data?.docs.length ?? 0,
          isLabelVisible: (snapshot.data?.docs.isNotEmpty ?? false),
          backgroundColor: Colors.red,
          child: const Icon(Icons.rule_folder_outlined),
        );
        if (MediaQuery.sizeOf(context).width < 600) {
          return IconButton.filledTonal(
            tooltip: snapshot.hasError
                ? 'Unable to load reconciliation requests'
                : 'Reconciliation requests',
            onPressed: open,
            icon: icon,
          );
        }
        return FilledButton.icon(
          onPressed: open,
          icon: icon,
          label: const Text('Reconciliation'),
        );
      },
    );
  }
}

class _RequestsDialog extends StatefulWidget {
  const _RequestsDialog({required this.db});
  final FirebaseFirestore db;
  @override
  State<_RequestsDialog> createState() => _RequestsDialogState();
}

class _RequestsDialogState extends State<_RequestsDialog> {
  bool busy = false;
  String? error;
  String search = '';
  int tab = 0;
  DateTime? rangeStart;
  DateTime? rangeEnd;
  late final stream = widget.db
      .collection('inventory_reconciliations')
      .snapshots();

  DateTime? requestDate(Map<String, dynamic> data) {
    final value = data['status'] == 'pending'
        ? data['createdAt']
        : data['reviewedAt'] ?? data['createdAt'];
    return value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse('$value');
  }

  Future<void> pickDateRange() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: rangeStart ?? now,
        end: rangeEnd ?? rangeStart ?? now,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        rangeStart = DateUtils.dateOnly(picked.start);
        rangeEnd = DateUtils.dateOnly(picked.end);
      });
    }
  }

  Future<void> decide(String id, bool approve) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final actor = await resolveSessionActor(widget.db, admin: true);
      await InventoryReconciliationService(
        widget.db,
      ).decide(id, approve: approve, actorId: actor.id);
    } catch (e) {
      if (mounted) setState(() => error = e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String dateLabel(DateTime? value) => value == null
      ? '--'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Dialog(
      insetPadding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 600 ? 8 : 20,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight:
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              32,
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 14, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDeep, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.rule_folder_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reconciliation requests',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Review bundle conversions and unbundle requests',
                          style: TextStyle(
                            color: Color(0xFFF9DCE5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (value) => setState(
                              () => search = value.trim().toLowerCase(),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search branch, bundle, item, or staff',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppColors.primaryDark,
                              ),
                              suffixIcon: IconButton(
                                tooltip: 'Filter by date range',
                                onPressed: pickDateRange,
                                icon: const Icon(
                                  Icons.calendar_month_rounded,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceTint,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (rangeStart != null || tab == 1)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InputChip(
                            avatar: const Icon(
                              Icons.date_range_rounded,
                              size: 17,
                              color: AppColors.primaryDark,
                            ),
                            label: Text(
                              rangeStart == null
                                  ? 'Completed today'
                                  : '${dateLabel(rangeStart)} – ${dateLabel(rangeEnd)}',
                            ),
                            onDeleted: () => setState(() {
                              rangeStart = null;
                              rangeEnd = null;
                            }),
                            backgroundColor: AppColors.blush,
                            side: BorderSide.none,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceTint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          _requestTab('Pending', 0),
                          _requestTab('Completed', 1),
                        ],
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: stream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text(
                              'Unable to load requests: ${snapshot.error}',
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            );
                          }
                          final all = snapshot.data!.docs;
                          final docs =
                              all.where((doc) {
                                final data = doc.data();
                                final status = '${data['status'] ?? ''}';
                                final pending = status == 'pending';
                                if (pending != (tab == 0)) return false;
                                final date = requestDate(data);
                                if (tab == 1 &&
                                    rangeStart == null &&
                                    !DateUtils.isSameDay(date, DateTime.now()))
                                  return false;
                                if (rangeStart != null) {
                                  if (date == null ||
                                      DateUtils.dateOnly(
                                        date,
                                      ).isBefore(rangeStart!) ||
                                      DateUtils.dateOnly(
                                        date,
                                      ).isAfter(rangeEnd!)) {
                                    return false;
                                  }
                                }
                                final preview = data['preview'] as Map? ?? {};
                                final details = [
                                  data['branchName'],
                                  data['name'],
                                  data['action'],
                                  data['status'],
                                  data['submittedByName'],
                                  ...bundleRows(
                                    preview['loose'],
                                  ).map((item) => item['name']),
                                  ...bundleRows(
                                    preview['bundles'],
                                  ).map((item) => item['name']),
                                ].join(' ').toLowerCase();
                                return details.contains(search);
                              }).toList()..sort((a, b) {
                                final first =
                                    requestDate(a.data()) ?? DateTime(1970);
                                final second =
                                    requestDate(b.data()) ?? DateTime(1970);
                                return second.compareTo(first);
                              });
                          if (docs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tab == 0
                                        ? Icons.inbox_outlined
                                        : Icons.task_alt_rounded,
                                    size: 42,
                                    color: AppColors.rose,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    tab == 0
                                        ? 'No matching pending requests'
                                        : 'No matching completed requests',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final searchedQuantity = docs.fold<int>(0, (
                            total,
                            doc,
                          ) {
                            final preview = doc.data()['preview'] as Map? ?? {};
                            return total +
                                aggregateUnbundlePreviewItems(
                                  preview['loose'],
                                ).fold<int>(
                                  0,
                                  (sum, item) =>
                                      sum + bundleQuantity(item['quantity']),
                                );
                          });
                          return ListView.builder(
                            itemCount: docs.length + (search.isEmpty ? 0 : 1),
                            itemBuilder: (context, index) {
                              if (search.isNotEmpty && index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'Search results: ${docs.length} requests • $searchedQuantity items',
                                    style: const TextStyle(
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              }
                              final doc =
                                  docs[index - (search.isEmpty ? 0 : 1)];
                              return _requestCard(doc.id, doc.data());
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _requestTab(String label, int index) => Expanded(
    child: Material(
      color: tab == index ? AppColors.primaryDark : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tab == index ? Colors.white : AppColors.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _requestCard(String id, Map<String, dynamic> data) {
    final preview = data['preview'] as Map? ?? {};
    final loose = aggregateUnbundlePreviewItems(preview['loose']);
    final totalLoose = loose.fold<int>(
      0,
      (total, item) => total + bundleQuantity(item['quantity']),
    );
    final bundles = bundleRows(preview['bundles']);
    final approved = data['status'] == 'approved';
    final action = data['action'] == 'convert'
        ? 'Convert to Updated Bundle'
        : 'Unbundle to Individual Items';
    final created = requestDate(data);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        iconColor: AppColors.primaryDark,
        collapsedIconColor: AppColors.primaryDark,
        leading: CircleAvatar(
          backgroundColor: approved ? const Color(0xFFE7F4EC) : AppColors.blush,
          child: Icon(
            approved ? Icons.check_rounded : Icons.hourglass_top_rounded,
            color: approved ? const Color(0xFF27834A) : AppColors.primaryDark,
          ),
        ),
        title: Text(
          '${data['branchName'] ?? 'Branch'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '$action  •  ${approved ? 'Approved' : data['status'] ?? 'Pending'}  •  ${dateLabel(created)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${data['name'] ?? 'Bundle'} ×${data['quantity'] ?? 0}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDeep,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(label: Text(action)),
              Chip(label: Text('Bundles (${data['quantity'] ?? 0})')),
              if (totalLoose > 0) Chip(label: Text('Items ($totalLoose)')),
            ],
          ),
          if (data['status'] != 'pending')
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Reviewed: ${dateLabel(created)} • ${data['reviewedByName'] ?? 'Super admin'}',
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Submitted by ${data['submittedByName'] ?? 'Staff'}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (loose.isNotEmpty) ...[
            _requestSectionLabel(
              'Items to unbundle • $totalLoose total',
              Icons.inventory_2_outlined,
            ),
            for (final item in loose)
              _requestItem(
                '${item['name'] ?? 'Item'}',
                '+${item['quantity'] ?? 0}',
                'Expiry: ${item['expirationDate'] ?? '--'}',
              ),
          ],
          if (bundles.isNotEmpty) ...[
            _requestSectionLabel('Converted bundles', Icons.all_inbox_rounded),
            for (final item in bundles)
              _requestItem(
                '${item['name'] ?? 'Bundle'}',
                '×${item['quantity'] ?? 0}',
                'Expiry: ${item['expirationDate'] ?? '--'}',
              ),
          ],
          if (loose.isEmpty && bundles.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No item details recorded.'),
            ),
          if (data['status'] == 'pending')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => decide(id, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.rose),
                    ),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : () => decide(id, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _requestSectionLabel(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 7, top: 4),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppColors.primaryDark),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.primaryDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _requestItem(String name, String quantity, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            quantity,
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showBranchBatchHistory(
  BuildContext context,
  String branchId,
  FirebaseFirestore db,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Batch history'),
    content: SizedBox(
      width: 620,
      height: 420,
      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: db
            .collection('staff_inventory')
            .where('staffId', isEqualTo: branchId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Text(
              'Unable to load batch history. Please try again.',
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final groups =
              <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            final key = data['isBundle'] == true
                ? bundleInventoryGroupKey(data)
                : '${data['sourceInventoryId']}';
            groups.putIfAbsent(key, () => doc);
          }
          if (groups.isEmpty)
            return const Text('No allocation batches recorded.');
          return ListView(
            children: [
              for (final doc in groups.values)
                ListTile(
                  title: Text('${doc.data()['name'] ?? 'Inventory'}'),
                  subtitle: const Text('View allocated and depleted batches'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showInventoryBatches(
                    context,
                    allocationId: doc.id,
                    scopeIds: [branchId],
                    database: db,
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
