import 'inventory_records_table.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

Future<void> showAdminInventoryRecords(
  BuildContext context, {
  String type = 'Categories',
  bool expired = false,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SizedBox(
      width: 1080,
      height: MediaQuery.sizeOf(context).height * .82,
      child: AdminVoidInventory(type: type, expired: expired, popup: true),
    ),
  ),
);

class AdminVoidInventory extends StatefulWidget {
  const AdminVoidInventory({
    super.key,
    required this.type,
    this.categoryId,
    this.expired = false,
    this.popup = false,
    this.firestore,
  });
  final String type;
  final bool popup;
  final FirebaseFirestore? firestore;
  final String? categoryId;
  final bool expired;
  @override
  State<AdminVoidInventory> createState() => _AdminVoidInventoryState();
}

class _AdminVoidInventoryState extends State<AdminVoidInventory> {
  late String? _category = widget.categoryId;
  late String _type = widget.type;
  String _query = '';
  DateTimeRange? _dates;
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  final Set<String> _restoring = {};
  bool _expired(Map data) {
    final raw = data['expirationDate'];
    final date = raw is Timestamp ? raw.toDate() : DateTime.tryParse('$raw');
    return date != null && date.isBefore(DateUtils.dateOnly(DateTime.now()));
  }

  Future<void> _restore(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic>? item,
    String field,
  ) async {
    final key = '${ref.id}-${item?['id'] ?? item?['name'] ?? 'parent'}';
    if (_restoring.contains(key)) return;
    setState(() => _restoring.add(key));
    try {
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        if (data == null) throw StateError('Record no longer exists.');
        if (item == null) {
          transaction.update(ref, {
            'isDeleted': false,
            'deletedAt': FieldValue.delete(),
            'voidReason': FieldValue.delete(),
          });
          return;
        }
        final values = (data[field] as List? ?? [])
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
        final index = values.indexWhere(
          (value) => item['id'] != null
              ? value['id'] == item['id']
              : value['name'] == item['name'] &&
                    value['removedAt'] == item['removedAt'],
        );
        if (index < 0) return;
        final restored = {...values[index]}
          ..remove('removedAt')
          ..remove('deletedAt')
          ..remove('voidReason');
        restored['isDeleted'] = false;
        if (field == 'bundleInstances') restored['status'] = 'available';
        if (field == 'removedItems') {
          values.removeAt(index);
          final active = List<dynamic>.from(data['items'] as List? ?? []);
          active.add(restored);
          transaction.update(ref, {'removedItems': values, 'items': active});
        } else {
          values[index] = restored;
          transaction.update(ref, {field: values});
        }
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Inventory restored.')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to restore inventory. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _restoring.remove(key));
    }
  }

  DateTime? _date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value');

  Widget _table(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final records =
        <
          ({
            QueryDocumentSnapshot<Map<String, dynamic>> doc,
            Map<String, dynamic> data,
            String field,
            bool parent,
          })
        >[];
    void add(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      Map<String, dynamic> data, {
      String field = '',
      bool parent = false,
    }) {
      final name = '${data['name'] ?? doc.data()['name'] ?? ''}';
      final reason = '${data['voidReason'] ?? data['reason'] ?? ''}';
      if (!'$name $reason ${data['publicId'] ?? data['id'] ?? ''}'
          .toLowerCase()
          .contains(_query))
        return;
      final date = _date(
        widget.expired
            ? data['expirationDate']
            : data['removedAt'] ?? data['deletedAt'],
      );
      if (_dates != null &&
          (date == null ||
              date.isBefore(DateUtils.dateOnly(_dates!.start)) ||
              !date.isBefore(
                DateUtils.dateOnly(_dates!.end).add(const Duration(days: 1)),
              )))
        return;
      records.add((doc: doc, data: data, field: field, parent: parent));
    }

    for (final doc in docs) {
      final data = doc.data();
      if (_type != 'Beverages' &&
          (data['isBundle'] == true) != (_type == 'Bundle'))
        continue;
      if (_type == 'Categories' && _category != null && doc.id != _category)
        continue;
      if (!widget.expired && data['isDeleted'] == true) {
        add(doc, data, parent: true);
        continue;
      }
      if (data['isDeleted'] == true) continue;
      if (_type == 'Beverages') {
        if (widget.expired && _expired(data)) add(doc, data, parent: true);
      } else if (_type == 'Bundle') {
        final instances = (data['bundleInstances'] as List? ?? [])
            .whereType<Map>()
            .toList();
        for (final instance in instances) {
          final item = Map<String, dynamic>.from(instance);
          if (widget.expired && '${item['expirationDate'] ?? ''}'.isEmpty) {
            final dates =
                ((item['items'] ?? data['items']) as List? ?? [])
                    .whereType<Map>()
                    .map((row) => _date(row['expirationDate']))
                    .whereType<DateTime>()
                    .toList()
                  ..sort();
            if (dates.isNotEmpty)
              item['expirationDate'] = dates.first
                  .toIso8601String()
                  .split('T')
                  .first;
          }
          if (widget.expired
              ? _expired(item)
              : item['isDeleted'] == true ||
                    ['void', 'voided', 'removed'].contains(item['status'])) {
            add(doc, item, field: 'bundleInstances');
          }
        }
        if (instances.isEmpty && widget.expired) {
          final effective = {...data};
          if ('${effective['expirationDate'] ?? ''}'.isEmpty) {
            final dates =
                (data['items'] as List? ?? [])
                    .whereType<Map>()
                    .map((row) => _date(row['expirationDate']))
                    .whereType<DateTime>()
                    .toList()
                  ..sort();
            if (dates.isNotEmpty)
              effective['expirationDate'] = dates.first
                  .toIso8601String()
                  .split('T')
                  .first;
          }
          if (_expired(effective)) add(doc, effective, parent: true);
        }
      } else {
        for (final field
            in widget.expired ? ['items'] : ['removedItems', 'items']) {
          for (final item in (data[field] as List? ?? []).whereType<Map>()) {
            if (widget.expired
                ? _expired(item)
                : field == 'removedItems' || item['isDeleted'] == true)
              add(doc, Map<String, dynamic>.from(item), field: field);
          }
        }
      }
    }
    records.sort(
      (a, b) =>
          (_date(
                    widget.expired
                        ? b.data['expirationDate']
                        : b.data['removedAt'] ?? b.data['deletedAt'],
                  ) ??
                  DateTime(0))
              .compareTo(
                _date(
                      widget.expired
                          ? a.data['expirationDate']
                          : a.data['removedAt'] ?? a.data['deletedAt'],
                    ) ??
                    DateTime(0),
              ),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        InventoryRecordsTable(
          headings: [
            'ID',
            'Item',
            'Qty',
            'Status',
            widget.expired ? 'Expiration date' : 'Voided on',
            if (!widget.expired) 'Reason',
            if (!widget.expired) 'Action',
          ],
          flex: {
            0: 1.4,
            1: 2.5,
            2: .8,
            3: 1.1,
            4: 1.6,
            if (!widget.expired) 5: 2.5,
          },
          rows: records.map((record) {
            final data = record.data;
            final date = _date(
              widget.expired
                  ? data['expirationDate']
                  : data['removedAt'] ?? data['deletedAt'],
            );
            return <Widget>[
              Text(
                '${data['publicId'] ?? data['bundleId'] ?? data['coffeeId'] ?? data['id'] ?? record.doc.id}',
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data['name'] ?? record.doc.data()['name'] ?? 'Item'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (!record.parent)
                    Text(
                      '${record.doc.data()['name'] ?? ''} ${record.field == 'bundleInstances' ? data['id'] ?? '' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              Text(
                '${record.field == 'bundleInstances' ? 1 : data['expiredQuantity'] ?? data['voidQuantity'] ?? data['stock'] ?? data['bundleCount'] ?? data['quantity'] ?? data['startingStock'] ?? '—'}',
              ),
              Text(widget.expired ? 'Expired' : 'Voided'),
              Text(
                date == null
                    ? 'Not recorded'
                    : MaterialLocalizations.of(context).formatFullDate(date),
              ),
              if (!widget.expired)
                Text(
                  '${data['voidReason'] ?? data['reason'] ?? 'Not recorded'}',
                ),
              if (!widget.expired)
                IconButton(
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore, color: AppColors.primaryDark),
                  onPressed: _restoring.isNotEmpty
                      ? null
                      : () => _restore(
                          record.doc.reference,
                          record.parent ? null : data,
                          record.field,
                        ),
                ),
            ];
          }).toList(),
        ),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No records match your filters.'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surfaceTint,
    appBar: AppBar(
      automaticallyImplyLeading: !widget.popup,
      title: Text(widget.expired ? 'Expired inventory' : 'Void records'),
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: TextField(
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search items',
              prefixIcon: const Icon(Icons.search),
              helperText: _dates == null
                  ? null
                  : '${MaterialLocalizations.of(context).formatMediumDate(_dates!.start)} – ${MaterialLocalizations.of(context).formatMediumDate(_dates!.end)}',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dates != null)
                    IconButton(
                      tooltip: 'Clear date filter',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dates = null),
                    ),
                  IconButton(
                    tooltip: 'Filter by date',
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () async {
                      final dates = await showDateRangePicker(
                        context: context,
                        initialDateRange: _dates,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (dates != null && mounted)
                        setState(() => _dates = dates);
                    },
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey(_type),
            stream: _db
                .collection(
                  _type == 'Beverages' ? 'coffee_products' : 'sales_inventory',
                )
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Center(child: Text('Unable to load records.'));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              if (_type != 'Beverages') return _table(snapshot.data!.docs);
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db.collection('coffee_addons').snapshots(),
                builder: (context, addons) {
                  if (addons.hasError)
                    return const Center(
                      child: Text('Unable to load add-on records.'),
                    );
                  if (!addons.hasData)
                    return const Center(child: CircularProgressIndicator());
                  return _table([...snapshot.data!.docs, ...addons.data!.docs]);
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
