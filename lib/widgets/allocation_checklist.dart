import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

  FirebaseAuth? _safeAuth() {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

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
                stream: (() {
                  final auth = _safeAuth();
                  final currentUser = auth?.currentUser;
                  return currentUser == null
                      ? null
                      : db
                            .collection('stock_adjustments')
                            .where('userId', isEqualTo: currentUser.uid)
                            .snapshots();
                })(),
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
    this.items = const [],
  });

  final String type;
  final int quantity;
  final String itemId;
  final String itemName;
  final String details;
  final bool hasPhysicalQuantity;
  final List<_ChecklistItemIssue> items;
}

class _ChecklistItemIssue {
  const _ChecklistItemIssue({
    required this.type,
    required this.quantity,
    required this.allocatedQuantity,
    required this.itemId,
    required this.itemName,
    this.comment = '',
  });

  final String type;
  final int quantity;
  final int allocatedQuantity;
  final String itemId;
  final String itemName;
  final String comment;

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'issueType': type,
    'quantity': quantity,
    'allocatedQuantity': allocatedQuantity,
    'comment': comment,
  };
}

class _ReturnIssueReport {
  const _ReturnIssueReport(this.entries);

  final List<_ReturnIssueEntry> entries;
}

class _ReturnIssueEntry {
  const _ReturnIssueEntry({
    required this.returnId,
    required this.type,
    required this.quantity,
    required this.comment,
  });

  final String returnId;
  final String type;
  final int quantity;
  final String comment;
}

class _ReturnIssueDialog extends StatefulWidget {
  const _ReturnIssueDialog({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  State<_ReturnIssueDialog> createState() => _ReturnIssueDialogState();
}

class _ReturnIssueDialogState extends State<_ReturnIssueDialog> {
  static const issueTypes = [
    'Missing',
    'Extra',
    'Incorrect',
    'Damaged',
    'Others',
  ];

  final quantityController = TextEditingController();
  final commentController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  late String selectedReturnId = widget.docs.first.id;
  String selectedType = issueTypes.first;
  final Map<String, _ReturnIssueEntry> issueEntries = {};
  String? formError;

  @override
  void dispose() {
    quantityController.dispose();
    commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.docs.firstWhere(
      (doc) => doc.id == selectedReturnId,
    );
    final selectedData = selected.data();
    final returnedQuantity = AllocationChecklistService.quantity(
      selectedData['quantity'] ?? selectedData['returnQuantity'] ?? 1,
    );
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: const Text('Report issue with return'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'The return will be completed, and this report will appear in the branch Admin’s completed returns.',
              ),
              if (widget.docs.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedReturnId,
                  decoration: const InputDecoration(labelText: 'Item'),
                  items: [
                    for (final doc in widget.docs)
                      DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          '${doc.data()['name'] ?? 'Item'} · Qty ${doc.data()['quantity'] ?? doc.data()['returnQuantity'] ?? 1}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == selectedReturnId) return;
                    _saveCurrentDraft();
                    setState(() {
                      selectedReturnId = value;
                      final entry = issueEntries[value];
                      selectedType = entry?.type ?? issueTypes.first;
                      quantityController.text =
                          entry?.quantity.toString() ?? '';
                      commentController.text = entry?.comment ?? '';
                      formError = null;
                    });
                  },
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  '${selectedData['name'] ?? 'Item'} · Returned quantity: $returnedQuantity',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final type in issueTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (value) =>
                    setState(() => selectedType = value ?? issueTypes.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Issue quantity',
                  helperText: 'Returned quantity: $returnedQuantity',
                ),
                validator: (value) {
                  final quantity = int.tryParse(value?.trim() ?? '');
                  if (quantity == null || quantity <= 0) {
                    return 'Enter a whole number greater than zero';
                  }
                  if (quantity > returnedQuantity) {
                    return 'Cannot exceed $returnedQuantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Optional comment',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saveCurrentIssue,
                icon: Icon(
                  issueEntries.containsKey(selectedReturnId)
                      ? Icons.edit_outlined
                      : Icons.add,
                ),
                label: Text(
                  issueEntries.containsKey(selectedReturnId)
                      ? 'Update this item report'
                      : 'Add this item report',
                ),
              ),
              if (formError != null) ...[
                const SizedBox(height: 8),
                Text(
                  formError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (issueEntries.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Reports added: ${issueEntries.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final entry in issueEntries.values)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_returnName(entry.returnId)} · ${entry.type} × ${entry.quantity}',
                    ),
                    subtitle: entry.comment.isEmpty
                        ? null
                        : Text(entry.comment),
                    trailing: IconButton(
                      tooltip: 'Remove report',
                      onPressed: () =>
                          setState(() => issueEntries.remove(entry.returnId)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final hasCurrentQuantity = quantityController.text
                .trim()
                .isNotEmpty;
            if (hasCurrentQuantity && !_saveCurrentIssue()) return;
            if (issueEntries.isEmpty) {
              setState(
                () => formError = 'Add an issue report for at least one item.',
              );
              return;
            }
            Navigator.pop(
              context,
              _ReturnIssueReport(issueEntries.values.toList()),
            );
          },
          child: const Text('Submit all reports'),
        ),
      ],
    );
  }

  String _returnName(String id) =>
      widget.docs
          .firstWhere((doc) => doc.id == id)
          .data()['name']
          ?.toString() ??
      'Item';

  void _saveCurrentDraft() {
    final quantity = int.tryParse(quantityController.text.trim());
    if (quantity == null || quantity <= 0) return;
    final data = widget.docs
        .firstWhere((doc) => doc.id == selectedReturnId)
        .data();
    final returnedQuantity = AllocationChecklistService.quantity(
      data['quantity'] ?? data['returnQuantity'] ?? 1,
    );
    if (quantity > returnedQuantity) return;
    issueEntries[selectedReturnId] = _ReturnIssueEntry(
      returnId: selectedReturnId,
      type: selectedType,
      quantity: quantity,
      comment: commentController.text.trim(),
    );
  }

  bool _saveCurrentIssue() {
    if (!formKey.currentState!.validate()) return false;
    final quantity = int.parse(quantityController.text.trim());
    setState(() {
      issueEntries[selectedReturnId] = _ReturnIssueEntry(
        returnId: selectedReturnId,
        type: selectedType,
        quantity: quantity,
        comment: commentController.text.trim(),
      );
      formError = null;
    });
    return true;
  }
}

class _IncomingIssueDialog extends StatefulWidget {
  const _IncomingIssueDialog({required this.data, required this.items});

  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> items;

  @override
  State<_IncomingIssueDialog> createState() => _IncomingIssueDialogState();
}

class _IncomingIssueDialogState extends State<_IncomingIssueDialog> {
  static const issueTypes = [
    'Missing',
    'Extra',
    'Incorrect',
    'Damaged',
    'Not received',
    'Others',
  ];

  final quantityController = TextEditingController();
  final commentController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final Map<String, _ChecklistItemIssue> issueEntries = {};
  late String selectedItemKey = _itemKey(widget.items.first, 0);
  String selectedType = issueTypes.first;
  String? formError;

  String _itemKey(Map<String, dynamic> item, int index) =>
      '${item['id'] ?? item['name'] ?? 'item'}-$index';

  int _indexForKey(String key) {
    for (var index = 0; index < widget.items.length; index++) {
      if (_itemKey(widget.items[index], index) == key) return index;
    }
    return -1;
  }

  int _quantity(Map<String, dynamic> item) =>
      AllocationChecklistService.quantity(
        item['stock'] ?? item['startingStock'],
      );

  int get _selectedIndex => _indexForKey(selectedItemKey);

  Map<String, dynamic> get _selectedItem => widget.items[_selectedIndex];

  @override
  void dispose() {
    quantityController.dispose();
    commentController.dispose();
    super.dispose();
  }

  void _selectItem(String? key) {
    if (key == null || key == selectedItemKey) return;
    setState(() {
      selectedItemKey = key;
      final entry = issueEntries[key];
      selectedType = entry?.type ?? issueTypes.first;
      quantityController.text = entry?.quantity.toString() ?? '';
      commentController.text = entry?.comment ?? '';
      formError = null;
    });
  }

  bool _saveCurrentIssue() {
    if (!formKey.currentState!.validate()) return false;
    final index = _selectedIndex;
    if (index < 0) return false;
    final item = _selectedItem;
    final quantity = int.parse(quantityController.text.trim());
    issueEntries[selectedItemKey] = _ChecklistItemIssue(
      type: selectedType,
      quantity: quantity,
      allocatedQuantity: _quantity(item),
      itemId: '${item['id'] ?? ''}',
      itemName: '${item['name'] ?? widget.data['name'] ?? 'Item'}',
      comment: commentController.text.trim(),
    );
    setState(() => formError = null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final item = _selectedItem;
    final allocated = _quantity(item);
    final currentEntry = issueEntries[selectedItemKey];
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 460),
      title: const Text('Report Issue'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('incoming-item-$selectedItemKey'),
                initialValue: selectedItemKey,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Item'),
                items: [
                  for (var index = 0; index < widget.items.length; index++)
                    DropdownMenuItem(
                      value: _itemKey(widget.items[index], index),
                      child: Text(
                        '${widget.items[index]['name'] ?? 'Item'} · Qty ${_quantity(widget.items[index])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _selectItem,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('incoming-reason-$selectedItemKey'),
                initialValue: selectedType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final type in issueTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (value) =>
                    setState(() => selectedType = value ?? issueTypes.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Issue quantity',
                  helperText:
                      'Allocated: $allocated${selectedType == 'Extra' ? '' : '; cannot exceed this amount'}',
                ),
                validator: (value) {
                  final amount = int.tryParse(value?.trim() ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter a whole number greater than zero';
                  }
                  if (selectedType != 'Extra' && amount > allocated) {
                    return 'Cannot exceed $allocated';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: selectedType == 'Others'
                      ? 'Describe the issue'
                      : 'Optional comment',
                ),
                validator: (value) =>
                    selectedType == 'Others' &&
                        (value == null || value.trim().isEmpty)
                    ? 'Please describe the issue'
                    : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saveCurrentIssue,
                icon: Icon(
                  currentEntry == null ? Icons.add : Icons.edit_outlined,
                ),
                label: Text(
                  currentEntry == null
                      ? 'Add this item report'
                      : 'Update this item report',
                ),
              ),
              if (formError != null) ...[
                const SizedBox(height: 8),
                Text(
                  formError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (issueEntries.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Reports added: ${issueEntries.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final entry in issueEntries.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${entry.value.itemName} · ${entry.value.type} × ${entry.value.quantity}',
                    ),
                    subtitle: entry.value.comment.isEmpty
                        ? null
                        : Text(entry.value.comment),
                    trailing: IconButton(
                      tooltip: 'Remove report',
                      onPressed: () => setState(() {
                        issueEntries.remove(entry.key);
                        if (entry.key == selectedItemKey) {
                          quantityController.clear();
                          commentController.clear();
                        }
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (quantityController.text.trim().isNotEmpty &&
                !_saveCurrentIssue()) {
              return;
            }
            if (issueEntries.isEmpty) {
              setState(
                () => formError = 'Add an issue report for at least one item.',
              );
              return;
            }
            final entries = issueEntries.values.toList();
            final first = entries.first;
            Navigator.pop(
              context,
              _ChecklistIssue(
                type: first.type,
                quantity: first.quantity,
                itemId: first.itemId,
                itemName: first.itemName,
                details: entries
                    .where((entry) => entry.comment.isNotEmpty)
                    .map((entry) => '${entry.itemName}: ${entry.comment}')
                    .join('; '),
                hasPhysicalQuantity: true,
                items: entries,
              ),
            );
          },
          child: const Text('Submit all reports'),
        ),
      ],
    );
  }
}

class _ChecklistReceiptSummary extends StatelessWidget {
  const _ChecklistReceiptSummary({
    required this.items,
    required this.issueReports,
  });

  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> issueReports;

  int _quantity(dynamic value) => AllocationChecklistService.quantity(value);

  Map<String, dynamic>? _reportFor(Map<String, dynamic> item) {
    final id = '${item['id'] ?? item['itemId'] ?? ''}';
    final name = '${item['name'] ?? ''}';
    for (final report in issueReports) {
      final reportId = '${report['itemId'] ?? ''}';
      if (id.isNotEmpty && reportId.isNotEmpty && id == reportId) {
        return report;
      }
      if (name.isNotEmpty && report['itemName'] == name) return report;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasIssues = issueReports.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8FA),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 19,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Received inventory details',
                  style: TextStyle(
                    color: AppColors.primaryDeep,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (hasIssues)
                _summaryBadge(
                  '${issueReports.length} issue${issueReports.length == 1 ? '' : 's'}',
                  const Color(0xFFFFE8E8),
                  const Color(0xFF9B2525),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _itemCard(items[index], _reportFor(items[index])),
          ],
        ],
      ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item, Map<String, dynamic>? issue) {
    final issueType = '${issue?['issueType'] ?? issue?['type'] ?? ''}'.trim();
    final issueQuantity = _quantity(issue?['quantity']);
    final allocated = issue == null
        ? _quantity(
            item['bundleCount'] ??
                item['stock'] ??
                item['startingStock'] ??
                item['quantity'],
          )
        : _quantity(
            issue['allocatedQuantity'] ??
                item['bundleCount'] ??
                item['stock'] ??
                item['startingStock'],
          );
    final received = issue == null
        ? _quantity(
            item['bundleCount'] ??
                item['stock'] ??
                item['startingStock'] ??
                item['quantity'],
          )
        : _quantity(
            issue['receivedQuantity'] ??
                (issueType == 'Extra'
                    ? allocated + issueQuantity
                    : issueType == 'Others'
                    ? allocated
                    : allocated - issueQuantity),
          );
    final (changeLabel, changeColor, changeBackground) = switch (issueType) {
      'Extra' => (
        '+$issueQuantity Extra',
        const Color(0xFF176B3A),
        const Color(0xFFE5F5EA),
      ),
      'Missing' || 'Not received' => (
        '−$issueQuantity $issueType',
        const Color(0xFF9B2525),
        const Color(0xFFFFE8E8),
      ),
      'Damaged' || 'Incorrect' => (
        '−$issueQuantity $issueType',
        const Color(0xFF9B4A13),
        const Color(0xFFFFF0DE),
      ),
      'Others' => (
        'Reported · $issueQuantity',
        const Color(0xFF5B4B79),
        const Color(0xFFF0EAF8),
      ),
      _ => ('No quantity change', AppColors.textMuted, AppColors.surfaceTint),
    };
    final comment = '${issue?['comment'] ?? ''}'.trim();

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: issue == null
              ? AppColors.border
              : changeColor.withValues(alpha: .28),
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${issue?['itemName'] ?? item['name'] ?? 'Item'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    fontSize: 14,
                  ),
                ),
              ),
              if (issue != null)
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.end,
                  children: [
                    _summaryBadge(
                      'REPORTED',
                      const Color(0xFFFFE8E8),
                      const Color(0xFF9B2525),
                    ),
                    _summaryBadge(changeLabel, changeBackground, changeColor),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(child: _quantityTile('Allocated', allocated)),
              const SizedBox(width: 8),
              Expanded(child: _quantityTile('Received', received)),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    comment,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _quantityTile(String label, int quantity) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
        Text(
          '$quantity',
          style: const TextStyle(
            color: AppColors.primaryDeep,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _summaryBadge(String label, Color background, Color foreground) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
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

  Future<_ReturnIssueReport?> askReturnIssue(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return null;
    return showDialog<_ReturnIssueReport>(
      context: context,
      builder: (_) => _ReturnIssueDialog(docs: docs),
    );
  }

  Future<_ChecklistIssue?> askIncomingIssue(Map<String, dynamic> data) async {
    final isPhysicalStock =
        data['isBundle'] == true ||
        AllocationChecklistService.type(data) == 'Categories';
    if (isPhysicalStock) {
      final incomingItems = data['isBundle'] == true
          ? [
              {
                'id':
                    '${data['sourceInventoryId'] ?? data['name'] ?? 'bundle'}',
                'name': data['name'] ?? 'Bundle',
                'stock': data['bundleCount'],
              },
            ]
          : AllocationChecklistService.rows(data['items']);
      if (incomingItems.isNotEmpty) {
        return showDialog<_ChecklistIssue>(
          context: context,
          useRootNavigator: true,
          builder: (_) =>
              _IncomingIssueDialog(data: data, items: incomingItems),
        );
      }
    }
    const issueTypes = [
      'Missing',
      'Extra',
      'Incorrect',
      'Damaged',
      'Not received',
      'Others',
    ];
    final physicalStock =
        data['isBundle'] == true ||
        AllocationChecklistService.type(data) == 'Categories';
    final items = data['isBundle'] == true
        ? [
            {
              'id': '${data['sourceInventoryId'] ?? data['name'] ?? 'bundle'}',
              'name': data['name'] ?? 'Bundle',
              'stock': data['bundleCount'],
            },
          ]
        : AllocationChecklistService.rows(data['items']);
    final quantityControllers = <String, TextEditingController>{};
    TextEditingController quantityController(Map<String, dynamic> item) =>
        quantityControllers.putIfAbsent(
          '${item['id'] ?? item['name'] ?? ''}',
          TextEditingController.new,
        );
    int itemQuantity(Map<String, dynamic> item) =>
        AllocationChecklistService.quantity(
          item['stock'] ?? item['startingStock'],
        );
    final detailsController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var selectedType = issueTypes.first;
    String? selectionError;
    final selectedItemKeys = <String>{
      if (items.isNotEmpty) '${items.first['id'] ?? items.first['name'] ?? ''}',
    };
    var confirming = false;
    _ChecklistIssue? pendingIssue;
    final result = await showDialog<_ChecklistIssue>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final quantityRequired =
              physicalStock &&
              selectedType != 'Others' &&
              selectedType != 'Not received';
          final selected = items
              .where(
                (item) => selectedItemKeys.contains(
                  '${item['id'] ?? item['name'] ?? ''}',
                ),
              )
              .toList();
          return AlertDialog(
            constraints: const BoxConstraints(maxWidth: 440),
            title: Text(confirming ? 'Confirm Issue Report' : 'Report Issue'),
            content: confirming
                ? pendingIssue!.items.isEmpty
                      ? Text(
                          'Submit this issue report: ${pendingIssue!.details}',
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Each affected item will be recorded separately:',
                            ),
                            const SizedBox(height: 8),
                            for (final issue in pendingIssue!.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '• ${issue.itemName}: ${issue.type} ${issue.quantity} / ${issue.allocatedQuantity}'
                                  '${issue.type == 'Not received' ? ' (pending Super Admin review)' : ''}',
                                ),
                              ),
                            if (pendingIssue!.details.isNotEmpty)
                              Text('Details: ${pendingIssue!.details}'),
                          ],
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
                          if (physicalStock) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Select every affected item',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            for (final item in items)
                              Builder(
                                builder: (context) {
                                  final key =
                                      '${item['id'] ?? item['name'] ?? ''}';
                                  final allocated = itemQuantity(item);
                                  final checked = selectedItemKeys.contains(
                                    key,
                                  );
                                  return Column(
                                    children: [
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        value: checked,
                                        title: Text(
                                          '${item['name'] ?? 'Item'} · Allocated $allocated',
                                        ),
                                        onChanged: (value) =>
                                            setDialogState(() {
                                              if (value == true) {
                                                selectedItemKeys.add(key);
                                              } else {
                                                selectedItemKeys.remove(key);
                                              }
                                              selectionError = null;
                                            }),
                                      ),
                                      if (checked && quantityRequired)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: TextFormField(
                                            controller: quantityController(
                                              item,
                                            ),
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              labelText:
                                                  '${item['name'] ?? 'Item'} issue quantity',
                                              helperText:
                                                  'Allocated: $allocated${selectedType == 'Extra' ? '' : '; cannot exceed this amount'}',
                                            ),
                                            validator: (value) {
                                              final amount = int.tryParse(
                                                value?.trim() ?? '',
                                              );
                                              if (amount == null ||
                                                  amount <= 0) {
                                                return 'Enter a whole number greater than zero';
                                              }
                                              if (selectedType != 'Extra' &&
                                                  amount > allocated) {
                                                return 'Cannot exceed $allocated';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      if (selectionError != null)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            selectionError!,
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
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
                  if (physicalStock &&
                      selectedType != 'Others' &&
                      selected.isEmpty) {
                    setDialogState(
                      () => selectionError = 'Select at least one item.',
                    );
                    return;
                  }
                  final issueEntries = <_ChecklistItemIssue>[
                    if (physicalStock &&
                        selectedType != 'Others' &&
                        selected.isNotEmpty)
                      for (final item in selected)
                        _ChecklistItemIssue(
                          type: selectedType,
                          quantity: selectedType == 'Not received'
                              ? itemQuantity(item)
                              : int.parse(quantityController(item).text.trim()),
                          allocatedQuantity: itemQuantity(item),
                          itemId: '${item['id'] ?? ''}',
                          itemName: '${item['name'] ?? 'Item'}',
                        ),
                  ];
                  final first = issueEntries.firstOrNull;
                  final detailsItem = selected.firstOrNull;
                  setDialogState(() {
                    pendingIssue = _ChecklistIssue(
                      type: selectedType,
                      quantity: first?.quantity ?? 0,
                      itemId: first?.itemId ?? '',
                      itemName:
                          first?.itemName ??
                          '${detailsItem?['name'] ?? data['name'] ?? 'Item'}',
                      details: detailsController.text.trim(),
                      hasPhysicalQuantity: physicalStock,
                      items: issueEntries,
                    );
                    confirming = true;
                  });
                },
                child: Text(
                  confirming
                      ? pendingIssue!.type == 'Others' ||
                                pendingIssue!.type == 'Not received'
                            ? 'Submit report'
                            : 'Confirm and receive'
                      : 'Add report',
                ),
              ),
            ],
          );
        },
      ),
    );
    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
    detailsController.dispose();
    return result;
  }

  Future<void> actReturns(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool accept,
  ) async {
    final returnIssue = widget.superAdmin && !accept
        ? await askReturnIssue(docs)
        : null;
    if (widget.superAdmin && !accept && returnIssue == null) return;
    final reason = accept
        ? ''
        : widget.superAdmin
        ? returnIssue!.entries.first.comment
        : await askReason(
            true,
            title: 'Report Issue',
            submitLabel: 'Submit report',
          );
    if (reason == null || !mounted) return;
    String message;
    var success = false;
    try {
      final actor = await resolveSessionActor(widget.db, admin: true);
      final service = AllocationChecklistService(widget.db);
      var changed = 0;
      if (widget.superAdmin) {
        if (!accept) {
          changed = await service.reportReturnIssues(
            actorId: actor.id,
            actorName: actor.name,
            reports: [
              for (final entry in returnIssue!.entries)
                {
                  'returnId': entry.returnId,
                  'issueType': entry.type,
                  'issueQuantity': entry.quantity,
                  'comment': entry.comment,
                },
            ],
          );
        } else {
          for (var start = 0; start < docs.length; start += 200) {
            changed += await service.decideReturns(
              docs.skip(start).take(200).map((doc) => doc.id).toList(),
              accept: accept,
              actorId: actor.id,
              actorName: actor.name,
              reason: reason,
            );
          }
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
          ? 'Issue report saved. The return is complete, and the branch Admin can view the report in Completed.'
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
                    ? 'Issue reported'
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
          report && incomingIssue != null && incomingIssue.hasPhysicalQuantity
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
              issueReports: [
                for (final issue in incomingIssue.items) issue.toMap(),
              ],
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
                  ? 'Issue reports submitted for ${incomingIssue?.items.length ?? 1} item(s).'
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
    final issueReports = AllocationChecklistService.rows(data['issueReports']);
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
    final isReceived = ChecklistStatus.label(data) == ChecklistStatus.received;
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
            if (isReceived && !type.startsWith('Beverages'))
              _ChecklistReceiptSummary(items: items, issueReports: issueReports)
            else
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
            if (!isReceived &&
                '${data['issueType'] ?? data['reason'] ?? ''}'.isNotEmpty)
              Text('Reason: ${data['issueType'] ?? data['reason']}'),
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
            if ('${data['issueReason'] ?? ''}'.isNotEmpty &&
                issueReports.isEmpty) ...[
              Text('Reported: ${data['issueReason'] ?? data['issueType']}'),
              if ('${data['issueDetails'] ?? ''}'.isNotEmpty)
                Text('Details: ${data['issueDetails']}'),
              Text(
                'Reported by ${data['reportedByName'] ?? data['reportedBy'] ?? 'Not recorded'} · ${date(data['reportedAt'])}',
              ),
            ],
            if ('${data['issueReason'] ?? ''}'.isNotEmpty &&
                issueReports.isNotEmpty)
              Text(
                'Reported by ${data['reportedByName'] ?? data['reportedBy'] ?? 'Not recorded'} · ${date(data['reportedAt'])}',
              ),
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
                    (widget.pendingOnly || (!widget.returnsOnly && tab != 1))
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
                          widget.returnsOnly &&
                          widget.superAdmin &&
                          selectedEnd != null;
                      final filterSubmittedAdminTab =
                          widget.returnsOnly &&
                          widget.admin &&
                          !widget.superAdmin &&
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
                                'Completed Return',
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
