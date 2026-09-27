import 'package:cloud_firestore/cloud_firestore.dart';

class AllocationChecklistService {
  final FirebaseFirestore db;
  AllocationChecklistService(this.db);

  static int quantity(dynamic value) => num.tryParse('$value')?.toInt() ?? 0;
  static List<Map<String, dynamic>> rows(dynamic value) =>
      (value is List ? value : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  static String type(Map<String, dynamic> data) =>
      data['isCoffee'] == true || data['isAddon'] == true
      ? 'Beverages'
      : data['isBundle'] == true
      ? 'Bundle'
      : 'Categories';

  Future<bool> decide(
    String id, {
    required bool accept,
    required String staffId,
    String reason = '',
  }) async {
    if (!accept && reason.trim().isEmpty)
      throw ArgumentError('Please enter a decline reason.');
    return db.runTransaction<bool>((tx) async {
      final ref = db.collection('allocation_checklist').doc(id);
      final snap = await tx.get(ref);
      final pending = snap.data();
      if (pending == null || pending['status'] != 'pending') return false;
      final destination = accept
          ? db.collection('staff_inventory').doc('${pending['targetDocId']}')
          : db
                .collection(
                  '${pending['sourceCollection'] ?? 'sales_inventory'}',
                )
                .doc('${pending['sourceInventoryId']}');
      final target = await tx.get(destination);
      final current = target.data() ?? <String, dynamic>{};
      final bundle = pending['isBundle'] == true;
      final beverage = type(pending) == 'Beverages';
      if (!accept && !target.exists)
        throw StateError(
          'Source inventory is missing. Ask the administrator to restore it before declining.',
        );
      final incoming = rows(pending['items']);
      final payload = Map<String, dynamic>.from(pending)
        ..remove('targetDocId')
        ..remove('status')
        ..remove('deliveryId');
      final result = <String, dynamic>{
        if (accept) ...payload,
        ...current,
        if (accept) 'isDeleted': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (bundle) {
        result['bundleCount'] =
            quantity(current['bundleCount']) + quantity(pending['bundleCount']);
        result['bundleInstances'] = [
          ...rows(current['bundleInstances']),
          ...rows(pending['bundleInstances']),
        ];
        if (accept)
          result['assignedStartingStock'] =
              quantity(
                current['assignedStartingStock'] ?? current['bundleCount'],
              ) +
              quantity(pending['bundleCount']);
      } else if (!beverage) {
        final items = rows(current['items']);
        for (final item in incoming) {
          final index = items.indexWhere(
            (old) => (item['id']?.toString().isNotEmpty ?? false)
                ? old['id'] == item['id']
                : old['name'] == item['name'],
          );
          final count = quantity(item['stock'] ?? item['startingStock']);
          if (index < 0) {
            items.add({...item, 'stock': count});
          } else {
            final old = items[index];
            items[index] = {
              ...old,
              'stock': quantity(old['stock'] ?? old['startingStock']) + count,
              if (accept)
                'startingStock': quantity(old['startingStock']) + count,
              if (accept)
                'assignedStartingStock':
                    quantity(
                      old['assignedStartingStock'] ?? old['startingStock'],
                    ) +
                    count,
            };
          }
        }
        result['items'] = items;
      } else if (accept) {
        result.addAll(payload);
      }
      if (accept) {
        result['assignedAt'] = FieldValue.serverTimestamp();
        result['updatedAt'] = FieldValue.serverTimestamp();
      }
      // Beverages/add-ons are catalog permissions; no physical stock was reserved.
      if (accept || !beverage)
        tx.set(destination, result, SetOptions(merge: true));
      tx.update(ref, {
        'status': accept ? 'accepted' : 'declined',
        'reason': reason.trim(),
        'decidedBy': staffId,
        'decidedAt': FieldValue.serverTimestamp(),
      });
      if (accept) {
        tx.set(db.collection('staff_inventory_history').doc('accepted_$id'), {
          'staffId': pending['staffId'],
          'staffName': pending['staffName'],
          'type': 'assignment',
          'allocationId': id,
          'createdAt': FieldValue.serverTimestamp(),
          'items': bundle || beverage
              ? [
                  {
                    ...payload,
                    'quantity': bundle ? quantity(pending['bundleCount']) : 1,
                  },
                ]
              : incoming
                    .map(
                      (item) => {
                        ...item,
                        'sourceInventoryId': pending['sourceInventoryId'],
                        'quantity': quantity(item['stock']),
                      },
                    )
                    .toList(),
        });
      } else {
        tx.set(
          db.collection('admin_notifications').doc('allocation_declined_$id'),
          {
            'title': 'Allocation declined',
            'message':
                '${pending['staffName'] ?? 'Branch'} declined ${pending['name'] ?? 'items'}. Reason: ${reason.trim()}',
            'type': 'allocation_declined',
            'category': 'Inventory',
            'allocationId': id,
            'branchId': pending['staffId'],
            'staffId': staffId,
            'reason': reason.trim(),
            'isRead': false,
            'toastShown': false,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
      return true;
    });
  }
}
