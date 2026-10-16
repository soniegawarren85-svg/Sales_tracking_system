import 'checklist_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<DocumentReference<Map<String, dynamic>>>> bundleMetadataTargets(
  FirebaseFirestore db,
  String id, {
  bool Function(Map<String, dynamic>)? needsUpdate,
}) async {
  final snapshots = await Future.wait([
    db
        .collection('staff_inventory')
        .where('sourceInventoryId', isEqualTo: id)
        .get(),
    db
        .collection('allocation_checklist')
        .where('sourceInventoryId', isEqualTo: id)
        .get(),
  ]);
  return snapshots
      .expand((snapshot) => snapshot.docs)
      .where((doc) {
        final data = doc.data();
        if (data['isDeleted'] == true || data['isVoided'] == true) return false;
        if (doc.reference.parent.id == 'allocation_checklist' &&
            !ChecklistStatus.incomingOpen(data)) {
          return false;
        }
        return needsUpdate?.call(data) ?? true;
      })
      .map((doc) => doc.reference)
      .toList();
}

Future<List<DocumentReference<Map<String, dynamic>>>> readBundleMetadataTargets(
  Transaction tx,
  List<DocumentReference<Map<String, dynamic>>> references,
) async {
  final targets = <DocumentReference<Map<String, dynamic>>>[];
  for (final snapshot in await Future.wait(references.map(tx.get))) {
    final ref = snapshot.reference;
    final data = snapshot.data();
    if (data == null || data['isDeleted'] == true || data['isBundle'] != true) {
      continue;
    }
    if (ref.parent.id == 'allocation_checklist' &&
        !ChecklistStatus.incomingOpen(data)) {
      continue;
    }
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
    for (final key in ['name', 'price', 'costPrice', 'imageUrl'])
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
    if (!central.exists || central.data()?['isDeleted'] == true) {
      throw StateError('Bundle is no longer available.');
    }
    final targets = await readBundleMetadataTargets(tx, references);
    tx.update(source, {...changes, 'updatedAt': FieldValue.serverTimestamp()});
    writeBundleMetadata(tx, targets, changes);
  });
}
