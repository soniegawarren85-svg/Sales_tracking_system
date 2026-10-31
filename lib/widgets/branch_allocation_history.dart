import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';
import '../services/checklist_status.dart';
import '../services/allocation_history_metadata.dart';
import '../services/inventory_display_ids.dart';
import '../theme/app_colors.dart';

DateTime allocationDate(Map<String, dynamic> data) {
  final raw = data['createdAt'] ?? data['assignedAt'];
  return raw is Timestamp
      ? raw.toDate()
      : DateTime.tryParse('$raw') ?? DateTime(0);
}

List<Map<String, dynamic>> allocationItems(Map<String, dynamic> record) {
  final type = AllocationChecklistService.type(record);
  if (type != 'Categories') {
    return [
      {
        ...record,
        '_type': type,
        '_quantity': record['isBundle'] == true
            ? AllocationChecklistService.quantity(
                record['bundleCount'] ?? record['quantity'],
              )
            : null,
      },
    ];
  }
  return AllocationChecklistService.rows(record['items'])
      .map(
        (item) => {
          ...item,
          '_type': AllocationChecklistService.type({...record, ...item}),
          '_category': item['categoryName'] ?? record['name'],
          '_quantity': AllocationChecklistService.type(item) == 'Beverages'
              ? null
              : AllocationChecklistService.quantity(
                  item['quantity'] ?? item['startingStock'] ?? item['stock'],
                ),
        },
      )
      .toList();
}

List<Map<String, dynamic>> groupAllocations(
  List<Map<String, dynamic>> records,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final record in records) {
    final key = '${record['deliveryId'] ?? record['_id']}';
    groups.putIfAbsent(key, () => []).add(record);
  }
  return groups.values.map((records) {
    final items = records.expand(allocationItems).toList();
    final complete = records.every(
      (r) => ChecklistStatus.label(r) == ChecklistStatus.received,
    );
    final allocatorNames = records
        .map((record) => '${record['allocatedByName'] ?? ''}'.trim())
        .where(
          (name) => name.isNotEmpty && name.toLowerCase() != 'not recorded',
        )
        .toSet();
    final allocatorIds = records
        .map((record) => '${record['allocatedByAdminId'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty && id.toLowerCase() != 'not recorded')
        .toSet();
    return {
      ...records.first,
      if (allocatorNames.isNotEmpty)
        'allocatedByName': allocatorNames.join(', '),
      if (allocatorIds.isNotEmpty)
        'allocatedByAdminId': allocatorIds.join(', '),
      '_records': records,
      '_items': items,
      '_complete': complete,
      '_quantity': items.fold<int>(
        0,
        (total, item) =>
            total + AllocationChecklistService.quantity(item['_quantity']),
      ),
      '_catalogCount': items.where((item) => item['_quantity'] == null).length,
    };
  }).toList()..sort((a, b) => allocationDate(b).compareTo(allocationDate(a)));
}

final _historyCache = Expando<Map<String, List<Map<String, dynamic>>>>();

Map<String, List<Map<String, dynamic>>> _cachedHistory(FirebaseFirestore db) =>
    _historyCache[db] ??= {};

Stream<List<Map<String, dynamic>>> branchAllocationHistory(
  FirebaseFirestore db,
  String branchId,
) {
  final metadata = AllocationHistoryMetadata(db);
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? deliveries, legacy;
  late StreamController<List<Map<String, dynamic>>> controller;
  final subscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  var revision = 0;
  var cancelled = false;
  void emit() {
    final version = ++revision;
    final records = (deliveries ?? [])
        .where((doc) => doc.data()['kind'] != 'return')
        .map((doc) => {...doc.data(), '_id': doc.id})
        .toList();
    final ids = records.map((r) => r['_id']).toSet();
    for (final doc
        in legacy ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
      final data = doc.data();
      if (data['type'] != 'assignment' || ids.contains(data['allocationId'])) {
        continue;
      }
      records.add({...data, '_id': doc.id, 'status': ChecklistStatus.received});
    }
    void publish() {
      if (cancelled || version != revision) return;
      final snapshot = List<Map<String, dynamic>>.of(records);
      _cachedHistory(db)[branchId] = snapshot;
      controller.add(snapshot);
    }

    publish();
    // Render saved records immediately. Legacy profile lookups must never
    // block the whole list, or overwrite a newer checklist snapshot.
    for (var index = 0; index < records.length; index++) {
      final position = index;
      unawaited(
        metadata
            .resolve(records[position])
            .then((resolved) {
              records[position] = resolved;
              publish();
            })
            .catchError((Object _) {
              // Keep the saved record visible when optional metadata is unavailable.
            }),
      );
    }
  }

  controller = StreamController<List<Map<String, dynamic>>>(
    onListen: () {
      for (final collection in [
        'allocation_checklist',
        'staff_inventory_history',
      ]) {
        subscriptions.add(
          db
              .collection(collection)
              .where('staffId', isEqualTo: branchId)
              .snapshots()
              .listen((snapshot) {
                if (collection == 'allocation_checklist') {
                  deliveries = snapshot.docs;
                } else {
                  legacy = snapshot.docs;
                }
                emit();
              }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      cancelled = true;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}

Future<void> showBranchAllocationHistory(
  BuildContext context,
  String branchId, {
  FirebaseFirestore? database,
  List<Map<String, dynamic>>? initialRecords,
}) => showDialog<void>(
  context: context,
  builder: (_) => AllocationHistoryDialog(
    branchId: branchId,
    database: database ?? FirebaseFirestore.instance,
    initialRecords: initialRecords,
  ),
);

class AllocationHistoryActions extends StatelessWidget {
  const AllocationHistoryActions({
    super.key,
    required this.branchId,
    this.database,
  });
  final String branchId;
  final FirebaseFirestore? database;
  @override
  Widget build(BuildContext context) {
    final db = database ?? FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('allocation_checklist')
          .where('staffId', isEqualTo: branchId)
          .snapshots(),
      builder: (context, snapshot) {
        final pendingCount =
            snapshot.data?.docs
                .where(
                  (doc) =>
                      doc.data()['kind'] != 'return' &&
                      doc.data()['isDeleted'] != true &&
                      ChecklistStatus.incomingOpen(doc.data()),
                )
                .map(
                  (doc) =>
                      '${doc.data()['batchId'] ?? doc.data()['allocationId'] ?? doc.id}',
                )
                .toSet()
                .length ??
            0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Pending allocations',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AllocationHistoryDialog(
                  branchId: branchId,
                  database: db,
                  pendingOnly: true,
                  initialRecords: snapshot.data?.docs
                      .where((doc) => doc.data()['kind'] != 'return')
                      .map(
                        (doc) => <String, dynamic>{
                          ...doc.data(),
                          '_id': doc.id,
                        },
                      )
                      .toList(),
                ),
              ),
              icon: Badge(
                label: Text('$pendingCount'),
                isLabelVisible: pendingCount > 0,
                backgroundColor: Colors.red,
                child: const Icon(Icons.pending_actions),
              ),
            ),
            IconButton(
              tooltip: 'Allocation history',
              onPressed: () => showBranchAllocationHistory(
                context,
                branchId,
                database: db,
                initialRecords: snapshot.data?.docs
                    .where((doc) => doc.data()['kind'] != 'return')
                    .map(
                      (doc) => <String, dynamic>{...doc.data(), '_id': doc.id},
                    )
                    .toList(),
              ),
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        );
      },
    );
  }
}

class AllocationHistoryDialog extends StatefulWidget {
  const AllocationHistoryDialog({
    super.key,
    required this.branchId,
    required this.database,
    this.pendingOnly = false,
    this.initialRecords,
  });
  final String branchId;
  final FirebaseFirestore database;
  final bool pendingOnly;
  final List<Map<String, dynamic>>? initialRecords;
  @override
  State<AllocationHistoryDialog> createState() =>
      _AllocationHistoryDialogState();
}

class _AllocationHistoryDialogState extends State<AllocationHistoryDialog> {
  late final _stream = branchAllocationHistory(
    widget.database,
    widget.branchId,
  );
  String _query = '';
  bool _issuesOnly = false;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  DateTime? _endDay;
  final _expanded = <String>{};

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _day, end: _endDay ?? _day),
    );
    if (picked != null && mounted) {
      setState(() {
        _day = picked.start;
        _endDay = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _frame(
    context,
    widget.pendingOnly ? 'Pending allocations' : 'Allocation history',
    Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: 'Search allocations, admin, or items',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!widget.pendingOnly)
                    IconButton.filledTonal(
                      tooltip: 'Filter by date',
                      onPressed: _pickDates,
                      icon: const Icon(Icons.date_range_outlined),
                    ),
                ],
              ),
              if (!widget.pendingOnly)
                Text(
                  '${MaterialLocalizations.of(context).formatShortDate(_day)} – ${MaterialLocalizations.of(context).formatShortDate(_endDay ?? _day)}',
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _stream,
            initialData:
                _cachedHistory(widget.database)[widget.branchId] ??
                widget.initialRecords,
            builder: (context, snapshot) {
              if (snapshot.hasError && !snapshot.hasData) {
                return const Center(
                  child: Text('Unable to load allocation history.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final hasIssues = snapshot.data!.any(
                (record) =>
                    ChecklistStatus.label(record) == ChecklistStatus.issue,
              );
              final scoped = snapshot.data!
                  .where(
                    (record) => widget.pendingOnly
                        ? ChecklistStatus.incomingOpen(record) &&
                              (!_issuesOnly ||
                                  ChecklistStatus.label(record) ==
                                      ChecklistStatus.issue)
                        : ChecklistStatus.label(record) ==
                              ChecklistStatus.received,
                  )
                  .toList();
              final records = groupAllocations(scoped).where((record) {
                final at = allocationDate(record);
                final withinDate =
                    !at.toLocal().isBefore(_day) &&
                    at.toLocal().isBefore(
                      (_endDay ?? _day).add(const Duration(days: 1)),
                    );
                final search =
                    '${record['allocatedByName']} ${record['branchName']} ${record['staffName']} ${record['_items']}'
                        .toLowerCase();
                return (widget.pendingOnly || withinDate) &&
                    search.contains(_query);
              }).toList();
              return Column(
                children: [
                  if (widget.pendingOnly && hasIssues)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FilterChip(
                        selected: _issuesOnly,
                        onSelected: (value) =>
                            setState(() => _issuesOnly = value),
                        avatar: const Badge(
                          backgroundColor: Colors.red,
                          child: Icon(Icons.report_outlined),
                        ),
                        label: const Text('Issue reported'),
                      ),
                    ),
                  Expanded(
                    child: records.isEmpty
                        ? const Center(child: Text('No matching allocations.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: records.length,
                            itemBuilder: (context, index) =>
                                _card(records[index]),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _card(Map<String, dynamic> data) {
    final complete = data['_complete'] == true;
    final expansionKey = '${data['deliveryId'] ?? data['_id']}';
    final records = AllocationChecklistService.rows(data['_records']);
    final received = records
        .where((r) => ChecklistStatus.label(r) == ChecklistStatus.received)
        .length;
    final issueReports = records
        .where((r) => ChecklistStatus.label(r) == ChecklistStatus.issue)
        .toList();
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.primaryDeep.withValues(alpha: .15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Allocated',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (issueReports.isNotEmpty)
                        const Chip(
                          avatar: Icon(Icons.report_outlined, size: 18),
                          label: Text('Issue Reported'),
                        ),
                      Chip(
                        avatar: Icon(
                          complete
                              ? Icons.check_circle_outline
                              : Icons.schedule,
                          size: 18,
                          color: complete
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                        ),
                        label: Text(complete ? 'Received' : 'Pending'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(_date(context, allocationDate(data), time: true)),
            const SizedBox(height: 16),
            Text('Allocated by: ${data['allocatedByName'] ?? 'Not recorded'}'),
            if ('${data['allocatedByAdminId'] ?? ''}'.trim().isNotEmpty)
              Text('Admin ID: ${data['allocatedByAdminId']}'),
            const SizedBox(height: 6),
            Text(
              'Branch: ${data['branchName'] ?? data['staffName'] ?? widget.branchId}',
            ),
            Text(
              'Branch ID: ${data['branchCode'] ?? data['branchId'] ?? data['staffId'] ?? widget.branchId}',
            ),
            const SizedBox(height: 6),
            Text(_quantity(data)),
            for (final receiver in records.where(
              (r) => ChecklistStatus.label(r) == ChecklistStatus.received,
            )) ...[
              const SizedBox(height: 6),
              Text(
                'Received by: ${receiver['confirmedByName'] ?? 'Not recorded'}',
              ),
              Text('Role: ${receiver['confirmedByRole'] ?? 'Not recorded'}'),
              Text(
                'Receiver ID: ${receiver['confirmedByPublicId'] ?? 'Not recorded'}',
              ),
            ],
            if (!complete && received > 0)
              Text(
                '$received of ${records.length} allocation records received',
              ),
            for (final record in records)
              if (![
                ChecklistStatus.received,
                ChecklistStatus.awaiting,
              ].contains(ChecklistStatus.label(record)))
                Text(
                  '${record['name'] ?? 'Allocation'}: ${ChecklistStatus.label(record)}',
                ),
            const Divider(height: 28),
            LayoutBuilder(
              builder: (context, constraints) {
                final reportButton = TextButton.icon(
                  onPressed: () => _showIssueReports(context, issueReports),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View issue report'),
                );
                final itemsButton = IconButton(
                  tooltip: _expanded.contains(expansionKey)
                      ? 'Collapse items'
                      : 'Expand items',
                  onPressed: () => setState(() {
                    if (!_expanded.add(expansionKey))
                      _expanded.remove(expansionKey);
                  }),
                  icon: Icon(
                    _expanded.contains(expansionKey)
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (issueReports.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: reportButton,
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: itemsButton,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    if (issueReports.isNotEmpty) reportButton,
                    const Spacer(),
                    itemsButton,
                  ],
                );
              },
            ),
            if (_expanded.contains(expansionKey))
              SizedBox(
                height: 420,
                child: _AllocationDetails(
                  key: ValueKey('$expansionKey:${data['_items']}'),
                  data: data,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showIssueReports(
  BuildContext context,
  List<Map<String, dynamic>> reports,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Issue report details'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < reports.length; index++) ...[
              if (index > 0) const Divider(height: 24),
              Text(
                '${reports[index]['name'] ?? 'Allocation'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Reason: ${reports[index]['issueReason'] ?? 'Not recorded'}',
              ),
              Text(
                'Reported by: ${reports[index]['reportedByName'] ?? reports[index]['reportedBy'] ?? 'Not recorded'}',
              ),
              if (_reportedDate(reports[index]['reportedAt']) case final date?)
                Text('Reported: ${_date(context, date, time: true)}'),
            ],
          ],
        ),
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

DateTime? _reportedDate(dynamic value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  final String date => DateTime.tryParse(date),
  _ => null,
};

String _quantity(Map<String, dynamic> data) {
  final count = data['_quantity'];
  final catalog = data['_catalogCount'] as int;
  if ((data['_items'] as List).isEmpty) return 'Qty: Not recorded';
  return 'Qty: $count allocated units${catalog > 0 ? ' • $catalog catalog items' : ''}';
}

String _date(BuildContext context, DateTime date, {bool time = false}) =>
    date.year == 0
    ? 'Date not recorded'
    : '${MaterialLocalizations.of(context).formatMediumDate(date)}${time ? ' • ${TimeOfDay.fromDateTime(date).format(context)}' : ''}';

Widget _frame(BuildContext context, String title, Widget body) => Dialog(
  insetPadding: const EdgeInsets.all(16),
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  child: SizedBox(
    width: 680,
    height: 700,
    child: Column(
      children: [
        Container(
          color: AppColors.primaryDeep,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    ),
  ),
);

class _AllocationDetails extends StatefulWidget {
  const _AllocationDetails({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<_AllocationDetails> createState() => _AllocationDetailsState();
}

class _AllocationDetailsState extends State<_AllocationDetails> {
  String _query = '';
  late final _items = AllocationChecklistService.rows(widget.data['_items']);
  late String _type = _items.isEmpty
      ? 'Categories'
      : '${_items.first['_type']}';
  @override
  Widget build(BuildContext context) {
    final visible = _items
        .where(
          (item) =>
              item['_type'] == _type &&
              '${item['name']} ${item['flavor']} ${item['variant']} ${item['_category']}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.data['branchName'] ?? widget.data['staffName'] ?? 'Branch'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search allocated items',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in ['Categories', 'Bundle', 'Beverages'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '$type (${_items.where((i) => i['_type'] == type).length})',
                          ),
                          selected: _type == type,
                          onSelected: (_) => setState(() => _type = type),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No allocated items to display.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    final parts = AllocationChecklistService.rows(
                      item['items'],
                    );
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item['name'] ?? 'Item'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (item['_category'] != null)
                              Text('${item['_category']}'),
                            if (item['flavor'] != null ||
                                item['variant'] != null)
                              Text('${item['flavor'] ?? item['variant']}'),
                            if (inventoryDisplayId(item) != '--')
                              Text('Item ID: ${inventoryDisplayId(item)}'),
                            const SizedBox(height: 10),
                            Text(
                              item['_quantity'] == null
                                  ? 'Catalog access'
                                  : 'Qty: ${item['_quantity']}',
                            ),
                            Text(
                              'Unit price: ${item['price'] == null && item['priceDelta'] == null && item['bundlePrice'] == null ? 'Not recorded' : '₱${item['bundlePrice'] ?? item['price'] ?? item['priceDelta']}'}',
                            ),
                            Text(
                              'Expiry: ${item['expirationDate'] == null || '${item['expirationDate']}'.isEmpty ? 'Not recorded' : item['expirationDate']}',
                            ),
                            if (item['_type'] == 'Bundle' &&
                                parts.isNotEmpty) ...[
                              const Divider(height: 24),
                              const Text(
                                'Bundle contents',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              for (final part in parts)
                                Text(
                                  '${part['name'] ?? 'Item'} • Qty: ${part['quantity'] ?? part['qty'] ?? 'Not recorded'}',
                                ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
