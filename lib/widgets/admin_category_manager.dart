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
  String _query = '';

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
                if (edited.trim().isNotEmpty) {
                  Navigator.pop(context, edited.trim());
                }
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
      if (sources.isEmpty) {
        throw StateError('This category no longer exists. Reopen the manager.');
      }
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
      if (refs.length > 450) {
        throw StateError(
          'Too many linked records for one change. Contact support.',
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              voidCategory ? 'Category voided.' : 'Category name saved.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 32,
        vertical: 24,
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        width: compact ? size.width : 620,
        height: (size.height * .72).clamp(360.0, 620.0),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F8),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('sales_inventory').snapshots(),
          builder: (context, snapshot) {
            final categories = <String, String>{};
            if (snapshot.hasData) {
              for (final data in currentCatalogCategories(
                snapshot.data!.docs.map((d) => d.data()).toList(),
              )) {
                categories[catalogCategoryKey(data)] = '${data['name']}';
              }
            }
            final filtered =
                categories.values
                    .where((name) => name.toLowerCase().contains(_query))
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 26,
                    compact ? 18 : 24,
                    compact ? 12 : 18,
                    compact ? 18 : 22,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFF0F1), Color(0xFFFFF8F8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9DDE3),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.category_rounded,
                          color: Color(0xFF8F123D),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Manage categories',
                              style: TextStyle(
                                color: Color(0xFF45101F),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Search, rename, or remove inventory categories',
                              style: TextStyle(
                                color: Colors.brown.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 18 : 24,
                    4,
                    compact ? 18 : 24,
                    12,
                  ),
                  child: TextField(
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search categories',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => setState(() => _query = ''),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFF0D7DC)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFF0D7DC)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF9A1747),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 20 : 28, 0, 24, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'INVENTORY CATEGORIES',
                          style: TextStyle(
                            color: Color(0xFF8A6570),
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (snapshot.hasData)
                        Text(
                          '${filtered.length} ${filtered.length == 1 ? 'category' : 'categories'}',
                          style: const TextStyle(
                            color: Color(0xFF8A6570),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: snapshot.hasError
                      ? const Center(child: Text('Unable to load categories.'))
                      : !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _query.isEmpty
                                      ? Icons.inventory_2_outlined
                                      : Icons.search_off_rounded,
                                  size: 38,
                                  color: const Color(0xFFB98896),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _query.isEmpty
                                      ? 'No categories yet'
                                      : 'No categories match "$_query"',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF704B56),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 22,
                            0,
                            compact ? 16 : 22,
                            20,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final name = filtered[index];
                            return Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 13 : 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF1E1E4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF0F2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.folder_outlined,
                                      color: Color(0xFF9A1747),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF3D2930),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Rename category',
                                    onPressed: busy
                                        ? null
                                        : () => change(name, false),
                                    icon: const Icon(Icons.edit_outlined),
                                    color: const Color(0xFF72515B),
                                  ),
                                  IconButton(
                                    tooltip: 'Void category and all items',
                                    onPressed: busy
                                        ? null
                                        : () => change(name, true),
                                    icon: const Icon(Icons.block_rounded),
                                    color: const Color(0xFF9A1747),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (busy)
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: Color(0xFF9A1747),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
