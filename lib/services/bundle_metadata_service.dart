import 'checklist_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<DocumentReference<Map<String, dynamic>>>> bundleMetadataTargets(
  FirebaseFirestore db,
  String id, {
  bool Function(Map<String, dynamic>)? needsUpdate,
}) async {
  // Catalog edits never rewrite delivered or pending allocation snapshots.
  return [];
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

List<Map<String, dynamic>> _bundleRecipeRows(dynamic value) =>
    (value is List ? value : const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

dynamic _recipeExpirationDate(List<Map<String, dynamic>> items) {
  final dates =
      items
          .map((item) {
            final value = item['expirationDate'];
            if (value is Timestamp) return value.toDate();
            if (value is DateTime) return value;
            return DateTime.tryParse('$value');
          })
          .whereType<DateTime>()
          .toList()
        ..sort();
  return dates.isEmpty ? '' : dates.first.toIso8601String();
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
    final update = <String, dynamic>{
      ...changes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (changes['items'] is List) {
      final recipe = _bundleRecipeRows(changes['items']);
      final expirationDate = _recipeExpirationDate(recipe);
      update['bundleInstances'] =
          _bundleRecipeRows(central.data()?['bundleInstances']).map((instance) {
            final status = '${instance['status'] ?? 'available'}'.toLowerCase();
            if (status.isNotEmpty && status != 'available') return instance;
            return {
              ...instance,
              'items': recipe
                  .map((item) => {...item}..remove('remaining'))
                  .toList(),
              'expirationDate': expirationDate,
            };
          }).toList();
    }
    tx.update(source, update);
    writeBundleMetadata(tx, targets, changes);
  });
}
