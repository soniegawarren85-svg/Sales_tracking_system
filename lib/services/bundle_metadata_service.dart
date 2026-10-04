import 'checklist_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<DocumentReference<Map<String, dynamic>>>> bundleMetadataTargets(
  FirebaseFirestore db,
  String id,
) async {
  final assigned = await db
      .collection('staff_inventory')
      .where('sourceInventoryId', isEqualTo: id)
      .get();
  final pending = await db
      .collection('allocation_checklist')
      .where('sourceInventoryId', isEqualTo: id)
      .get();
  return [
    ...assigned.docs,
    ...pending.docs,
  ].map((doc) => doc.reference).toList();
}

Future<List<DocumentReference<Map<String, dynamic>>>> readBundleMetadataTargets(
  Transaction tx,
  List<DocumentReference<Map<String, dynamic>>> references,
) async {
  final targets = <DocumentReference<Map<String, dynamic>>>[];
  for (final ref in references) {
    final data = (await tx.get(ref)).data();
    if (data == null || data['isDeleted'] == true || data['isBundle'] != true)
      continue;
    if (ref.parent.id == 'allocation_checklist' && !ChecklistStatus.incomingOpen(data))
      continue;
    targets.add(ref);
  }
  return targets;
}

void writeBundleMetadata(
  Transaction tx,
  List<DocumentReference<Map<String, dynamic>>> targets,
  Map<String, dynamic> changes,
) {
  final metadata = {
    for (final key in ['name', 'price', 'imageUrl'])
      if (changes.containsKey(key)) key: changes[key],
    'updatedAt': FieldValue.serverTimestamp(),
  };
  for (final target in targets) {
    tx.update(target, metadata);
  }
}

/// Update current stock and pending deliveries, preserving historical receipts.
Future<void> updateBundleMetadata(
  FirebaseFirestore db,
  String id,
  Map<String, dynamic> changes,
) async {
  final references = await bundleMetadataTargets(db, id);
  final source = db.collection('sales_inventory').doc(id);
  await db.runTransaction((tx) async {
    final central = await tx.get(source);
    if (!central.exists || central.data()?['isDeleted'] == true)
      throw StateError('Bundle is no longer available.');
    final targets = await readBundleMetadataTargets(tx, references);
    tx.update(source, {...changes, 'updatedAt': FieldValue.serverTimestamp()});
    writeBundleMetadata(tx, targets, changes);
  });
}
