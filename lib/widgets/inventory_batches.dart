import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/allocation_checklist_service.dart';
import '../services/bundle_stock_service.dart';
import '../services/inventory_reconciliation_service.dart';
import '../services/session_actor.dart';
import '../services/number_format.dart';

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
    final key = id.isNotEmpty ? id.toLowerCase() : '$name|$variant';
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
  return bundleRows(record['items']).where((item) {
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
  FirebaseFirestore? database,
}) => showDialog<void>(
  context: context,
  builder: (_) => _BatchDialog(
    allocationId: allocationId,
    scopeIds: scopeIds,
    itemId: itemId,
    db: database ?? FirebaseFirestore.instance,
  ),
);

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({
    required this.allocationId,
    required this.scopeIds,
    required this.db,
    this.itemId,
  });
  final String allocationId;
  final List<String> scopeIds;
  final String? itemId;
  final FirebaseFirestore db;
  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final original =
          (await widget.db
                  .collection('staff_inventory')
                  .doc(widget.allocationId)
                  .get())
              .data();
      if (original == null || !widget.scopeIds.contains(original['staffId'])) {
        throw StateError('This allocation is no longer available.');
      }
      final docs = await widget.db
          .collection('staff_inventory')
          .where('staffId', isEqualTo: original['staffId'])
          .get();
      final rows = docs.docs
          .where(
            (d) =>
                d.data()['isDeleted'] != true &&
                (d.data()['isBundle'] == true) ==
                    (original['isBundle'] == true) &&
                (original['isBundle'] == true
                    ? bundleInventoryGroupKey(d.data()) ==
                          bundleInventoryGroupKey(original)
                    : d.data()['sourceInventoryId'] ==
                          original['sourceInventoryId']),
          )
          .map((d) => <String, dynamic>{...d.data(), '_id': d.id})
          .toList();
      rows.sort(
        (a, b) => date(b['assignedAt']).compareTo(date(a['assignedAt'])),
      );
      if (mounted) setState(() => records = rows);
    } catch (e) {
      if (mounted) setState(() => error = e is StateError ? e.message : '$e');
    }
  }

  DateTime date(dynamic value) => value is Timestamp
      ? value.toDate()
      : DateTime.tryParse('$value') ?? DateTime(1970);
  String dateLabel(dynamic value) => value == null || '$value'.isEmpty
      ? '--'
      : date(value).toIso8601String().split('T').first;
  String originBatchLabel(
    Map<String, dynamic> instance,
    Map<String, String> labels,
  ) {
    final originId = instance['originBatchId'];
    if (originId == null) return '';
    final label = labels['$originId'] ?? 'Batch - 001';
    return '\n(Og ${label.replaceFirst('Batch - ', 'Batch-')})';
  }

  Future<void> submit() async {
    if (selectedAllocation == null || selected.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
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
        '${record['_id']}': allocationInstanceBatches(
          record,
          '${record['_id']}',
        ),
    };
    final visibleRecords = (records ?? <Map<String, dynamic>>[])
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
        title: const Text('Allocation batches'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (records == null && error == null)
                  const LinearProgressIndicator(),
                if (bundle) ...[
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
                  const Text(
                    'Select available bundles from one allocation batch. Stock is reserved until the administrator reviews your request.',
                  ),
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No available bundles to request.'),
                  ),
                if (bundle)
                  for (final record in visibleRecords)
                    for (final batch
                        in batchesByAllocation['${record['_id']}'] ?? [])
                      Builder(
                        builder: (context) {
                          final instances =
                              batch['instances'] as List<Map<String, dynamic>>;
                          final selectedCount = instances
                              .where(
                                (instance) =>
                                    selected.contains('${instance['id']}'),
                              )
                              .length;
                          final allSelected = selectedCount == instances.length;
                          final someSelected =
                              selectedCount > 0 && !allSelected;
                          return Card(
                            child: ExpansionTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${record['name']} - ${dateLabel(batch['assignedAt'])}',
                                    ),
                                  ),
                                  Checkbox(
                                    tristate: true,
                                    value: allSelected
                                        ? true
                                        : someSelected
                                        ? null
                                        : false,
                                    onChanged: busy
                                        ? null
                                        : (checked) => setState(
                                            () => toggleBatchSelection(
                                              '${record['_id']}',
                                              instances,
                                              checked == true,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${record['origin'] == 'unbundle' ? 'Unbundle' : 'Allocated'} | ${instanceBatchLabels['${batch['batchId']}'] ?? 'Batch - 001'}',
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
                                      return ListTile(
                                        title: Text(
                                          '${allocationInstanceLabel(instance, index)} | ${formatMoney(num.tryParse('${instance['price'] ?? record['price']}') ?? 0)}',
                                        ),
                                        subtitle: Text(
                                          '${instance['status'] ?? 'available'} | Expiry: ${dateLabel(instance['expirationDate'])}\n${bundleRows(instance['items']).map((i) => '${i['name']} x${i['quantity']} (${dateLabel(i['expirationDate'])})').join('\n')}${originBatchLabel(instance, instanceBatchLabels)}',
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
                        final itemNames = items
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
                        return Card(
                          child: ExpansionTile(
                            title: Text(title),
                            subtitle: Text(
                              '${record['origin'] == 'unbundle' || items.any((item) => item['origin'] == 'unbundle') ? 'Unbundle' : 'Allocated'} | ${batchLabels['${record['_id']}'] ?? 'Batch - 001'}',
                            ),
                            children: [
                              for (final item in items)
                                ListTile(
                                  title: Text(
                                    '${item['name']} - ${item['stock'] ?? item['startingStock']} remaining',
                                  ),
                                  subtitle: Text(
                                    '${formatMoney(num.tryParse('${item['price']}') ?? 0)} | Expiry: ${dateLabel(item['expirationDate'])}${item['origin'] == 'unbundle' ? '\nUnbundle: +${item['unbundledQuantity']}' : ''}',
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
          if (bundle)
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
    if (MediaQuery.sizeOf(context).width < 600) {
      return IconButton.filledTonal(
        tooltip: 'Reconciliation requests',
        onPressed: open,
        icon: const Icon(Icons.rule_folder_outlined),
      );
    }
    return FilledButton.icon(
      onPressed: open,
      icon: const Icon(Icons.rule_folder_outlined),
      label: const Text('Reconciliation'),
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
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
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
                          _requestTab('Pending Requests', 0),
                          _requestTab('Completed Requests', 1),
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
                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
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
