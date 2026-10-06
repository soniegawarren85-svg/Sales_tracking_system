import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/session_actor.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';
import '../services/checklist_status.dart';
import '../theme/app_colors.dart';
import 'checklist_return_dialog.dart';
import 'return_batch_cards.dart';

class AllocationChecklistButton extends StatelessWidget {
  final List<String> scopeIds;
  final FirebaseFirestore? database;
  final bool isAdmin;
  const AllocationChecklistButton({
    super.key,
    required this.scopeIds,
    this.database,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final db = database ?? FirebaseFirestore.instance;
    final ids = scopeIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty && !isAdmin) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: checklistQuery(db, ids, isAdmin).snapshots(),
      builder: (context, snapshot) {
        final records =
            snapshot.data?.docs.map((doc) => doc.data()).toList() ?? [];
        final incoming = records.any(ChecklistStatus.incomingOpen);
        final returned = records.any(ChecklistStatus.returnOpen);
        final compact = MediaQuery.sizeOf(context).width < 600;
        Widget button({required bool returns}) {
          final label = returns ? 'Returns' : 'Checklist';
          final icon = Badge(
            isLabelVisible: returns ? returned : incoming,
            backgroundColor: Colors.red,
            child: Icon(
              returns
                  ? Icons.assignment_return_outlined
                  : Icons.checklist_rounded,
            ),
          );
          void open() => showDialog<void>(
            context: context,
            builder: (_) => _ChecklistDialog(
              ids: ids,
              db: db,
              admin: isAdmin,
              returnsOnly: returns,
            ),
          );
          if (compact)
            return IconButton.filledTonal(
              tooltip: label,
              onPressed: open,
              icon: icon,
            );
          return Tooltip(
            message: label,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
                shape: const StadiumBorder(),
              ),
              icon: icon,
              label: Text(label),
              onPressed: open,
            ),
          );
        }

        if (isAdmin) return button(returns: true);
        return Flex(
          direction: compact ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          children: [
            button(returns: false),
            SizedBox(width: compact ? 8 : 0, height: compact ? 0 : 8),
            button(returns: true),
          ],
        );
      },
    );
  }
}

Query<Map<String, dynamic>> checklistQuery(
  FirebaseFirestore db,
  List<String> ids,
  bool admin,
) {
  final query = db.collection('allocation_checklist');
  return admin ? query : query.where('staffId', whereIn: ids.take(30).toList());
}

class _ChecklistDialog extends StatefulWidget {
  final List<String> ids;
  final FirebaseFirestore db;
  final bool admin;
  final bool pendingOnly;
  final bool returnsOnly;
  const _ChecklistDialog({
    required this.ids,
    required this.db,
    required this.admin,
    this.pendingOnly = false,
    this.returnsOnly = false,
  });
  @override
  State<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends State<_ChecklistDialog> {
  String search = '', filter = 'All items';
  int tab = 0;
  DateTime selectedDay = DateUtils.dateOnly(DateTime.now());
  bool acceptingAll = false;
  final busy = <String>{};
  late final stream = checklistQuery(
    widget.db,
    widget.ids,
    widget.admin,
  ).snapshots();

  String date(dynamic value) {
    final parsed = value is Timestamp
        ? value.toDate()
        : DateTime.tryParse('$value');
    return parsed == null ? 'Not recorded' : parsed.toLocal().toString();
  }

  dynamic _checklistDate(Map<String, dynamic> data) {
    final isReceived =
        data['kind'] != 'return' &&
        ChecklistStatus.label(data) == ChecklistStatus.received;
    if (isReceived) {
      return data['confirmedAt'] ??
          data['decidedAt'] ??
          data['createdAt'] ??
          data['assignedAt'];
    }
    return data['createdAt'] ?? data['assignedAt'];
  }

  Future<void> pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDay,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => selectedDay = picked);
  }

  Future<void> acceptAll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (acceptingAll || docs.isEmpty) return;
    final confirmed = await confirmChecklistReceipt(
      context,
      title: 'Accept all pending returns?',
      message:
          'Confirm receipt of all ${docs.length} pending return records across all dates.',
    );
    if (!confirmed || !mounted) return;
    setState(() => acceptingAll = true);
    try {
      await actReturns(docs, true);
    } finally {
      if (mounted) setState(() => acceptingAll = false);
    }
  }

  Future<String?> askReason(bool admin) async {
    var reason = '';
    final form = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        title: Text('Report Issue'),
        content: Form(
          key: form,
          child: TextFormField(
            autofocus: true,
            maxLines: 3,
            onChanged: (value) => reason = value,
            decoration: InputDecoration(
              labelText: 'Reason',
              hintText: 'Missing, extra, incorrect, or damaged items',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'A reason is required'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(context, reason.trim());
            },
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
  }

  Future<void> actReturns(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool accept,
  ) async {
    final reason = accept ? '' : await askReason(true);
    if (reason == null || !mounted) return;
    String message;
    var success = false;
    try {
      final actor = await resolveSessionActor(widget.db, admin: true);
      final service = AllocationChecklistService(widget.db);
      var changed = 0;
      if (accept) {
        for (var start = 0; start < docs.length; start += 200) {
          changed += await service.decideReturns(
            docs.skip(start).take(200).map((doc) => doc.id).toList(),
            accept: true,
            actorId: actor.id,
            actorName: actor.name,
          );
        }
      } else {
        for (final doc in docs) {
          if (await service.report(
            doc.id,
            admin: true,
            actorId: actor.id,
            actorName: actor.name,
            reason: reason,
            scopeIds: widget.ids,
          ))
            changed++;
        }
      }
      success = changed > 0;
      message = changed == 0
          ? 'These returns have already been processed.'
          : accept
          ? '$changed returned item records accepted successfully.'
          : 'Issue reported for $changed return records. They remain pending for acceptance.';
    } catch (error) {
      message =
          'Unable to confirm this decision: $error. Check the current status before trying again.';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        icon: Icon(
          success ? Icons.check_circle : Icons.info_outline,
          color: success ? Colors.green.shade700 : AppColors.primaryDeep,
        ),
        title: Text(
          success
              ? accept
                    ? 'Return accepted'
                    : 'Issue reported'
              : 'Return status',
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> act(String id, {bool report = false}) async {
    if (busy.contains(id)) return;
    setState(() => busy.add(id));
    try {
      final reason = report ? await askReason(widget.admin) : '';
      if (reason == null || !mounted) return;
      if (!report) {
        final confirmed = await confirmChecklistReceipt(
          context,
          title: widget.admin
              ? 'Receive returned items?'
              : 'Receive allocated items?',
          message:
              'Confirm that all items have arrived and you have checked them. Proceed to mark this transaction as received.',
        );
        if (!confirmed || !mounted) return;
      }
      final actor = await resolveSessionActor(widget.db, admin: widget.admin);
      final name = actor.name;
      final service = AllocationChecklistService(widget.db);
      final changed = report
          ? await service.report(
              id,
              admin: widget.admin,
              actorId: actor.id,
              actorName: name,
              reason: reason,
              scopeIds: widget.ids,
            )
          : widget.admin
          ? await service.confirmReturn(id, actorId: actor.id, actorName: name)
          : await service.decide(
              id,
              accept: true,
              staffId: actor.id,
              actorName: name,
              scopeIds: widget.ids,
            );
      if (!mounted) return;
      if (report) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed
                  ? 'Report submitted.'
                  : 'This transaction has already been processed.',
            ),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            constraints: const BoxConstraints(maxWidth: 400),
            icon: Icon(
              changed ? Icons.check_circle : Icons.info_outline,
              color: changed ? Colors.green.shade700 : AppColors.primaryDeep,
            ),
            title: Text(
              changed ? 'Items received successfully' : 'Receipt status',
            ),
            content: Text(
              changed
                  ? 'Done. The items are marked as received.'
                  : 'This transaction has already been processed.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update checklist: $error')),
        );
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  Widget record(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final returned = data['kind'] == 'return';
    if (returned)
      return ReturnItemCard(
        key: ValueKey(doc.id),
        db: doc.reference.firestore,
        data: data,
      );
    final type = AllocationChecklistService.type(data);
    final items = returned
        ? [data]
        : type == 'Categories'
        ? AllocationChecklistService.rows(data['items'])
        : [data];
    final actionable = ChecklistStatus.pending(data, admin: widget.admin);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${data['name'] ?? 'Delivery'} · $type',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ChecklistStatus.label(data) == ChecklistStatus.received
                  ? 'Done · Received'
                  : ChecklistStatus.label(data),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Branch: ${data['branchName'] ?? data['staffName'] ?? data['staffId'] ?? 'Not recorded'}',
            ),
            Text(
              '${ChecklistStatus.label(data) == ChecklistStatus.received ? 'Received' : 'Assigned'}: ${date(_checklistDate(data))}',
            ),
            Text(
              returned
                  ? 'Staff: ${data['submittedByName'] ?? data['staffName'] ?? data['submittedBy'] ?? 'Not recorded'}'
                  : 'Allocated by: ${data['allocatedByName'] ?? data['allocatedBy'] ?? 'Not recorded (legacy delivery)'}',
            ),
            const Divider(),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${item['name'] ?? 'Item'} — ${returned
                      ? item['quantity']
                      : type == 'Beverages'
                      ? 'Catalog access'
                      : item['bundleCount'] ?? item['stock'] ?? item['startingStock'] ?? 0}',
                ),
              ),
            if ('${data['reason'] ?? ''}'.isNotEmpty)
              Text('Reason: ${data['reason']}'),
            if (returned) ...[
              Text(
                'Return type: ${data['returnSourceCollection'] == 'completed_sales'
                    ? 'Refund'
                    : data['returnSourceCollection'] == 'stock_adjustments'
                    ? 'Reduce'
                    : 'Stock return'}',
              ),
              if (data['sourceDate'] != null)
                Text('Original date: ${date(data['sourceDate'])}'),
              if (data['sourceReceiptId'] != null)
                Text('Receipt: ${data['sourceReceiptId']}'),
              if (data['unitPrice'] != null)
                Text('Unit price: ₱${data['unitPrice']}'),
              if ((data['sourceItem'] as Map?)?['expirationDate'] != null)
                Text(
                  'Expiry: ${(data['sourceItem'] as Map)['expirationDate']}',
                ),
              if (data['sourceStaffName'] != null)
                Text('Recorded by: ${data['sourceStaffName']}'),
              if (data['returnSourceId'] != null)
                Text('Source reference: ${data['returnSourceId']}'),
            ],
            if ('${data['issueReason'] ?? ''}'.isNotEmpty) ...[
              Text('Reported: ${data['issueReason']}'),
              Text(
                'By ${data['reportedByName'] ?? data['reportedBy']} · ${date(data['reportedAt'])}',
              ),
            ],
            if (data['confirmedAt'] != null || data['decidedAt'] != null)
              Text(
                'Confirmed by: ${data['confirmedByName'] ?? data['confirmedBy'] ?? data['decidedBy']}\n${date(data['confirmedAt'] ?? data['decidedAt'])}',
              ),
            if (returned &&
                ChecklistStatus.label(data) == ChecklistStatus.completed)
              const Text(
                'Return received and recorded separately from sellable stock.',
              ),
            if (actionable) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: busy.contains(doc.id)
                        ? null
                        : () => act(doc.id, report: true),
                    child: Text(
                      widget.admin ? 'Report Discrepancy' : 'Report Issue',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy.contains(doc.id) ? null : () => act(doc.id),
                    icon: const Icon(Icons.check),
                    label: Text(
                      busy.contains(doc.id)
                          ? 'Processing…'
                          : widget.admin
                          ? 'Confirm Return Received'
                          : 'Confirm Received',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SizedBox(
      width: 600,
      height: 640,
      child: Column(
        children: [
          Container(
            color: AppColors.primaryDeep,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.pendingOnly
                        ? widget.returnsOnly
                              ? 'Pending returns'
                              : 'Pending items'
                        : widget.returnsOnly
                        ? 'Returns'
                        : 'Checklist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.admin && widget.returnsOnly && !widget.pendingOnly)
                  IconButton(
                    tooltip: 'View pending returns',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ChecklistDialog(
                        ids: widget.ids,
                        db: widget.db,
                        admin: true,
                        pendingOnly: true,
                        returnsOnly: true,
                      ),
                    ),
                    icon: const Icon(
                      Icons.visibility_outlined,
                      color: Colors.white,
                    ),
                  ),
                if (!widget.pendingOnly && !widget.returnsOnly)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ChecklistDialog(
                        ids: widget.ids,
                        db: widget.db,
                        admin: widget.admin,
                        pendingOnly: true,
                      ),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View pending'),
                  ),
                IconButton(
                  tooltip: 'Close checklist',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (value) =>
                  setState(() => search = value.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search',
                suffixIcon: widget.pendingOnly
                    ? null
                    : IconButton(
                        tooltip: 'Filter by date',
                        onPressed: pickDay,
                        icon: const Icon(Icons.calendar_today_outlined),
                      ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(
                    child: Text(
                      'Unable to load checklist. Please reopen to retry.',
                    ),
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final all = snapshot.data!.docs;
                final pending = all
                    .where(
                      (doc) => widget.returnsOnly
                          ? ChecklistStatus.returnOpen(doc.data())
                          : ChecklistStatus.pending(
                              doc.data(),
                              admin: widget.admin,
                            ),
                    )
                    .toList();
                final docs =
                    all.where((doc) {
                      final d = doc.data();
                      if (widget.pendingOnly) {
                        final isPending = widget.returnsOnly
                            ? ChecklistStatus.returnOpen(d)
                            : ChecklistStatus.pending(d, admin: widget.admin);
                        return isPending &&
                            (!widget.returnsOnly || d['kind'] == 'return') &&
                            '${d['name']} ${d['items']} ${d['branchName']} ${d['staffName']}'
                                .toLowerCase()
                                .contains(search);
                      }
                      final rawDate = _checklistDate(d);
                      final at = rawDate is Timestamp
                          ? rawDate.toDate()
                          : DateTime.tryParse('$rawDate');
                      if (!DateUtils.isSameDay(at?.toLocal(), selectedDay))
                        return false;
                      final inTab = widget.returnsOnly
                          ? d['kind'] == 'return' &&
                                (widget.admin
                                    ? (tab == 1
                                          ? ChecklistStatus.label(d) ==
                                                ChecklistStatus.completed
                                          : ChecklistStatus.label(d) !=
                                                ChecklistStatus.completed)
                                    : (tab == 2
                                          ? ChecklistStatus.label(d) ==
                                                ChecklistStatus.completed
                                          : ChecklistStatus.label(d) !=
                                                ChecklistStatus.completed))
                          : d['kind'] != 'return' &&
                                (tab == 1
                                    ? ChecklistStatus.label(d) ==
                                          ChecklistStatus.received
                                    : ChecklistStatus.incomingOpen(d));
                      if (widget.returnsOnly) return inTab;
                      return inTab &&
                          (filter == 'All items' ||
                              AllocationChecklistService.type(d) == filter) &&
                          '${d['name']} ${d['items']} ${d['staffName']} ${d['branchName']} ${d['submittedByName']} ${ChecklistStatus.label(d)}'
                              .toLowerCase()
                              .contains(search);
                    }).toList()..sort((a, b) {
                      int time(Map<String, dynamic> d) {
                        final value = _checklistDate(d);
                        return value is Timestamp
                            ? value.millisecondsSinceEpoch
                            : 0;
                      }

                      return time(b.data()).compareTo(time(a.data()));
                    });
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.admin &&
                        tab == 0 &&
                        (!widget.returnsOnly || widget.pendingOnly))
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton.icon(
                          onPressed: acceptingAll || pending.isEmpty
                              ? null
                              : () => acceptAll(pending),
                          icon: const Icon(Icons.done_all),
                          label: Text(
                            acceptingAll
                                ? 'Accepting...'
                                : 'Accept all (${pending.length})',
                          ),
                        ),
                      ),
                    if (!widget.pendingOnly)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(selectedDay),
                        ),
                      ),
                    if (!widget.pendingOnly)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final entry in [
                              if (widget.admin) ...[
                                'Returned Items',
                                'Completed Return',
                              ] else if (widget.returnsOnly) ...[
                                'Return Items',
                                'Pending Confirmation',
                                'Completed Return',
                              ] else ...[
                                'Incoming Items',
                                'Complete',
                              ],
                            ].asMap().entries)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(entry.value),
                                  selected: tab == entry.key,
                                  onSelected: (_) =>
                                      setState(() => tab = entry.key),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (!widget.pendingOnly &&
                        !widget.returnsOnly &&
                        !widget.admin)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final type in [
                              'All items',
                              'Categories',
                              'Bundle',
                              'Beverages',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(type),
                                  selected: filter == type,
                                  onSelected: (_) =>
                                      setState(() => filter = type),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: widget.returnsOnly && tab == 0 && !widget.admin
                          ? ChecklistReturnDialog(
                              db: widget.db,
                              scopeIds: widget.ids,
                              searchText: search,
                              selectedDay: selectedDay,
                              onSubmitted: () => setState(() => tab = 1),
                            )
                          : widget.returnsOnly
                          ? ReturnBatchList(
                              admin: widget.admin,
                              onDecision: widget.admin ? actReturns : null,
                              docs: docs,
                              search: search,
                              itemBuilder: record,
                            )
                          : docs.isEmpty
                          ? const Center(
                              child: Text('No matching transactions.'),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: docs.length,
                              itemBuilder: (_, index) => record(docs[index]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
