import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/allocation_checklist_service.dart';
import '../theme/app_colors.dart';

class AllocationChecklistButton extends StatelessWidget {
  final List<String> scopeIds;
  final FirebaseFirestore? database;
  const AllocationChecklistButton({
    super.key,
    required this.scopeIds,
    this.database,
  });

  @override
  Widget build(BuildContext context) {
    final db = database ?? FirebaseFirestore.instance;
    final ids = scopeIds.where((id) => id.isNotEmpty).toSet().take(30).toList();
    if (ids.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('allocation_checklist')
          .where('staffId', whereIn: ids)
          .snapshots(),
      builder: (context, snapshot) {
        final pending =
            snapshot.data?.docs
                .where((doc) => doc.data()['status'] == 'pending')
                .length ??
            0;
        return FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
          ),
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text('Checklist ($pending)'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _ChecklistDialog(ids: ids, db: db),
          ),
        );
      },
    );
  }
}

class _ChecklistDialog extends StatefulWidget {
  final List<String> ids;
  final FirebaseFirestore db;
  const _ChecklistDialog({required this.ids, required this.db});
  @override
  State<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends State<_ChecklistDialog> {
  String search = '', filter = 'All items';
  final busy = <String>{};
  late final stream = widget.db
      .collection('allocation_checklist')
      .where('staffId', whereIn: widget.ids)
      .snapshots();

  Future<void> decide(String id, bool accept) async {
    String reason = '';
    if (!accept) {
      var declineReason = '';
      final form = GlobalKey<FormState>();
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline allocation'),
          content: Form(
            key: form,
            child: TextFormField(
              onChanged: (value) => declineReason = value,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Explain why this delivery cannot be accepted',
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
                  Navigator.pop(context, declineReason.trim());
              },
              child: const Text('Decline and return'),
            ),
          ],
        ),
      );
      if (value == null || !mounted) return;
      reason = value;
    }
    setState(() => busy.add(id));
    try {
      final changed = await AllocationChecklistService(widget.db).decide(
        id,
        accept: accept,
        staffId: FirebaseAuth.instance.currentUser!.uid,
        reason: reason,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed
                  ? accept
                        ? 'Allocation accepted. Inventory updated.'
                        : 'Allocation returned. Admin notified.'
                  : 'This allocation has already been processed.',
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to process allocation: $error')),
        );
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SizedBox(
      width: 980,
      height: 650,
      child: Column(
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Allocation checklist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: busy.isEmpty ? () => Navigator.pop(context) : null,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) =>
                  setState(() => search = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search items or categories',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['All items', 'Categories', 'Bundle', 'Beverages']
                    .map(
                      (type) => ChoiceChip(
                        label: Text(type),
                        selected: filter == type,
                        onSelected: (_) => setState(() => filter = type),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(
                    child: Text('Unable to load checklist. Please try again.'),
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data();
                  return data['status'] == 'pending' &&
                      (filter == 'All items' ||
                          AllocationChecklistService.type(data) == filter) &&
                      '${data['name']} ${data['items']}'.toLowerCase().contains(
                        search,
                      );
                }).toList();
                if (docs.isEmpty)
                  return const Center(child: Text('No pending allocations.'));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index], data = doc.data();
                    final type = AllocationChecklistService.type(data);
                    final items = type == 'Categories'
                        ? AllocationChecklistService.rows(data['items'])
                        : [data];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${data['name'] ?? 'Delivery'} • $type',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            Text('${data['staffName'] ?? ''}'),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Item')),
                                  DataColumn(label: Text('ID')),
                                  DataColumn(label: Text('Quantity')),
                                ],
                                rows: items
                                    .map(
                                      (item) => DataRow(
                                        cells: [
                                          DataCell(
                                            Text('${item['name'] ?? ''}'),
                                          ),
                                          DataCell(
                                            Text(
                                              '${item['publicId'] ?? item['id'] ?? '—'}',
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              type == 'Beverages'
                                                  ? 'Catalog'
                                                  : '${item['bundleCount'] ?? item['stock'] ?? item['startingStock'] ?? 0}',
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 12,
                              children: [
                                OutlinedButton(
                                  onPressed: busy.contains(doc.id)
                                      ? null
                                      : () => decide(doc.id, false),
                                  child: const Text('Decline'),
                                ),
                                FilledButton.icon(
                                  onPressed: busy.contains(doc.id)
                                      ? null
                                      : () => decide(doc.id, true),
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    busy.contains(doc.id)
                                        ? 'Processing…'
                                        : 'Accept',
                                  ),
                                ),
                              ],
                            ),
                          ],
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
  );
}
