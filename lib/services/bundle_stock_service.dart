import 'bundle_metadata_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

List<Map<String, dynamic>> bundleRows(dynamic value) =>
    (value is List ? value : const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
int bundleQuantity(dynamic value) => num.tryParse('$value')?.toInt() ?? 0;

List<Map<String, dynamic>> bundleBeverageSizes(
  String id,
  Map<String, dynamic> data,
) {
  if (data['isDeleted'] == true ||
      data['isAvailable'] == false ||
      bundleExpired(data, DateTime.now()))
    return [];
  return bundleRows(data['sizes'])
      .where((size) => '${size['name'] ?? ''}'.isNotEmpty)
      .map(
        (size) => <String, dynamic>{
          'id': size['name'],
          'variantId': size['name'],
          'coffeeSize': size['name'],
          'name': '${data['name']} (${size['name']})',
          'sourceInventoryId': id,
          'sourceCollection': 'coffee_products',
          'publicId': data['publicId'] ?? data['coffeeId'],
          'isCoffee': true,
          'price':
              (num.tryParse('${data['basePrice']}') ?? 0) +
              (num.tryParse('${size['priceDelta']}') ?? 0),
          'expirationDate': data['expirationDate'] ?? '',
          if (data['stock'] != null || data['startingStock'] != null)
            'stock': data['stock'] ?? data['startingStock'],
          'untrackedStock':
              data['stock'] == null && data['startingStock'] == null,
        },
      )
      .toList();
}

bool bundleExpired(Map data, DateTime now) {
  final raw = data['expirationDate'];
  final date = raw is Timestamp ? raw.toDate() : DateTime.tryParse('$raw');
  return date != null && date.isBefore(DateTime(now.year, now.month, now.day));
}

bool bundleInstanceAvailable(Map instance, Map bundle, {DateTime? now}) {
  final day = now ?? DateTime.now();
  if (instance['isDeleted'] == true ||
      instance['isVoided'] == true ||
      ![
        'available',
        '',
      ].contains('${instance['status'] ?? 'available'}'.toLowerCase()))
    return false;
  if (bundleExpired(instance, day)) return false;
  final ownItems = bundleRows(instance['items']);
  // New instances carry their own expiry snapshot. Older ones inherit recipe
  // dates only when no batch date was recorded.
  final items =
      ownItems.any((item) => '${item['expirationDate'] ?? ''}'.isNotEmpty)
      ? ownItems
      : '${instance['expirationDate'] ?? ''}'.isNotEmpty
      ? <Map<String, dynamic>>[]
      : bundleRows(bundle['items']);
  return !items.any((item) => bundleExpired(item, day));
}

int availableBundleStock(Map bundle, {DateTime? now}) {
  if (bundle['isDeleted'] == true) return 0;
  final instances = bundleRows(bundle['bundleInstances']);
  if (instances.isNotEmpty)
    return instances
        .where(
          (instance) => bundleInstanceAvailable(instance, bundle, now: now),
        )
        .length;
  if (bundleExpired(bundle, now ?? DateTime.now()) ||
      !bundleInstanceAvailable({}, bundle, now: now))
    return 0;
  return bundleQuantity(bundle['bundleCount']);
}

class BundleStockService {
  BundleStockService(this.db);
  final FirebaseFirestore db;

  /// Append a fresh batch and reserve its ingredients in the same transaction.
  Future<Map<String, List<dynamic>>> restock(
    String id,
    int quantity,
    Map<String, dynamic> changes, {
    List<Map<String, dynamic>>? ingredients,
    Map<String, dynamic>? newBundle,
  }) async {
    if (quantity < 1 || quantity > 100)
      throw ArgumentError('Add between 1 and 100 bundles at a time.');
    final candidates = await db.collection('sales_inventory').get();
    final ref = db.collection('sales_inventory').doc(id);
    final batchId = db.collection('sales_inventory').doc().id;
    final initial = newBundle ?? (await ref.get()).data();
    if (initial == null) throw StateError('Bundle no longer exists.');
    final requested = ingredients ?? bundleRows(initial['items']);
    final selectedSources = <String>{};
    for (final ingredient in requested) {
      if (ingredient['sourceCollection'] == 'coffee_products') continue;
      final sourceId = '${ingredient['sourceInventoryId'] ?? ''}';
      if (sourceId.isNotEmpty) {
        selectedSources.add(sourceId);
        continue;
      }
      for (final candidate in candidates.docs) {
        if (candidate.data()['isBundle'] == true ||
            candidate.data()['isDeleted'] == true)
          continue;
        if (ingredient['parentName'] != null &&
            candidate.data()['name'] != ingredient['parentName'])
          continue;
        if (bundleRows(candidate.data()['items']).any(
          (item) =>
              '${ingredient['variantId'] ?? ingredient['itemId'] ?? ''}'
                  .isNotEmpty
              ? '${item['id']}' ==
                    '${ingredient['variantId'] ?? ingredient['itemId']}'
              : item['name'] == ingredient['name'],
        ))
          selectedSources.add(candidate.id);
      }
    }
    final metadataTargets = await bundleMetadataTargets(db, id);
    return db.runTransaction<Map<String, List<dynamic>>>((tx) async {
      final linked = await readBundleMetadataTargets(tx, metadataTargets);
      final snap = await tx.get(ref);
      if (newBundle != null && snap.exists)
        throw StateError('Bundle already exists.');
      final bundle = snap.data() ?? newBundle;
      if (bundle == null || bundle['isDeleted'] == true)
        throw StateError('Bundle no longer available.');
      final recipe = requested;
      if (recipe.isEmpty) throw StateError('This bundle has no ingredients.');
      final sources = <String, Map<String, dynamic>>{};
      for (final sourceId in selectedSources) {
        final current = (await tx.get(
          db.collection('sales_inventory').doc(sourceId),
        )).data();
        if (current != null && current['isDeleted'] != true)
          sources[sourceId] = current;
      }
      final itemsBySource = {
        for (final entry in sources.entries)
          entry.key: bundleRows(entry.value['items']),
      };
      final touched = <String>{};
      final fresh = <Map<String, dynamic>>[];
      final coffees = <String, Map<String, dynamic>>{};
      for (final ingredient in recipe.where(
        (item) => item['sourceCollection'] == 'coffee_products',
      )) {
        final coffeeId = '${ingredient['sourceInventoryId']}';
        if (coffees.containsKey(coffeeId)) continue;
        final data = (await tx.get(
          db.collection('coffee_products').doc(coffeeId),
        )).data();
        if (data == null) throw StateError('Beverage no longer exists.');
        coffees[coffeeId] = data;
      }
      for (final ingredient in recipe) {
        if (ingredient['sourceCollection'] == 'coffee_products') {
          final coffeeId = '${ingredient['sourceInventoryId']}';
          final coffee = coffees[coffeeId]!;
          final options = bundleBeverageSizes(coffeeId, coffee)
              .where(
                (size) =>
                    size['coffeeSize'] ==
                    (ingredient['coffeeSize'] ?? ingredient['variantId']),
              )
              .toList();
          if (options.length != 1)
            throw StateError('Selected beverage size is unavailable.');
          final option = options.single;
          final perBundle = bundleQuantity(ingredient['quantity']);
          if (perBundle < 1)
            throw StateError('Beverage quantity must be positive.');
          if (option['untrackedStock'] != true) {
            final stock = bundleQuantity(option['stock']);
            if (stock < perBundle * quantity)
              throw StateError(
                'Not enough ${coffee['name']} stock for the selected sizes.',
              );
            coffee['stock'] = stock - perBundle * quantity;
          }
          fresh.add(
            {...option, 'quantity': perBundle, 'remaining': perBundle}
              ..remove('stock')
              ..remove('untrackedStock'),
          );
          continue;
        }
        final matches = <(String, int)>[];
        for (final entry in itemsBySource.entries) {
          final sourceId = '${ingredient['sourceInventoryId'] ?? ''}';
          if (sourceId.isNotEmpty && entry.key != sourceId) continue;
          if (sourceId.isEmpty &&
              ingredient['parentName'] != null &&
              sources[entry.key]!['name'] != ingredient['parentName'])
            continue;
          for (var index = 0; index < entry.value.length; index++) {
            final item = entry.value[index];
            final variantId =
                '${ingredient['variantId'] ?? ingredient['itemId'] ?? ''}';
            if (variantId.isNotEmpty
                ? [
                    item['id'],
                    item['publicId'],
                    if (item['id'] == null && item['publicId'] == null)
                      item['name'],
                  ].any((value) => '$value' == variantId)
                : item['name'] == ingredient['name'])
              matches.add((entry.key, index));
          }
        }
        if (matches.length != 1)
          throw StateError(
            'Cannot uniquely locate ${ingredient['name']} in inventory.',
          );
        final match = matches.single;
        final item = itemsBySource[match.$1]![match.$2];
        if (item['isDeleted'] == true ||
            item['isVoided'] == true ||
            bundleExpired(item, DateTime.now()))
          throw StateError(
            '${item['name']} is expired or voided. Update its inventory first.',
          );
        final perBundle = bundleQuantity(ingredient['quantity']);
        final needed = perBundle * quantity;
        final stock = bundleQuantity(item['stock'] ?? item['startingStock']);
        if (perBundle < 1 || stock < needed)
          throw StateError(
            'Not enough ${item['name']}. Need $needed, available $stock.',
          );
        item['stock'] = stock - needed;
        touched.add(match.$1);
        fresh.add({
          'name': item['name'],
          'publicId': item['publicId'],
          'price': item['price'] ?? 0,
          'parentName': sources[match.$1]!['name'],
          'sourceInventoryId': match.$1,
          'variantId': item['id'] ?? item['publicId'] ?? item['name'],
          'expirationDate': item['expirationDate'] ?? '',
          'quantity': perBundle,
          'remaining': perBundle,
        });
      }
      final dates =
          fresh
              .map((item) => DateTime.tryParse('${item['expirationDate']}'))
              .whereType<DateTime>()
              .toList()
            ..sort();
      final expiry = dates.isEmpty ? '' : dates.first.toIso8601String();
      final instances = bundleRows(bundle['bundleInstances']);
      for (final instance in instances) {
        final oldItems = bundleRows(instance['items']);
        if ('${instance['expirationDate'] ?? ''}'.isEmpty &&
            !oldItems.any(
              (item) => '${item['expirationDate'] ?? ''}'.isNotEmpty,
            )) {
          instance['expirationDate'] = bundle['expirationDate'] ?? '';
          instance['items'] = bundleRows(
            bundle['items'],
          ).map((item) => {...item}..remove('imageUrl')).toList();
        } else {
          instance['items'] = oldItems
              .map((item) => {...item}..remove('imageUrl'))
              .toList();
        }
      }
      // Preserve legacy stock instead of dropping it when introducing instances.
      if (instances.isEmpty) {
        for (var i = 0; i < bundleQuantity(bundle['bundleCount']); i++) {
          instances.add({
            'id': '$id-legacy-$i',
            'number': i + 1,
            'status': 'available',
            'expirationDate': bundle['expirationDate'] ?? '',
            'items': bundleRows(
              bundle['items'],
            ).map((item) => {...item}..remove('imageUrl')).toList(),
          });
        }
      }
      final offset = instances.length;
      for (var i = 0; i < quantity; i++) {
        instances.add({
          'id': '${bundle['bundleId'] ?? id}-$batchId-$i',
          'number': offset + i + 1,
          'status': 'available',
          'expirationDate': expiry,
          'items': fresh,
        });
      }
      writeBundleMetadata(tx, linked, changes);
      for (final sourceId in touched) {
        tx.update(db.collection('sales_inventory').doc(sourceId), {
          'items': itemsBySource[sourceId],
        });
      }
      for (final coffee in coffees.entries) {
        if (coffee.value['stock'] != null)
          tx.update(db.collection('coffee_products').doc(coffee.key), {
            'stock': coffee.value['stock'],
          });
      }
      final saved = <String, dynamic>{
        if (newBundle != null) ...newBundle,
        ...changes,
        'bundleCount': bundleQuantity(bundle['bundleCount']) + quantity,
        'bundleInstances': instances,
        'items': fresh.map((item) => {...item}..remove('remaining')).toList(),
        'updatedAt': Timestamp.now(),
        if (newBundle != null) 'expirationDate': expiry,
      };
      if (newBundle == null) {
        tx.update(ref, saved);
      } else {
        tx.set(ref, saved);
      }
      return {
        ...itemsBySource,
        for (final coffee in coffees.entries)
          'coffee:${coffee.key}': bundleBeverageSizes(coffee.key, coffee.value),
      };
    });
  }
}
