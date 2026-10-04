import 'dart:async';
import '../services/return_metadata_service.dart';
import '../services/return_batch_service.dart';
import '../services/public_item_id.dart';
import '../theme/app_colors.dart';
import 'return_batch_cards.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';

class ChecklistReturnDialog extends StatefulWidget {
  const ChecklistReturnDialog({
    super.key,
    required this.db,
    required this.scopeIds,
    this.searchText = '',
    this.onSubmitted,
  });
  final FirebaseFirestore db;
  final List<String> scopeIds;
  final String searchText;
  final VoidCallback? onSubmitted;
  @override
  State<ChecklistReturnDialog> createState() => _ChecklistReturnDialogState();
}

class _ChecklistReturnDialogState extends State<ChecklistReturnDialog> {
  final options = <Map<String, dynamic>>[];
  final branches = <String, String>{};
  String source = 'All', error = '';
  String? branch;
  bool loading = true, saving = false;
  String? batchId;
  List<Map<String, dynamic>>? pendingItems;
  String actorName = '', actorPublicId = '';
  final profiles = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Please sign in again.');
      final ids = widget.scopeIds.toSet().toList();
      final snapshots = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var offset = 0; offset < ids.length; offset += 30) {
        snapshots.addAll(
          (await widget.db
                  .collection('staff_inventory')
                  .where('staffId', whereIn: ids.skip(offset).take(30).toList())
                  .get())
              .docs,
        );
      }
      final records = await Future.wait([
        widget.db
            .collection('completed_sales')
            .where('userId', isEqualTo: user.uid)
            .get(),
        widget.db
            .collection('stock_adjustments')
            .where('userId', isEqualTo: user.uid)
            .get(),
        widget.db
            .collection('stock_adjustments')
            .where('staffId', isEqualTo: user.uid)
            .get(),
      ]);
      final choices = <Map<String, dynamic>>[];
      final refunds = {for (final doc in records.first.docs) doc.id: doc};
      final reductions = {
        for (final snapshot in records.skip(1))
          for (final doc in snapshot.docs) doc.id: doc,
      };
      for (var offset = 0; offset < ids.length; offset += 30) {
        final scope = ids.skip(offset).take(30).toList();
        final branchRecords = await Future.wait([
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
        for (final doc in branchRecords.first.docs) {
          refunds[doc.id] = doc;
        }
        for (final snapshot in branchRecords.skip(1)) {
          for (final doc in snapshot.docs) {
            reductions[doc.id] = doc;
          }
        }
      }
      final staffUids = {
        user.uid,
        ...refunds.values.map((doc) => '${doc.data()['userId'] ?? ''}'),
        ...reductions.values.map(
          (doc) => '${doc.data()['userId'] ?? doc.data()['staffId'] ?? ''}',
        ),
      }.where((id) => id.isNotEmpty).toSet();
      await Future.wait(
        staffUids.map((id) async {
          Map<String, dynamic> profile = {};
          try {
            profile =
                (await widget.db
                        .collection('staff_requests')
                        .doc(id)
                        .get()
                        .timeout(const Duration(seconds: 6)))
                    .data() ??
                {};
          } catch (_) {
            // Older records may outlive a staff profile or its read access.
          }
          final fullName =
              [profile['firstName'], profile['middleName'], profile['lastName']]
                  .map((v) => '${v ?? ''}'.trim())
                  .where((v) => v.isNotEmpty)
                  .join(' ');
          profiles[id] = {
            'name': returnText([fullName, profile['name']], ''),
            'staffId': publicItemId(
              returnText([
                profile['staffId'],
                profile['publicId'],
              ], 'Not recorded'),
            ),
          };
        }),
      );
      actorName = returnText([
        profiles[user.uid]?['name'],
        user.displayName,
        user.email,
      ], 'Staff');
      actorPublicId = '${profiles[user.uid]?['staffId'] ?? 'Not recorded'}';
      final branchNames = <String, String>{};
      for (final id in ids) {
        final data = (await widget.db.collection('branches').doc(id).get())
            .data();
        if (data != null && data['isDeleted'] != true)
          branchNames[id] = '${data['name'] ?? data['branchName'] ?? id}';
      }
      void add(
        String collection,
        String id,
        String key,
        Map<String, dynamic> data,
        Map<String, dynamic> item,
        int count,
      ) {
        if (count <= 0 || data['isDeleted'] == true) return;
        final branchId =
            data['branchId'] ??
            (ids.contains(data['staffId']) && data['staffId'] != user.uid
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
        final profile = profiles['${data['userId'] ?? data['staffId']}'];
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
            if (returnItemName(candidate).toLowerCase() == name.toLowerCase())
              matches.add({
                ...candidate,
                'isBundle': saved['isBundle'],
                'isCoffee': saved['isCoffee'],
                'isAddon': saved['isAddon'],
              });
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
          'itemDisplayId':
              returnItemCode(item) == '--' || resolved['publicId'] != null
              ? returnItemCode(resolved)
              : returnItemCode(item),
          'isBundle': item['isBundle'] == true || resolved['isBundle'] == true,
          'isCoffee': item['isCoffee'] == true || resolved['isCoffee'] == true,
          'isAddon': item['isAddon'] == true || resolved['isAddon'] == true,
          'staffName': returnText(
            [profile?['name'], data['staffName'], data['staffFullName']],
            (data['userId'] ?? data['staffId']) == user.uid
                ? actorName
                : 'Not recorded',
          ),
          'staffPublicId': returnText(
            [data['staffPublicId'], profile?['staffId']],
            (data['userId'] ?? data['staffId']) == user.uid
                ? actorPublicId
                : 'Not recorded',
          ),
          'branchName': branchNames[branchId],
          'comment': returnText([
            item['comment'],
            data['comment'],
            data['details'],
          ], ''),
          'quantity': count,
          'unitPrice': item['price'] ?? item['unitPrice'] ?? data['unitPrice'],
          'expirationDate':
              item['expirationDate'] ?? resolved['expirationDate'],
          'date': data['timestamp'] ?? data['createdAt'],
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
      await Future.wait(
        choices.map((item) async {
          try {
            final resolved = await metadata
                .resolve(item)
                .timeout(const Duration(seconds: 6));
            item.addAll(resolved);
            item['staffName'] = resolved['sourceStaffName'];
            item['staffPublicId'] = resolved['sourceStaffId'];
          } catch (_) {}
        }),
      );
      if (!mounted) return;
      setState(() {
        options
          ..clear()
          ..addAll(choices);
        branches
          ..clear()
          ..addAll(branchNames);
        if (branches.isEmpty && ids.isNotEmpty)
          branches[ids.first] = 'Assigned inventory';
        branch = branches.length == 1 ? branches.keys.first : null;
        loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          error = 'Unable to load return items: $e';
          loading = false;
        });
    }
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
          'Return these ${items.length} refund/reduce records to the admin with their quantities and reasons?',
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Please sign in again.');
      await ReturnBatchService(widget.db)
          .submit(
            batchId: batchId!,
            items: pendingItems!,
            actorId: user.uid,
            actorName: actorName,
            actorPublicId: actorPublicId,
            scopeIds: widget.scopeIds,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final submittedKeys = pendingItems!.map((item) => item['key']).toSet();
      final count = pendingItems!.length;
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
            'Return submitted successfully',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.primaryDeep,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '$count return records were sent together. You can track admin acceptance in Pending Confirmation.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('View pending confirmation'),
            ),
          ],
        ),
      );
      if (mounted) widget.onSubmitted?.call();
    } on TimeoutException {
      if (mounted)
        setState(
          () => error =
              'The server has not confirmed this batch yet. Check your connection and Pending Confirmation, or retry the same batch safely. No success is reported until confirmed.',
        );
    } catch (e) {
      if (mounted)
        setState(
          () => error =
              'Return was not confirmed: $e. Retry uses the same batch to prevent duplicates.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = options
        .where(
          (o) =>
              (source == 'All' || o['collection'] == source) &&
              '${o['label']} ${o['reason']}'.toLowerCase().contains(
                widget.searchText.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            children: [
              for (final entry in {
                'All': 'All',
                'stock_adjustments': 'Reduce',
                'completed_sales': 'Refund',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: source == entry.key,
                  onSelected: saving
                      ? null
                      : (_) => setState(() => source = entry.key),
                ),
            ],
          ),
        ),
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
                  loading || saving || (visible.isEmpty && pendingItems == null)
                  ? null
                  : () => submit(visible),
              icon: const Icon(Icons.assignment_return_outlined),
              label: Text(
                saving
                    ? 'Submitting...'
                    : pendingItems != null
                    ? 'Retry same batch'
                    : 'Submit Return (${visible.length})',
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
