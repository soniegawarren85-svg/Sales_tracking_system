List<Map<String, dynamic>> removeAllocatedCatalogVariant(
  List<dynamic> allocatedItems,
  Map<String, dynamic> removedVariant,
) {
  final targetIds = _variantIds(removedVariant);
  final targetName = '${removedVariant['name'] ?? ''}'.trim();
  final matchingNames = allocatedItems.whereType<Map>().where((raw) {
    final item = Map<String, dynamic>.from(raw);
    return targetName.isNotEmpty &&
        '${item['name'] ?? ''}'.trim() == targetName &&
        _variantIds(item).isEmpty;
  }).length;
  var removedLegacyMatch = false;

  return allocatedItems
      .whereType<Map>()
      .map((raw) => Map<String, dynamic>.from(raw))
      .where((item) {
        final itemIds = _variantIds(item);
        if (targetIds.isNotEmpty) {
          if (itemIds.isNotEmpty) {
            return !targetIds.any(itemIds.contains);
          }
          if (targetName.isEmpty ||
              matchingNames != 1 ||
              '${item['name'] ?? ''}'.trim() != targetName ||
              removedLegacyMatch) {
            return true;
          }
          removedLegacyMatch = true;
          return false;
        }

        if (targetName.isEmpty ||
            '${item['name'] ?? ''}'.trim() != targetName ||
            removedLegacyMatch) {
          return true;
        }
        removedLegacyMatch = true;
        return false;
      })
      .toList();
}

Set<String> _variantIds(Map item) => {
  for (final key in const ['id', 'itemId', 'variantId'])
    if (item[key] != null && '${item[key]}'.trim().isNotEmpty)
      '${item[key]}'.trim(),
};
