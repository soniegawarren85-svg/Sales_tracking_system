import 'dart:async';
import '../services/return_metadata_service.dart';
import '../services/return_batch_service.dart';
import '../theme/app_colors.dart';
import 'return_batch_cards.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/session_actor.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';

class ChecklistReturnDialog extends StatefulWidget {
  const ChecklistReturnDialog({
    super.key,
    required this.db,
    required this.scopeIds,
    this.searchText = '',
    this.selectedDay,
    this.onSubmitted,
  });
  final FirebaseFirestore db;
  final List<String> scopeIds;
  final String searchText;
  final DateTime? selectedDay;
  final VoidCallback? onSubmitted;
  @override
  State<ChecklistReturnDialog> createState() => _ChecklistReturnDialogState();
}

class _ChecklistReturnDialogState extends State<ChecklistReturnDialog> {
  final options = <Map<String, dynamic>>[];
  final branches = <String, String>{};
  String error = '';
  String? branch;
  bool loading = true, saving = false;
  bool resolvingItemCodes = false;
  String? batchId;
  List<Map<String, dynamic>>? pendingItems;
  String actorName = '', actorPublicId = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      resolvingItemCodes = false;
      error = '';
    });
    try {
      final user = await resolveBranchInventoryActor(widget.db);

      final ids = widget.scopeIds.toSet().toList();
      final inventoryQueries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      final branchQueries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var offset = 0; offset < ids.length; offset += 30) {
        final scope = ids.skip(offset).take(30).toList();
        inventoryQueries.add(
          widget.db
              .collection('staff_inventory')
              .where('staffId', whereIn: scope)
              .get(),
        );
        branchQueries.addAll([
          widget.db
              .collection('completed_sales')
              .where('branchId', whereIn: scope)
              .get(),
          widget.db
              .collection('stock_adjustments')
              .where('branchId', whereIn: scope)
              .get(),
          widget.db
              .collection('stock_adjustments')
              .where('staffId', whereIn: scope)
              .get(),
        ]);
      }
      final personalQueries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        widget.db
            .collection('completed_sales')
            .where('userId', isEqualTo: user.id)
            .get(),
        widget.db
            .collection('stock_adjustments')
            .where('userId', isEqualTo: user.id)
            .get(),
        widget.db
            .collection('stock_adjustments')
            .where('staffId', isEqualTo: user.id)
            .get(),
      ];
      final queryResults = await Future.wait([
        ...inventoryQueries,
        ...personalQueries,
        ...branchQueries,
      ]);
      final snapshots = <QueryDocumentSnapshot<Map<String, dynamic>>>[
        for (final snapshot in queryResults.take(inventoryQueries.length))
          ...snapshot.docs,
      ];
      final personalOffset = inventoryQueries.length;
      final branchOffset = personalOffset + personalQueries.length;
      final choices = <Map<String, dynamic>>[];
      final refunds = {
        for (final doc in queryResults[personalOffset].docs) doc.id: doc,
      };
      final reductions = {
        for (final snapshot in queryResults.skip(personalOffset + 1).take(2))
          for (final doc in snapshot.docs) doc.id: doc,
      };
      for (var index = 0; index < branchQueries.length; index++) {
        final snapshot = queryResults[branchOffset + index];
        final target = index % 3 == 0 ? refunds : reductions;
        for (final doc in snapshot.docs) {
          target[doc.id] = doc;
        }
      }
      actorName = returnText([user.name], 'Staff');
      actorPublicId = returnText([user.publicId]);
      final branchNames = <String, String>{
        for (final id in ids) id: ids.length == 1 ? 'Assigned inventory' : id,
      };
      final sourceRecords = <String, Map<String, dynamic>>{};
      void add(
        String collection,
        String id,
        String key,
        Map<String, dynamic> data,
        Map<String, dynamic> item,
        int count,
      ) {
        if (count <= 0 || data['isDeleted'] == true) return;
        sourceRecords['$collection/$id'] = data;
        final branchId =
            data['branchId'] ??
            (ids.contains(data['staffId']) && data['staffId'] != user.id
                ? data['staffId']
                : null) ??
            (collection == 'staff_inventory'
                ? data['staffId']
                : snapshots
                      .where((doc) => doc.id == data['categoryId'])
                      .firstOrNull
                      ?.data()['staffId']);
        if (branchId != null && !ids.contains(branchId)) return;
        final name = returnItemName(item);
        final matches = <Map<String, dynamic>>[];
        for (final stock in snapshots) {
          final saved = stock.data();
          if (branchId != null && saved['staffId'] != branchId) continue;
          final candidates =
              saved['isBundle'] == true ||
                  saved['isCoffee'] == true ||
                  saved['isAddon'] == true
              ? [saved]
              : AllocationChecklistService.rows(saved['items']);
          for (final candidate in candidates) {
            if (returnItemName(candidate).toLowerCase() == name.toLowerCase()) {
              matches.add({
                ...candidate,
                'isBundle': saved['isBundle'],
                'isCoffee': saved['isCoffee'],
                'isAddon': saved['isAddon'],
              });
            }
          }
        }
        final resolved = matches.length == 1 ? matches.single : item;
        if (branchId != null && ids.contains(branchId)) {
          branchNames.putIfAbsent(
            '$branchId',
            () => '${data['branchName'] ?? data['staffName'] ?? branchId}',
          );
        }
        choices.add({
          'key': '$collection/$id/$key',
          'collection': collection,
          'id': id,
          'line': key,
          'name': name,
          'sourceItem': item,
          'userId': data['userId'] ?? data['staffId'],
          'itemDisplayId': returnItemCode(item) == '--'
              ? returnItemCode(resolved)
              : returnItemCode(item),
          'isBundle': item['isBundle'] == true || resolved['isBundle'] == true,
          'isCoffee': item['isCoffee'] == true || resolved['isCoffee'] == true,
          'isAddon': item['isAddon'] == true || resolved['isAddon'] == true,
          'staffName': returnText(
            [data['staffName'], data['staffFullName']],
            (data['userId'] ?? data['staffId']) == user.id
                ? actorName
                : 'Not recorded',
          ),
          'staffPublicId': returnText(
            [data['staffPublicId']],
            (data['userId'] ?? data['staffId']) == user.id
                ? actorPublicId
                : 'Not recorded',
          ),
          'branchName': returnText([
            branchNames[branchId],
            data['branchName'],
            data['staffName'],
          ], 'Not recorded'),
          'comment': returnText([
            item['comment'],
            data['comment'],
            data['details'],
          ], ''),
          'quantity': count,
          'unitPrice': item['price'] ?? item['unitPrice'] ?? data['unitPrice'],
          'expirationDate':
              item['expirationDate'] ?? resolved['expirationDate'],
          'date':
              data['refundAt'] ??
              data['reducedAt'] ??
              data['timestamp'] ??
              data['createdAt'],
          'sourceDate':
              data['refundAt'] ??
              data['reducedAt'] ??
              data['timestamp'] ??
              data['createdAt'],
          'reason': returnText([
            item['refundReason'],
            data['reason'],
            data['refundReason'],
            data['reductionReason'],
          ]),
          'branchId': branchId,
          'label':
              '$name · $count available · ${branchNames[branchId] ?? data['branchName'] ?? 'Select branch'} · $id',
        });
      }

      for (final doc in refunds.values) {
        final d = doc.data();
        if ('${d['type'] ?? d['status']}'.toLowerCase() != 'refund') continue;
        final claimed = d['checklistReturnedQuantities'] as Map? ?? {};
        final items = AllocationChecklistService.rows(d['items']);
        for (var index = 0; index < items.length; index++) {
          add(
            'completed_sales',
            doc.id,
            '$index',
            d,
            items[index],
            AllocationChecklistService.quantity(items[index]['quantity']) -
                AllocationChecklistService.quantity(claimed['$index']),
          );
        }
      }
      for (final doc in reductions.values) {
        final d = doc.data();
        if (d['type'] == 'addon_void') continue;
        final claimed = d['checklistReturnedQuantities'] as Map? ?? {};
        add(
          'stock_adjustments',
          doc.id,
          'item',
          d,
          {...d, 'name': d['itemName'] ?? d['categoryName']},
          AllocationChecklistService.quantity(d['quantity']) -
              AllocationChecklistService.quantity(claimed['item']),
        );
      }
      final metadata = ReturnMetadataService(widget.db);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        options
          ..clear()
          ..addAll(sortReturnRecordsNewestFirst(choices));
        branches
          ..clear()
          ..addAll(branchNames);
        if (branches.isEmpty && ids.isNotEmpty) {
          branches[ids.first] = 'Assigned inventory';
        }
        branch = branches.length == 1 ? branches.keys.first : null;
        loading = false;
        resolvingItemCodes = choices.any(
          (item) => returnItemCode(item) == '--',
        );
      });
      unawaited(_resolveBranches(ids, generation));
      unawaited(_resolveMetadata(choices, sourceRecords, metadata, generation));
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          error = 'Unable to load return items: $e';
          loading = false;
        });
      }
    }
  }

  Future<void> _resolveMetadata(
    List<Map<String, dynamic>> choices,
    Map<String, Map<String, dynamic>> sourceRecords,
    ReturnMetadataService metadata,
    int generation,
  ) async {
    await Future.wait(
      choices.map((item) async {
        try {
          final resolved = await metadata
              .resolve(
                item,
                sourceData:
                    sourceRecords['${item['collection']}/${item['id']}'],
              )
              .timeout(const Duration(seconds: 6));
          item.addAll(resolved);
          item['staffName'] = resolved['sourceStaffName'];
          item['staffPublicId'] = resolved['sourceStaffId'];
        } catch (_) {}
      }),
    );
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      resolvingItemCodes = false;
      options
        ..clear()
        ..addAll(sortReturnRecordsNewestFirst(choices));
    });
  }

  Future<void> _resolveBranches(List<String> ids, int generation) async {
    try {
      final docs = await Future.wait(
        ids.map((id) => widget.db.collection('branches').doc(id).get()),
      );
      if (!mounted || generation != _loadGeneration) return;
      final names = <String, String>{};
      for (var index = 0; index < docs.length; index++) {
        final data = docs[index].data();
        if (data != null && data['isDeleted'] != true) {
          final id = ids[index];
          names[id] = '${data['name'] ?? data['branchName'] ?? id}';
        }
      }
      setState(() {
        branches
          ..clear()
          ..addAll(names);
        for (final id in ids) {
          branches.putIfAbsent(
            id,
            () => ids.length == 1 ? 'Assigned inventory' : id,
          );
        }
        for (final item in options) {
          final name = branches[item['branchId']];
          if (name != null) item['branchName'] = name;
        }
        if (branches.isEmpty && ids.isNotEmpty) {
          branches[ids.first] = 'Assigned inventory';
        }
      });
    } catch (_) {}
  }

  Future<void> submit(List<Map<String, dynamic>> visible) async {
    if (saving) return;
    final items =
        pendingItems ??
        visible
            .map(
              (item) => {
                ...item,
                'branchId': item['branchId'] ?? branch,
                'branchName':
                    branches[item['branchId'] ?? branch] ?? item['branchName'],
              },
            )
            .toList();
    if (items.any((item) => !widget.scopeIds.contains(item['branchId']))) {
      setState(() => error = 'Select the original branch before submitting.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        constraints: const BoxConstraints(maxWidth: 420),
        title: Text(
          pendingItems == null
              ? 'Submit returned items?'
              : 'Retry this return batch?',
          style: const TextStyle(
            color: AppColors.primaryDeep,
            fontWeight: FontWeight.bold,
            fontSize: 19,
          ),
        ),
        content: Text(
          'Return these ${items.fold<int>(0, (total, item) => total + AllocationChecklistService.quantity(item['quantity']))} items from ${items.length} refund/reduce records to the super admin with their quantities and reasons?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDeep,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm return'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    pendingItems ??= items;
    batchId ??= widget.db.collection('allocation_checklist').doc().id;
    setState(() {
      saving = true;
      error = '';
    });
    try {
      final user = await resolveBranchInventoryActor(widget.db);

      await ReturnBatchService(widget.db)
          .submit(
            batchId: batchId!,
            items: pendingItems!,
            actorId: user.id,
            actorName: actorName,
            actorPublicId: actorPublicId,
            scopeIds: widget.scopeIds,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final submittedKeys = pendingItems!.map((item) => item['key']).toSet();
      final count = pendingItems!.fold<int>(
        0,
        (total, item) =>
            total + AllocationChecklistService.quantity(item['quantity']),
      );
      setState(() {
        options.removeWhere((item) => submittedKeys.contains(item['key']));
        pendingItems = null;
        batchId = null;
        saving = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 380),
          backgroundColor: Colors.white,
          icon: const Icon(
            Icons.check_circle,
            color: AppColors.primaryDeep,
            size: 38,
          ),
          title: const Text(
            'Items returned successfully',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.primaryDeep,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Successfully returned $count ${count == 1 ? 'item' : 'items'}.',
          ),
        ),
      );
      if (mounted) await load();
    } on TimeoutException {
      if (mounted) {
        setState(
          () => error =
              'The server has not confirmed this batch yet. Check your connection and Pending Confirmation, or retry the same batch safely. No success is reported until confirmed.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Return was not confirmed: $e. Retry uses the same batch to prevent duplicates.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = options
        .where(
          (o) =>
              "${o['label']} ${o['reason']} ${o['collection'] == 'completed_sales' ? 'Refund' : 'Reduce'}"
                  .toLowerCase()
                  .contains(widget.searchText.toLowerCase()),
        )
        .toList();
    final visibleQuantity = visible.fold<int>(
      0,
      (total, item) =>
          total + AllocationChecklistService.quantity(item['quantity']),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (branches.length > 1 && visible.any((o) => o['branchId'] == null))
          Padding(
            padding: const EdgeInsets.all(8),
            child: DropdownButtonFormField<String>(
              initialValue: branch,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Original branch'),
              items: branches.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => branch = value),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed:
                  loading ||
                      resolvingItemCodes ||
                      saving ||
                      (visible.isEmpty && pendingItems == null)
                  ? null
                  : () => submit(visible),
              icon: const Icon(Icons.keyboard_return_rounded),
              label: Text(
                saving
                    ? 'Submitting...'
                    : resolvingItemCodes
                    ? 'Loading item details...'
                    : pendingItems != null
                    ? 'Retry same batch'
                    : 'Submit Return ($visibleQuantity)',
              ),
            ),
          ),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(error, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No unsubmitted refunds or reductions.'),
                      TextButton(onPressed: load, child: const Text('Refresh')),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return ReturnItemCard(
                      data: {
                        ...item,
                        'branchName':
                            branches[item['branchId'] ?? branch] ??
                            item['branchName'],
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
