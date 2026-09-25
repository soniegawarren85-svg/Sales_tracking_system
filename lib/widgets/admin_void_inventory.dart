import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminVoidInventory extends StatefulWidget {
  const AdminVoidInventory({
    super.key,
    required this.type,
    this.categoryId,
    this.expired = false,
  });
  final String type;
  final String? categoryId;
  final bool expired;
  @override
  State<AdminVoidInventory> createState() => _AdminVoidInventoryState();
}

class _AdminVoidInventoryState extends State<AdminVoidInventory> {
  late String? _category = widget.categoryId;
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
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        if (data == null) throw StateError('Record no longer exists.');
        if (item == null) {
          transaction.update(ref, {
            'isDeleted': false,
            'deletedAt': FieldValue.delete(),
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
          ..remove('deletedAt');
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF4F8),
    appBar: AppBar(
      title: Text('${widget.expired ? 'Expired' : 'Void'} • ${widget.type}'),
      backgroundColor: const Color(0xFFFCE4EC),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(
            widget.type == 'Coffee' ? 'coffee_products' : 'sales_inventory',
          )
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(child: Text('Unable to load inventory.'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs
            .where(
              (doc) =>
                  widget.type == 'Coffee' ||
                  (doc.data()['isBundle'] == true) == (widget.type == 'Bundle'),
            )
            .toList();
        final rows = <Widget>[];
        void row(
          QueryDocumentSnapshot<Map<String, dynamic>> doc,
          Map<String, dynamic> data, {
          String field = '',
          bool parent = false,
        }) {
          rows.add(
            Card(
              child: ListTile(
                leading: Icon(
                  widget.expired ? Icons.event_busy : Icons.block,
                  color: const Color(0xFFE91E63),
                ),
                title: Text(
                  '${data['name'] ?? data['bundleId'] ?? doc.data()['name'] ?? 'Item'}',
                ),
                subtitle: Text(
                  parent
                      ? 'Entire ${widget.type == 'Categories' ? 'category' : widget.type.toLowerCase()}'
                      : '${doc.data()['name'] ?? ''} • ${data['expirationDate'] ?? ''}',
                ),
                trailing: widget.expired
                    ? null
                    : IconButton(
                        tooltip: 'Restore',
                        onPressed: _restoring.isNotEmpty
                            ? null
                            : () => _restore(
                                doc.reference,
                                parent ? null : data,
                                field,
                              ),
                        icon: const Icon(Icons.restore),
                      ),
              ),
            ),
          );
        }

        for (final doc in docs) {
          if (widget.type == 'Categories' &&
              _category != null &&
              doc.id != _category)
            continue;
          final data = doc.data();
          if (!widget.expired && data['isDeleted'] == true) {
            row(doc, data, parent: true);
            continue;
          }
          if (widget.expired && data['isDeleted'] == true) continue;
          if (widget.type == 'Coffee') {
            if (widget.expired && _expired(data)) row(doc, data, parent: true);
            continue;
          }
          if (widget.type == 'Bundle') {
            for (final item
                in (data['bundleInstances'] as List? ?? []).whereType<Map>()) {
              if (widget.expired
                  ? _expired(item)
                  : item['isDeleted'] == true ||
                        ['void', 'voided', 'removed'].contains(item['status']))
                row(
                  doc,
                  Map<String, dynamic>.from(item),
                  field: 'bundleInstances',
                );
            }
            if (widget.expired && _expired(data)) row(doc, data, parent: true);
          } else {
            for (final field
                in widget.expired ? ['items'] : ['removedItems', 'items']) {
              for (final item
                  in (data[field] as List? ?? []).whereType<Map>()) {
                if (widget.expired
                    ? _expired(item)
                    : field == 'removedItems' || item['isDeleted'] == true)
                  row(doc, Map<String, dynamic>.from(item), field: field);
              }
            }
          }
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.type == 'Categories')
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All categories'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  ...docs.map(
                    (doc) => ChoiceChip(
                      label: Text('${doc.data()['name'] ?? 'Category'}'),
                      selected: _category == doc.id,
                      onSelected: (_) => setState(() => _category = doc.id),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No records in this section.'),
              )
            else
              ...rows,
          ],
        );
      },
    ),
  );
}
