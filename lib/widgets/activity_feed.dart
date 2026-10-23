import 'screen_loading_region.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';

class ActivityFeed extends StatefulWidget {
  const ActivityFeed({
    super.key,
    this.actorId,
    this.actorIds,
    this.branchId,
    this.search = '',
    this.range,
    this.database,
    this.compact = false,
    this.cardRows = false,
    this.includeBranchActivity = false,
    this.includeReceipts = false,
  });
  final String? actorId, branchId;
  final Set<String>? actorIds;
  final String search;
  final DateTimeRange? range;
  final FirebaseFirestore? database;
  final bool compact;
  final bool cardRows;
  final bool includeBranchActivity;
  final bool includeReceipts;

  @override
  State<ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<ActivityFeed> {
  static const _pageSize = 5;
  int _page = 0;

  String? get actorId => widget.actorId;
  Set<String>? get actorIds => widget.actorIds;
  String? get branchId => widget.branchId;
  String get search => widget.search;
  DateTimeRange? get range => widget.range;
  FirebaseFirestore? get database => widget.database;
  bool get compact => widget.compact;
  bool get cardRows => widget.cardRows;
  bool get includeBranchActivity => widget.includeBranchActivity;
  bool get includeReceipts => widget.includeReceipts;

  @override
  void didUpdateWidget(covariant ActivityFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actorId != widget.actorId ||
        oldWidget.actorIds != widget.actorIds ||
        oldWidget.branchId != widget.branchId ||
        oldWidget.search != widget.search ||
        oldWidget.range != widget.range) {
      _page = 0;
    }
  }

  String _label(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ')
      .replaceFirstMapped(
        RegExp(r'^[a-z]'),
        (match) => match[0]!.toUpperCase(),
      );

  String _formatValue(dynamic value) {
    if (value == null || value == '') return 'Not set';
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is DateTime) return value.toLocal().toString();
    if (value is List) {
      return value.map(_formatValue).join('\n');
    }
    if (value is Map) {
      if (value.containsKey('name') &&
          (value.containsKey('quantity') || value.containsKey('qty'))) {
        return '${value['name']} × ${value['quantity'] ?? value['qty']}';
      }
      return value.entries
          .map(
            (entry) =>
                '${_label('${entry.key}')}: ${_formatValue(entry.value)}',
          )
          .join(' • ');
    }
    return '$value';
  }

  DateTime? _dateOf(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  IconData _iconFor(String action) {
    if (action.startsWith('inventory') || action == 'allocation_received') {
      return Icons.inventory_2_outlined;
    }
    if (action.contains('return')) return Icons.assignment_return_outlined;
    if (action.contains('account') || action.contains('staff')) {
      return Icons.person_add_alt_1_rounded;
    }
    if (action.contains('setting') || action.contains('permission')) {
      return Icons.tune_rounded;
    }
    if (action.contains('branch')) return Icons.storefront_outlined;
    if (action.contains('cash')) return Icons.payments_outlined;
    return Icons.history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final db = database ?? FirebaseFirestore.instance;
    final actors = {?actorId, ...?actorIds};
    Query<Map<String, dynamic>> query = db
        .collection('activity_logs')
        .orderBy('createdAt', descending: true);
    if (range != null) {
      query = query
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range!.start),
          )
          .where(
            'createdAt',
            isLessThan: Timestamp.fromDate(
              DateTime(range!.end.year, range!.end.month, range!.end.day + 1),
            ),
          );
    } else {
      query = query.limit(actors.isEmpty ? 100 : 200);
    }
    const branchActions = {
      'inventory_allocated',
      'return_approved',
      'return_rejected',
    };
    Widget feed(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> receipts,
    ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Unable to load activities.');
        }
        if (!snapshot.hasData) {
          return const Center(child: ScreenLoadingIndicator());
        }
        final rows =
            [
                  ...snapshot.data!.docs.map((d) => d.data()),
                  ...receipts
                      .where(
                        (doc) =>
                            doc.data()['confirmedBy'] != null ||
                            doc.data()['kind'] == 'return',
                      )
                      .map((doc) {
                        final r = doc.data();
                        final returned = r['kind'] == 'return';
                        return <String, dynamic>{
                          'action': returned
                              ? 'return_submitted'
                              : 'allocation_received',
                          'description': returned
                              ? 'Submitted items for return to Super Admin'
                              : 'Received allocation from ${r['allocatedByName'] ?? 'Super admin'}: ${r['name'] ?? 'Items'}',
                          'actorId': returned
                              ? r['submittedBy']
                              : r['confirmedBy'],
                          'actorName': returned
                              ? r['submittedByName']
                              : r['confirmedByName'] ?? 'Receiver',
                          'actorPublicId': returned
                              ? r['submittedByStaffId']
                              : r['confirmedByPublicId'] ?? '',
                          'actorRole': returned
                              ? (r['submittedByRole'] ?? 'Branch account')
                              : r['confirmedByRole'] ?? 'Receiver',
                          'branchIds': [r['staffId']],
                          'createdAt': returned
                              ? r['createdAt']
                              : r['confirmedAt'] ?? r['decidedAt'],
                        };
                      }),
                ]
                .where(
                  (r) =>
                      (actors.isEmpty ||
                          actors.contains('${r['actorId']}') ||
                          (includeBranchActivity &&
                              branchActions.contains(r['action']) &&
                              branchId != null &&
                              ((r['branchIds'] as List? ?? []).contains(
                                    branchId,
                                  ) ||
                                  r['branchId'] == branchId))) &&
                      (branchId == null ||
                          (r['branchIds'] as List? ?? []).contains(branchId)) &&
                      (range == null ||
                          reportInRange(
                            r['createdAt'],
                            range!.start,
                            range!.end.add(const Duration(days: 1)),
                          )) &&
                      '${r['description']} ${r['actorName']} ${r['actorPublicId']}'
                          .toLowerCase()
                          .contains(search.toLowerCase()),
                )
                .toList()
              ..sort(
                (a, b) => (_dateOf(b['createdAt'])?.millisecondsSinceEpoch ?? 0)
                    .compareTo(
                      _dateOf(a['createdAt'])?.millisecondsSinceEpoch ?? 0,
                    ),
              );
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No activities recorded yet.'),
          );
        }
        final pageCount = (rows.length / _pageSize).ceil();
        final currentPage = _page.clamp(0, pageCount - 1);
        final pageRows = rows
            .skip(currentPage * _pageSize)
            .take(_pageSize)
            .toList();
        return Column(
          children: [
            ...pageRows.map((r) {
              final action = '${r['action'] ?? 'activity'}';
              final rawDetails = r['details'];
              final details = rawDetails is Map
                  ? Map<String, dynamic>.from(rawDetails)
                  : <String, dynamic>{};
              final fields = details.remove('fields');
              final date = _dateOf(r['createdAt']);
              final actorName = '${r['actorName'] ?? 'Unknown user'}';
              final actorId = '${r['actorPublicId'] ?? ''}'.trim();
              final actorRole = '${r['actorRole'] ?? ''}'.trim();
              final detailLines = <Widget>[
                for (final entry in details.entries)
                  if (entry.value != null && entry.value != '')
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: Colors.blueGrey.shade700,
                            fontSize: compact ? 12 : 13,
                            height: 1.45,
                          ),
                          children: [
                            TextSpan(
                              text: '${_label(entry.key)}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: _formatValue(entry.value)),
                          ],
                        ),
                      ),
                    ),
                if (fields is List && fields.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      'Updated fields: ${fields.map((field) => _label('$field')).join(', ')}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade700,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                  ),
              ];
              final content = Padding(
                padding: EdgeInsets.all(compact ? 14 : 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xffffe4eb),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _iconFor(action),
                        color: const Color(0xff8f1538),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${r['description'] ?? 'Activity'}',
                                style: TextStyle(
                                  fontSize: compact ? 14 : 15,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xff252333),
                                  height: 1.3,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xffffe4eb),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _label(action),
                                  style: const TextStyle(
                                    color: Color(0xff8f1538),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (detailLines.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(11, 8, 11, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xfffff6f8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: detailLines,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 6),
                            Text(
                              'Activity recorded: ${_label(action)}',
                              style: TextStyle(
                                color: Colors.blueGrey.shade600,
                                fontSize: compact ? 12 : 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 14,
                                color: Colors.blueGrey.shade500,
                              ),
                              Text(
                                [
                                  actorName,
                                  if (actorId.isNotEmpty) actorId,
                                  if (actorRole.isNotEmpty) _label(actorRole),
                                ].join(' • '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade600,
                                ),
                              ),
                              if (date != null) ...[
                                const Text('•', style: TextStyle(fontSize: 11)),
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 13,
                                  color: Colors.blueGrey.shade500,
                                ),
                                Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(date),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade600,
                                  ),
                                ),
                                Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatTimeOfDay(
                                    TimeOfDay.fromDateTime(date),
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (cardRows) {
                return Card(
                  margin: const EdgeInsets.fromLTRB(0, 5, 0, 9),
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xffffc9d6)),
                  ),
                  color: Colors.white,
                  child: content,
                );
              }
              return content;
            }),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${currentPage + 1} / $pageCount • ${rows.length} activities',
                ),
                IconButton(
                  tooltip: 'Previous activities',
                  onPressed: currentPage > 0
                      ? () => setState(() => _page = currentPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Next activities',
                  onPressed: currentPage + 1 < pageCount
                      ? () => setState(() => _page = currentPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (!includeReceipts || branchId == null) return feed(const []);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('allocation_checklist')
          .where('staffId', isEqualTo: branchId)
          .snapshots(),
      builder: (context, receipts) => feed(receipts.data?.docs ?? const []),
    );
  }
}

class RecentActivityPanel extends StatefulWidget {
  const RecentActivityPanel({super.key, this.database});
  final FirebaseFirestore? database;
  @override
  State<RecentActivityPanel> createState() => _RecentActivityPanelState();
}

class _RecentActivityPanelState extends State<RecentActivityPanel> {
  late DateTimeRange range = DateTimeRange(
    start: DateUtils.dateOnly(DateTime.now()),
    end: DateUtils.dateOnly(DateTime.now()),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Recent Activities',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Filter activity dates',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () async {
              final result = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: range,
              );
              if (result != null && mounted) setState(() => range = result);
            },
          ),
        ],
      ),
      Text(
        '${MaterialLocalizations.of(context).formatShortDate(range.start)} – ${MaterialLocalizations.of(context).formatShortDate(range.end)}',
      ),
      const SizedBox(height: 12),
      ActivityFeed(
        database: widget.database,
        range: range,
        compact: true,
        cardRows: true,
      ),
    ],
  );
}
