import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'inventory_display_ids.dart';

String shortCode(String prefix, int number) =>
    '$prefix-${number.toString().padLeft(3, '0')}';
String categoryPrefix(String name) {
  final letters = name.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
  return letters.isEmpty
      ? 'IT'
      : letters.substring(0, letters.length < 2 ? letters.length : 2);
}

class ShortIdService {
  static final _db = FirebaseFirestore.instance;
  static bool _running = false;
  static Future<String> next(String prefix) => _db.runTransaction((tx) async {
    final ref = _db.collection('system_counters').doc('public_$prefix');
    final doc = await tx.get(ref);
    final number = ((doc.data()?['count'] as num?)?.toInt() ?? 0) + 1;
    tx.set(ref, {'count': number});
    return shortCode(prefix, number);
  });
  // Add display codes while preserving document IDs and item stock references.
  static Future<void> refresh() async {
    if (_running) return;
    _running = true;
    try {
      for (final name in [
        'sales_inventory',
        'coffee_products',
        'coffee_addons',
        'branches',
      ]) {
        final snapshot = await _db
            .collection(name)
            .get(const GetOptions(source: Source.server));
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final prefix = name == 'branches'
              ? 'BR'
              : name == 'coffee_addons'
              ? 'AD'
              : name == 'coffee_products'
              ? 'CF'
              : data['isBundle'] == true
              ? 'BND'
              : 'CAT';
          if (data['publicId'] == null) {
            final code = await next(prefix);
            await _db.runTransaction((tx) async {
              final current = await tx.get(doc.reference);
              if (current.data()?['publicId'] != null) return;
              tx.update(doc.reference, {
                'publicId': code,
                if (name == 'branches') 'branchCode': code,
              });
            });
          }
          if (name == 'sales_inventory' && data['isBundle'] != true) {
            final prefix = categoryPrefix('${data['name'] ?? ''}');
            await _db.runTransaction((tx) async {
              final current = await tx.get(doc.reference);
              final counter = _db
                  .collection('system_counters')
                  .doc('public_$prefix');
              final counterDoc = await tx.get(counter);
              var number = (counterDoc.data()?['count'] as num?)?.toInt() ?? 0;
              var changed = false;
              final items = (current.data()?['items'] as List? ?? [])
                  .whereType<Map>()
                  .map((raw) {
                    final item = Map<String, dynamic>.from(raw);
                    if (item['publicId'] == null) {
                      item['publicId'] = shortCode(prefix, ++number);
                      changed = true;
                    }
                    return item;
                  })
                  .toList();
              if (changed) {
                tx.update(doc.reference, {'items': items});
                tx.set(counter, {'count': number});
              }
            });
          }
        }
      }
      // Older allocations predate the public codes. Refresh only their display
      // fields, transactionally, so current stock and receipt references survive.
      final allocations = await _db.collection('staff_inventory').get();
      for (final allocation in allocations.docs) {
        final sourceId =
            allocation.data()['sourceInventoryId']?.toString() ?? '';
        if (sourceId.isEmpty) continue;
        final collection = allocation.data()['isCoffee'] == true
            ? 'coffee_products'
            : 'sales_inventory';
        await _db.runTransaction((tx) async {
          final current = await tx.get(allocation.reference);
          final source = await tx.get(_db.collection(collection).doc(sourceId));
          if (!current.exists || !source.exists) return;
          final data = current.data()!;
          final aligned = alignInventoryDisplayIds(data, source.data()!);
          final patch = <String, dynamic>{};
          if (aligned['publicId'] != data['publicId'])
            patch['publicId'] = aligned['publicId'];
          final oldItems = (data['items'] as List? ?? [])
              .whereType<Map>()
              .map((item) => item['publicId'])
              .toList();
          final newItems = (aligned['items'] as List? ?? [])
              .whereType<Map>()
              .map((item) => item['publicId'])
              .toList();
          if (jsonEncode(oldItems) != jsonEncode(newItems))
            patch['items'] = aligned['items'];
          if (patch.isNotEmpty) tx.update(allocation.reference, patch);
        });
      }
    } finally {
      _running = false;
    }
  }
}
