import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'admin_catalog.dart';
import 'void_reason_dialog.dart';

Future<void> showCategoryManager(
  BuildContext context, {
  FirebaseFirestore? database,
}) => showDialog<void>(
  context: context,
  builder: (_) => _CategoryManager(database: database),
);

class _CategoryManager extends StatefulWidget {
  const _CategoryManager({this.database});
  final FirebaseFirestore? database;
  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  late final db = widget.database ?? FirebaseFirestore.instance;
  bool busy = false;
  Future<void> change(String name, bool voidCategory) async {
    String? value;
    if (voidCategory) {
      value = await showVoidReasonDialog(
        context,
        '$name category and all its items',
      );
    } else {
      var edited = name;
      value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename category'),
          content: TextFormField(
            initialValue: name,
            onChanged: (v) => edited = v,
            decoration: const InputDecoration(labelText: 'Category name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (edited.trim().isNotEmpty)
                  Navigator.pop(context, edited.trim());
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    }
    if (value == null || !mounted) return;
    setState(() => busy = true);
    try {
      final all = await db.collection('sales_inventory').get();
      final key = name.trim().toLowerCase();
      final sources = all.docs
          .where(
            (d) =>
                d.data()['isBundle'] != true &&
                d.data()['isDeleted'] != true &&
                d.data()['isVoided'] != true &&
                catalogCategoryKey(d.data()) == key,
          )
          .toList();
      if (sources.isEmpty)
        throw StateError('This category no longer exists. Reopen the manager.');
      if (!voidCategory &&
          currentCatalogCategories(all.docs.map((d) => d.data()).toList()).any(
            (data) =>
                catalogCategoryKey(data) == value!.toLowerCase() &&
                catalogCategoryKey(data) != key,
          )) {
        throw StateError('A category with this name already exists.');
      }
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final source in sources) {
        refs.add(source.reference);
        for (final collection in ['staff_inventory', 'allocation_checklist']) {
          final linked = await db
              .collection(collection)
              .where('sourceInventoryId', isEqualTo: source.id)
              .get();
          refs.addAll(
            linked.docs
                .where(
                  (d) =>
                      collection != 'allocation_checklist' ||
                      [
                        'pending',
                        'Awaiting Confirmation',
                        'Issue Reported',
                      ].contains(d.data()['status']),
                )
                .map((d) => d.reference),
          );
        }
      }
      if (refs.length > 450)
        throw StateError(
          'Too many linked records for one change. Contact support.',
        );
      await db.runTransaction((tx) async {
        final records = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in refs) {
          records.add(await tx.get(ref));
        }
        for (final record in records) {
          if (!record.exists) continue;
          tx.update(record.reference, {
            if (!voidCategory) ...{'name': value, 'categoryName': value},
            if (voidCategory) ...{
              'isDeleted': true,
              'deletedAt': FieldValue.serverTimestamp(),
              'voidReason': value,
              'voidedBy': FirebaseAuth.instance.currentUser?.uid,
              if (record.reference.parent.id == 'allocation_checklist')
                'status': 'voided',
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              voidCategory ? 'Category voided.' : 'Category name saved.',
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Manage categories')),
        IconButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    content: SizedBox(
      width: 560,
      height: 400,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('sales_inventory').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Text('Unable to load categories.');
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final categories = <String, String>{};
          for (final data in currentCatalogCategories(
            snapshot.data!.docs.map((d) => d.data()).toList(),
          )) {
            categories[catalogCategoryKey(data)] = '${data['name']}';
          }
          return ListView(
            children: [
              for (final name in categories.values)
                ListTile(
                  title: Text(name),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Rename category',
                        onPressed: busy ? null : () => change(name, false),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Void category and all items',
                        onPressed: busy ? null : () => change(name, true),
                        icon: const Icon(Icons.block),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
