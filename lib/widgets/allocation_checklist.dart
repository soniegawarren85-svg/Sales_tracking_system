import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/session_actor.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';
import '../services/low_stock_reports.dart';
import '../services/checklist_status.dart';
import '../theme/app_colors.dart';
import 'checklist_return_dialog.dart';
import 'return_batch_cards.dart';
import 'branch_permission_gate.dart';

class AllocationChecklistButton extends StatelessWidget {
  final List<String> scopeIds;
  final FirebaseFirestore? database;
  final bool isAdmin;
  final bool isSuperAdmin;
  final bool hideForBranchAdmin;
  final GlobalKey? checklistTourKey;
  final GlobalKey? returnsTourKey;
  const AllocationChecklistButton({
    super.key,
    required this.scopeIds,
    this.database,
    this.isAdmin = false,
    this.isSuperAdmin = false,
    this.hideForBranchAdmin = false,
    this.checklistTourKey,
    this.returnsTourKey,
  });

  @override
  Widget build(BuildContext context) {
    final db = database ?? FirebaseFirestore.instance;
    final ids = scopeIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty && !isAdmin) return const SizedBox.shrink();
    if (!isAdmin && hideForBranchAdmin) {
      return _BranchAdminAwareChecklistButton(database: db, scopeIds: ids);
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: checklistQuery(db, ids, isAdmin || isSuperAdmin).snapshots(),
      builder: (context, snapshot) {
        final records =
            snapshot.data?.docs.map((doc) => doc.data()).toList() ?? [];
        final incoming = records.any(ChecklistStatus.incomingOpen);
        final returned = records.any(
          isSuperAdmin
              ? ChecklistStatus.returnPendingForSuperAdmin
              : isAdmin
              ? ChecklistStatus.returnPendingForAdmin
              : ChecklistStatus.returnOpen,
        );
        final compact = MediaQuery.sizeOf(context).width < 600;
        Widget button({
          required bool returns,
          bool hasUnsubmittedReductions = false,
        }) {
          final label = returns ? 'Returns' : 'Checklist';
          final icon = Badge(
            isLabelVisible: returns
                ? returned || hasUnsubmittedReductions
                : incoming,
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
              superAdmin: isSuperAdmin,
              returnsOnly: returns,
            ),
          );
          if (compact) {
            return KeyedSubtree(
              key: returns ? returnsTourKey : checklistTourKey,
              child: IconButton.filledTonal(
                tooltip: label,
                onPressed: open,
                icon: icon,
              ),
            );
          }
          return KeyedSubtree(
            key: returns ? returnsTourKey : checklistTourKey,
            child: Tooltip(
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
            ),
          );
        }

        if (isAdmin || isSuperAdmin) return button(returns: true);
        return Flex(
          direction: Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            BranchPermissionGate(
              permission: 'allowChecklist',
              database: db,
              child: button(returns: false),
            ),
            const SizedBox(width: 8),
            BranchPermissionGate(
              permission: 'allowReturns',
              database: db,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseAuth.instance.currentUser == null
                    ? null
                    : db
                          .collection('stock_adjustments')
                          .where(
                            'userId',
                            isEqualTo: FirebaseAuth.instance.currentUser!.uid,
                          )
                          .snapshots(),
                builder: (context, adjustments) {
                  final hasUnsubmittedReductions =
                      adjustments.data?.docs.any((doc) {
                        final data = doc.data();
                        if (data['type'] == 'addon_void' ||
                            data['isDeleted'] == true) {
                          return false;
                        }
                        final total = int.tryParse('${data['quantity']}') ?? 0;
                        final returned =
                            int.tryParse(
                              '${(data['checklistReturnedQuantities'] as Map?)?['item'] ?? 0}',
                            ) ??
                            0;
                        return total > returned;
                      }) ??
                      false;
                  return button(
                    returns: true,
                    hasUnsubmittedReductions: hasUnsubmittedReductions,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BranchAdminAwareChecklistButton extends StatefulWidget {
  const _BranchAdminAwareChecklistButton({
    required this.database,
    required this.scopeIds,
  });

  final FirebaseFirestore database;
  final List<String> scopeIds;

  @override
  State<_BranchAdminAwareChecklistButton> createState() =>
      _BranchAdminAwareChecklistButtonState();
}

class _BranchAdminAwareChecklistButtonState
    extends State<_BranchAdminAwareChecklistButton> {
  late final Future<bool> _adminExists = branchHasActiveAdmin(
    firestore: widget.database,
    branchIds: widget.scopeIds,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _adminExists,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        // This is a visibility check only. Firestore can be temporarily
        // unavailable while the app is offline; do not surface that check as
        // an inventory warning or block the rest of the screen.
        return const SizedBox.shrink();
      }
      if (!snapshot.hasData || snapshot.data == true) {
        return const SizedBox.shrink();
      }
      return AllocationChecklistButton(
        database: widget.database,
        scopeIds: widget.scopeIds,
      );
    },
  );
}

Query<Map<String, dynamic>> checklistQuery(
  FirebaseFirestore db,
  List<String> ids,
  bool admin,
) {
  final query = db.collection('allocation_checklist');
  return admin ? query : query.where('staffId', whereIn: ids.take(30).toList());
}

class _ChecklistIssue {
  const _ChecklistIssue({
    required this.type,
    required this.quantity,
    required this.itemId,
    required this.itemName,
    required this.details,
    required this.hasPhysicalQuantity,
  });

  final String type;
  final int quantity;
  final String itemId;
  final String itemName;
  final String details;
  final bool hasPhysicalQuantity;
}

class _ChecklistDialog extends StatefulWidget {
  final List<String> ids;
  final FirebaseFirestore db;
  final bool admin;
  final bool superAdmin;
  final bool pendingOnly;
  final bool returnsOnly;
  const _ChecklistDialog({
    required this.ids,
    required this.db,
    required this.admin,
    this.superAdmin = false,
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
  DateTime? selectedEnd = DateUtils.dateOnly(DateTime.now());
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
    if (ChecklistStatus.isReturnRecord(data) &&
        ChecklistStatus.label(data) == ChecklistStatus.awaitingSuperAdmin) {
      return data['forwardedAt'] ?? data['createdAt'];
    }
    if (ChecklistStatus.isReturnRecord(data) &&
        ChecklistStatus.label(data) == ChecklistStatus.completed) {
      return data['confirmedAt'] ?? data['decidedAt'] ?? data['createdAt'];
    }
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
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: selectedDay,
        end: selectedEnd ?? selectedDay,
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        selectedDay = picked.start;
        selectedEnd = picked.end;
      });
    }
  }

  Future<void> acceptAll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (acceptingAll || docs.isEmpty) return;
    final confirmed = await confirmChecklistReceipt(
      context,
      title: widget.superAdmin
          ? 'Accept all pending returns?'
          : 'Submit all returns to Super Admin?',
      message: widget.superAdmin
          ? 'Confirm receipt of all ${docs.length} pending return records across all dates.'
          : 'Submit all ${docs.length} pending return records across all dates for Super Admin review.',
    );
    if (!confirmed || !mounted) return;
    setState(() => acceptingAll = true);
    try {
      await actReturns(docs, true);
    } finally {
      if (mounted) setState(() => acceptingAll = false);
    }
  }

  Future<void> acceptAllIncoming(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (acceptingAll || docs.isEmpty || widget.admin) return;
    final confirmed = await confirmChecklistReceipt(
      context,
      title: 'Accept all incoming items?',
      message:
          'Confirm that you checked all ${docs.length} pending allocations. Each allocation will be recorded as received.',
    );
    if (!confirmed || !mounted) return;
    setState(() => acceptingAll = true);
    var accepted = 0;
    try {
      final actor = await resolveBranchInventoryActor(widget.db);
      final service = AllocationChecklistService(widget.db);
      for (final doc in docs) {
        try {
          if (await service.decide(
            doc.id,
            accept: true,
            staffId: actor.id,
            actorName: actor.name,
            actorPublicId: actor.publicId,
            actorRole: actor.role,
            scopeIds: widget.ids,
          )) {
            accepted++;
          }
        } catch (error) {
          debugPrint('Bulk checklist accept ${doc.id}: $error');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted == docs.length
                  ? 'All $accepted allocations accepted.'
                  : '$accepted of ${docs.length} allocations accepted. Reopen the checklist to retry the rest.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => acceptingAll = false);
    }
  }

  Future<String?> askReason(
    bool admin, {
    String title = 'Report Issue',
    String submitLabel = 'Submit report',
  }) async {
    var reason = '';
    final form = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        title: Text(title),
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.of(dialogContext).pop(reason.trim());
              }
            },
            child: Text(submitLabel),
          ),
        ],
      ),
    );
  }

  Future<_ChecklistIssue?> askIncomingIssue(Map<String, dynamic> data) async {
    const issueTypes = [
      'Missing',
      'Extra',
      'Incorrect',
      'Damaged',
      'Not received',
      'Others',
    ];
    final items = AllocationChecklistService.rows(data['items']);
    final physicalStock =
        data['isBundle'] == true ||
        AllocationChecklistService.type(data) == 'Categories';
    final quantityController = TextEditingController();
    final detailsController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var selectedType = issueTypes.first;
    var selectedItemKey = items.isEmpty
        ? ''
        : '${items.first['id'] ?? items.first['name'] ?? ''}';
    var confirming = false;
    _ChecklistIssue? pendingIssue;
    final result = await showDialog<_ChecklistIssue>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedItem = items.cast<Map<String, dynamic>?>().firstWhere(
            (item) =>
                item != null &&
                '${item['id'] ?? item['name'] ?? ''}' == selectedItemKey,
            orElse: () => null,
          );
          final allocatedQuantity = data['isBundle'] == true
              ? AllocationChecklistService.quantity(data['bundleCount'])
              : AllocationChecklistService.quantity(
                  selectedItem?['stock'] ?? selectedItem?['startingStock'],
                );
          final quantityRequired = physicalStock && selectedType != 'Others';
          final receivingQuantity =
              pendingIssue == null ||
                  !pendingIssue!.hasPhysicalQuantity ||
                  pendingIssue!.type == 'Others'
              ? 0
              : switch (pendingIssue!.type) {
                  'Missing' ||
                  'Not received' ||
                  'Damaged' ||
                  'Incorrect' => allocatedQuantity - pendingIssue!.quantity,
                  'Extra' => allocatedQuantity + pendingIssue!.quantity,
                  _ => 0,
                };
          return AlertDialog(
            constraints: const BoxConstraints(maxWidth: 440),
            title: Text(confirming ? 'Confirm Issue Report' : 'Report Issue'),
            content: confirming
                ? Text(
                    pendingIssue!.type == 'Others'
                        ? 'Submit this issue report: ${pendingIssue!.details}'
                        : pendingIssue!.type == 'Missing'
                        ? pendingIssue!.quantity >= allocatedQuantity
                              ? 'All $allocatedQuantity ${pendingIssue!.itemName} are missing. This allocation will be cancelled, removed from staff inventory, and reported to Admin.'
                              : '${pendingIssue!.quantity} ${pendingIssue!.itemName} are missing. The remaining $receivingQuantity will be received and the issue will be reported to Admin.'
                        : pendingIssue!.type == 'Damaged' ||
                              pendingIssue!.type == 'Incorrect'
                        ? '${pendingIssue!.quantity} ${pendingIssue!.itemName} will be excluded from staff inventory and sent to Admin for return confirmation. The remaining $receivingQuantity will be received.'
                        : pendingIssue!.type == 'Not received'
                        ? '${pendingIssue!.quantity} ${pendingIssue!.itemName} will be reported as not received. Super Admin must review it and restore that quantity to main inventory. The remaining $receivingQuantity will be received.'
                        : '${pendingIssue!.type == 'Missing' ? 'Only' : 'Staff inventory will receive'} $receivingQuantity ${pendingIssue!.itemName}${pendingIssue!.type == 'Missing' ? ' will be added to staff inventory.' : ' including the reported extra quantity.'}',
                  )
                : Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: selectedType,
                            decoration: const InputDecoration(
                              labelText: 'Reason',
                            ),
                            items: [
                              for (final type in issueTypes)
                                DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                            ],
                            onChanged: (value) => setDialogState(
                              () => selectedType = value ?? issueTypes.first,
                            ),
                          ),
                          if (physicalStock && data['isBundle'] != true) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: selectedItemKey,
                              decoration: const InputDecoration(
                                labelText: 'Item',
                              ),
                              items: [
                                for (final item in items)
                                  DropdownMenuItem(
                                    value:
                                        '${item['id'] ?? item['name'] ?? ''}',
                                    child: Text('${item['name'] ?? 'Item'}'),
                                  ),
                              ],
                              onChanged: (value) => setDialogState(
                                () =>
                                    selectedItemKey = value ?? selectedItemKey,
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Select an item'
                                  : null,
                            ),
                          ],
                          if (quantityRequired) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: quantityController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                helperText: selectedType == 'Extra'
                                    ? 'Allocated: $allocatedQuantity'
                                    : 'Allocated: $allocatedQuantity; cannot exceed this amount',
                              ),
                              validator: (value) {
                                final quantity = int.tryParse(
                                  value?.trim() ?? '',
                                );
                                if (quantity == null || quantity <= 0) {
                                  return 'Enter a whole number greater than zero';
                                }
                                if (selectedType != 'Extra' &&
                                    quantity > allocatedQuantity) {
                                  return 'Cannot exceed $allocatedQuantity';
                                }
                                return null;
                              },
                            ),
                          ],
                          if (!physicalStock)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'This allocation grants catalog access and has no physical quantity to receive.',
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: detailsController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: selectedType == 'Others'
                                  ? 'Describe the issue'
                                  : 'Additional details (optional)',
                            ),
                            validator: (value) =>
                                selectedType == 'Others' &&
                                    (value == null || value.trim().isEmpty)
                                ? 'Please describe the issue'
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () {
                  if (confirming) {
                    setDialogState(() => confirming = false);
                  } else {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(confirming ? 'Back' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (confirming) {
                    Navigator.pop(dialogContext, pendingIssue);
                    return;
                  }
                  if (!formKey.currentState!.validate()) return;
                  final item = selectedItem ?? const <String, dynamic>{};
                  setDialogState(() {
                    pendingIssue = _ChecklistIssue(
                      type: selectedType,
                      quantity: quantityRequired
                          ? int.parse(quantityController.text.trim())
                          : 0,
                      itemId: '${item['id'] ?? ''}',
                      itemName: data['isBundle'] == true
                          ? '${data['name'] ?? 'Bundle'}'
                          : '${item['name'] ?? data['name'] ?? 'Item'}',
                      details: detailsController.text.trim(),
                      hasPhysicalQuantity: physicalStock,
                    );
                    confirming = true;
                  });
                },
                child: Text(
                  confirming
                      ? pendingIssue!.type == 'Others'
                            ? 'Submit report'
                            : 'Confirm and receive'
                      : 'Continue',
                ),
              ),
            ],
          );
        },
      ),
    );
    quantityController.dispose();
    detailsController.dispose();
    return result;
  }

  Future<void> actReturns(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool accept,
  ) async {
    final reason = accept
        ? ''
        : await askReason(
            true,
            title: widget.superAdmin ? 'Reject this return' : 'Report Issue',
            submitLabel: widget.superAdmin ? 'Reject Return' : 'Submit report',
          );
    if (reason == null || !mounted) return;
    String message;
    var success = false;
    try {
      final actor = await resolveSessionActor(widget.db, admin: true);
      final service = AllocationChecklistService(widget.db);
      var changed = 0;
      if (widget.superAdmin) {
        for (var start = 0; start < docs.length; start += 200) {
          changed += await service.decideReturns(
            docs.skip(start).take(200).map((doc) => doc.id).toList(),
            accept: accept,
            actorId: actor.id,
            actorName: actor.name,
            reason: reason,
          );
        }
      } else if (accept) {
        for (var start = 0; start < docs.length; start += 200) {
          changed += await service.forwardReturns(
            docs.skip(start).take(200).map((doc) => doc.id).toList(),
            actorId: actor.id,
            actorName: actor.name,
            scopeIds: widget.ids,
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
          )) {
            changed++;
          }
        }
      }
      success = changed > 0;
      message = changed == 0
          ? 'These returns have already been processed.'
          : accept
          ? widget.superAdmin
                ? '$changed returned item records accepted successfully.'
                : '$changed return records submitted to Super Admin.'
          : widget.superAdmin
          ? '$changed return records rejected. They will no longer appear as pending.'
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
                    ? widget.superAdmin
                          ? 'Return accepted'
                          : 'Return submitted'
                    : widget.superAdmin
                    ? 'Return rejected'
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
      final doc = await widget.db
          .collection('allocation_checklist')
          .doc(id)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      final incomingIssue = report && !widget.admin && !widget.returnsOnly
          ? await askIncomingIssue(data)
          : null;
      // Dismissing the detailed staff issue form means cancel. Do not open the
      // generic reason dialog underneath it after the user cancels.
      if (report &&
          !widget.admin &&
          !widget.returnsOnly &&
          incomingIssue == null) {
        return;
      }
      final reason = report && (widget.admin || widget.returnsOnly)
          ? await askReason(widget.admin)
          : incomingIssue?.details ?? '';
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
      final actor = widget.admin
          ? await resolveSessionActor(widget.db, admin: true)
          : await resolveBranchInventoryActor(widget.db);
      final name = actor.name;
      final service = AllocationChecklistService(widget.db);
      final changed =
          report &&
              incomingIssue != null &&
              incomingIssue.hasPhysicalQuantity &&
              incomingIssue.type != 'Others'
          ? await service.decide(
              id,
              accept: true,
              staffId: actor.id,
              actorName: name,
              actorPublicId: actor.publicId,
              actorRole: actor.role,
              scopeIds: widget.ids,
              issueType: incomingIssue.type,
              issueQuantity: incomingIssue.quantity,
              issueItemId: incomingIssue.itemId,
              issueItemName: incomingIssue.itemName,
              reason: incomingIssue.details,
            )
          : report
          ? await service.report(
              id,
              admin: widget.admin,
              actorId: actor.id,
              actorName: name,
              reason: incomingIssue == null
                  ? reason
                  : '${incomingIssue.type}${incomingIssue.details.isEmpty ? '' : ': ${incomingIssue.details}'}',
              scopeIds: widget.ids,
            )
          : widget.admin
          ? await service.confirmReturn(id, actorId: actor.id, actorName: name)
          : await service.decide(
              id,
              accept: true,
              staffId: actor.id,
              actorName: name,
              actorPublicId: actor.publicId,
              actorRole: actor.role,
              scopeIds: widget.ids,
            );
      if (!mounted) return;
      if (report) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed
                  ? incomingIssue?.type == 'Damaged' ||
                            incomingIssue?.type == 'Incorrect'
                        ? 'Issue reported. The affected quantity is pending Admin return confirmation.'
                        : incomingIssue?.type == 'Not received'
                        ? 'Not received quantity reported. It is pending Super Admin review.'
                        : incomingIssue?.hasPhysicalQuantity == true
                        ? 'Issue reported and the adjusted quantity was received.'
                        : 'Report submitted.'
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update checklist: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  Widget record(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final returned = ChecklistStatus.isReturnRecord(data);
    if (returned) {
      return ReturnItemCard(
        key: ValueKey(doc.id),
        db: doc.reference.firestore,
        data: data,
      );
    }
    final type = AllocationChecklistService.type(data);
    final items = returned
        ? [data]
        : type == 'Categories'
        ? AllocationChecklistService.rows(data['items'])
        : [data];
    final actionable = ChecklistStatus.pending(data, admin: widget.admin);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shadowColor: AppColors.primaryDark.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.primary.withOpacity(0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['name']?.toString() ?? 'Delivery',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blush,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    type,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: ChecklistStatus.label(data) == ChecklistStatus.received
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  ChecklistStatus.label(data) == ChecklistStatus.received
                      ? 'Done · Received'
                      : ChecklistStatus.label(data),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Branch: ${data['branchName'] ?? data['staffName'] ?? data['staffId'] ?? 'Not recorded'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${ChecklistStatus.label(data) == ChecklistStatus.received ? 'Received' : 'Assigned'}: ${date(_checklistDate(data))}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            Text(
              returned
                  ? 'Staff: ${data['submittedByName'] ?? data['staffName'] ?? data['submittedBy'] ?? 'Not recorded'}'
                  : 'Allocated by: ${data['allocatedByName'] ?? data['allocatedBy'] ?? 'Not recorded (legacy delivery)'}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const Divider(height: 20),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${item['name'] ?? 'Item'} — ${returned
                      ? item['quantity']
                      : type.startsWith('Beverages')
                      ? 'Catalog access'
                      : item['bundleCount'] ?? item['stock'] ?? item['startingStock'] ?? 0}',
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 14),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: AppColors.primaryDark,
                        side: BorderSide(
                          color: AppColors.primary.withOpacity(0.45),
                        ),
                      ),
                      onPressed: busy.contains(doc.id)
                          ? null
                          : () => act(doc.id, report: true),
                      icon: const Icon(Icons.flag_outlined, size: 17),
                      label: Text(
                        widget.admin ? 'Report Discrepancy' : 'Report Issue',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        backgroundColor: AppColors.primaryDark,
                      ),
                      onPressed: busy.contains(doc.id)
                          ? null
                          : () => act(doc.id),
                      icon: const Icon(Icons.check, size: 17),
                      label: Text(
                        busy.contains(doc.id)
                            ? 'Processing…'
                            : widget.admin
                            ? 'Confirm Return'
                            : 'Confirm Received',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
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
      width: MediaQuery.sizeOf(context).width > 784
          ? 760
          : MediaQuery.sizeOf(context).width - 24,
      height: MediaQuery.sizeOf(context).height > 784
          ? 760
          : MediaQuery.sizeOf(context).height - 24,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDeep, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.returnsOnly && widget.admin
                        ? Icons.assignment_return_rounded
                        : Icons.checklist_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.pendingOnly
                            ? widget.returnsOnly
                                  ? 'Pending returns'
                                  : 'Pending items'
                            : widget.returnsOnly
                            ? 'Returns'
                            : 'Checklist',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (widget.admin && widget.returnsOnly)
                        Text(
                          widget.superAdmin
                              ? 'Confirm returns submitted by branch admins'
                              : 'Submit branch returns for Super Admin review',
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
                  tooltip: 'Close checklist',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: TextField(
              onChanged: (value) =>
                  setState(() => search = value.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primaryDark,
                ),
                hintText: 'Search items or type (Bundle, Beverages, Add-ons)',
                suffixIcon:
                    (widget.pendingOnly ||
                        (widget.returnsOnly
                            ? widget.admin
                                  ? tab == 0
                                  : tab != 2
                            : tab != 1))
                    ? null
                    : IconButton(
                        tooltip: 'Filter by date range',
                        onPressed: pickDay,
                        icon: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.primaryDark,
                        ),
                      ),
                filled: true,
                fillColor: AppColors.surfaceTint,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Unable to load checklist. Please reopen to retry.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!.docs;
                final pending = all
                    .where(
                      (doc) => widget.returnsOnly
                          ? widget.superAdmin
                                ? ChecklistStatus.returnPendingForSuperAdmin(
                                    doc.data(),
                                  )
                                : widget.admin
                                ? ChecklistStatus.returnPendingForAdmin(
                                    doc.data(),
                                  )
                                : ChecklistStatus.returnOpen(doc.data())
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
                            ? widget.superAdmin
                                  ? ChecklistStatus.returnPendingForSuperAdmin(
                                      d,
                                    )
                                  : widget.admin
                                  ? ChecklistStatus.returnPendingForAdmin(d)
                                  : ChecklistStatus.returnOpen(d)
                            : ChecklistStatus.pending(d, admin: widget.admin);
                        return isPending &&
                            (!widget.returnsOnly ||
                                ChecklistStatus.isReturnRecord(d)) &&
                            '${d['name']} ${d['items']} ${d['branchName']} ${d['staffName']}'
                                .toLowerCase()
                                .contains(search);
                      }
                      final superAdminCompletedTab =
                          widget.returnsOnly && widget.superAdmin && tab == 1;
                      final superAdminAcceptedReturn =
                          superAdminCompletedTab &&
                          ChecklistStatus.isReturnRecord(d) &&
                          ChecklistStatus.label(d) == ChecklistStatus.completed;
                      final rawDate = superAdminAcceptedReturn
                          ? (d['confirmedAt'] ??
                                d['decidedAt'] ??
                                d['completedAt'] ??
                                d['createdAt'])
                          : _checklistDate(d);
                      final at = rawDate is Timestamp
                          ? rawDate.toDate()
                          : DateTime.tryParse('$rawDate');
                      final filterDate = widget.returnsOnly
                          ? ChecklistStatus.label(d) ==
                                ChecklistStatus.completed
                          : ChecklistStatus.label(d) ==
                                ChecklistStatus.received;
                      final filterCompletedSuperAdminTab =
                          superAdminCompletedTab && selectedEnd != null;
                      final filterSubmittedAdminTab =
                          widget.returnsOnly &&
                          widget.admin &&
                          !widget.superAdmin &&
                          tab > 0 &&
                          selectedEnd != null;
                      final shouldFilterDate =
                          filterCompletedSuperAdminTab ||
                          filterSubmittedAdminTab ||
                          filterDate;
                      final localDate = at?.toLocal();
                      final rangeEnd = (selectedEnd ?? selectedDay).add(
                        const Duration(days: 1),
                      );
                      if (shouldFilterDate &&
                          (localDate == null ||
                              localDate.isBefore(selectedDay) ||
                              !localDate.isBefore(rangeEnd))) {
                        return false;
                      }
                      final inTab = widget.returnsOnly
                          ? ChecklistStatus.isReturnRecord(d) &&
                                ((widget.admin || widget.superAdmin)
                                    ? widget.superAdmin
                                          ? (tab == 0
                                                ? ChecklistStatus.returnPendingForSuperAdmin(
                                                    d,
                                                  )
                                                : ChecklistStatus.label(d) ==
                                                      ChecklistStatus.completed)
                                          : (tab == 0
                                                ? ChecklistStatus.returnPendingForAdmin(
                                                    d,
                                                  )
                                                : tab == 1
                                                ? ChecklistStatus.label(d) ==
                                                      ChecklistStatus
                                                          .awaitingSuperAdmin
                                                : [
                                                    ChecklistStatus.completed,
                                                    ChecklistStatus
                                                        .returnDeclined,
                                                  ].contains(
                                                    ChecklistStatus.label(d),
                                                  ))
                                    : (tab == 2
                                          ? ChecklistStatus.label(d) ==
                                                ChecklistStatus.completed
                                          : ChecklistStatus.label(d) !=
                                                ChecklistStatus.completed))
                          : !ChecklistStatus.isReturnRecord(d) &&
                                (tab == 1
                                    ? ChecklistStatus.label(d) ==
                                          ChecklistStatus.received
                                    : ChecklistStatus.incomingOpen(d));
                      if (widget.returnsOnly) return inTab;
                      return inTab &&
                          (filter == 'All items' ||
                              AllocationChecklistService.type(d) == filter) &&
                          '${d['name']} ${d['items']} ${AllocationChecklistService.type(d)} ${d['staffName']} ${d['branchName']} ${d['submittedByName']} ${ChecklistStatus.label(d)}'
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
                    if (widget.admin && widget.returnsOnly && tab == 0)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton.icon(
                          onPressed: acceptingAll || pending.isEmpty
                              ? null
                              : () => acceptAll(pending),
                          icon: const Icon(Icons.done_all),
                          label: Text(
                            acceptingAll
                                ? widget.superAdmin
                                      ? 'Accepting...'
                                      : 'Submitting...'
                                : widget.superAdmin
                                ? 'Accept all (${pending.length})'
                                : 'Submit all to Super Admin (${pending.length})',
                          ),
                        ),
                      ),
                    if (!widget.admin &&
                        !widget.returnsOnly &&
                        !widget.pendingOnly &&
                        tab == 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: FilledButton.icon(
                          onPressed: acceptingAll || pending.isEmpty
                              ? null
                              : () => acceptAllIncoming(pending),
                          icon: acceptingAll
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.done_all_rounded),
                          label: Text(
                            acceptingAll
                                ? 'Accepting…'
                                : 'Accept all (${pending.length})',
                          ),
                        ),
                      ),
                    if (!widget.pendingOnly &&
                        selectedEnd != null &&
                        (widget.returnsOnly && widget.admin && tab > 0 ||
                            tab ==
                                (widget.returnsOnly && !widget.admin ? 2 : 1)))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '${MaterialLocalizations.of(context).formatMediumDate(selectedDay)} – ${MaterialLocalizations.of(context).formatMediumDate(selectedEnd ?? selectedDay)}',
                        ),
                      ),
                    if (!widget.pendingOnly &&
                        widget.admin &&
                        widget.returnsOnly)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceTint,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Row(
                            children: [
                              _returnTab(
                                widget.superAdmin
                                    ? 'Pending Returns'
                                    : 'Pending Returned',
                                0,
                              ),
                              if (!widget.superAdmin)
                                _returnTab('Sent to Super Admin', 1),
                              _returnTab(
                                'Completed',
                                widget.superAdmin ? 1 : 2,
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (!widget.pendingOnly)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final entry in [
                              if (widget.admin) ...[
                                'Pending Returned',
                                'Completed Return',
                              ] else if (widget.returnsOnly) ...[
                                'Return Items',
                                'Pending Confirmation',
                                'Completed Return',
                              ] else ...[
                                'Incoming Items',
                                'Complete Items',
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
                    if (widget.returnsOnly &&
                        tab == (widget.admin ? (widget.superAdmin ? 1 : 2) : 2))
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${widget.admin && !widget.superAdmin && tab == 1 ? 'Submitted returns' : 'Completed returns'}: ${docs.length} • ${docs.fold<num>(0, (sum, doc) => sum + (num.tryParse('${doc.data()['quantity']}') ?? 0))} items',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: widget.returnsOnly && tab == 0 && !widget.admin
                          ? ChecklistReturnDialog(
                              db: widget.db,
                              scopeIds: widget.ids,
                              searchText: search,

                              onSubmitted: () => setState(() => tab = 1),
                            )
                          : widget.returnsOnly
                          ? ReturnBatchList(
                              admin: widget.admin,
                              superAdmin: widget.superAdmin,
                              forwardToSuperAdmin:
                                  widget.admin && !widget.superAdmin,
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

  Widget _returnTab(String label, int index) => Expanded(
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
}
