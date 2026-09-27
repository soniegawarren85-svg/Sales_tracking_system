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

/// Copy display codes only: stock quantities and internal references belong to
/// the allocation and must never be replaced with the central inventory's.
Map<String, dynamic> alignInventoryDisplayIds(
  Map<String, dynamic> allocation,
  Map<String, dynamic> source,
) {
  final sourceItems = (source['items'] as List? ?? []).whereType<Map>();
  final items = (allocation['items'] as List? ?? []).whereType<Map>().map((
    raw,
  ) {
    final item = Map<String, dynamic>.from(raw);
    final identity = (item['id'] ?? item['itemId'] ?? item['variantId'])
        ?.toString();
    final matches = sourceItems.where(
      (candidate) =>
          identity != null &&
          identity ==
              (candidate['id'] ?? candidate['itemId'] ?? candidate['variantId'])
                  ?.toString(),
    );
    if (matches.length == 1 && matches.first['publicId'] != null) {
      item['publicId'] = matches.first['publicId'];
    }
    return item;
  }).toList();
  return {
    ...allocation,
    if (source['publicId'] != null) 'publicId': source['publicId'],
    if (allocation['items'] is List) 'items': items,
  };
}
