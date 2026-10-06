import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';
import '../services/checklist_status.dart';
import '../services/return_batch_service.dart';
import '../theme/app_colors.dart';
import 'horizontal_controls.dart';
import '../services/return_metadata_service.dart';

String returnDateLabel(dynamic value) {
  final date = value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value');
  if (date == null) return 'Not recorded';
  final local = date.toLocal();
  return '${local.month}/${local.day}/${local.year} • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String returnExpiryLabel(dynamic value) {
  final date = value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('${value ?? ''}');
  if (date == null) return returnText([value], 'Not recorded in source');
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class ReturnStaffDetails extends StatefulWidget {
  const ReturnStaffDetails({super.key, required this.data, required this.db});
  final Map<String, dynamic> data;
  final FirebaseFirestore db;
  @override
  State<ReturnStaffDetails> createState() => _ReturnStaffDetailsState();
}

class _ReturnStaffDetailsState extends State<ReturnStaffDetails> {
  late final future = resolve();
  Future<Map<String, dynamic>> resolve() async {
    final resolver = ReturnMetadataService(widget.db);
    for (final identity in [
      widget.data['submittedBy'],
      widget.data['submittedByName'],
    ]) {
      if (identity == null || '$identity'.isEmpty) continue;
      try {
        final profile = await resolver
            .profile('$identity')
            .timeout(const Duration(seconds: 6));
        if (profile.isNotEmpty) return profile;
      } catch (_) {}
    }
    return {};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Staff: ${returnText([snapshot.data?['name'], widget.data['submittedByName'], widget.data['staffName']])}',
        ),
        Text(
          'Staff ID: ${returnText([snapshot.data?['staffId'], widget.data['submittedByStaffId']])}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class ReturnItemCard extends StatefulWidget {
  const ReturnItemCard({super.key, required this.data, this.footer, this.db});
  final Map<String, dynamic> data;
  final Widget? footer;
  final FirebaseFirestore? db;
  @override
  State<ReturnItemCard> createState() => _ReturnItemCardState();
}

Map<String, dynamic> returnDisplayMetadata(Map<String, dynamic>? data) => {
  for (final key in [
    'name',
    'itemDisplayId',
    'sourceStaffName',
    'sourceStaffId',
    'expirationDate',
    'isBundle',
    'isCoffee',
    'isAddon',
  ])
    if (data?.containsKey(key) == true) key: data![key],
};

class _ResolvedReturnMetadata extends InheritedWidget {
  const _ResolvedReturnMetadata({
    super.key,
    required this.data,
    required super.child,
  });
  final Map<String, dynamic>? data;
  @override
  bool updateShouldNotify(_ResolvedReturnMetadata oldWidget) =>
      data != oldWidget.data;
}

class _ReturnItemCardState extends State<ReturnItemCard> {
  late final Future<Map<String, dynamic>>? metadata = widget.db == null
      ? null
      : ReturnMetadataService(widget.db!).resolve(widget.data);
  @override
  Widget build(BuildContext context) {
    final resolved = context
        .dependOnInheritedWidgetOfExactType<_ResolvedReturnMetadata>()
        ?.data;
    if (resolved != null) {
      return _ReturnItemContent(
        data: {...widget.data, ...returnDisplayMetadata(resolved)},
        footer: widget.footer,
      );
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: metadata,
      builder: (context, snapshot) => _ReturnItemContent(
        data: {...widget.data, ...returnDisplayMetadata(snapshot.data)},
        footer: widget.footer,
      ),
    );
  }
}

class _ReturnItemContent extends StatelessWidget {
  const _ReturnItemContent({required this.data, this.footer});
  final Map<String, dynamic> data;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    final source = data['returnSourceCollection'] ?? data['collection'];
    final original = Map<String, dynamic>.from(
      data['sourceItem'] as Map? ?? data,
    );
    final name = returnText([data['name']], returnItemName(original));
    final code = returnText([data['itemDisplayId']], returnItemCode(original));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                    Text(
                      'Item ID: $code',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.blush,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Qty ${data['quantity'] ?? 0}',
                  style: const TextStyle(
                    color: AppColors.primaryDeep,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Source: ${source == 'completed_sales'
                ? 'Refund'
                : source == 'stock_adjustments'
                ? 'Reduce items'
                : 'Inventory return'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Staff: ${returnText([data['sourceStaffName'], data['staffName'], data['submittedByName']])}',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'Staff ID: ${returnText([data['sourceStaffId'], data['staffPublicId'], data['submittedByStaffId']])}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          Text(
            'Branch: ${returnText([data['branchName']])}',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'Recorded: ${returnDateLabel(data['sourceDate'] ?? data['date'] ?? data['createdAt'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Reason: ${returnText([data['originalReason'], data['reason']])}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if ('${data['comment'] ?? ''}'.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Details: ${data['comment']}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if ('${data['issueReason'] ?? ''}'.trim().isNotEmpty)
            Text(
              'Admin discrepancy: ${data['issueReason']}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.primaryDeep,
              ),
            ),
          if (data['unitPrice'] != null)
            Text(
              'Unit price: ₱${data['unitPrice']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          Text(
            'Expiry: ${returnExpiryLabel(data['expirationDate'] ?? original['expirationDate'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (data['confirmedAt'] != null)
            Text(
              'Accepted by ${data['confirmedByName'] ?? data['confirmedBy'] ?? 'Admin'} • ${returnDateLabel(data['confirmedAt'])}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primaryDeep,
              ),
            ),
          if (ChecklistStatus.label(data) == ChecklistStatus.returnDeclined)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Declined by ${returnText([data['declinedByName']])}\nReason: ${returnText([data['declineReason']])}',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
  }
}

Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
groupReturnBatches(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final doc in docs) {
    final data = doc.data();
    final raw = data['createdAt'];
    final date = raw is Timestamp ? raw.toDate() : DateTime.tryParse('$raw');
    final minute = date == null
        ? (data['batchId'] ?? doc.id)
        : date.millisecondsSinceEpoch ~/ 60000;
    final actor = returnText([
      data['submittedBy'],
      data['userId'],
      data['submittedByStaffId'],
      data['submittedByName'],
    ], doc.id);
    final key = '$minute/${data['branchId'] ?? data['staffId']}/$actor';
    groups.putIfAbsent(key, () => []).add(doc);
  }
  return groups;
}

class ReturnBatchList extends StatefulWidget {
  const ReturnBatchList({
    super.key,
    required this.docs,
    required this.itemBuilder,
    this.search = '',
    this.admin = false,
    this.onDecision,
  });
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Widget Function(QueryDocumentSnapshot<Map<String, dynamic>>)
  itemBuilder;
  final String search;
  final bool admin;
  final Future<void> Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    bool,
  )?
  onDecision;
  @override
  State<ReturnBatchList> createState() => _ReturnBatchListState();
}

class _ReturnBatchListState extends State<ReturnBatchList> {
  final metadata = <String, Map<String, dynamic>>{};
  ReturnMetadataService? resolver;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant ReturnBatchList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docs != widget.docs) load();
  }

  Future<void> load() async {
    final current = ++revision;
    if (widget.docs.isEmpty) return;
    resolver ??= ReturnMetadataService(widget.docs.first.reference.firestore);
    final results = await Future.wait(
      widget.docs.map((doc) async {
        try {
          return MapEntry(doc.id, await resolver!.resolve(doc.data()));
        } catch (_) {
          return MapEntry(doc.id, doc.data());
        }
      }),
    );
    if (mounted && current == revision)
      setState(() => metadata.addEntries(results));
  }

  @override
  Widget build(BuildContext context) {
    final batches = groupReturnBatches(widget.docs).values
        .where(
          (batch) => batch.any(
            (doc) => doc
                .data()
                .values
                .join(' ')
                .toLowerCase()
                .contains(widget.search.toLowerCase()),
          ),
        )
        .toList();
    if (batches.isEmpty)
      return const Center(child: Text('No matching return batches.'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: batches.length,
      itemBuilder: (context, index) {
        final batch = batches[index];
        final data = batch.first.data();
        final completed = batch
            .where(
              (doc) =>
                  ChecklistStatus.label(doc.data()) ==
                  ChecklistStatus.completed,
            )
            .length;
        final declined = batch
            .where(
              (doc) =>
                  ChecklistStatus.label(doc.data()) ==
                  ChecklistStatus.returnDeclined,
            )
            .toList();
        final pending = batch
            .where((doc) => ChecklistStatus.returnOpen(doc.data()))
            .toList();
        final status = completed == batch.length
            ? 'Done · Return accepted'
            : pending.isEmpty && declined.isNotEmpty
            ? (declined.length == batch.length
                  ? 'Return declined'
                  : 'Return reviewed')
            : widget.admin
            ? 'Review returned items'
            : completed > 0
            ? 'Waiting Admin Confirmation • $completed/${batch.length} accepted'
            : 'Waiting Admin Confirmation';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: completed == batch.length
                    ? Colors.green.shade700
                    : declined.isNotEmpty
                    ? Colors.red.shade800
                    : AppColors.primaryDeep,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      completed == batch.length
                          ? Icons.check_circle_outline
                          : declined.isNotEmpty
                          ? Icons.cancel_outlined
                          : widget.admin
                          ? Icons.assignment_return_outlined
                          : Icons.hourglass_top_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            returnText([data['branchName'], data['staffId']]),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.primaryDeep,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('View'),
                          onPressed:
                              !batch.every(
                                (doc) => metadata.containsKey(doc.id),
                              )
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _ReturnBatchDetails(
                                    docs: batch,
                                    itemBuilder: widget.itemBuilder,
                                    metadata: metadata,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ReturnStaffDetails(
                      key: ValueKey(
                        '${data['submittedBy']}/${data['submittedByName']}',
                      ),
                      data: data,
                      db: batch.first.reference.firestore,
                    ),
                    Text(
                      'Returned: ${returnDateLabel(data['createdAt'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final type in [
                          'Categories',
                          'Bundle',
                          'Beverages',
                        ])
                          Chip(
                            backgroundColor: AppColors.surfaceTint,
                            label: Text(
                              '$type (${batch.where((doc) => AllocationChecklistService.type(metadata[doc.id] ?? doc.data()) == type).length})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryDeep,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (completed > 0 || declined.isNotEmpty)
                      Text(
                        '$completed accepted · ${declined.length} declined · ${pending.length} awaiting review',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (widget.admin &&
                        pending.isNotEmpty &&
                        widget.onDecision != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ReturnDecisionButtons(
                          key: ValueKey(batch.first.id),
                          onDecision: (accept) =>
                              widget.onDecision!(pending, accept),
                        ),
                      ),
                    if (declined.isNotEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.message_outlined, size: 18),
                        label: const Text('View reason'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            constraints: const BoxConstraints(maxWidth: 460),
                            title: const Text('Reason for declining'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final doc in declined)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Text(
                                        '${returnText([metadata[doc.id]?['name'], doc.data()['name']])}\n${returnText([doc.data()['declineReason']])}\nAdmin: ${returnText([doc.data()['declinedByName']])}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ReturnDecisionButtons extends StatefulWidget {
  const ReturnDecisionButtons({super.key, required this.onDecision});
  final Future<void> Function(bool accept) onDecision;
  @override
  State<ReturnDecisionButtons> createState() => _ReturnDecisionButtonsState();
}

class _ReturnDecisionButtonsState extends State<ReturnDecisionButtons> {
  bool saving = false;
  bool confirming = false;
  Future<void> decide(bool accept) async {
    if (saving) return;
    setState(() {
      saving = true;
      confirming = accept;
    });
    try {
      if (accept) {
        final confirmed = await confirmChecklistReceipt(
          context,
          title: 'Accept returned items?',
          message:
              'Confirm that you have received all returned items in this batch. Proceed to mark this return as done for you and the staff.',
        );
        if (!confirmed || !mounted) return;
      }
      setState(() => confirming = false);
      await widget.onDecision(accept);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        onPressed: saving ? null : () => decide(true),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Accept'),
      ),
      OutlinedButton.icon(
        onPressed: saving ? null : () => decide(false),
        icon: const Icon(Icons.report_problem_outlined, size: 18),
        label: const Text('Report Issue'),
      ),
      if (saving && !confirming)
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Processing...'),
          ],
        ),
    ],
  );
}

Future<bool> confirmChecklistReceipt(
  BuildContext context, {
  required String title,
  required String message,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        icon: const Icon(Icons.task_alt, color: AppColors.primaryDeep),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    ) ==
    true;

class _ReturnBatchDetails extends StatefulWidget {
  const _ReturnBatchDetails({
    required this.docs,
    required this.itemBuilder,
    required this.metadata,
  });
  final Map<String, Map<String, dynamic>> metadata;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Widget Function(QueryDocumentSnapshot<Map<String, dynamic>>)
  itemBuilder;
  @override
  State<_ReturnBatchDetails> createState() => _ReturnBatchDetailsState();
}

class _ReturnBatchDetailsState extends State<_ReturnBatchDetails> {
  String search = '', type = 'All';
  late final stream = widget.docs.first.reference.parent
      .where('staffId', isEqualTo: widget.docs.first.data()['staffId'])
      .snapshots();
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      final ids = widget.docs.map((doc) => doc.id).toSet();
      final docs = (snapshot.data?.docs ?? widget.docs)
          .where(
            (doc) =>
                ids.contains(doc.id) &&
                (type == 'All' ||
                    AllocationChecklistService.type(
                          widget.metadata[doc.id] ?? doc.data(),
                        ) ==
                        type) &&
                doc.data().values.join(' ').toLowerCase().contains(search),
          )
          .toList();
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        clipBehavior: Clip.antiAlias,
        backgroundColor: AppColors.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 540,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AppColors.primaryDeep,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Returned items',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close returned items',
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
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search returned items',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: HorizontalControls(
                  children: [
                    for (final value in [
                      'All',
                      'Categories',
                      'Bundle',
                      'Beverages',
                    ])
                      ChoiceChip(
                        label: Text(value),
                        selected: type == value,
                        onSelected: (_) => setState(() => type = value),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? const Center(child: Text('No matching items.'))
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: docs
                            .map(
                              (doc) => _ResolvedReturnMetadata(
                                key: ValueKey(doc.id),
                                data: widget.metadata[doc.id],
                                child: widget.itemBuilder(doc),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
