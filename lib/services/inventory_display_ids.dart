import 'public_item_id.dart';

String inventoryDisplayId(Map<String, dynamic> data) {
  for (final key in [
    'publicId',
    'addonId',
    'coffeeId',
    'bundleId',
    'id',
    'itemId',
    'variantId',
    'sourceInventoryId',
  ]) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return publicItemId(value);
  }
  return '--';
}

bool inventoryVariantsMatch(Map first, Map second) {
  String normalizedVariant(Map item) =>
      [item['variant'], item['variantName'], item['size'], item['coffeeSize']]
          .map((value) => '${value ?? ''}'.trim().toLowerCase())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');

  final firstVariant = normalizedVariant(first);
  final secondVariant = normalizedVariant(second);
  if (firstVariant.isNotEmpty &&
      secondVariant.isNotEmpty &&
      firstVariant != secondVariant) {
    return false;
  }

  final firstIds = [
    for (final key in [
      'publicId',
      'itemPublicId',
      'id',
      'itemId',
      'variantId',
      'sourceItemId',
    ])
      '${first[key] ?? ''}'.trim().toLowerCase(),
  ].where((id) => id.isNotEmpty).toSet();
  final secondIds = [
    for (final key in [
      'publicId',
      'itemPublicId',
      'id',
      'itemId',
      'variantId',
      'sourceItemId',
    ])
      '${second[key] ?? ''}'.trim().toLowerCase(),
  ].where((id) => id.isNotEmpty).toSet();
  if (firstIds.intersection(secondIds).isNotEmpty) return true;

  final firstName = '${first['name'] ?? first['variant'] ?? ''}'
      .trim()
      .toLowerCase();
  final secondName = '${second['name'] ?? second['variant'] ?? ''}'
      .trim()
      .toLowerCase();
  return firstName.isNotEmpty && firstName == secondName;
}

bool inventoryCatalogVariantMatches(
  Map catalogItem,
  Map allocatedItem,
  Iterable<Map> catalogItems,
) {
  if (inventoryVariantsMatch(catalogItem, allocatedItem)) return true;

  final allocatedIds = [
    for (final key in [
      'publicId',
      'itemPublicId',
      'id',
      'itemId',
      'variantId',
      'sourceItemId',
    ])
      '${allocatedItem[key] ?? ''}'.trim().toLowerCase(),
  ].where((id) => id.isNotEmpty).toSet();
  final catalogIds = [
    for (final key in [
      'publicId',
      'itemPublicId',
      'id',
      'itemId',
      'variantId',
      'sourceItemId',
    ])
      '${catalogItem[key] ?? ''}'.trim().toLowerCase(),
  ].where((id) => id.isNotEmpty).toSet();
  final sharedIds = allocatedIds.intersection(catalogIds);
  if (sharedIds.isEmpty) return false;

  final matchingIds = catalogItems.map((item) {
    final ids = [
      for (final key in [
        'publicId',
        'itemPublicId',
        'id',
        'itemId',
        'variantId',
        'sourceItemId',
      ])
        '${item[key] ?? ''}'.trim().toLowerCase(),
    ].where((id) => id.isNotEmpty).toSet();
    return ids.intersection(sharedIds);
  });
  final idCounts = <String, int>{};
  for (final ids in matchingIds) {
    for (final id in ids) {
      idCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return idCounts.values.any((count) => count == 1);
}

/// Keep allocation stock and references while refreshing catalog display data.
Map<String, dynamic> alignInventoryDisplayIds(
  Map<String, dynamic> allocation,
  Map<String, dynamic> source,
) {
  final sourceItems = (source['items'] as List? ?? []).whereType<Map>();
  final items = (allocation['items'] as List? ?? []).whereType<Map>().map((
    raw,
  ) {
    final item = Map<String, dynamic>.from(raw);
    final matches = sourceItems.where((candidate) {
      return inventoryCatalogVariantMatches(candidate, item, sourceItems);
    }).toList();
    if (matches.length == 1) {
      final sourceItem = matches.single;
      if (sourceItem['publicId'] != null) {
        item['publicId'] = sourceItem['publicId'];
      }
      if (sourceItem['price'] != null) {
        item['price'] = item['branchPriceOverride'] ?? sourceItem['price'];
      }
      if (sourceItem['name'] != null) {
        item['name'] = item['branchNameOverride'] ?? sourceItem['name'];
      }
      if (sourceItem['imageUrl'] != null) {
        item['imageUrl'] = sourceItem['imageUrl'];
      }
    }
    return item;
  }).toList();
  return {
    ...allocation,
    if (source['publicId'] != null) 'publicId': source['publicId'],
    if (allocation['items'] is List) 'items': items,
  };
}
