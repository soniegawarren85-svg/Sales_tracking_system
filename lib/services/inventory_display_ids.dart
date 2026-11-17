import 'package:cloud_firestore/cloud_firestore.dart';

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

String inventoryCategoryIdentity(Map data, {Map? catalog}) {
  final id = [
    catalog?['publicId'],
    catalog?['categoryId'],
    data['publicId'],
    data['categoryId'],
  ]
      .map((value) => '${value ?? ''}'.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (id.isNotEmpty) return 'id:${id.toLowerCase()}';

  final name = '${catalog?['name'] ?? data['name'] ?? ''}'
      .trim()
      .toLowerCase();
  return name.isEmpty ? '' : 'name:$name';
}

bool inventoryCatalogIsNewer(Map candidate, Map current) {
  DateTime? timestamp(Map data) {
    for (final key in ['timestamp', 'createdAt', 'updatedAt']) {
      final value = data[key];
      final date = value is Timestamp
          ? value.toDate()
          : value is DateTime
          ? value
          : DateTime.tryParse('$value');
      if (date != null) return date;
    }
    return null;
  }

  final candidateDate = timestamp(candidate);
  final currentDate = timestamp(current);
  if (candidateDate != null || currentDate != null) {
    if (candidateDate == null) return false;
    if (currentDate == null) return true;
    if (candidateDate != currentDate) {
      return candidateDate.isAfter(currentDate);
    }
  }

  int sequence(Map data) {
    final id = '${data['publicId'] ?? data['categoryId'] ?? ''}';
    final digits = RegExp(r'(\d+)$').firstMatch(id)?.group(1);
    return int.tryParse(digits ?? '') ?? -1;
  }

  return sequence(candidate) > sequence(current);
}

List<Map<String, dynamic>> aggregateInventoryAllocationItems(
  Iterable<Map<String, dynamic>> items,
) {
  int quantity(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  DateTime? date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value');

  final aggregated = <String, Map<String, dynamic>>{};
  for (final item in items) {
    final id = [
      item['publicId'],
      item['itemPublicId'],
      item['id'],
      item['itemId'],
      item['variantId'],
      item['sourceItemId'],
    ]
        .map((value) => '${value ?? ''}'.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final name = '${item['name'] ?? ''}'.trim().toLowerCase();
    final variant = '${item['variant'] ?? ''}'.trim().toLowerCase();
    final expiry = item['origin'] == 'unbundle'
        ? '|${item['expirationDate'] ?? ''}'
        : '';
    final key = id.isNotEmpty
        ? '${id.toLowerCase()}|$variant$expiry'
        : '$name|$variant$expiry';
    final current = aggregated[key];
    final stock = quantity(item['stock'] ?? item['startingStock']);
    if (current == null) {
      aggregated[key] = Map<String, dynamic>.from(item)..['stock'] = stock;
      continue;
    }

    current['stock'] = quantity(current['stock']) + stock;
    current['startingStock'] =
        quantity(current['startingStock']) + quantity(item['startingStock']);
    current['assignedStartingStock'] =
        quantity(current['assignedStartingStock']) +
        quantity(item['assignedStartingStock']);
    final existingDate = date(current['allocatedAt'] ?? current['assignedAt']);
    final incomingDate = date(item['allocatedAt'] ?? item['assignedAt']);
    if (incomingDate != null &&
        (existingDate == null || incomingDate.isAfter(existingDate))) {
      current['allocatedAt'] = incomingDate;
    }
    if (current['origin'] == 'unbundle' && item['origin'] != 'unbundle') {
      for (final field in ['sourceDocId', 'price', 'imageUrl']) {
        if (item[field] != null) current[field] = item[field];
      }
    }
  }
  return aggregated.values
      .map(
        (item) => Map<String, dynamic>.from(item)
          ..remove('origin')
          ..remove('unbundledQuantity'),
      )
      .toList();
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
