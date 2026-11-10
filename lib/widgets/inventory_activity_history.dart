import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class InventoryActivityHistoryButton extends StatelessWidget {
  const InventoryActivityHistoryButton({
    super.key,
    required this.branchId,
    required this.type,
    this.addons = false,
    this.database,
  });

  final String branchId;
  final String type;
  final bool addons;
  final FirebaseFirestore? database;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Inventory activity history',
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _InventoryActivityHistoryDialog(
        branchId: branchId,
        type: type,
        addons: addons,
        database: database ?? FirebaseFirestore.instance,
      ),
    ),
    icon: const Icon(Icons.history_rounded),
    color: Colors.blueGrey,
  );
}

class _InventoryActivityHistoryDialog extends StatefulWidget {
  const _InventoryActivityHistoryDialog({
    required this.branchId,
    required this.type,
    required this.addons,
    required this.database,
  });

  final String branchId;
  final String type;
  final bool addons;
  final FirebaseFirestore database;

  @override
  State<_InventoryActivityHistoryDialog> createState() =>
      _InventoryActivityHistoryDialogState();
}

class _InventoryActivityHistoryDialogState
    extends State<_InventoryActivityHistoryDialog> {
  final _search = TextEditingController();
  DateTimeRange? _dateRange = () {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateTimeRange(start: today, end: today);
  }();
  late final Future<List<String>> _branchStaffIds = widget.database
      .collection('staff_requests')
      .where('branchIds', arrayContains: widget.branchId)
      .get()
      .then(
        (snapshot) => snapshot.docs
            .expand((doc) {
              final data = doc.data();
              return [doc.id, data['uid'], data['userId'], data['staffId']];
            })
            .map((id) => '${id ?? ''}'.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .take(30)
            .toList(),
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse('$value')?.toLocal();
  }

  bool _matchesType(Map<String, dynamic> item) {
    final bundle = item['isBundle'] == true;
    final addon =
        item['isAddon'] == true ||
        item['sourceCollection'] == 'coffee_addons' ||
        '${item['type'] ?? ''}'.toLowerCase().contains('add-on');
    final beverage =
        item['isCoffee'] == true ||
        '${item['coffeeSize'] ?? ''}'.trim().isNotEmpty ||
        '${item['size'] ?? ''}'.trim().isNotEmpty;
    if (widget.addons) return addon;
    switch (widget.type) {
      case 'Categories':
        return !bundle && !beverage && !addon;
      case 'Bundle':
        return bundle;
      case 'Beverages':
        return beverage && !addon;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _salesRows(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final sale = doc.data();
      final status = '${sale['status'] ?? ''}'.toLowerCase();
      if (sale['isVoided'] == true ||
          {'void', 'voided', 'cancelled', 'canceled'}.contains(status)) {
        continue;
      }
      final items = (sale['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(_matchesType)
          .toList();
      if (items.isEmpty) continue;
      final returned =
          '${sale['type'] ?? ''}'.toLowerCase() == 'refund' ||
          '${sale['status'] ?? ''}'.toLowerCase() == 'refund';
      final names = items
          .map((item) {
            final variant = '${item['variant'] ?? item['coffeeSize'] ?? ''}'
                .trim();
            final name = '${item['name'] ?? 'Item'}';
            return variant.isEmpty ? name : '$name ($variant)';
          })
          .toSet()
          .join(', ');
      final quantity = items.fold<int>(
        0,
        (total, item) =>
            total +
            ((item['quantity'] as num?)?.toInt() ??
                int.tryParse('${item['quantity']}') ??
                0),
      );
      final total = items.fold<double>(
        0,
        (sum, item) =>
            sum +
            (((item['price'] as num?)?.toDouble() ?? 0) *
                ((item['quantity'] as num?)?.toDouble() ?? 0)),
      );
      rows.add({
        'createdAt': sale['timestamp'] ?? sale['createdAt'],
        'title': returned ? 'Returned sale' : 'Sold',
        'description': names,
        'quantity': quantity,
        'amount': total,
        'actor': sale['staffName'] ?? sale['userName'] ?? 'Branch staff',
        'source': 'sale',
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _activityRows(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) => [
    for (final doc in docs)
      if (_activityMatches(doc.data()))
        {
          'createdAt': doc.data()['createdAt'],
          'title': _actionLabel(doc.data()['action']),
          'description': doc.data()['description'] ?? 'Inventory activity',
          'quantity': doc.data()['details']?['quantity'] ?? 0,
          'amount': 0,
          'actor': doc.data()['actorName'] ?? 'User',
          'source': 'activity',
        },
  ];

  List<Map<String, dynamic>> _adjustmentRows(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) => [
    for (final doc in docs)
      if (_adjustmentMatches(doc.data()))
        {
          'createdAt': doc.data()['createdAt'],
          'title': _adjustmentTitle(doc.data()),
          'description':
              [
                    doc.data()['itemName'] ?? 'Inventory item',
                    doc.data()['reason'],
                    doc.data()['comment'],
                  ]
                  .where((value) => value != null && '$value'.trim().isNotEmpty)
                  .join(' · '),
          'quantity': doc.data()['quantity'] ?? 0,
          'amount': doc.data()['lossAmount'] ?? 0,
          'actor':
              doc.data()['staffName'] ??
              doc.data()['userName'] ??
              'Branch staff',
          'source': 'adjustment',
        },
  ];

  bool _adjustmentMatches(Map<String, dynamic> data) {
    final kind = '${data['type'] ?? ''}'.toLowerCase();
    final category = '${data['categoryName'] ?? ''}'.toLowerCase();
    final addon = kind.contains('addon') || category.contains('add-on');
    final bundle = kind.contains('bundle') || data['isBundle'] == true;
    final beverage =
        data['isCoffee'] == true ||
        data['coffeeSize'] != null ||
        category.contains('beverage');
    if (widget.addons) return addon;
    switch (widget.type) {
      case 'Categories':
        return !addon && !bundle && !beverage;
      case 'Bundle':
        return bundle;
      case 'Beverages':
        return beverage && !addon;
      default:
        return true;
    }
  }

  String _adjustmentTitle(Map<String, dynamic> data) {
    final type = '${data['type'] ?? ''}'.toLowerCase();
    if (type.contains('void')) return 'Voided';
    if (type.contains('return') || type.contains('expired')) return 'Returned';
    if (type.contains('unbundle')) return 'Bundle unbundled';
    return 'Reduced';
  }

  bool _activityMatches(Map<String, dynamic> data) {
    final action = '${data['action'] ?? ''}'.toLowerCase();
    if (widget.type == 'Bundle') {
      return action == 'bundle_unbundled' || action == 'bundle_returned';
    }
    return action.contains('return') &&
        (widget.type == 'All' ||
            widget.type == 'Categories' ||
            widget.type == 'Beverages');
  }

  String _actionLabel(dynamic value) {
    switch ('$value') {
      case 'bundle_unbundled':
        return 'Bundle unbundled';
      case 'bundle_returned':
        return 'Bundle returned';
      default:
        return 'Returned';
    }
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
    final db = widget.database;
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7F1236), Color(0xFFB91C4B)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'INVENTORY HISTORY',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${widget.type == 'All' ? 'Inventory' : widget.type} activity',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search this inventory history',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: const Color(0xFFFFF8FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFF0D7E0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFF0D7E0),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _dateRange == null
                        ? 'Filter by date range'
                        : 'Change date range',
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range_rounded),
                  ),
                ],
              ),
              if (_dateRange != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBE8EE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_dateRange!.start.year}-${_dateRange!.start.month.toString().padLeft(2, '0')}-${_dateRange!.start.day.toString().padLeft(2, '0')} – '
                        '${_dateRange!.end.year}-${_dateRange!.end.month.toString().padLeft(2, '0')}-${_dateRange!.end.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Color(0xFF7F1236),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: _branchStaffIds,
                  builder: (context, staffIdsSnapshot) {
                    if (staffIdsSnapshot.hasError) {
                      return const Center(
                        child: Text('Unable to load branch staff history.'),
                      );
                    }
                    if (!staffIdsSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final staffIds = staffIdsSnapshot.data!;
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db
                          .collection('completed_sales')
                          .where(
                            'userId',
                            whereIn: staffIds.isEmpty
                                ? const ['__no_branch_staff__']
                                : staffIds,
                          )
                          .snapshots(),
                      builder: (context, userSalesSnapshot) {
                        if (userSalesSnapshot.hasError) {
                          return const Center(
                            child: Text('Unable to load branch sales history.'),
                          );
                        }
                        if (!userSalesSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: db
                              .collection('completed_sales')
                              .where('branchId', isEqualTo: widget.branchId)
                              .snapshots(),
                          builder: (context, salesSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: db
                                .collection('completed_sales')
                                .where('staffId', isEqualTo: widget.branchId)
                                .snapshots(),
                            builder: (context, legacySalesSnapshot) =>
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: db
                                      .collection('activity_logs')
                                      .where(
                                        'branchIds',
                                        arrayContains: widget.branchId,
                                      )
                                      .snapshots(),
                                  builder: (context, activitySnapshot) =>
                                      StreamBuilder<
                                        QuerySnapshot<Map<String, dynamic>>
                                      >(
                                        stream: db
                                            .collection('stock_adjustments')
                                            .where(
                                              'branchId',
                                              isEqualTo: widget.branchId,
                                            )
                                            .snapshots(),
                                        builder: (context, adjustmentSnapshot) {
                                          if (salesSnapshot.hasError ||
                                              legacySalesSnapshot.hasError ||
                                              activitySnapshot.hasError ||
                                              adjustmentSnapshot.hasError) {
                                            return const Center(
                                              child: Text(
                                                'Unable to load inventory history.',
                                              ),
                                            );
                                          }
                                          if (!salesSnapshot.hasData ||
                                              !legacySalesSnapshot.hasData ||
                                              !activitySnapshot.hasData ||
                                              !adjustmentSnapshot.hasData) {
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          }
                                          final query = _search.text
                                              .trim()
                                              .toLowerCase();
                                          final salesDocs = {
                                            for (final doc
                                                in salesSnapshot.data!.docs)
                                              doc.id: doc,
                                            for (final doc
                                                in userSalesSnapshot.data!.docs)
                                              doc.id: doc,
                                            for (final doc
                                                in legacySalesSnapshot
                                                    .data!
                                                    .docs)
                                              doc.id: doc,
                                          }.values;
                                          final rows =
                                              [
                                                ..._salesRows(salesDocs),
                                                ..._activityRows(
                                                  activitySnapshot.data!.docs,
                                                ),
                                                ..._adjustmentRows(
                                                  adjustmentSnapshot.data!.docs,
                                                ),
                                              ]..sort((a, b) {
                                                final left =
                                                    _date(a['createdAt']) ??
                                                    DateTime.fromMillisecondsSinceEpoch(
                                                      0,
                                                    );
                                                final right =
                                                    _date(b['createdAt']) ??
                                                    DateTime.fromMillisecondsSinceEpoch(
                                                      0,
                                                    );
                                                return right.compareTo(left);
                                              });
                                          final filtered = rows.where((row) {
                                            final date = _date(
                                              row['createdAt'],
                                            );
                                            if (_dateRange != null &&
                                                (date == null ||
                                                    date.isBefore(
                                                      DateUtils.dateOnly(
                                                        _dateRange!.start,
                                                      ),
                                                    ) ||
                                                    date.isAfter(
                                                      DateUtils.dateOnly(
                                                            _dateRange!.end,
                                                          )
                                                          .add(
                                                            const Duration(
                                                              days: 1,
                                                            ),
                                                          )
                                                          .subtract(
                                                            const Duration(
                                                              microseconds: 1,
                                                            ),
                                                          ),
                                                    ))) {
                                              return false;
                                            }
                                            return '${row['title']} ${row['description']} ${row['actor']}'
                                                .toLowerCase()
                                                .contains(query);
                                          }).toList();
                                          if (filtered.isEmpty) {
                                            return const Center(
                                              child: Text(
                                                'No activity records found.',
                                              ),
                                            );
                                          }
                                          return ListView.separated(
                                            itemCount: filtered.length,
                                            separatorBuilder: (_, _) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final row = filtered[index];
                                              final date = _date(
                                                row['createdAt'],
                                              );
                                              final dateText = date == null
                                                  ? 'Date not recorded'
                                                  : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                              final amount =
                                                  (row['amount'] as num?)
                                                      ?.toDouble() ??
                                                  0;
                                              return ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: CircleAvatar(
                                                  child: Icon(
                                                    row['title'] == 'Sold'
                                                        ? Icons
                                                              .point_of_sale_rounded
                                                        : Icons
                                                              .assignment_return_rounded,
                                                  ),
                                                ),
                                                title: Text(
                                                  '${row['title']} · ${row['description']}',
                                                ),
                                                subtitle: Text(
                                                  '$dateText · ${row['actor']} · Qty ${row['quantity']}'
                                                  '${amount > 0 ? ' · ₱${amount.toStringAsFixed(2)}' : ''}',
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
